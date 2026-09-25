import Foundation

/// Shared status classification surfaced by `RealHeartRateEstimator`,
/// `LiveSpo2Estimator`, and (as of this port) `MorphologyWaveformEstimator`
/// alongside their existing numeric output, so the UI can show WHY a value
/// isn't displaying instead of collapsing every non-value case into the
/// same generic placeholder. Direct port of
/// android/app/.../signal/EstimatorStatus.kt.
///
/// PURELY ADDITIVE: does not change any estimator's numeric computation,
/// thresholds, or its `update()`'s existing `Double?`/`Estimate?` return
/// contract.
enum EstimatorStatus {
    /// A value was computed this tick, or the cached value from the last
    /// successful tick is still within its normal recompute cadence.
    case ok

    /// Not enough buffered samples, or too short a time window, to compute
    /// anything yet -- normal right after app start or right after a face
    /// is reacquired following a gap. Not a signal-quality problem.
    case warmingUp

    /// A real signal-quality problem this tick: measured fs too low for the
    /// required band, no FFT/ratio bin fell inside the valid band, or a
    /// degenerate (near-zero) AC/DC value was observed.
    case lowSignalQuality
}
