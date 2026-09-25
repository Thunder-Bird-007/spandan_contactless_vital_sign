import Foundation

/// Keep `AdaptiveHarmonicFilter`'s ABPF comb output wherever its OWN notch
/// confidence already clears this project's 0.3 bar; substitute
/// `HarmonicSelectiveGaussianFilter` (alpha 0.15) only where ABPF already
/// fails. Direct port of
/// android/app/.../signal/HarmonicFilterConfidenceGate.kt (read directly
/// before writing this), itself a port of
/// `matlab/src/morphology/harmonicFilterConfidenceGate.m`. This is the
/// MATLAB side's PRODUCTION DEFAULT for Branch 2 -- the design principle it
/// encodes (never override an already-successful primary result) is why
/// `MorphologyWaveformEstimator` uses this SAME safe single-fallback mode.
///
/// NOT PORTED, DELIBERATELY: the MATLAB source's mode (b), "pick whichever
/// of several fallback candidates self-reports the highest confidence." Its
/// own header documents that mode as VERIFIED AND ACTIVELY DISCOURAGED --
/// tested on the MATLAB side and found to produce the WORST median waveform
/// correlation of every method compared (a selection-bias artifact, not a
/// real gain). `select` below only ever accepts a `fallbacks` array and
/// picks the best of it BY DESIGN when the primary fails, which reproduces
/// that same discouraged mode if a caller ever passes more than one
/// candidate -- so far, no caller does (`MorphologyWaveformEstimator`
/// always passes exactly one, matching the Android port).
enum HarmonicFilterConfidenceGate {

    struct Candidate {
        let signal: [Double]
        let notchConfidence: Double
        let methodLabel: String
    }

    struct Result {
        let selectedSignal: [Double]
        let selectedMethodLabel: String
        let selectedNotchConfidence: Double
        let wasSubstituted: Bool
    }

    /// - Parameter fallbacks: one or more candidates to consider if
    ///   `primary` fails the bar. `MorphologyWaveformEstimator` always
    ///   passes exactly one (the safe mode) -- see this type's own doc for
    ///   why. Returns nil if `fallbacks` is empty (a caller error).
    static func select(
        primary: Candidate,
        fallbacks: [Candidate],
        confidenceThreshold: Double = 0.3
    ) -> Result? {
        guard !fallbacks.isEmpty else { return nil }

        if !primary.notchConfidence.isNaN && primary.notchConfidence > confidenceThreshold {
            return Result(selectedSignal: primary.signal, selectedMethodLabel: primary.methodLabel, selectedNotchConfidence: primary.notchConfidence, wasSubstituted: false)
        }

        let best = fallbacks.max { $0.notchConfidence < $1.notchConfidence } ?? fallbacks[0]
        return Result(selectedSignal: best.signal, selectedMethodLabel: best.methodLabel, selectedNotchConfidence: best.notchConfidence, wasSubstituted: true)
    }
}
