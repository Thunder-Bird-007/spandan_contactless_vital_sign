import Foundation
import os

/// Branch 2 (waveform morphology / dicrotic notch) live orchestrator,
/// mirroring `matlab/src/pipeline/estimateVitalsAndMorphology.m`'s own
/// Branch 2 sequence and ported directly from
/// android/app/.../signal/MorphologyWaveformEstimator.kt (read directly
/// before writing this, including its Segment 31 `continuousWaveform`
/// addition -- see that field's own doc below): detrend -> shared f0 from a
/// wide-band CHROM pulse -> `AdaptiveHarmonicFilter` (ABPF) per channel,
/// forced onto that shared f0 -> `PulseExtraction.chromCombine` ->
/// `FixPolarity` (heuristic -- no contact-PPG ground truth exists on iOS
/// either, ever) -> `ResampleUniform` -> `EnsembleAverageBeats` ->
/// `NotchDetectIEM`, with `useConfidenceGate` (default true) substituting
/// `HarmonicSelectiveGaussianFilter` (alpha 0.15) via
/// `HarmonicFilterConfidenceGate` wherever ABPF's own notch confidence
/// fails this project's 0.3 bar.
///
/// Reads from the SAME `RgbSample` window Branch 1's `RealHeartRateEstimator`
/// already consumes -- both estimators run independently side by side,
/// neither reads or modifies the other's state, matching Branch 1/Branch
/// 2's deliberate MATLAB-side separation (the wide-band/harmonic-comb
/// filtering Branch 2 needs measurably hurts Branch 1's HR accuracy -- a
/// documented harmonic-lock case on the MATLAB side -- so the two branches
/// must never share a filter choice).
///
/// FAIL-SOFT LAYER (deliberate divergence from a pure port, stated
/// explicitly, matching the Android port's own convention): `EnsembleAverageBeats.apply`
/// and `FixPolarity.apply` can return nil on a bad window (too few beats,
/// too-short signal) -- this live estimator, running on uncontrolled camera
/// data, treats that as `EstimatorStatus.lowSignalQuality` instead of
/// crashing.
///
/// HONEST STATUS: this is a from-scratch Swift port with NO iPhone/Mac
/// available to build or run it on this session (same limitation the
/// original iOS Branch 1 port's own README already documents) -- verified
/// only by unit test and CI build (`.github/workflows/ios-build.yml`).
final class MorphologyWaveformEstimator {

    struct Estimate {
        let notchDetected: Bool
        let notchPositionNormalized: Double
        let notchDepth: Double
        /// Clipped to [0,1] -- see `NotchDetectIEM`'s own doc for why this
        /// alone is a near-useless gate at scale; `notchConfidenceRaw` is
        /// surfaced too.
        let notchConfidence: Double
        /// UNCLIPPED -- the value that actually carries ranking information
        /// once `notchConfidence` clips at 1.0.
        let notchConfidenceRaw: Double
        let harmonicMethodUsed: String // "adaptiveHarmonic" or "gaussian015"
        let gateSubstituted: Bool
        let waveform: [Double] // prototype.trimmedMean -- 1 ensemble-averaged cardiac cycle
        /// The SAME selected candidate's (ABPF or Gaussian, whichever
        /// `harmonicMethodUsed` names) continuous, polarity-corrected,
        /// uniformly-resampled pulse -- the SAME signal `EnsembleAverageBeats`
        /// then chops into individual beats to build `waveform` above --
        /// tail-windowed to the last `continuousDisplaySeconds` seconds.
        /// Real Branch 2 output (post ABPF/Gaussian harmonic filtering +
        /// CHROM combine + polarity fix), NOT raw/Branch-1 data, and spans
        /// several real cardiac cycles -- added (mirroring the Android
        /// port's own Segment 31) so the UI can show a multi-cycle
        /// scrolling trace ("like a PPG monitor") instead of one averaged
        /// beat.
        let continuousWaveform: [Double]
        let fs: Double // the real, runtime-measured fs this estimate ran at
        let bandModeUsed: MorphologyBandpassFilter.BandMode
    }

    private static let logger = Logger(subsystem: "com.spandan.app", category: "MorphologyWaveformEstimator")

    private let useConfidenceGate: Bool

    init(useConfidenceGate: Bool = true) {
        self.useConfidenceGate = useConfidenceGate
    }

    private var lastComputeMs: Int64 = 0
    private var cached: Estimate?

    private(set) var lastStatus: EstimatorStatus = .warmingUp

    @discardableResult
    func update(samples: [RgbSample], nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Estimate? {
        if nowMs - lastComputeMs < Self.recomputeIntervalMs {
            return cached
        }
        lastComputeMs = nowMs

        guard samples.count >= Self.minSamples else {
            lastStatus = .warmingUp
            return cached
        }
        let windowSeconds = Double(samples.last!.timestampMs - samples.first!.timestampMs) / 1000.0
        guard windowSeconds >= Self.minWindowSeconds else {
            lastStatus = .warmingUp
            return cached
        }

        let fs = Double(samples.count - 1) / windowSeconds

        guard let bandMode = MorphologyBandpassFilter.pick(fs: fs) else {
            Self.logger.warning("Measured fs=\(fs, format: .fixed(precision: 2))Hz too low for even MID band (0.6-6.0Hz); skipping this window")
            lastStatus = .lowSignalQuality
            return cached
        }

        let rawR = samples.map { Double($0.red) }
        let rawG = samples.map { Double($0.green) }
        let rawB = samples.map { Double($0.blue) }
        let timestampsSeconds = samples.map { Double($0.timestampMs) / 1000.0 }

        let detrendedR = BandpassFilter.detrend(rawR)
        let detrendedG = BandpassFilter.detrend(rawG)
        let detrendedB = BandpassFilter.detrend(rawB)

        // --- Shared f0 from a wide/mid-band CHROM pulse.
        guard let wideR = MorphologyBandpassFilter.apply(detrendedR, fs: fs, mode: bandMode)?.filtered,
              let wideG = MorphologyBandpassFilter.apply(detrendedG, fs: fs, mode: bandMode)?.filtered,
              let wideB = MorphologyBandpassFilter.apply(detrendedB, fs: fs, mode: bandMode)?.filtered else {
            lastStatus = .lowSignalQuality
            return cached
        }
        let pulseWide = PulseExtraction.chromCombine(rFiltered: wideR, gFiltered: wideG, bFiltered: wideB, rRaw: rawR, gRaw: rawG, bRaw: rawB)
        guard let sharedF0Hz = HeartRateFft.estimateBpm(pulseWide, fs: fs).map({ $0.bpm / 60.0 }) else {
            Self.logger.warning("No FFT bin fell inside 0.7-4Hz for the shared f0 estimate; skipping this window")
            lastStatus = .lowSignalQuality
            return cached
        }

        // --- ABPF comb, forced onto the shared f0 across all 3 channels.
        guard let abpfR = AdaptiveHarmonicFilter.apply(detrendedR, frameRate: fs, numHarmonics: Self.numHarmonics, f0HzOverride: sharedF0Hz)?.filtered,
              let abpfG = AdaptiveHarmonicFilter.apply(detrendedG, frameRate: fs, numHarmonics: Self.numHarmonics, f0HzOverride: sharedF0Hz)?.filtered,
              let abpfB = AdaptiveHarmonicFilter.apply(detrendedB, frameRate: fs, numHarmonics: Self.numHarmonics, f0HzOverride: sharedF0Hz)?.filtered else {
            lastStatus = .lowSignalQuality
            return cached
        }
        let pulseAbpf = PulseExtraction.chromCombine(rFiltered: abpfR, gFiltered: abpfG, bFiltered: abpfB, rRaw: rawR, gRaw: rawG, bRaw: rawB)

        var harmonicMethodUsed = "adaptiveHarmonic"
        var gateSubstituted = false

        guard let abpfNotch = computeNotch(pulse: pulseAbpf, fs: fs, timestampsSeconds: timestampsSeconds) else {
            lastStatus = .lowSignalQuality
            return cached
        }

        var finalNotch = abpfNotch

        if useConfidenceGate && abpfNotch.confidence <= Self.confidenceGateBar {
            if let gauR = HarmonicSelectiveGaussianFilter.apply(detrendedR, frameRate: fs, numHarmonics: Self.numHarmonics, f0HzOverride: sharedF0Hz, alpha: Self.gaussianAlpha)?.filtered,
               let gauG = HarmonicSelectiveGaussianFilter.apply(detrendedG, frameRate: fs, numHarmonics: Self.numHarmonics, f0HzOverride: sharedF0Hz, alpha: Self.gaussianAlpha)?.filtered,
               let gauB = HarmonicSelectiveGaussianFilter.apply(detrendedB, frameRate: fs, numHarmonics: Self.numHarmonics, f0HzOverride: sharedF0Hz, alpha: Self.gaussianAlpha)?.filtered {
                let pulseGaussian = PulseExtraction.chromCombine(rFiltered: gauR, gFiltered: gauG, bFiltered: gauB, rRaw: rawR, gRaw: rawG, bRaw: rawB)

                if let gaussianNotch = computeNotch(pulse: pulseGaussian, fs: fs, timestampsSeconds: timestampsSeconds) {
                    let gateResult = HarmonicFilterConfidenceGate.select(
                        primary: .init(signal: pulseAbpf, notchConfidence: abpfNotch.confidence, methodLabel: "adaptiveHarmonic"),
                        fallbacks: [.init(signal: pulseGaussian, notchConfidence: gaussianNotch.confidence, methodLabel: "gaussian015")]
                    )
                    if let gateResult = gateResult, gateResult.wasSubstituted {
                        harmonicMethodUsed = "gaussian015"
                        gateSubstituted = true
                        finalNotch = gaussianNotch
                    }
                    // else: ABPF stays selected -- gateResult still reports
                    // it, but abpfNotch (already computed) is identical, no
                    // need to recompute anything.
                }
                // If the Gaussian candidate itself failed (too-short/too-
                // few-beats window), the gate never gets a chance to run --
                // stay on ABPF's own result, which already succeeded above.
            }
        }

        let estimate = Estimate(
            notchDetected: finalNotch.detected,
            notchPositionNormalized: finalNotch.positionNormalized,
            notchDepth: finalNotch.depth,
            notchConfidence: finalNotch.confidence,
            notchConfidenceRaw: finalNotch.confidenceRaw,
            harmonicMethodUsed: harmonicMethodUsed,
            gateSubstituted: gateSubstituted,
            waveform: finalNotch.waveform,
            continuousWaveform: finalNotch.continuousWaveform,
            fs: fs,
            bandModeUsed: bandMode
        )

        Self.logger.debug(
            """
            fs=\(fs, format: .fixed(precision: 2))Hz band=\(String(describing: bandMode)) method=\(harmonicMethodUsed) \
            substituted=\(gateSubstituted) notchDetected=\(estimate.notchDetected) \
            notchConf=\(estimate.notchConfidence, format: .fixed(precision: 3)) notchConfRaw=\(estimate.notchConfidenceRaw, format: .fixed(precision: 3))
            """
        )

        cached = estimate
        lastStatus = .ok
        return estimate
    }

    private struct NotchWithWaveform {
        let detected: Bool
        let positionNormalized: Double
        let depth: Double
        let confidence: Double
        let confidenceRaw: Double
        let waveform: [Double]
        let continuousWaveform: [Double] // tail-windowed resampled.sigUniform -- see Estimate.continuousWaveform's own doc
    }

    /// `FixPolarity` -> `ResampleUniform` -> `EnsembleAverageBeats` ->
    /// `NotchDetectIEM`, exactly matching the MATLAB pipeline's own
    /// per-candidate sequence. Returns nil if `EnsembleAverageBeats` can't
    /// find enough beats in THIS particular candidate signal.
    private func computeNotch(pulse: [Double], fs: Double, timestampsSeconds: [Double]) -> NotchWithWaveform? {
        guard let polarity = FixPolarity.apply(pulse, frameRate: fs) else { return nil }
        let resampled = ResampleUniform.apply(polarity.oriented, timestampsSeconds: timestampsSeconds)
        guard let beats = EnsembleAverageBeats.apply(resampled.sigUniform, fs: resampled.targetFs) else { return nil }
        guard let hrBpmUsed = HeartRateFft.estimateBpm(resampled.sigUniform, fs: resampled.targetFs)?.bpm else { return nil }
        let effectiveFsHz = Double(beats.prototype.trimmedMean.count) * (hrBpmUsed / 60.0)
        guard let notch = NotchDetectIEM.apply(beats.prototype.trimmedMean, fs: effectiveFsHz) else { return nil }

        // Tail-window resampled.sigUniform to the last
        // continuousDisplaySeconds -- the full window can be up to
        // SignalBuffer.windowDurationSeconds (25s) long, which at a resting
        // HR would cram 25-40+ cycles into one view; a shorter recent slice
        // reads like an actual monitor trace, not a dense scribble.
        let displaySamples = min(Int(resampled.targetFs * Self.continuousDisplaySeconds), resampled.sigUniform.count)
        let continuousWaveform = Array(resampled.sigUniform.suffix(displaySamples))

        return NotchWithWaveform(
            detected: notch.detected, positionNormalized: notch.positionNormalized, depth: notch.depth,
            confidence: notch.confidence, confidenceRaw: notch.confidenceRaw,
            waveform: beats.prototype.trimmedMean, continuousWaveform: continuousWaveform
        )
    }

    /// Heavier per-window cost than Branch 1 -- recomputed less often than
    /// `RealHeartRateEstimator`'s 1000ms. Not tuned against a real on-device
    /// CPU budget this session (no device attached, mirroring the Android
    /// port's own un-tuned starting point before its own on-device pass).
    private static let recomputeIntervalMs: Int64 = 2000
    private static let minWindowSeconds = 10.0 // FixPolarity's own minimum
    private static let minSamples = 60

    private static let numHarmonics = 6
    private static let gaussianAlpha = 0.15 // this project's own validated value, not the paper's 0.5
    private static let confidenceGateBar = 0.3

    /// How many of the most recent seconds of the continuous, resampled
    /// pulse to expose via `Estimate.continuousWaveform` -- see that
    /// field's own doc. Same value the Android port's own Segment 31 used
    /// (an arbitrary, unmeasured choice there too -- not re-verified for
    /// iOS specifically).
    private static let continuousDisplaySeconds = 8.0
}
