package com.spandan.app.signal

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

class AdaptiveHarmonicFilterTest {

    private fun rms(x: DoubleArray): Double = sqrt(x.sumOf { it * it } / x.size)

    @Test
    fun keepsEnergyAtFundamentalAndSecondHarmonicButRejectsInterHarmonicNoise() {
        val fs = 30.0
        val n = (fs * 20).toInt()
        val f0 = 1.2 // 72bpm

        // A cardiac-like signal (f0 + 2*f0) PLUS a strong interference tone
        // sitting between the fundamental and 2nd harmonic (not a multiple of f0).
        val interferenceHz = 1.8
        val signal = DoubleArray(n) { i ->
            val t = i / fs
            sin(2 * PI * f0 * t) + 0.5 * sin(2 * PI * 2 * f0 * t) + 2.0 * sin(2 * PI * interferenceHz * t)
        }

        val result = AdaptiveHarmonicFilter.apply(signal, fs, numHarmonics = 6, f0HzOverride = f0)

        // Reconstruct what a pure f0+2f0 cardiac signal (no interference)
        // would look like, and compare the comb's output against it -- the
        // comb should be MUCH closer to the clean cardiac signal than the
        // raw (interference-dominated) input is.
        val cleanCardiac = DoubleArray(n) { i ->
            val t = i / fs
            sin(2 * PI * f0 * t) + 0.5 * sin(2 * PI * 2 * f0 * t)
        }

        fun rmsError(a: DoubleArray, b: DoubleArray): Double {
            var s = 0.0
            for (i in a.indices) { val d = a[i] - b[i]; s += d * d }
            return sqrt(s / a.size)
        }

        val errorBefore = rmsError(signal, cleanCardiac)
        val errorAfter = rmsError(result.filtered, cleanCardiac)

        assertTrue(
            "expected the harmonic comb to reject the 1.8Hz interference and recover the cardiac shape " +
                "(errorBefore=$errorBefore, errorAfter=$errorAfter)",
            errorAfter < errorBefore * 0.5
        )
    }

    @Test
    fun harmonicsUsedHzStopsAtNyquist() {
        val fs = 10.0 // Nyquist = 5Hz
        val n = 300
        val f0 = 1.0
        val signal = DoubleArray(n) { sin(2 * PI * f0 * it / fs) }
        val result = AdaptiveHarmonicFilter.apply(signal, fs, numHarmonics = 10, f0HzOverride = f0)
        // Harmonics 1..4 (1,2,3,4Hz) are below Nyquist(5Hz); 5Hz is AT Nyquist
        // (round(5/freqRes) could land exactly on the Nyquist bin depending on
        // freqResolution -- assert the used list never exceeds Nyquist, not an
        // exact count, since freqResolution depends on n/fs).
        assertTrue(result.harmonicsUsedHz.isNotEmpty())
        for (h in result.harmonicsUsedHz) assertTrue("harmonic $h exceeds Nyquist", h <= fs / 2.0 + 1e-9)
    }

    @Test
    fun outputIsFiniteAndSameLengthAsInput() {
        val fs = 25.0
        val n = 400
        val signal = DoubleArray(n) { sin(2 * PI * 1.3 * it / fs) }
        val result = AdaptiveHarmonicFilter.apply(signal, fs, f0HzOverride = 1.3)
        assertTrue(result.filtered.size == n)
        for (v in result.filtered) assertTrue(v.isFinite())
    }
}
