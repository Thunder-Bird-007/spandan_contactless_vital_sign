import Foundation

/// A WIDER bandpass than `BandpassFilter`'s own 0.7-4Hz HR-tuned band: the
/// dicrotic notch is carried by the 3rd-5th cardiac harmonics, not the
/// fundamental, so a 4Hz cutoff throws away the harmonic content the notch
/// needs, by construction, at every HR this project's cohorts actually sit
/// at. Direct port of android/app/.../signal/MorphologyBandpassFilter.kt
/// (read directly before writing this).
///
/// Reuses `BandpassFilter.designButterworthBandpass`/`BandpassFilter.filtfilt`
/// directly rather than duplicating the Butterworth-design/filtfilt
/// machinery -- `BandpassFilter.swift` itself is Branch 1, already
/// measured/validated on Android and ported faithfully to iOS; this file
/// only CALLS its already-available static methods with different
/// order/cutoff arguments, it does not modify them.
///
/// MATLAB source, exact parameters (confirmed via the Android port's own
/// header, itself read from `matlab/src/morphology/bandpassMorphology.m`):
/// filterOrder = 3 (one order higher than bandpassClean.m's 2); 'wide' =
/// 0.5-8.0Hz (DEFAULT, matches Branch 2's production default); 'mid' =
/// 0.6-6.0Hz (validated non-default alternative, useful when 'wide' isn't
/// admissible under Nyquist -- see `pick` below).
enum MorphologyBandpassFilter {

    enum BandMode {
        case wide
        case mid

        var lowHz: Double {
            switch self {
            case .wide: return 0.5
            case .mid: return 0.6
            }
        }
        var highHz: Double {
            switch self {
            case .wide: return 8.0
            case .mid: return 6.0
            }
        }
    }

    static let order = 3

    struct Result {
        let filtered: [Double]
        let bandUsed: BandMode
    }

    /// Butterworth order-3 bandpass + filtfilt at `mode`'s cutoffs, against
    /// a RUNTIME-MEASURED `fs` (never hardcoded, same discipline as
    /// `BandpassFilter`). Returns nil if `mode`'s high cutoff is at or above
    /// the Nyquist frequency for `fs` -- a live caller should check `pick`
    /// or `isAdmissible` first rather than relying on this for control flow
    /// (mirrors the Android port's own guard, adapted to Swift's Optional
    /// convention instead of a thrown exception).
    static func apply(_ sigDetrended: [Double], fs: Double, mode: BandMode) -> Result? {
        guard isAdmissible(fs: fs, mode: mode) else { return nil }
        let (b, a) = BandpassFilter.designButterworthBandpass(order: order, lowHz: mode.lowHz, highHz: mode.highHz, fs: fs)
        return Result(filtered: BandpassFilter.filtfilt(b: b, a: a, x: sigDetrended), bandUsed: mode)
    }

    /// True if `mode`'s high cutoff is strictly below Nyquist for `fs` --
    /// same condition the MATLAB source checks before erroring.
    static func isAdmissible(fs: Double, mode: BandMode) -> Bool {
        mode.highHz < fs / 2.0
    }

    /// Segment 18/19 interaction (Android's own docs), stated plainly:
    /// Branch 2's wide 0.5-8Hz band needs fs comfortably above 16Hz to stay
    /// meaningful under Nyquist. iOS camera throughput has not been
    /// measured on real hardware this session (no device available) -- this
    /// function stays defensive regardless, same as the Android port.
    ///
    /// Picks the widest ('wide' preferred, then 'mid') admissible mode for
    /// `fs`, or nil if fs is too low for even 'mid' -- callers
    /// (`MorphologyWaveformEstimator`) should treat nil as "skip this
    /// window" (fail soft), not crash.
    static func pick(fs: Double) -> BandMode? {
        if isAdmissible(fs: fs, mode: .wide) { return .wide }
        if isAdmissible(fs: fs, mode: .mid) { return .mid }
        return nil
    }
}
