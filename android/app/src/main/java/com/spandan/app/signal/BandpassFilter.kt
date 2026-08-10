package com.spandan.app.signal

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Real port of matlab/src/filtering/detrendSignal.m + matlab/src/filtering/bandpassClean.m
 * (both read directly from source before writing this, not from memory/description).
 *
 * MATLAB source, exact parameters confirmed:
 *   detrendSignal.m:  detrendOrder = 3;  signalDetrended = detrend(signalRaw, 3)
 *   bandpassClean.m:  filterOrder = 2;   lowCutoffHz = 0.7;  highCutoffHz = 4.0;
 *                      cutoffs normalized by frameRate/2 (Nyquist);
 *                      [b,a] = butter(2, [lowN highN], 'bandpass');
 *                      signalFiltered = filtfilt(b, a, signalDetrended)
 *   (effective filter order after filtfilt's forward+reverse pass is 2x the
 *   butter() order, i.e. 4th order overall -- matches bandpassClean.m's own KDoc.)
 *
 * "frameRate" in MATLAB == fs here, ALWAYS derived from real sample timestamps by
 * the caller (RealHeartRateEstimator), never hardcoded -- same discipline the
 * MATLAB side needed because UBFC subjects varied ~28.6-29.8fps; a live camera
 * varies similarly by device/lighting.
 */
object BandpassFilter {

    const val LOW_HZ = 0.7
    const val HIGH_HZ = 4.0
    const val ORDER = 2

    /**
     * Cubic-polynomial detrend, matching detrendSignal.m's `detrend(x, 3)`: fit a
     * degree-3 polynomial (least squares) against sample position and subtract it.
     *
     * Fitted against position normalized to [-1, 1] rather than raw 1..N for
     * numerical conditioning -- a polynomial least-squares fit is invariant to an
     * affine reparametrization of the x-axis, so the trend actually removed at each
     * sample is identical to MATLAB's regardless of which x-axis convention is used.
     */
    fun detrend(x: DoubleArray, order: Int = 3): DoubleArray {
        val n = x.size
        if (n <= order) return x.copyOf()
        val t = DoubleArray(n) { i -> if (n == 1) 0.0 else -1.0 + 2.0 * i / (n - 1) }
        val coeffs = polyfitLeastSquares(t, x, order)
        return DoubleArray(n) { i -> x[i] - evalPoly(coeffs, t[i]) }
    }

    /** Zero-phase Butterworth bandpass, matching bandpassClean.m exactly (order 2,
     *  0.7-4Hz, filtfilt) against a RUNTIME-MEASURED fs. Batch operation over the
     *  whole array passed in -- not a causal/streaming filter, same as MATLAB's
     *  offline filtfilt call, since zero-phase response requires seeing the whole
     *  window at once. */
    fun apply(x: DoubleArray, fs: Double): DoubleArray {
        if (fs <= 2.0 * HIGH_HZ) {
            // Nyquist too low for the 4Hz upper cutoff -- caller (RealHeartRateEstimator)
            // should already guard against this; fail soft rather than throw on-device.
            return x.copyOf()
        }
        val (b, a) = designButterworthBandpass(ORDER, LOW_HZ, HIGH_HZ, fs)
        return filtfilt(b, a, x)
    }

    // ---- Butterworth bandpass design: bilinear transform of the analog prototype ----
    // Mirrors the classic analog-lowpass-prototype -> lowpass-to-bandpass transform ->
    // bilinear-transform (with prewarping) -> zpk2tf chain that both MATLAB's butter()
    // and scipy's butter() use internally for digital bandpass design.

    fun designButterworthBandpass(order: Int, lowHz: Double, highHz: Double, fs: Double): Pair<DoubleArray, DoubleArray> {
        val nyquist = fs / 2.0
        val wn1 = lowHz / nyquist
        val wn2 = highHz / nyquist
        require(wn1 > 0.0 && wn2 < 1.0 && wn1 < wn2) {
            "Bandpass cutoffs [$lowHz,$highHz]Hz out of range for fs=$fs (need fs > ${2 * highHz})"
        }

        // Classic bilinear-transform normalization constant (Wn is already normalized
        // so Nyquist == 1; this "fs=2" is the standard analog<->digital frequency-
        // warping convention here, not the real camera sample rate).
        val fsInternal = 2.0
        val warped1 = 2.0 * fsInternal * tan(PI * wn1 / fsInternal)
        val warped2 = 2.0 * fsInternal * tan(PI * wn2 / fsInternal)
        val wo = sqrt(warped1 * warped2)
        val bw = warped2 - warped1

        // Analog Butterworth lowpass prototype poles (cutoff 1 rad/s, unity gain, no zeros).
        val protoPoles = (0 until order).map { k ->
            val m = (-order + 1 + 2 * k).toDouble()
            val angle = PI * m / (2.0 * order)
            Complex(-cos(angle), -sin(angle))
        }

        // Lowpass -> bandpass analog transform: doubles the pole count, adds `order`
        // zeros at s=0.
        val pLp = protoPoles.map { it * (bw / 2.0) }
        val bpPoles = mutableListOf<Complex>()
        for (p in pLp) {
            val disc = (p * p) - Complex.real(wo * wo)
            val root = disc.sqrtC()
            bpPoles += p + root
            bpPoles += p - root
        }
        val bpZeros = List(order) { Complex.ZERO }
        val kBp = Math.pow(bw, order.toDouble()) // prototype gain was 1

        // Bilinear transform (analog -> digital), fs2 = 2*fsInternal.
        val fs2 = Complex.real(2.0 * fsInternal)
        val zDigital = bpZeros.map { z -> (fs2 + z) / (fs2 - z) }.toMutableList()
        val pDigital = bpPoles.map { p -> (fs2 + p) / (fs2 - p) }
        val degree = bpPoles.size - bpZeros.size // = order; zeros "at infinity" -> z = -1
        repeat(degree) { zDigital += Complex(-1.0, 0.0) }

        var gainNum = Complex.real(1.0)
        for (z in bpZeros) gainNum = gainNum * (fs2 - z)
        var gainDen = Complex.real(1.0)
        for (p in bpPoles) gainDen = gainDen * (fs2 - p)
        val kDigital = kBp * (gainNum / gainDen).re

        val bCoeffs = polyFromRoots(zDigital).map { it.re * kDigital }.toDoubleArray()
        val aCoeffs = polyFromRoots(pDigital).map { it.re }.toDoubleArray()
        return bCoeffs to aCoeffs
    }

    // ---- IIR filtering: lfilter (Direct Form II Transposed) + filtfilt ----

    /** Single causal IIR pass, Direct Form II Transposed, zero initial state
     *  (matches scipy/MATLAB's `filter(b, a, x)` with default zero ICs). */
    fun lfilter(b: DoubleArray, a: DoubleArray, x: DoubleArray): DoubleArray {
        val n = maxOf(b.size, a.size)
        val bn = DoubleArray(n) { if (it < b.size) b[it] else 0.0 }
        val an = DoubleArray(n) { if (it < a.size) a[it] else 0.0 }
        val a0 = an[0]
        val y = DoubleArray(x.size)
        val z = DoubleArray(n - 1)
        for (i in x.indices) {
            val xi = x[i]
            val yi = (bn[0] * xi + (if (n > 1) z[0] else 0.0)) / a0
            for (j in 0 until n - 2) {
                z[j] = bn[j + 1] * xi + z[j + 1] - an[j + 1] * yi
            }
            if (n > 1) z[n - 2] = bn[n - 1] * xi - an[n - 1] * yi
            y[i] = yi
        }
        return y
    }

    /** filtfilt-equivalent: forward pass, reverse, forward pass again, reverse back --
     *  zero-phase response, matching MATLAB's filtfilt. Uses odd-reflection edge
     *  padding (same default MATLAB/scipy use) to suppress startup transients. Runs
     *  over the WHOLE array passed in, batch, not sample-by-sample. */
    fun filtfilt(b: DoubleArray, a: DoubleArray, x: DoubleArray): DoubleArray {
        val n = x.size
        val edge = 3 * (maxOf(b.size, a.size) - 1)
        if (n <= edge) {
            // Too short to safely pad/filter zero-phase -- fail soft with a single
            // causal pass rather than crash on-device on an early, small window.
            return lfilter(b, a, x)
        }

        val padded = DoubleArray(n + 2 * edge)
        for (i in 0 until edge) padded[i] = 2 * x[0] - x[edge - i]
        for (i in 0 until n) padded[edge + i] = x[i]
        for (i in 0 until edge) padded[edge + n + i] = 2 * x[n - 1] - x[n - 2 - i]

        val forward = lfilter(b, a, padded)
        val backward = lfilter(b, a, forward.reversedArray())
        val result = backward.reversedArray()

        return result.copyOfRange(edge, edge + n)
    }

    // ---- small linear-algebra/complex helpers, private to this file ----

    private data class Complex(val re: Double, val im: Double) {
        operator fun plus(o: Complex) = Complex(re + o.re, im + o.im)
        operator fun minus(o: Complex) = Complex(re - o.re, im - o.im)
        operator fun times(o: Complex) = Complex(re * o.re - im * o.im, re * o.im + im * o.re)
        operator fun times(s: Double) = Complex(re * s, im * s)
        operator fun div(o: Complex): Complex {
            val denom = o.re * o.re + o.im * o.im
            return Complex((re * o.re + im * o.im) / denom, (im * o.re - re * o.im) / denom)
        }
        fun sqrtC(): Complex {
            val r = sqrt(re * re + im * im)
            val reOut = sqrt(max(0.0, (r + re) / 2.0))
            var imOut = sqrt(max(0.0, (r - re) / 2.0))
            if (im < 0.0) imOut = -imOut
            return Complex(reOut, imOut)
        }
        companion object {
            val ZERO = Complex(0.0, 0.0)
            fun real(x: Double) = Complex(x, 0.0)
        }
    }

    private fun convolve(a: List<Complex>, b: List<Complex>): List<Complex> {
        val result = MutableList(a.size + b.size - 1) { Complex.ZERO }
        for (i in a.indices) for (j in b.indices) {
            result[i + j] = result[i + j] + a[i] * b[j]
        }
        return result
    }

    /** Coefficients (highest degree first, monic) of the polynomial with the given
     *  roots -- e.g. for z-domain zeros/poles this gives the b0..bN / a0..aN
     *  ordering that `lfilter`/`filtfilt` expect directly. */
    private fun polyFromRoots(roots: List<Complex>): List<Complex> {
        var coeffs: List<Complex> = listOf(Complex(1.0, 0.0))
        for (r in roots) {
            coeffs = convolve(coeffs, listOf(Complex(1.0, 0.0), Complex(-r.re, -r.im)))
        }
        return coeffs
    }

    private fun polyfitLeastSquares(t: DoubleArray, y: DoubleArray, degree: Int): DoubleArray {
        val m = degree + 1
        val ata = Array(m) { DoubleArray(m) }
        val aty = DoubleArray(m)
        for (i in t.indices) {
            val powers = DoubleArray(m)
            var p = 1.0
            for (k in 0 until m) { powers[k] = p; p *= t[i] }
            for (r in 0 until m) {
                aty[r] += powers[r] * y[i]
                for (c in 0 until m) ata[r][c] += powers[r] * powers[c]
            }
        }
        return solveLinearSystem(ata, aty)
    }

    private fun solveLinearSystem(a: Array<DoubleArray>, bVec: DoubleArray): DoubleArray {
        val n = bVec.size
        val m = Array(n) { i -> DoubleArray(n + 1) { j -> if (j < n) a[i][j] else bVec[i] } }
        for (col in 0 until n) {
            var pivotRow = col
            for (r in col + 1 until n) if (abs(m[r][col]) > abs(m[pivotRow][col])) pivotRow = r
            val tmp = m[col]; m[col] = m[pivotRow]; m[pivotRow] = tmp
            val pivotVal = m[col][col]
            if (abs(pivotVal) < 1e-12) continue // degenerate (e.g. near-constant signal); leave row as-is
            for (c in col until n + 1) m[col][c] /= pivotVal
            for (r in 0 until n) {
                if (r == col) continue
                val factor = m[r][col]
                for (c in col until n + 1) m[r][c] -= factor * m[col][c]
            }
        }
        return DoubleArray(n) { i -> m[i][n] }
    }

    private fun evalPoly(coeffsAscending: DoubleArray, t: Double): Double {
        var result = 0.0
        var p = 1.0
        for (c in coeffsAscending) { result += c * p; p *= t }
        return result
    }
}
