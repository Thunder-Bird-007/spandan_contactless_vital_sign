package com.spandan.app.signal

import org.jtransforms.fft.DoubleFFT_1D
import kotlin.math.exp

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/harmonicSelectiveGaussianFilter.m` (read directly
 * from source before writing this): [AdaptiveHarmonicFilter]'s hard-edged
 * rectangular comb, but with Gaussian-tapered (no hard edge, no
 * Gibbs-ringing) passbands centered on the cardiac fundamental and its
 * harmonics. Reference: Dominguez-Hernandez, Paez & Padilla, "Harmonic-
 * Selective Gaussian Filtering...", Sensors 26(12):3710 (2026),
 * doi:10.3390/s26123710.
 *
 * This is the MATLAB side's own PRODUCTION FALLBACK candidate (used by
 * `morphology/harmonicFilterConfidenceGate.m` at alpha=0.15 wherever
 * [AdaptiveHarmonicFilter]'s own notch confidence fails this project's 0.3
 * bar) -- see [HarmonicFilterConfidenceGate.kt] for the gate this file
 * feeds. NOT a standalone default; only ever invoked from behind that gate,
 * matching `pipeline/estimateVitalsAndMorphology.m`'s own
 * `opts.useConfidenceGate` design exactly.
 */
object HarmonicSelectiveGaussianFilter {

    data class Result(val filtered: DoubleArray, val f0Hz: Double, val harmonicsUsedHz: List<Double>)

    /**
     * @param alpha bandwidth scaling (sigma = alpha*f0). 0.15 is this
     *   project's own validated production value (Segment 13), NOT the
     *   paper's own default of 0.5 -- see
     *   `matlab/docs/Segment13_Task1_Gaussian_Regression_Root_Cause_and_Gate.md`.
     *   Exposed as a parameter, not hardcoded, matching the MATLAB source's
     *   own convention.
     */
    fun apply(
        sigDetrended: DoubleArray,
        frameRate: Double,
        numHarmonics: Int = 6,
        f0HzOverride: Double? = null,
        alpha: Double = 0.15
    ): Result {
        val sigRow = sigDetrended
        val n = sigRow.size

        val f0Hz = f0HzOverride ?: (
            HeartRateFft.estimateBpm(sigRow, frameRate)?.bpm?.div(60.0)
                ?: error("HarmonicSelectiveGaussianFilter: no FFT bin fell inside the 0.7-4Hz band; caller must supply f0HzOverride")
            )

        val sigma = alpha * f0Hz
        require(sigma > 0.0) { "alpha*f0Hz must be positive (alpha=$alpha, f0Hz=$f0Hz)" }
        val sigmaSq = sigma * sigma

        val freqResolution = frameRate / n
        val nyquistHz = frameRate / 2.0

        // Signed frequency axis (0-based, matching MATLAB's 0:N-1 binIdx,
        // folded to negative frequency above Nyquist) -- same convention the
        // MATLAB source builds by hand.
        val freqAxis = DoubleArray(n) { k ->
            val f = k * freqResolution
            if (f > nyquistHz) f - frameRate else f
        }

        val mask = DoubleArray(n)
        val harmonicsUsedHz = mutableListOf<Double>()

        for (h in 1..numHarmonics) {
            val harmonicFreqHz = h * f0Hz
            if (harmonicFreqHz <= nyquistHz) harmonicsUsedHz.add(harmonicFreqHz)
            for (k in 0 until n) {
                val fMinus = freqAxis[k] - harmonicFreqHz
                val fPlus = freqAxis[k] + harmonicFreqHz
                mask[k] += exp(-(fMinus * fMinus) / sigmaSq) + exp(-(fPlus * fPlus) / sigmaSq)
            }
        }

        val complexData = DoubleArray(2 * n)
        for (i in 0 until n) complexData[2 * i] = sigRow[i]
        DoubleFFT_1D(n.toLong()).complexForward(complexData)

        val filteredComplex = DoubleArray(2 * n)
        for (k in 0 until n) {
            filteredComplex[2 * k] = complexData[2 * k] * mask[k]
            filteredComplex[2 * k + 1] = complexData[2 * k + 1] * mask[k]
        }
        DoubleFFT_1D(n.toLong()).complexInverse(filteredComplex, true)

        val filtered = DoubleArray(n) { i -> filteredComplex[2 * i] } // real part -- mask is symmetric by construction
        return Result(filtered, f0Hz, harmonicsUsedHz)
    }
}
