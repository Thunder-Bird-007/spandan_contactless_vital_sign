import Foundation

/// Shape-preserving PCHIP (Piecewise Cubic Hermite Interpolating Polynomial)
/// interpolator, matching MATLAB's `interp1(x, y, xq, 'pchip')` convention.
/// Direct port of android/app/.../signal/PchipInterpolator.kt (read
/// directly before writing this).
///
/// Used by `ResampleUniform`, `EnsembleAverageBeats`, and `NotchDetectIEM`.
///
/// WHY PCHIP SPECIFICALLY (same reasoning the Android port's own header
/// gives): unlike a cubic spline, PCHIP is shape-preserving -- it does not
/// overshoot between input samples near a sharp feature. The dicrotic notch
/// is exactly that kind of sharp feature; a spline's overshoot could
/// fabricate a fake notch-like ripple that was never in the original signal.
///
/// Algorithm: Fritsch & Carlson (1980)'s monotonicity-preserving derivative
/// estimate at each knot (weighted harmonic mean of the two adjacent secant
/// slopes when they agree in sign, zero when they don't), then a standard
/// cubic Hermite evaluation between knots.
enum PchipInterpolator {

    /// Interpolates `y` (sampled at strictly increasing `x`) at each point
    /// in `xq`, via PCHIP. `xq` need not be sorted or evenly spaced; any
    /// `xq` value outside `[x.first, x.last]` is clamped to the nearest
    /// endpoint.
    static func interpolate(_ x: [Double], _ y: [Double], _ xq: [Double]) -> [Double] {
        let n = x.count
        precondition(n >= 2, "PCHIP needs at least 2 knots (got \(n))")
        precondition(y.count == n, "x and y must have the same length")

        if n == 2 {
            // Degenerate case: a single segment is just linear interpolation.
            let slope = (y[1] - y[0]) / (x[1] - x[0])
            return xq.map { xqi in
                let t = min(max(xqi, x[0]), x[1])
                return y[0] + slope * (t - x[0])
            }
        }

        var h = [Double](repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) { h[i] = x[i + 1] - x[i] }
        precondition(h.allSatisfy { $0 > 0.0 }, "x must be strictly increasing")
        var delta = [Double](repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) { delta[i] = (y[i + 1] - y[i]) / h[i] }

        var d = [Double](repeating: 0.0, count: n)
        // Interior derivatives: Fritsch-Carlson weighted harmonic mean, zero
        // at a local extremum (sign change in the secant slopes) -- THIS is
        // the property that prevents overshoot.
        for i in 1..<(n - 1) {
            if delta[i - 1] * delta[i] <= 0.0 {
                d[i] = 0.0
            } else {
                let w1 = 2.0 * h[i] + h[i - 1]
                let w2 = h[i] + 2.0 * h[i - 1]
                d[i] = (w1 + w2) / (w1 / delta[i - 1] + w2 / delta[i])
            }
        }
        // Endpoint derivatives: one-sided three-point estimate, clipped to
        // preserve shape (standard PCHIP end-condition, matches MATLAB).
        d[0] = endpointDerivative(h0: h[0], h1: h[1], delta0: delta[0], delta1: delta[1])
        d[n - 1] = endpointDerivative(h0: h[n - 2], h1: h[n - 3], delta0: delta[n - 2], delta1: delta[n - 3])

        let xMin = x[0]
        let xMax = x[n - 1]

        return xq.map { xqi in
            let t = min(max(xqi, xMin), xMax)
            // Binary search for the segment containing t (x is sorted ascending).
            var lo = 0
            var hi = n - 2
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if x[mid] <= t { lo = mid } else { hi = mid - 1 }
            }
            let i = lo
            let hiI = h[i]
            let s = (t - x[i]) / hiI
            let s2 = s * s
            let s3 = s2 * s
            // Cubic Hermite basis functions.
            let h00 = 2.0 * s3 - 3.0 * s2 + 1.0
            let h10 = s3 - 2.0 * s2 + s
            let h01 = -2.0 * s3 + 3.0 * s2
            let h11 = s3 - s2
            return h00 * y[i] + h10 * hiI * d[i] + h01 * y[i + 1] + h11 * hiI * d[i + 1]
        }
    }

    private static func endpointDerivative(h0: Double, h1: Double, delta0: Double, delta1: Double) -> Double {
        var d0 = ((2.0 * h0 + h1) * delta0 - h0 * delta1) / (h0 + h1)
        if sign(d0) != sign(delta0) {
            d0 = 0.0
        } else if sign(delta0) != sign(delta1) && abs(d0) > abs(3.0 * delta0) {
            d0 = 3.0 * delta0
        }
        return d0
    }

    private static func sign(_ v: Double) -> Int {
        if v > 0.0 { return 1 }
        if v < 0.0 { return -1 }
        return 0
    }
}
