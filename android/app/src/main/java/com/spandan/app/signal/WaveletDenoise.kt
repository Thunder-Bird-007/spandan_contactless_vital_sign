package com.spandan.app.signal

import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.sign
import kotlin.math.sqrt

/**
 * Kotlin port of matlab/src/filtering/waveletDenoise.m (Segment 8, Action 4/[2026-09-13]
 * PROMOTED TO DEFAULT). Same math, read directly from that source before writing this:
 * DWT wavelet-shrinkage denoising via Donoho-Johnstone universal soft-thresholding.
 *
 *   1. Decompose the signal via a 3-level DWT, db4 (Daubechies-4, 8-tap) wavelet.
 *   2. Estimate noise sigma from the FINEST-level (level 1) detail coefficients' median
 *      absolute deviation: sigma = median(abs(d1)) / 0.6745 (the classic Donoho &
 *      Johnstone 1994 "WaveShrink" MAD-to-sigma correction, not re-derived here).
 *   3. Universal threshold: T = sigma * sqrt(2 * log(n)), n = original signal length.
 *   4. Soft-threshold EVERY level's detail coefficients with that one threshold T:
 *      d -> sign(d) * max(abs(d) - T, 0).
 *   5. Leave the coarsest-level approximation coefficients untouched.
 *   6. Reconstruct via inverse DWT.
 *
 * Called from [RealHeartRateEstimator] on each raw R/G/B channel of the rolling window,
 * BEFORE [BandpassFilter.detrend]/[BandpassFilter.apply] -- same relative position as the
 * MATLAB chain (waveletDenoise.m -> detrendSignal.m -> bandpassClean.m).
 *
 * DIFFERENCE FROM THE MATLAB PORT, STATED EXPLICITLY: MATLAB's wavedec/waverec use a
 * symmetric ('sym', half-point) boundary extension internally: this port uses PERIODIC
 * (circular) boundary extension instead, a standard, simpler-to-implement-correctly
 * alternative that still gives an exact, perfectly-invertible orthogonal DWT for the same
 * db4 filter bank (both conventions use the identical filter coefficients and the
 * identical Donoho-Johnstone thresholding math above -- only the edge handling for the
 * last few samples of each level differs). Per this port's own verification task, this
 * does not need to numerically match MATLAB sample-for-sample, only to genuinely denoise
 * -- see WaveletDenoiseSmokeTest for the synthetic before/after RMSE check.
 */
object WaveletDenoise {

    // Standard Daubechies-4 (db4, 8-tap) orthogonal filter bank coefficients -- the same
    // values MATLAB's Wavelet Toolbox and every other standard wavelet library (e.g.
    // PyWavelets' Wavelet('db4').filter_bank) use; not re-derived here.
    private val DEC_LO = doubleArrayOf(
        -0.010597401785069032, 0.032883011666982945, 0.030841381835560764, -0.18703481171888114,
        -0.02798376941698385, 0.6308807679295904, 0.7148465705525415, 0.23037781330885523
    )
    private val DEC_HI = doubleArrayOf(
        -0.23037781330885523, 0.7148465705525415, -0.6308807679295904, -0.02798376941698385,
        0.18703481171888114, 0.030841381835560764, -0.032883011666982945, -0.010597401785069032
    )
    private val REC_LO = DEC_LO.reversedArray()
    private val REC_HI = DEC_HI.reversedArray()

    private const val MAD_TO_SIGMA = 0.6745

    data class Result(val denoised: DoubleArray, val thresholdUsed: Double, val sigmaEstimate: Double)

    /** Convenience overload matching waveletDenoise.m's primary output (sigDenoised only). */
    fun denoise(sig: DoubleArray, numLevels: Int = 3): DoubleArray = denoiseWithStats(sig, numLevels).denoised

    /**
     * Full port, mirroring waveletDenoise.m's [sigDenoised, thresholdUsed, sigmaEstimate]
     * three-output signature.
     */
    fun denoiseWithStats(sig: DoubleArray, numLevels: Int = 3): Result {
        val n = sig.size
        val minLenForLevels = 1 shl numLevels // 2^numLevels
        if (n < minLenForLevels * DEC_LO.size) {
            // Too short to safely run `numLevels` DWT levels with an 8-tap filter --
            // fail soft (same "guard, don't crash on-device" discipline as
            // BandpassFilter.apply's short-window fallback) rather than produce
            // garbage from a decomposition level with almost no samples.
            return Result(sig.copyOf(), 0.0, 0.0)
        }

        // Pad to a multiple of 2^numLevels via edge replication, so every level's
        // signal length divides evenly in two -- avoids any per-level odd-length
        // bookkeeping. Trimmed back to n at the end, same contract as waveletDenoise.m.
        val paddedLen = ((n + minLenForLevels - 1) / minLenForLevels) * minLenForLevels
        val padded = DoubleArray(paddedLen) { if (it < n) sig[it] else sig[n - 1] }

        // --- Forward: numLevels-level DWT, finest detail first. ---
        val details = ArrayList<DoubleArray>(numLevels)
        var approx = padded
        for (level in 1..numLevels) {
            val (a, d) = dwtSingleLevel(approx)
            details.add(d)
            approx = a
        }

        // --- Sigma from the FINEST-level (level 1) detail coefficients' MAD. ---
        val d1 = details[0]
        val sigmaEstimate = median(DoubleArray(d1.size) { abs(d1[it]) }) / MAD_TO_SIGMA

        // --- Universal threshold, n = ORIGINAL (unpadded) signal length. ---
        val thresholdUsed = sigmaEstimate * sqrt(2.0 * ln(n.toDouble()))

        // --- Soft-threshold every level's detail coefficients; approximation left
        // untouched. ---
        val thresholdedDetails = details.map { softThreshold(it, thresholdUsed) }

        // --- Reconstruct. ---
        var recon = approx
        for (level in numLevels downTo 1) {
            recon = idwtSingleLevel(recon, thresholdedDetails[level - 1])
        }

        val denoised = DoubleArray(n) { recon[it] }
        return Result(denoised, thresholdUsed, sigmaEstimate)
    }

    // ---- single-level periodized orthogonal DWT (analysis/synthesis pair) ----

    /** One level of decomposition: circular convolution with DEC_LO/DEC_HI, downsample
     *  by 2. Requires x.size even (guaranteed by the padding in [denoiseWithStats]). */
    private fun dwtSingleLevel(x: DoubleArray): Pair<DoubleArray, DoubleArray> {
        val n = x.size
        val half = n / 2
        val approx = DoubleArray(half)
        val detail = DoubleArray(half)
        for (i in 0 until half) {
            var aSum = 0.0
            var dSum = 0.0
            for (k in DEC_LO.indices) {
                val idx = ((2 * i - k) % n + n) % n
                val xv = x[idx]
                aSum += DEC_LO[k] * xv
                dSum += DEC_HI[k] * xv
            }
            approx[i] = aSum
            detail[i] = dSum
        }
        return approx to detail
    }

    /** Inverse of [dwtSingleLevel]: upsample approx/detail by 2, circular-convolve with
     *  REC_LO/REC_HI, sum. Output length is exactly 2 * approx.size. */
    private fun idwtSingleLevel(approx: DoubleArray, detail: DoubleArray): DoubleArray {
        val n = approx.size * 2
        val recon = DoubleArray(n)
        for (m in 0 until n) {
            var sum = 0.0
            for (k in REC_LO.indices) {
                val idxUp = ((m - k) % n + n) % n
                if (idxUp % 2 == 0) sum += REC_LO[k] * approx[idxUp / 2]
            }
            for (k in REC_HI.indices) {
                val idxUp = ((m - k) % n + n) % n
                if (idxUp % 2 == 0) sum += REC_HI[k] * detail[idxUp / 2]
            }
            recon[m] = sum
        }
        return recon
    }

    // ---- small stats/threshold helpers, private to this file ----

    private fun softThreshold(d: DoubleArray, t: Double): DoubleArray =
        DoubleArray(d.size) { i -> sign(d[i]) * maxOf(abs(d[i]) - t, 0.0) }

    private fun median(x: DoubleArray): Double {
        if (x.isEmpty()) return 0.0
        val sorted = x.copyOf().also { it.sort() }
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2.0 else sorted[mid]
    }
}
