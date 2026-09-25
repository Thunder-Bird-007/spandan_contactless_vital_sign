import Foundation

/// Corrects rPPG waveform sign using a skewness heuristic. Direct port of
/// android/app/.../signal/FixPolarity.kt (read directly before writing
/// this). NEITHER `fixPolarityByGroundTruth.m` NOR
/// `estimateLagPolarityByGroundTruth.m` is ported -- both are ground-truth-
/// anchored and unusable live (neither Android nor iOS has a contact-PPG
/// reference to anchor against, ever). This heuristic IS what the MATLAB
/// source itself falls back to for exactly this no-ground-truth case.
///
/// CARRIED-OVER CAVEAT, stated in the Android port's own header and
/// repeated here rather than silently dropped: measured on all 5 UBFC
/// DATASET_1 subjects, this heuristic agreed with the ground-truth-anchored
/// rule on only 3/5 (60%) -- and it did not fail randomly, it flipped ALL 5
/// subjects (a systematic all-flip bias, not scatter). This is a real,
/// known limitation of the ONLY polarity method a live camera app can use,
/// not fixed by this port.
enum FixPolarity {

    struct Result {
        let oriented: [Double]
        let wasFlipped: Bool
        let skewValue: Double
    }

    private static let minDurationSec = 10.0

    /// `frameRate` must produce at least `minDurationSec` of coverage for
    /// `sig`'s length, matching `fixPolarity.m`'s own hard error exactly
    /// (skewness over a shorter window is not reliable enough to anchor
    /// polarity) -- returns nil rather than crashing, since this runs live
    /// on uncontrolled camera data (the fail-soft layer lives in the
    /// caller, `MorphologyWaveformEstimator`, same split
    /// `RealHeartRateEstimator` already uses).
    static func apply(_ sig: [Double], frameRate: Double) -> Result? {
        guard Double(sig.count) / frameRate >= minDurationSec else { return nil }

        let n = sig.count
        let mean = sig.reduce(0.0, +) / Double(n)
        var sumSq = 0.0
        var sumCube = 0.0
        for v in sig {
            let c = v - mean
            sumSq += c * c
            sumCube += c * c * c
        }
        let populationStd = (sumSq / Double(n)).squareRoot()
        let thirdMoment = sumCube / Double(n)
        let skewValue = thirdMoment / (populationStd * populationStd * populationStd)

        let wasFlipped = skewValue < 0.0
        let oriented = wasFlipped ? sig.map { -$0 } : sig
        return Result(oriented: oriented, wasFlipped: wasFlipped, skewValue: skewValue)
    }
}
