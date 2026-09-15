package com.spandan.app.signal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.exp
import kotlin.random.Random

class EnsembleAverageBeatsTest {

    /** One asymmetric cardiac-like cycle (fast rise, slower decay), given a
     *  fraction-of-cycle in [0,1). */
    private fun beatShape(frac: Double): Double =
        if (frac < 0.25) frac / 0.25 else exp(-(frac - 0.25) * 3.0)

    private fun buildBeatTrain(fs: Double, durationSec: Double, periodSec: Double, noiseStd: Double, rng: Random): DoubleArray {
        val n = (fs * durationSec).toInt()
        return DoubleArray(n) { i ->
            val t = i / fs
            val frac = (t % periodSec) / periodSec
            beatShape(frac) + noiseStd * (rng.nextDouble() - 0.5)
        }
    }

    @Test
    fun findsRoughlyTheExpectedBeatCountAndRecoversTheBeatShape() {
        val fs = 250.0 // matches ResampleUniform's own default target grid
        val durationSec = 20.0
        val periodSec = 0.8 // 75bpm
        val rng = Random(11)
        // Small noise -- large enough to be a real (not zero) perturbation,
        // small enough not to dominate the deterministic per-sample slope
        // right at the negative-going zero crossing (which would cause
        // spurious extra crossings/"chattering", a test-construction
        // artifact this project's real camera signal -- already band-
        // limited by the harmonic-comb/Gaussian filter before reaching
        // this function -- would not exhibit at anywhere near this density).
        val sig = buildBeatTrain(fs, durationSec, periodSec, noiseStd = 0.005, rng = rng)

        val result = EnsembleAverageBeats.apply(sig, fs)

        val expectedBeats = (durationSec / periodSec).toInt()
        assertTrue(
            "expected beatsFound near $expectedBeats, got ${result.stats.beatsFound}",
            kotlin.math.abs(result.stats.beatsFound - expectedBeats) <= 2
        )
        assertTrue(result.stats.beatsAveraged > 0)
        assertEquals(result.stats.beatsAveraged, result.beatMatrix.size)
        assertEquals(256, result.prototype.trimmedMean.size)

        // NOTE on why this checks shape qualitatively rather than by direct
        // correlation against `beatShape` sampled at [0,1): beat segmentation
        // happens on a NEGATIVE-GOING ZERO CROSSING, which for this synthetic
        // shape falls partway through the decay limb (not at this test's own
        // frac=0 rise-start convention) -- so each extracted, then time-
        // warped, beat is a ROTATED version of `beatShape`, not a
        // fraction-for-fraction match. That rotation is expected, correct
        // behavior of the port (matching `ensembleAverageBeats.m`'s own
        // documented method), not a bug -- so this test checks the two
        // properties the two-anchor time warp actually GUARANTEES instead:
        // the peak lands at (approximately) `systolicAnchorFraction` (0.25),
        // and the shape around it still looks like a real beat (fast rise
        // into the peak, decay after it), not `beatShape` at literal index i.
        val trimmedMean = result.prototype.trimmedMean
        var peakIdx = 0
        var peakVal = trimmedMean[0]
        for (i in 1 until trimmedMean.size) if (trimmedMean[i] > peakVal) { peakVal = trimmedMean[i]; peakIdx = i }
        val peakFrac = peakIdx / (trimmedMean.size - 1.0)
        assertTrue(
            "expected the time-warped peak near the 0.25 anchor fraction, got $peakFrac",
            kotlin.math.abs(peakFrac - 0.25) < 0.08
        )
        assertTrue("expected a decay after the peak", trimmedMean[peakIdx] > trimmedMean[trimmedMean.size - 1])
        assertTrue("expected a rise into the peak", trimmedMean[peakIdx] > trimmedMean[0])
    }

    @Test
    fun throwsWhenFarTooFewBeatsArePresent() {
        val fs = 50.0
        val sig = DoubleArray(30) { it.toDouble() } // way too short for even one full beat cycle at 50Hz
        var threw = false
        try {
            EnsembleAverageBeats.apply(sig, fs)
        } catch (e: IllegalStateException) {
            threw = true
        }
        assertTrue(threw)
    }
}
