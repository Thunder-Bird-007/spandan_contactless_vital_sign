import Foundation

/// Real port of matlab/src/filtering/detrendSignal.m + matlab/src/filtering/bandpassClean.m,
/// itself a line-for-line translation of android/app/.../signal/BandpassFilter.kt
/// (read directly before writing this, not from memory/description). Same MATLAB
/// source, same exact parameters:
///
///   detrendSignal.m:  detrendOrder = 3;  signalDetrended = detrend(signalRaw, 3)
///   bandpassClean.m:  filterOrder = 2;   lowCutoffHz = 0.7;  highCutoffHz = 4.0;
///                      cutoffs normalized by frameRate/2 (Nyquist);
///                      [b,a] = butter(2, [lowN highN], 'bandpass');
///                      signalFiltered = filtfilt(b, a, signalDetrended)
///   (effective filter order after filtfilt's forward+reverse pass is 2x the
///   butter() order, i.e. 4th order overall.)
///
/// "fs" here is ALWAYS derived from real sample timestamps by the caller
/// (RealHeartRateEstimator/LiveSpo2Estimator), never hardcoded -- same discipline
/// the Android port and the MATLAB side both needed (UBFC subjects varied
/// ~28.6-29.8fps; a live camera varies at least as much by device/lighting).
enum BandpassFilter {

    static let lowHz = 0.7
    static let highHz = 4.0
    static let order = 2

    /// Cubic-polynomial detrend, matching detrendSignal.m's `detrend(x, 3)`: fit a
    /// degree-3 polynomial (least squares) against sample position and subtract it.
    /// Fitted against position normalized to [-1, 1] for numerical conditioning
    /// (same as the Android port) -- a polynomial least-squares fit is invariant to
    /// an affine reparametrization of the x-axis, so the trend removed is identical
    /// regardless of x-axis convention.
    static func detrend(_ x: [Double], order: Int = 3) -> [Double] {
        let n = x.count
        guard n > order else { return x }
        let t: [Double] = (0..<n).map { i in n == 1 ? 0.0 : -1.0 + 2.0 * Double(i) / Double(n - 1) }
        let coeffs = polyfitLeastSquares(t: t, y: x, degree: order)
        return (0..<n).map { i in x[i] - evalPoly(coeffs, t[i]) }
    }

    /// Zero-phase Butterworth bandpass, matching bandpassClean.m exactly (order 2,
    /// 0.7-4Hz, filtfilt) against a RUNTIME-MEASURED fs. Batch operation over the
    /// whole array passed in -- not causal/streaming, same as MATLAB's offline
    /// filtfilt call, since zero-phase response requires seeing the whole window.
    static func apply(_ x: [Double], fs: Double) -> [Double] {
        guard fs > 2.0 * highHz else {
            // Nyquist too low for the 4Hz upper cutoff -- caller should already
            // guard against this; fail soft rather than crash on-device.
            return x
        }
        let (b, a) = designButterworthBandpass(order: order, lowHz: lowHz, highHz: highHz, fs: fs)
        return filtfilt(b: b, a: a, x: x)
    }

    // MARK: - Butterworth bandpass design: bilinear transform of the analog prototype
    // Mirrors the classic analog-lowpass-prototype -> lowpass-to-bandpass transform ->
    // bilinear-transform (with prewarping) -> zpk2tf chain both MATLAB's and scipy's
    // butter() use internally for digital bandpass design.

    static func designButterworthBandpass(order: Int, lowHz: Double, highHz: Double, fs: Double) -> ([Double], [Double]) {
        let nyquist = fs / 2.0
        let wn1 = lowHz / nyquist
        let wn2 = highHz / nyquist
        precondition(
            wn1 > 0.0 && wn2 < 1.0 && wn1 < wn2,
            "Bandpass cutoffs [\(lowHz),\(highHz)]Hz out of range for fs=\(fs) (need fs > \(2 * highHz))"
        )

        // Classic bilinear-transform normalization constant (Wn is already normalized
        // so Nyquist == 1; this "fs=2" is the standard analog<->digital frequency-
        // warping convention here, not the real camera sample rate).
        let fsInternal = 2.0
        let warped1 = 2.0 * fsInternal * tan(Double.pi * wn1 / fsInternal)
        let warped2 = 2.0 * fsInternal * tan(Double.pi * wn2 / fsInternal)
        let wo = (warped1 * warped2).squareRoot()
        let bw = warped2 - warped1

        // Analog Butterworth lowpass prototype poles (cutoff 1 rad/s, unity gain, no zeros).
        let protoPoles: [Complex] = (0..<order).map { k in
            let m = Double(-order + 1 + 2 * k)
            let angle = Double.pi * m / (2.0 * Double(order))
            return Complex(re: -cos(angle), im: -sin(angle))
        }

        // Lowpass -> bandpass analog transform: doubles the pole count, adds `order`
        // zeros at s=0.
        let pLp = protoPoles.map { $0 * (bw / 2.0) }
        var bpPoles: [Complex] = []
        for p in pLp {
            let disc = (p * p) - Complex.real(wo * wo)
            let root = disc.sqrtC()
            bpPoles.append(p + root)
            bpPoles.append(p - root)
        }
        let bpZeros = [Complex](repeating: .zero, count: order)
        let kBp = pow(bw, Double(order)) // prototype gain was 1

        // Bilinear transform (analog -> digital), fs2 = 2*fsInternal.
        let fs2 = Complex.real(2.0 * fsInternal)
        var zDigital = bpZeros.map { z in (fs2 + z) / (fs2 - z) }
        let pDigital = bpPoles.map { p in (fs2 + p) / (fs2 - p) }
        let degree = bpPoles.count - bpZeros.count // = order; zeros "at infinity" -> z = -1
        zDigital.append(contentsOf: [Complex](repeating: Complex(re: -1.0, im: 0.0), count: degree))

        var gainNum = Complex.real(1.0)
        for z in bpZeros { gainNum = gainNum * (fs2 - z) }
        var gainDen = Complex.real(1.0)
        for p in bpPoles { gainDen = gainDen * (fs2 - p) }
        let kDigital = kBp * (gainNum / gainDen).re

        let bCoeffs = polyFromRoots(zDigital).map { $0.re * kDigital }
        let aCoeffs = polyFromRoots(pDigital).map { $0.re }
        return (bCoeffs, aCoeffs)
    }

    // MARK: - IIR filtering: lfilter (Direct Form II Transposed) + filtfilt

    /// Single causal IIR pass, Direct Form II Transposed, zero initial state
    /// (matches scipy/MATLAB's `filter(b, a, x)` with default zero ICs).
    static func lfilter(b: [Double], a: [Double], x: [Double]) -> [Double] {
        let n = max(b.count, a.count)
        var bn = [Double](repeating: 0.0, count: n)
        var an = [Double](repeating: 0.0, count: n)
        for i in 0..<b.count { bn[i] = b[i] }
        for i in 0..<a.count { an[i] = a[i] }
        let a0 = an[0]
        var y = [Double](repeating: 0.0, count: x.count)
        var z = [Double](repeating: 0.0, count: max(n - 1, 0))
        for i in 0..<x.count {
            let xi = x[i]
            let yi = (bn[0] * xi + (n > 1 ? z[0] : 0.0)) / a0
            for j in 0..<max(n - 2, 0) {
                z[j] = bn[j + 1] * xi + z[j + 1] - an[j + 1] * yi
            }
            if n > 1 { z[n - 2] = bn[n - 1] * xi - an[n - 1] * yi }
            y[i] = yi
        }
        return y
    }

    /// filtfilt-equivalent: forward pass, reverse, forward pass again, reverse back
    /// -- zero-phase response, matching MATLAB's filtfilt. Uses odd-reflection edge
    /// padding (same default MATLAB/scipy use) to suppress startup transients. Runs
    /// over the WHOLE array passed in, batch, not sample-by-sample.
    static func filtfilt(b: [Double], a: [Double], x: [Double]) -> [Double] {
        let n = x.count
        let edge = 3 * (max(b.count, a.count) - 1)
        guard n > edge else {
            // Too short to safely pad/filter zero-phase -- fail soft with a single
            // causal pass rather than crash on-device on an early, small window.
            return lfilter(b: b, a: a, x: x)
        }

        var padded = [Double](repeating: 0.0, count: n + 2 * edge)
        for i in 0..<edge { padded[i] = 2 * x[0] - x[edge - i] }
        for i in 0..<n { padded[edge + i] = x[i] }
        for i in 0..<edge { padded[edge + n + i] = 2 * x[n - 1] - x[n - 2 - i] }

        let forward = lfilter(b: b, a: a, x: padded)
        let backward = lfilter(b: b, a: a, x: Array(forward.reversed()))
        let result = Array(backward.reversed())

        return Array(result[edge..<(edge + n)])
    }

    // MARK: - Small linear-algebra/complex helpers, private to this file

    struct Complex {
        var re: Double
        var im: Double

        static let zero = Complex(re: 0.0, im: 0.0)
        static func real(_ x: Double) -> Complex { Complex(re: x, im: 0.0) }

        static func + (l: Complex, r: Complex) -> Complex { Complex(re: l.re + r.re, im: l.im + r.im) }
        static func - (l: Complex, r: Complex) -> Complex { Complex(re: l.re - r.re, im: l.im - r.im) }
        static func * (l: Complex, r: Complex) -> Complex {
            Complex(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re)
        }
        static func * (l: Complex, s: Double) -> Complex { Complex(re: l.re * s, im: l.im * s) }
        static func / (l: Complex, r: Complex) -> Complex {
            let denom = r.re * r.re + r.im * r.im
            return Complex(re: (l.re * r.re + l.im * r.im) / denom, im: (l.im * r.re - l.re * r.im) / denom)
        }

        func sqrtC() -> Complex {
            let r = (re * re + im * im).squareRoot()
            let reOut = max(0.0, (r + re) / 2.0).squareRoot()
            var imOut = max(0.0, (r - re) / 2.0).squareRoot()
            if im < 0.0 { imOut = -imOut }
            return Complex(re: reOut, im: imOut)
        }
    }

    private static func convolve(_ a: [Complex], _ b: [Complex]) -> [Complex] {
        var result = [Complex](repeating: .zero, count: a.count + b.count - 1)
        for i in 0..<a.count {
            for j in 0..<b.count {
                result[i + j] = result[i + j] + a[i] * b[j]
            }
        }
        return result
    }

    /// Coefficients (highest degree first, monic) of the polynomial with the given
    /// roots -- e.g. for z-domain zeros/poles this gives the b0..bN / a0..aN
    /// ordering that `lfilter`/`filtfilt` expect directly.
    private static func polyFromRoots(_ roots: [Complex]) -> [Complex] {
        var coeffs: [Complex] = [Complex(re: 1.0, im: 0.0)]
        for r in roots {
            coeffs = convolve(coeffs, [Complex(re: 1.0, im: 0.0), Complex(re: -r.re, im: -r.im)])
        }
        return coeffs
    }

    private static func polyfitLeastSquares(t: [Double], y: [Double], degree: Int) -> [Double] {
        let m = degree + 1
        var ata = [[Double]](repeating: [Double](repeating: 0.0, count: m), count: m)
        var aty = [Double](repeating: 0.0, count: m)
        for i in 0..<t.count {
            var powers = [Double](repeating: 0.0, count: m)
            var p = 1.0
            for k in 0..<m { powers[k] = p; p *= t[i] }
            for r in 0..<m {
                aty[r] += powers[r] * y[i]
                for c in 0..<m { ata[r][c] += powers[r] * powers[c] }
            }
        }
        return solveLinearSystem(ata, aty)
    }

    private static func solveLinearSystem(_ a: [[Double]], _ bVec: [Double]) -> [Double] {
        let n = bVec.count
        var m: [[Double]] = (0..<n).map { i in
            var row = a[i]
            row.append(bVec[i])
            return row
        }
        for col in 0..<n {
            var pivotRow = col
            for r in (col + 1)..<n where abs(m[r][col]) > abs(m[pivotRow][col]) { pivotRow = r }
            m.swapAt(col, pivotRow)
            let pivotVal = m[col][col]
            if abs(pivotVal) < 1e-12 { continue } // degenerate (e.g. near-constant signal); leave row as-is
            for c in col...n { m[col][c] /= pivotVal }
            for r in 0..<n where r != col {
                let factor = m[r][col]
                for c in col...n { m[r][c] -= factor * m[col][c] }
            }
        }
        return (0..<n).map { m[$0][n] }
    }

    private static func evalPoly(_ coeffsAscending: [Double], _ t: Double) -> Double {
        var result = 0.0
        var p = 1.0
        for c in coeffsAscending {
            result += c * p
            p *= t
        }
        return result
    }
}
