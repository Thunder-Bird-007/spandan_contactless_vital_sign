package com.spandan.app.signal

/**
 * Segment 19 (Branch 2 morphology port) -- shared-Fritsch-Carlson PCHIP
 * (Piecewise Cubic Hermite Interpolating Polynomial) interpolator, matching
 * MATLAB's `interp1(x, y, xq, 'pchip')` / `pchip(x, y, xq)` convention. Used
 * by [ResampleUniform] (port of `morphology/resampleUniform.m`),
 * [EnsembleAverageBeats] (port of `morphology/ensembleAverageBeats.m`'s own
 * per-beat resample + time-warp `interp1(...,'pchip')` calls), and
 * [NotchDetectIEM] (port of `morphology/notchDetectIEM.m`'s envelope
 * `interp1(...,'pchip')` calls).
 *
 * WHY PCHIP SPECIFICALLY (same reasoning `resampleUniform.m`'s own header
 * gives): unlike a cubic spline, PCHIP is shape-preserving -- it does not
 * overshoot between input samples near a sharp feature. The dicrotic notch
 * is exactly that kind of sharp feature; a spline's overshoot could
 * fabricate a fake notch-like ripple that was never in the original signal.
 *
 * Algorithm: Fritsch & Carlson (1980)'s monotonicity-preserving derivative
 * estimate at each knot (weighted harmonic mean of the two adjacent secant
 * slopes when they agree in sign, zero when they don't -- this is what
 * prevents overshoot), then a standard cubic Hermite evaluation between
 * knots. This is the same construction MATLAB's own `pchip`/`interp1(...,
 * 'pchip')` documents itself as using -- not independently derived math, a
 * standard, named algorithm.
 */
object PchipInterpolator {

    /**
     * Interpolates [y] (sampled at strictly increasing [x]) at each point in
     * [xq], via PCHIP. [xq] need not be sorted or evenly spaced; any [xq]
     * value outside `[x.first(), x.last()]` is clamped to the nearest
     * endpoint (extrapolation is not needed anywhere this project uses
     * PCHIP -- every caller queries strictly inside the knot range).
     */
    fun interpolate(x: DoubleArray, y: DoubleArray, xq: DoubleArray): DoubleArray {
        val n = x.size
        require(n >= 2) { "PCHIP needs at least 2 knots (got $n)" }
        require(y.size == n) { "x and y must have the same length" }

        if (n == 2) {
            // Degenerate case: a single segment is just linear interpolation
            // (Hermite with zero curvature reduces to this when there's only
            // one secant slope to work with).
            val slope = (y[1] - y[0]) / (x[1] - x[0])
            return DoubleArray(xq.size) { i ->
                val t = xq[i].coerceIn(x[0], x[1])
                y[0] + slope * (t - x[0])
            }
        }

        val h = DoubleArray(n - 1) { i -> x[i + 1] - x[i] }
        require(h.all { it > 0.0 }) { "x must be strictly increasing" }
        val delta = DoubleArray(n - 1) { i -> (y[i + 1] - y[i]) / h[i] }

        val d = DoubleArray(n)
        // Interior derivatives: Fritsch-Carlson weighted harmonic mean,
        // zero at a local extremum (sign change in the secant slopes) --
        // THIS is the property that prevents overshoot.
        for (i in 1 until n - 1) {
            d[i] = if (delta[i - 1] * delta[i] <= 0.0) {
                0.0
            } else {
                val w1 = 2.0 * h[i] + h[i - 1]
                val w2 = h[i] + 2.0 * h[i - 1]
                (w1 + w2) / (w1 / delta[i - 1] + w2 / delta[i])
            }
        }
        // Endpoint derivatives: one-sided three-point estimate, clipped to
        // preserve shape (standard PCHIP end-condition, matches MATLAB).
        d[0] = endpointDerivative(h[0], h[1], delta[0], delta[1])
        d[n - 1] = endpointDerivative(h[n - 2], h[n - 3], delta[n - 2], delta[n - 3])

        val xMin = x[0]
        val xMax = x[n - 1]

        return DoubleArray(xq.size) { qi ->
            val t = xq[qi].coerceIn(xMin, xMax)
            // Binary search for the segment containing t (x is sorted ascending).
            var lo = 0
            var hi = n - 2
            while (lo < hi) {
                val mid = (lo + hi + 1) / 2
                if (x[mid] <= t) lo = mid else hi = mid - 1
            }
            val i = lo
            val hi_ = h[i]
            val s = (t - x[i]) / hi_
            val s2 = s * s
            val s3 = s2 * s
            // Cubic Hermite basis functions.
            val h00 = 2.0 * s3 - 3.0 * s2 + 1.0
            val h10 = s3 - 2.0 * s2 + s
            val h01 = -2.0 * s3 + 3.0 * s2
            val h11 = s3 - s2
            h00 * y[i] + h10 * hi_ * d[i] + h01 * y[i + 1] + h11 * hi_ * d[i + 1]
        }
    }

    private fun endpointDerivative(h0: Double, h1: Double, delta0: Double, delta1: Double): Double {
        var d0 = ((2.0 * h0 + h1) * delta0 - h0 * delta1) / (h0 + h1)
        if (sign(d0) != sign(delta0)) {
            d0 = 0.0
        } else if (sign(delta0) != sign(delta1) && kotlin.math.abs(d0) > kotlin.math.abs(3.0 * delta0)) {
            d0 = 3.0 * delta0
        }
        return d0
    }

    private fun sign(v: Double): Int = when {
        v > 0.0 -> 1
        v < 0.0 -> -1
        else -> 0
    }
}
