package com.spandan.app.signal

/**
 * Segment 16 Task 1/2/3 -- shared status classification surfaced by
 * [RealHeartRateEstimator] and [LiveSpo2Estimator] alongside their existing
 * numeric output, so the UI (MainActivity, Task 3) can show WHY a value
 * isn't displaying instead of collapsing every non-value case into the same
 * generic "-- bpm"/"-- %" placeholder.
 *
 * PURELY ADDITIVE: does not change either estimator's numeric computation,
 * thresholds, or its update()'s existing `Double?` return contract. Both
 * estimators already branch over exactly these cases internally (see each
 * update()'s own early-return sites, unchanged by this task) -- this enum
 * only gives each branch a name a caller outside the class can read, instead
 * of the branch being visible only via Log.d/Log.w.
 */
enum class EstimatorStatus {
    /** A value was computed this tick, or the cached value from the last
     *  successful tick is still within its normal recompute cadence. */
    OK,

    /** Not enough buffered samples, or too short a time window, to compute
     *  anything yet -- normal right after app start or right after a face
     *  is reacquired following a gap. Not a signal-quality problem. */
    WARMING_UP,

    /** A real signal-quality problem this tick: measured fs too low for the
     *  required band, no FFT/ratio bin fell inside the valid band, or a
     *  degenerate (near-zero) AC/DC value was observed. E.g. very poor
     *  lighting, a mostly-occluded ROI, or motion severe enough to corrupt
     *  the window. */
    LOW_SIGNAL_QUALITY
}
