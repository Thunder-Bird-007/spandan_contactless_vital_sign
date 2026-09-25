import Foundation

/// Direct (O(n^2)) complex DFT forward/inverse pair, shared by
/// `AdaptiveHarmonicFilter` and `HarmonicSelectiveGaussianFilter` -- both
/// need a FULL complex spectrum (to build a frequency-domain mask, then
/// inverse-transform back to the time domain), unlike `HeartRateFft.swift`
/// (which only ever reads out magnitude for a handful of in-band bins).
///
/// The Android port uses JTransforms' O(n log n) FFT; this uses a direct
/// DFT sum instead, same choice and same reasoning `HeartRateFft.swift`'s
/// own header already documents for this codebase: window lengths here
/// aren't guaranteed to be powers of two (Accelerate's classic FFT needs
/// that, and vDSP_DFT's arbitrary-length setup can fail for some N), and n
/// (a camera window, on the order of hundreds of samples, recomputed at
/// most every few seconds) makes even an O(n^2) DFT computationally
/// trivial. A direct DFT computes the EXACT same bin values a real FFT
/// would (`X[k] = sum_i x[i] * exp(-j*2*pi*k*i/n)` is the same number
/// regardless of algorithm) -- this is numerically equivalent, not an
/// approximation.
enum ComplexDFT {

    /// Forward DFT of a real-valued signal. Returns the full-length
    /// (`re`, `im`) spectrum, bins `0..<n` (not just the positive-frequency
    /// half), matching JTransforms' `complexForward` convention the Android
    /// port relies on for its own mask/mirror-bin logic.
    static func forward(_ x: [Double]) -> (re: [Double], im: [Double]) {
        let n = x.count
        var re = [Double](repeating: 0.0, count: n)
        var im = [Double](repeating: 0.0, count: n)
        for k in 0..<n {
            var sumRe = 0.0
            var sumIm = 0.0
            let omega = -2.0 * Double.pi * Double(k) / Double(n)
            for i in 0..<n {
                let angle = omega * Double(i)
                sumRe += x[i] * cos(angle)
                sumIm += x[i] * sin(angle)
            }
            re[k] = sumRe
            im[k] = sumIm
        }
        return (re, im)
    }

    /// Inverse DFT, returning only the real part (both callers here build a
    /// conjugate-symmetric mask by construction -- either an explicit mirror-
    /// bin mask or a symmetric Gaussian frequency-axis mask -- so the
    /// imaginary part is expected to be ~0 and is discarded, matching the
    /// Android port's own `filteredComplex[2*i]` real-part-only readout).
    static func inverse(re: [Double], im: [Double]) -> [Double] {
        let n = re.count
        var out = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            var sum = 0.0
            let omega = 2.0 * Double.pi * Double(i) / Double(n)
            for k in 0..<n {
                let angle = omega * Double(k)
                sum += re[k] * cos(angle) - im[k] * sin(angle)
            }
            out[i] = sum / Double(n)
        }
        return out
    }
}
