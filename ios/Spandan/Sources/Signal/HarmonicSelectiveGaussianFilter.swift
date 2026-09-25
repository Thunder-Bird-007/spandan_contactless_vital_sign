import Foundation

/// `AdaptiveHarmonicFilter`'s hard-edged rectangular comb, but with
/// Gaussian-tapered (no hard edge, no Gibbs-ringing) passbands centered on
/// the cardiac fundamental and its harmonics. Direct port of
/// android/app/.../signal/HarmonicSelectiveGaussianFilter.kt (read directly
/// before writing this), itself a port of
/// `matlab/src/morphology/harmonicSelectiveGaussianFilter.m`. Reference:
/// Dominguez-Hernandez, Paez & Padilla, "Harmonic-Selective Gaussian
/// Filtering...", Sensors 26(12):3710 (2026), doi:10.3390/s26123710.
///
/// This is the MATLAB side's own PRODUCTION FALLBACK candidate (used by
/// `HarmonicFilterConfidenceGate` at alpha=0.15 wherever
/// `AdaptiveHarmonicFilter`'s own notch confidence fails this project's 0.3
/// bar) -- NOT a standalone default; only ever invoked from behind that
/// gate.
enum HarmonicSelectiveGaussianFilter {

    struct Result {
        let filtered: [Double]
        let f0Hz: Double
        let harmonicsUsedHz: [Double]
    }

    /// - Parameter alpha: bandwidth scaling (sigma = alpha*f0). 0.15 is this
    ///   project's own validated production value, NOT the paper's own
    ///   default of 0.5.
    static func apply(
        _ sigDetrended: [Double],
        frameRate: Double,
        numHarmonics: Int = 6,
        f0HzOverride: Double? = nil,
        alpha: Double = 0.15
    ) -> Result? {
        let n = sigDetrended.count

        guard let f0Hz = f0HzOverride ?? HeartRateFft.estimateBpm(sigDetrended, fs: frameRate).map({ $0.bpm / 60.0 }) else {
            return nil
        }

        let sigma = alpha * f0Hz
        guard sigma > 0.0 else { return nil }
        let sigmaSq = sigma * sigma

        let freqResolution = frameRate / Double(n)
        let nyquistHz = frameRate / 2.0

        // Signed frequency axis (0-based, folded to negative frequency
        // above Nyquist) -- same convention the MATLAB source builds by hand.
        let freqAxis: [Double] = (0..<n).map { k in
            let f = Double(k) * freqResolution
            return f > nyquistHz ? f - frameRate : f
        }

        var mask = [Double](repeating: 0.0, count: n)
        var harmonicsUsedHz: [Double] = []

        for h in 1...numHarmonics {
            let harmonicFreqHz = Double(h) * f0Hz
            if harmonicFreqHz <= nyquistHz { harmonicsUsedHz.append(harmonicFreqHz) }
            for k in 0..<n {
                let fMinus = freqAxis[k] - harmonicFreqHz
                let fPlus = freqAxis[k] + harmonicFreqHz
                mask[k] += exp(-(fMinus * fMinus) / sigmaSq) + exp(-(fPlus * fPlus) / sigmaSq)
            }
        }

        let (spectrumRe, spectrumIm) = ComplexDFT.forward(sigDetrended)

        var filteredRe = [Double](repeating: 0.0, count: n)
        var filteredIm = [Double](repeating: 0.0, count: n)
        for k in 0..<n {
            filteredRe[k] = spectrumRe[k] * mask[k]
            filteredIm[k] = spectrumIm[k] * mask[k]
        }

        let filtered = ComplexDFT.inverse(re: filteredRe, im: filteredIm)
        return Result(filtered: filtered, f0Hz: f0Hz, harmonicsUsedHz: harmonicsUsedHz)
    }
}
