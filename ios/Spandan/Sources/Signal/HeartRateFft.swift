import Foundation

/// Real port of matlab/src/heartrate/fftHeartRate.m (read directly from source
/// before writing this), ported from android/app/.../signal/HeartRateFft.kt: FFT
/// magnitude spectrum -> restrict to the 0.7-4Hz physiological band (masking
/// BEFORE peak search, matching the MATLAB source's explicit safety-net comment --
/// a global max could otherwise land outside the valid band) -> peak bin -> Hz ->
/// bpm.
///
/// **Implementation note, flagged plainly rather than silently substituted:** the
/// Android port uses JTransforms' O(n log n) complex FFT of the whole window, then
/// reads out magnitude only for in-band bins. This port instead computes a direct
/// DFT sum (O(band-width * n)) for ONLY the handful of bins whose frequency falls
/// in 0.7-4Hz. Both compute the exact same DFT bin values -- `X[k] = sum_i x[i] *
/// exp(-j*2*pi*k*i/n)` is the same number regardless of the algorithm used to get
/// it -- so this is numerically equivalent, not an approximation. It was chosen
/// because window lengths here aren't guaranteed to be powers of two (Accelerate's
/// classic FFT needs that, and vDSP_DFT's arbitrary-length setup can fail for some
/// N), and because n (~300-800 samples, recomputed at most once/second) makes even
/// an O(n^2)-for-all-bins DFT computationally trivial, let alone one restricted to
/// just the in-band bins.
///
/// fs is always the caller's runtime-measured value -- never hardcoded, same as
/// MATLAB's `freqResolution = frameRate / signalLength`.
enum HeartRateFft {

    static let lowBandHz = 0.7
    static let highBandHz = 4.0

    struct Result {
        let bpm: Double
        let peakFreqHz: Double
    }

    /// Returns nil if no FFT bin falls inside the 0.7-4Hz band for this fs/window
    /// length (mirrors fftHeartRate.m's `error('fftHeartRate:emptyBand', ...)`,
    /// translated to a soft nil since this runs live on-device rather than as an
    /// offline batch script).
    static func estimateBpm(_ pulseSignal: [Double], fs: Double) -> Result? {
        let n = pulseSignal.count
        guard n >= 4 else { return nil }

        // fft() of a real signal is symmetric -- keep only 0Hz..Nyquist, same as
        // fftHeartRate.m's `numPositiveBins = floor(signalLength/2) + 1`.
        let numPositiveBins = n / 2 + 1
        let freqResolution = fs / Double(n)

        var peakFreqHz = -1.0
        var peakMag = -1.0
        for k in 0..<numPositiveBins {
            let freq = Double(k) * freqResolution
            if freq < lowBandHz || freq > highBandHz { continue }

            var re = 0.0
            var im = 0.0
            let omega = -2.0 * Double.pi * Double(k) / Double(n)
            for i in 0..<n {
                let angle = omega * Double(i)
                re += pulseSignal[i] * cos(angle)
                im += pulseSignal[i] * sin(angle)
            }
            let mag = (re * re + im * im).squareRoot()
            if mag > peakMag {
                peakMag = mag
                peakFreqHz = freq
            }
        }
        guard peakFreqHz >= 0.0 else { return nil }

        return Result(bpm: peakFreqHz * 60.0, peakFreqHz: peakFreqHz)
    }
}
