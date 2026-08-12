import Foundation
import os

/// Real HR pipeline, ported from android/app/.../signal/RealHeartRateEstimator.kt
/// (read directly before writing this): detrend -> bandpass -> CHROM/POS ->
/// re-filter -> FFT peak -> CHROM/POS switch -> bpm.
///
/// Ports (in order) matlab/src/filtering/detrendSignal.m, bandpassClean.m,
/// matlab/src/pulseextraction/{chromCombine,posCombine}.m, and
/// matlab/src/heartrate/fftHeartRate.m, operating on SignalBuffer's current window.
///
/// The displayed value is chosen per reading by the CHROM/POS switching rule in
/// docs/Android_HR_Switching_Port_Spec.md (exact formula/threshold, ported
/// verbatim, not reinterpreted): relative_disagreement < 29.27% -> CHROM,
/// otherwise -> POS. Both raw values are still exposed via `Estimate` and logged
/// every recompute so the switch's behavior can be audited against
/// CHROM-alone/POS-alone.
///
/// This is a BATCH operation over the whole buffered window, not a causal/
/// streaming filter -- recomputed at most once per `recomputeIntervalMs`, because
/// zero-phase filtfilt requires seeing the whole window at once (same reason
/// MATLAB's filtfilt call is offline/batch, not sample-by-sample).
final class RealHeartRateEstimator {

    /// `chromBpm`/`posBpm`: the raw, un-switched values (kept for auditing/logging).
    /// `displayedBpm`: the value the switching rule actually selects.
    /// `relativeDisagreement`: `abs(chromBpm-posBpm) / mean(chromBpm,posBpm)`, a
    /// fraction (0.0-1.0+), per the spec.
    /// `usedPos`: true if the switch fired, i.e. displayedBpm == posBpm.
    struct Estimate {
        let chromBpm: Double
        let posBpm: Double
        let displayedBpm: Double
        let relativeDisagreement: Double
        let usedPos: Bool
    }

    private static let logger = Logger(subsystem: "com.spandan.app", category: "RealHeartRateEstimator")

    private static let recomputeIntervalMs: Int64 = 1000
    private static let minWindowSeconds = 4.0
    private static let minSamples = 60

    /// Exact threshold from docs/Android_HR_Switching_Port_Spec.md section 3 -- a
    /// natural gap measured in the 112-subject UBFC+VIPL pool's
    /// relative_disagreement distribution, not a value invented here.
    static let switchThreshold = 0.2927

    private var lastComputeMs: Int64 = 0
    private var cached: Estimate?

    /// Returns the latest displayed bpm (CHROM or POS, per the switching rule), or
    /// nil if not enough buffered data yet (early in a session, or fs momentarily
    /// unmeasurable).
    @discardableResult
    func update(samples: [RgbSample], nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Double? {
        if nowMs - lastComputeMs < Self.recomputeIntervalMs {
            return cached?.displayedBpm
        }
        lastComputeMs = nowMs

        guard samples.count >= Self.minSamples else { return cached?.displayedBpm }
        let windowSeconds = Double(samples.last!.timestampMs - samples.first!.timestampMs) / 1000.0
        guard windowSeconds >= Self.minWindowSeconds else { return cached?.displayedBpm }

        // Runtime-measured fs from real sample timestamps -- never hardcoded, same
        // discipline as bandpassClean.m/fftHeartRate.m's own "frameRate must not be
        // hardcoded" notes, since on-device camera fps varies by device/lighting.
        let fs = Double(samples.count - 1) / windowSeconds
        guard fs > 2.0 * HeartRateFft.highBandHz else {
            Self.logger.warning("Measured fs=\(fs, format: .fixed(precision: 2))Hz too low for the 0.7-4Hz band; skipping this window")
            return cached?.displayedBpm
        }

        let rawR = samples.map { Double($0.red) }
        let rawG = samples.map { Double($0.green) }
        let rawB = samples.map { Double($0.blue) }

        let detrendedR = BandpassFilter.detrend(rawR)
        let detrendedG = BandpassFilter.detrend(rawG)
        let detrendedB = BandpassFilter.detrend(rawB)

        let filteredR = BandpassFilter.apply(detrendedR, fs: fs)
        let filteredG = BandpassFilter.apply(detrendedG, fs: fs)
        let filteredB = BandpassFilter.apply(detrendedB, fs: fs)

        let chromRaw = PulseExtraction.chromCombine(
            rFiltered: filteredR, gFiltered: filteredG, bFiltered: filteredB,
            rRaw: rawR, gRaw: rawG, bRaw: rawB
        )
        let posRaw = PulseExtraction.posCombine(
            rFiltered: filteredR, gFiltered: filteredG, bFiltered: filteredB,
            rRaw: rawR, gRaw: rawG, bRaw: rawB
        )

        // Re-filter after combination: combining channels can reintroduce
        // out-of-band content, same reasoning as Segment 4's explanation doc.
        let chromFiltered = BandpassFilter.apply(chromRaw, fs: fs)
        let posFiltered = BandpassFilter.apply(posRaw, fs: fs)

        guard let chromResult = HeartRateFft.estimateBpm(chromFiltered, fs: fs),
              let posResult = HeartRateFft.estimateBpm(posFiltered, fs: fs) else {
            Self.logger.warning("No FFT bin fell inside 0.7-4Hz for fs=\(fs, format: .fixed(precision: 2)) n=\(samples.count); keeping last estimate")
            return cached?.displayedBpm
        }

        let decision = Self.switchingDecision(chromBpm: chromResult.bpm, posBpm: posResult.bpm)

        Self.logger.debug(
            """
            fs=\(fs, format: .fixed(precision: 2))Hz n=\(samples.count) window=\(windowSeconds, format: .fixed(precision: 1))s \
            HR_chrom=\(chromResult.bpm, format: .fixed(precision: 1)) HR_pos=\(posResult.bpm, format: .fixed(precision: 1)) \
            relative_disagreement=\(decision.relativeDisagreement * 100.0, format: .fixed(precision: 2))% \
            displayed=\(decision.usedPos ? "POS" : "CHROM") (\(decision.displayedBpm, format: .fixed(precision: 1)))
            """
        )

        let estimate = Estimate(
            chromBpm: chromResult.bpm,
            posBpm: posResult.bpm,
            displayedBpm: decision.displayedBpm,
            relativeDisagreement: decision.relativeDisagreement,
            usedPos: decision.usedPos
        )
        cached = estimate
        return estimate.displayedBpm
    }

    /// The CHROM/POS switching rule, factored out as a pure function so it's
    /// directly unit-testable without a full buffered window (see
    /// SpandanTests/RealHeartRateEstimatorSwitchingTests.swift).
    static func switchingDecision(
        chromBpm: Double,
        posBpm: Double
    ) -> (displayedBpm: Double, usedPos: Bool, relativeDisagreement: Double) {
        let meanBpm = (chromBpm + posBpm) / 2.0
        let relativeDisagreement = meanBpm > 0 ? abs(chromBpm - posBpm) / meanBpm : 0.0
        let usedPos = relativeDisagreement >= switchThreshold
        let displayedBpm = usedPos ? posBpm : chromBpm
        return (displayedBpm, usedPos, relativeDisagreement)
    }
}
