import Foundation

/// Resamples a pulse signal onto a uniform high-rate time grid using its
/// REAL per-sample timestamps (never assuming uniform `1/fs` spacing) via
/// `PchipInterpolator`. Direct port of
/// android/app/.../signal/ResampleUniform.kt (read directly before writing
/// this), itself a port of `matlab/src/morphology/resampleUniform.m`.
///
/// Camera frame timing is irregular, and the dicrotic notch is a fine
/// (tens-of-ms) time-domain feature that irregular-spacing-as-if-uniform
/// would smear -- the same reasoning the MATLAB source's own header gives.
///
/// `RgbSample.timestampMs` (already real per-frame acquisition times) is
/// this port's equivalent of `roi/extractROISignals.m`'s `roiTimestamps`
/// output -- converted to seconds here since MATLAB's own convention is
/// seconds throughout.
enum ResampleUniform {

    static let defaultTargetFs = 250.0

    struct Result {
        let sigUniform: [Double]
        let timeUniform: [Double]
        let targetFs: Double
    }

    static func apply(_ sig: [Double], timestampsSeconds: [Double], targetFs: Double = defaultTargetFs) -> Result {
        precondition(sig.count == timestampsSeconds.count, "sig and timestampsSeconds must have the same number of elements")
        precondition(sig.count >= 2, "need at least 2 samples to resample")

        let startSec = timestampsSeconds.first!
        let endSec = timestampsSeconds.last!
        let stepSec = 1.0 / targetFs
        let numSteps = Int((endSec - startSec) / stepSec) + 1
        let timeUniform = (0..<numSteps).map { startSec + Double($0) * stepSec }

        let sigUniform = PchipInterpolator.interpolate(timestampsSeconds, sig, timeUniform)
        return Result(sigUniform: sigUniform, timeUniform: timeUniform, targetFs: targetFs)
    }
}
