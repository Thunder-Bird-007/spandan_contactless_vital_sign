package com.spandan.app.signal

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

class HarmonicSelectiveGaussianFilterTest {

    @Test
    fun rejectsFarInterferenceLikeTheHardComb() {
        val fs = 30.0
        val n = (fs * 20).toInt()
        val f0 = 1.2
        val interferenceHz = 1.8

        val signal = DoubleArray(n) { i ->
            val t = i / fs
            sin(2 * PI * f0 * t) + 0.5 * sin(2 * PI * 2 * f0 * t) + 2.0 * sin(2 * PI * interferenceHz * t)
        }
        val cleanCardiac = DoubleArray(n) { i ->
            val t = i / fs
            sin(2 * PI * f0 * t) + 0.5 * sin(2 * PI * 2 * f0 * t)
        }

        fun rmsError(a: DoubleArray, b: DoubleArray): Double {
            var s = 0.0
            for (i in a.indices) { val d = a[i] - b[i]; s += d * d }
            return sqrt(s / a.size)
        }

        val result = HarmonicSelectiveGaussianFilter.apply(signal, fs, numHarmonics = 6, f0HzOverride = f0, alpha = 0.15)
        val errorBefore = rmsError(signal, cleanCardiac)
        val errorAfter = rmsError(result.filtered, cleanCardiac)

        assertTrue(
            "expected the Gaussian harmonic filter to reject far interference too (errorBefore=$errorBefore, errorAfter=$errorAfter)",
            errorAfter < errorBefore * 0.5
        )
    }

    @Test
    fun widerAlphaPassesMoreOfANearbyToneThanNarrowerAlpha() {
        val fs = 30.0
        val n = (fs * 20).toInt()
        val f0 = 1.2
        // A tone close to (but not exactly at) 2*f0 -- a wide sigma (alpha=0.5)
        // should pass more of it through than a narrow sigma (alpha=0.15).
        val nearSecondHarmonicHz = 2 * f0 + 0.3
        val signal = DoubleArray(n) { i -> sin(2 * PI * nearSecondHarmonicHz * i / fs) }

        val narrow = HarmonicSelectiveGaussianFilter.apply(signal, fs, numHarmonics = 6, f0HzOverride = f0, alpha = 0.15)
        val wide = HarmonicSelectiveGaussianFilter.apply(signal, fs, numHarmonics = 6, f0HzOverride = f0, alpha = 0.5)

        fun rms(x: DoubleArray) = sqrt(x.sumOf { it * it } / x.size)

        assertTrue(
            "expected alpha=0.5 to pass more energy of a near-2f0 tone than alpha=0.15",
            rms(wide.filtered) > rms(narrow.filtered)
        )
    }

    @Test
    fun outputIsFiniteAndSameLengthAsInput() {
        val fs = 25.0
        val n = 400
        val signal = DoubleArray(n) { sin(2 * PI * 1.3 * it / fs) }
        val result = HarmonicSelectiveGaussianFilter.apply(signal, fs, f0HzOverride = 1.3)
        assertTrue(result.filtered.size == n)
        for (v in result.filtered) assertTrue(v.isFinite())
    }
}
