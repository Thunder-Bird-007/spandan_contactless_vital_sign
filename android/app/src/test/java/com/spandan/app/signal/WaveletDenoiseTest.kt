package com.spandan.app.signal

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Plain Kotlin/JUnit test, no Android device needed. Segment 8 Action 4/[2026-09-13
 * PROMOTED TO DEFAULT] Action 5 verification: same "verify before trusting on real
 * data" discipline as BandpassFilterTest and the MATLAB side's own smoke test
 * (waveletDenoise.m's header: RMSE-vs-clean dropped 0.3185 -> 0.1968 on a synthetic
 * 1.2Hz sinusoid + Gaussian noise signal).
 *
 * This port does not need to match that MATLAB RMSE number exactly (different
 * boundary handling -- see WaveletDenoise.kt's header) but MUST show a real
 * reduction in noisy-vs-clean RMSE, not a no-op.
 */
class WaveletDenoiseTest {

    private fun rmse(a: DoubleArray, b: DoubleArray): Double {
        var sumSq = 0.0
        for (i in a.indices) {
            val e = a[i] - b[i]
            sumSq += e * e
        }
        return sqrt(sumSq / a.size)
    }

    @Test
    fun denoiseReducesRmseAgainstCleanSignal() {
        val fs = 30.0
        val durationSeconds = 20.0
        val n = (fs * durationSeconds).toInt()
        val freqHz = 1.2 // ~72bpm, matching the MATLAB smoke test's own signal

        val rng = Random(42)
        val clean = DoubleArray(n) { i -> sin(2 * PI * freqHz * i / fs) }
        // Gaussian noise via Box-Muller, std dev 0.3 -- same order of magnitude as the
        // MATLAB smoke test's own noisy-signal RMSE-vs-clean (0.3185).
        val noisy = DoubleArray(n) { i ->
            val u1 = rng.nextDouble().coerceIn(1e-12, 1.0)
            val u2 = rng.nextDouble()
            val gaussian = sqrt(-2.0 * kotlin.math.ln(u1)) * kotlin.math.cos(2 * PI * u2)
            clean[i] + 0.3 * gaussian
        }

        val denoised = WaveletDenoise.denoise(noisy)

        val rmseBefore = rmse(noisy, clean)
        val rmseAfter = rmse(denoised, clean)

        println("WaveletDenoiseTest: RMSE-vs-clean before=$rmseBefore after=$rmseAfter")

        assertTrue(
            "Expected a real RMSE reduction from wavelet denoising (before=$rmseBefore, after=$rmseAfter)",
            rmseAfter < rmseBefore
        )
    }

    @Test
    fun denoiseIsNotANoOp() {
        val n = 256
        val rng = Random(7)
        val signal = DoubleArray(n) { rng.nextDouble() * 2.0 - 1.0 }

        val result = WaveletDenoise.denoiseWithStats(signal)

        assertTrue("Expected a positive threshold on random noise", result.thresholdUsed > 0.0)
        assertTrue("Expected a positive sigma estimate", result.sigmaEstimate > 0.0)

        var changed = false
        for (i in signal.indices) {
            if (kotlin.math.abs(signal[i] - result.denoised[i]) > 1e-9) {
                changed = true
                break
            }
        }
        assertTrue("Expected denoise() to actually change a noisy signal, not pass it through unchanged", changed)
    }
}
