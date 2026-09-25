import Foundation

/// Harmonic-comb filter (ABPF, Moco/Stuijk/de Haan, Sci Rep 8:8501, 2018).
/// Direct port of android/app/.../signal/AdaptiveHarmonicFilter.kt (read
/// directly before writing this), itself a port of
/// `matlab/src/morphology/adaptiveHarmonicFilter.m`. Keeps only narrow
/// (3-bin) windows around the cardiac fundamental and each of its
/// harmonics, zeroes everything else, inverse-transforms back -- rejects
/// inter-harmonic noise a flat bandpass (`MorphologyBandpassFilter`) would
/// pass through.
///
/// Uses `ComplexDFT` (see that file's own KDoc for why a direct DFT, not
/// Accelerate/vDSP, matching this codebase's own `HeartRateFft.swift`
/// precedent) instead of JTransforms.
enum AdaptiveHarmonicFilter {

    struct Result {
        let filtered: [Double]
        let f0Hz: Double
        let harmonicsUsedHz: [Double]
    }

    /// - Parameters:
    ///   - numHarmonics: how many harmonics (h=1...numHarmonics) to keep. 6,
    ///     matching the MATLAB default, unless the caller passes otherwise.
    ///   - f0HzOverride: if non-nil, skips the internal
    ///     `HeartRateFft.estimateBpm` call and uses this as f0 -- used by
    ///     `MorphologyWaveformEstimator` to force all three R/G/B channels
    ///     onto the SAME shared f0 (estimated once from the combined
    ///     wide-band CHROM pulse), matching the MATLAB pipeline's own
    ///     design exactly.
    ///
    /// Returns nil if `f0HzOverride` is nil and no FFT bin falls inside
    /// `HeartRateFft`'s 0.7-4Hz band (mirrors the MATLAB source's own hard
    /// error, adapted to Swift's Optional convention -- a live caller here
    /// should always supply `f0HzOverride` from an already-validated shared
    /// estimate, per the design above, so this path should not normally be
    /// hit).
    static func apply(_ sigDetrended: [Double], frameRate: Double, numHarmonics: Int = 6, f0HzOverride: Double? = nil) -> Result? {
        let n = sigDetrended.count

        guard let f0Hz = f0HzOverride ?? HeartRateFft.estimateBpm(sigDetrended, fs: frameRate).map({ $0.bpm / 60.0 }) else {
            return nil
        }

        let freqResolution = frameRate / Double(n)
        let nyquistBinIdx0 = n / 2 // 0-based index of the Nyquist (or highest positive-freq) bin

        let (spectrumRe, spectrumIm) = ComplexDFT.forward(sigDetrended)

        var mask = [Bool](repeating: false, count: n)
        var harmonicsUsedHz: [Double] = []

        for h in 1...numHarmonics {
            let harmonicFreqHz = Double(h) * f0Hz
            let centerBinIdx0 = Int((harmonicFreqHz / freqResolution).rounded())
            if centerBinIdx0 > nyquistBinIdx0 { continue } // this harmonic and all higher ones are above Nyquist
            harmonicsUsedHz.append(harmonicFreqHz)

            for offset in -1...1 {
                let binIdx0 = centerBinIdx0 + offset
                if binIdx0 < 1 || binIdx0 > nyquistBinIdx0 { continue } // skip DC (bin 0) and anything past Nyquist
                mask[binIdx0] = true
                let mirror0 = n - binIdx0
                if mirror0 >= 0 && mirror0 < n { mask[mirror0] = true }
            }
        }

        var filteredRe = [Double](repeating: 0.0, count: n)
        var filteredIm = [Double](repeating: 0.0, count: n)
        for k in 0..<n where mask[k] {
            filteredRe[k] = spectrumRe[k]
            filteredIm[k] = spectrumIm[k]
        }

        let filtered = ComplexDFT.inverse(re: filteredRe, im: filteredIm)
        return Result(filtered: filtered, f0Hz: f0Hz, harmonicsUsedHz: harmonicsUsedHz)
    }
}
