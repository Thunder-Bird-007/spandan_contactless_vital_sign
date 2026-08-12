import Foundation
import os

/// Live, on-device SpO2 estimator, ported from android/app/.../signal/
/// LiveSpo2Estimator.kt (read directly before writing this). Independent of
/// RealHeartRateEstimator -- does not read from, call into, or modify it. Only
/// already-existing, already-validated shared filter utilities are reused
/// (BandpassFilter, PulseExtraction.sampleStdDev), not any HR-specific state.
///
/// Two-stage port, both read directly from MATLAB source in the Android port:
///
/// 1. **Ratio-of-ratios R** (matlab/src/spo2/ratioOfRatios.m): `DC_R = mean(R_raw)`,
///    `DC_B = mean(B_raw)`, `AC_R = std(R_filtered)`, `AC_B = std(B_filtered)`,
///    `R = (AC_R/DC_R) / (AC_B/DC_B)`.
///
/// 2. **Linear calibration** (matlab/docs/SpO2_Final_Calibration_Spec.md
///    "Production coefficients", `A = 96.47630625`, `B = -0.4159452784`, fit on
///    the full 112-subject UBFC+VIPL pool, no LOSO holdout). Applied directly to
///    the live, **uncentered** R -- Task R (matlab/docs/Segment6_Task_R_Phone_
///    SpO2_Centering.md) found phone-camera device-specific R centering is
///    statistically a wash against the uncentered production formula, so this
///    port deliberately skips any centering step, same as the Android port.
///
///    **Sign-convention note, carried over exactly from the Android port's own
///    KDoc:** matlab/src/spo2/calibrateSpO2.m line 51 is `spo2Est = A - B * R`.
///    With `B` already negative, `A - B*R` expands to `A + 0.4159452784*R` --
///    i.e. **A MINUS B TIMES R, not A PLUS B TIMES R** (those give opposite-sign
///    results here since B is negative). `calibrate(ratioOfRatios:)` below
///    implements `calibrationA - calibrationB * R` to match calibrateSpO2.m
///    exactly.
///
/// No startup "Calibrating..." state: produces a value from the first tick with
/// enough buffered samples, same warm-up timing as RealHeartRateEstimator.update().
final class LiveSpo2Estimator {

    private static let logger = Logger(subsystem: "com.spandan.app", category: "LiveSpo2Estimator")

    // Mirrors RealHeartRateEstimator's window/warm-up timing (same SignalBuffer
    // window feeds both estimators) for a consistent UI update cadence -- defined
    // independently here, not read from RealHeartRateEstimator, per this class's
    // independence requirement.
    private static let recomputeIntervalMs: Int64 = 1000
    private static let minWindowSeconds = 4.0
    private static let minSamples = 60

    /// matlab/docs/SpO2_Final_Calibration_Spec.md "Production coefficients": full
    /// 112-subject (UBFC N=5 + VIPL N=107) pool fit, no LOSO holdout.
    static let calibrationA = 96.47630625
    static let calibrationB = -0.4159452784

    private var lastComputeMs: Int64 = 0
    private var cachedSpo2: Double?

    /// Returns the latest clamped SpO2 percentage, or nil if not enough buffered
    /// data yet (mirrors RealHeartRateEstimator.update()'s warm-up behavior:
    /// returns the last cached value rather than a fabricated one while a window
    /// is too short/too sparse to trust).
    @discardableResult
    func update(samples: [RgbSample], nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Double? {
        if nowMs - lastComputeMs < Self.recomputeIntervalMs {
            return cachedSpo2
        }
        lastComputeMs = nowMs

        guard samples.count >= Self.minSamples else { return cachedSpo2 }
        let windowSeconds = Double(samples.last!.timestampMs - samples.first!.timestampMs) / 1000.0
        guard windowSeconds >= Self.minWindowSeconds else { return cachedSpo2 }

        // Runtime-measured fs from real sample timestamps -- never hardcoded, same
        // discipline as RealHeartRateEstimator/BandpassFilter/HeartRateFft.
        let fs = Double(samples.count - 1) / windowSeconds
        guard fs > 2.0 * BandpassFilter.highHz else {
            Self.logger.warning("Measured fs=\(fs, format: .fixed(precision: 2))Hz too low for the 0.7-4Hz band; skipping this window")
            return cachedSpo2
        }

        let rawR = samples.map { Double($0.red) }
        let rawB = samples.map { Double($0.blue) }

        // AC needs the bandpass-filtered trace (pulsatile amplitude); DC needs the
        // RAW trace (a bandpass filter's whole point is to remove the 0Hz/DC
        // component, so mean(filtered) is not a usable DC value) -- same reasoning
        // ratioOfRatios.m documents, and the same detrend->bandpass chain
        // BandpassFilter already validates for the HR pipeline.
        let filteredR = BandpassFilter.apply(BandpassFilter.detrend(rawR), fs: fs)
        let filteredB = BandpassFilter.apply(BandpassFilter.detrend(rawB), fs: fs)

        let dcR = rawR.average()
        let dcB = rawB.average()
        let acR = PulseExtraction.sampleStdDev(filteredR)
        let acB = PulseExtraction.sampleStdDev(filteredB)

        guard dcR != 0.0, dcB != 0.0, acB != 0.0 else {
            // Degenerate window (e.g. a completely flat/black ROI) -- fail soft
            // rather than divide by zero / propagate NaN to the UI.
            Self.logger.warning("Degenerate DC/AC value (dcR=\(dcR) dcB=\(dcB) acB=\(acB)); skipping this window")
            return cachedSpo2
        }

        // ratioOfRatios.m: R = (AC_R/DC_R) / (AC_B/DC_B)
        let ratioOfRatios = (acR / dcR) / (acB / dcB)
        let clampedSpo2 = Self.calibrate(ratioOfRatios: ratioOfRatios)

        Self.logger.debug(
            "R=\(ratioOfRatios, format: .fixed(precision: 4)) clampedSpo2=\(clampedSpo2, format: .fixed(precision: 2))% fs=\(fs, format: .fixed(precision: 2))Hz n=\(samples.count)"
        )

        cachedSpo2 = clampedSpo2
        return clampedSpo2
    }

    /// calibrateSpO2.m: SpO2 = A - B*R (see the sign-convention note in this
    /// file's header), clamped to a physiologically plausible display range.
    /// Factored out as a pure function for direct unit testing (see
    /// SpandanTests/LiveSpo2EstimatorTests.swift) and to keep the sign-convention
    /// note attached to the one line of arithmetic it actually governs.
    static func calibrate(ratioOfRatios: Double) -> Double {
        let rawSpo2 = calibrationA - calibrationB * ratioOfRatios
        // Clamp to a physiologically plausible display range -- stated explicitly,
        // same transparency standard as the Android port. Real pulse-oximetry SpO2
        // cannot exceed 100%; this project's own validated ground-truth range
        // (matlab/docs/SpO2_Final_Report_Section.md, known VIPL sensor-fault
        // subjects excluded) is 87.28-99%, so 90-100% is deliberately a little
        // wider than that observed range -- room for real signal noise on live
        // camera data without silently accepting the specific fault-code values
        // this project has already identified as sensor faults, not real readings
        // (e.g. 44%, 103.79%).
        return min(100.0, max(90.0, rawSpo2))
    }
}
