package com.spandan.app.signal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random

/**
 * Plain Kotlin/JUnit -- exercises the full [MorphologyWaveformEstimator]
 * orchestration end to end on a SYNTHETIC pulsatile RGB stream (no camera
 * needed), since no physical device was available this session to verify
 * it any other way. Component-level correctness of each stage is already
 * covered by that stage's own test ([AdaptiveHarmonicFilterTest],
 * [EnsembleAverageBeatsTest], [NotchDetectIEMTest], etc.) -- this test's
 * job is to catch WIRING mistakes between them (wrong argument order, a
 * mismatched fs, an exception that escapes the fail-soft try/catch) that a
 * component-level test can't see.
 */
class MorphologyWaveformEstimatorTest {

    /** Builds a synthetic RGB stream at [fs] Hz for [durationSec] seconds,
     *  where each channel is `baseline * (1 + k * m(t))` -- k differs per
     *  channel (same asymmetry CHROM/POS rely on to isolate a pulse from a
     *  generic per-channel modulation), m(t) a two-harmonic pulsatile
     *  waveform at [f0]Hz plus small noise, roughly mimicking real ROI
     *  pixel-average scale/modulation depth. */
    private fun buildPulsatileSamples(fs: Double, durationSec: Double, f0: Double, startMs: Long = 0L): List<RgbSample> {
        val n = (fs * durationSec).toInt()
        val rng = Random(99)
        return (0 until n).map { i ->
            val t = i / fs
            val m = sin(2 * PI * f0 * t) + 0.3 * sin(2 * PI * 2 * f0 * t)
            val noise = (rng.nextDouble() - 0.5) * 0.01
            RgbSample(
                timestampMs = startMs + (t * 1000).toLong(),
                red = (150.0 * (1.0 + 0.02 * m + noise)).toFloat(),
                green = (120.0 * (1.0 + 0.05 * m + noise)).toFloat(),
                blue = (100.0 * (1.0 + 0.03 * m + noise)).toFloat()
            )
        }
    }

    @Test
    fun returnsNullAndWarmingUpWithTooFewSamples() {
        val estimator = MorphologyWaveformEstimator()
        val samples = buildPulsatileSamples(fs = 20.0, durationSec = 1.0, f0 = 1.2)
        val result = estimator.update(samples)
        assertNull(result)
        assertEquals(EstimatorStatus.WARMING_UP, estimator.lastStatus)
    }

    @Test
    fun producesAWellFormedEstimateAtAGoodFrameRateWithWideBand() {
        val estimator = MorphologyWaveformEstimator()
        // fs=20Hz, Nyquist=10Hz -- comfortably admits the WIDE band (0.5-8Hz).
        val samples = buildPulsatileSamples(fs = 20.0, durationSec = 25.0, f0 = 1.2)
        val result = estimator.update(samples)

        assertTrue("expected a non-null estimate at a good frame rate", result != null)
        result!!
        assertEquals(EstimatorStatus.OK, estimator.lastStatus)
        assertEquals(MorphologyBandpassFilter.BandMode.WIDE, result.bandModeUsed)
        assertEquals(256, result.waveform.size)
        assertTrue(result.notchConfidence in 0.0..1.0)
        assertTrue(result.notchConfidenceRaw >= 0.0)
        assertTrue(result.harmonicMethodUsed == "adaptiveHarmonic" || result.harmonicMethodUsed == "gaussian015")
        assertTrue(result.fs > 19.0 && result.fs < 21.0)
        for (v in result.waveform) assertTrue(v.isFinite())
    }

    @Test
    fun fallsBackToMidBandWhenWideIsNotAdmissible() {
        val estimator = MorphologyWaveformEstimator()
        // fs=14Hz, Nyquist=7Hz -- WIDE (needs <8) is inadmissible, MID (needs <6) is.
        val samples = buildPulsatileSamples(fs = 14.0, durationSec = 25.0, f0 = 1.2)
        val result = estimator.update(samples)

        assertTrue("expected a non-null estimate at fs=14Hz via the MID fallback", result != null)
        assertEquals(MorphologyBandpassFilter.BandMode.MID, result!!.bandModeUsed)
        assertEquals(EstimatorStatus.OK, estimator.lastStatus)
    }

    @Test
    fun skipsTheWindowRatherThanCrashWhenFsIsTooLowForEitherBand() {
        val estimator = MorphologyWaveformEstimator()
        // fs=10Hz, Nyquist=5Hz -- too low for even MID (needs <6).
        val samples = buildPulsatileSamples(fs = 10.0, durationSec = 25.0, f0 = 1.2)
        val result = estimator.update(samples)

        assertNull(result)
        assertEquals(EstimatorStatus.LOW_SIGNAL_QUALITY, estimator.lastStatus)
    }

    @Test
    fun neverThrowsAcrossARangeOfRealisticFrameRates() {
        // Sweep across this project's own documented on-device fps range
        // (13.44-21.40, see android/docs/Segment7_Task_G_Throughput_Profiling.md)
        // plus a couple of values outside it -- the orchestrator must fail
        // soft (null + LOW_SIGNAL_QUALITY) on every input, never throw,
        // since this runs live on uncontrolled camera data.
        for (fs in listOf(9.0, 11.0, 13.44, 16.0, 18.0, 21.4, 25.0, 30.0)) {
            val estimator = MorphologyWaveformEstimator()
            val samples = buildPulsatileSamples(fs = fs, durationSec = 25.0, f0 = 1.2)
            try {
                estimator.update(samples)
            } catch (e: Exception) {
                org.junit.Assert.fail("MorphologyWaveformEstimator.update threw at fs=$fs: $e")
            }
        }
    }
}
