package com.spandan.app.signal

/**
 * Segment 16 Task 1 -- DISPLAY-LEVEL temporal smoothing of the already-computed,
 * already-switched (CHROM/POS) bpm sequence [RealHeartRateEstimator] produces.
 *
 * WHY THIS EXISTS, AND WHY IT IS NOT KALMAN FILTERING: android/README.md's
 * "Window-length change" and "Diagnostic" sections already root-caused the
 * on-screen HR jitter to sparse real-device sampling (coarse FFT bin
 * resolution from a short window), and matlab/docs/
 * Segment6_Task5_RAKF_Kalman_Smoothing.md already tested residual/quality-
 * adaptive Kalman smoothing (RAKF) on the MATLAB side and found it the WORST
 * of six methods compared (MAE 12.15 vs. 9.35 baseline on the 107-subject
 * VIPL pool) -- worse than doing nothing. Per Segment 16's own brief, RAKF is
 * NOT re-implemented or re-proposed here. What IS different this time,
 * stated explicitly rather than glossed over:
 *   1. RAKF operated on the SIGNAL itself (a state-space model estimating the
 *      true underlying bpm from noisy per-window measurements, feeding back
 *      into what's treated as "the" HR estimate). This class does not do
 *      that -- it never touches [RealHeartRateEstimator]'s own computation,
 *      never feeds smoothed output back into any DSP stage, and is applied
 *      strictly AFTER the CHROM/POS switch has already produced a value.
 *      It changes only what character appears in [MainActivity]'s hrText
 *      view, nothing the pipeline itself sees or uses.
 *   2. RAKF's failure mode (per the MATLAB doc's own analysis) was that
 *      residual-adaptive smoothing actively fought Task P/Q's own
 *      window-to-window quality signal, and random-walk state smoothing
 *      lags behind genuine step changes in HR under the SAME per-window
 *      noise floor that made naive/gating-only windowing win instead. A
 *      rolling median has a different, simpler failure mode (median lag
     *  behind a step change, bounded by median window length) and does not
 *      claim to track a state-space model of "the true HR" at all -- it is
 *      explicitly a display convenience, not an accuracy claim, matching the
 *      android/README.md follow-up note that first flagged this idea
 *      ("could reduce on-screen jitter for display purposes... a real
 *      deviation from faithful port... not added without an explicit
 *      decision from the team" -- this task IS that explicit decision).
 *   3. This is gated OFF by default ([MainActivity.ENABLE_HR_DISPLAY_SMOOTHING])
 *      pending a real on-device before/after comparison -- not evaluated on
 *      real hardware in the same session this class was written (no test
 *      device was available), consistent with this project's own standing
 *      discipline of not promoting an unevaluated change to the default.
 *      See docs/Segment16_Task1_HR_Stability.md for the exact test plan for
 *      whoever next has the physical device.
 *
 * Two modes, both operating on a short rolling history of raw bpm values
 * (NOT the raw RGB signal, NOT FFT bins -- purely a sequence of already-
 * final bpm numbers):
 *   - [Mode.ROLLING_MEDIAN] (default): median of the last [windowSize]
 *     displayed values. Robust to a single wild outlier reading (a median
 *     of 5 needs 3 bad readings in a row to move much), at the cost of a
 *     step lag of up to [windowSize] ticks after a genuine HR change.
 *   - [Mode.EMA]: exponential moving average, `smoothed = alpha*new +
 *     (1-alpha)*old`. Reacts faster to a sustained change than the median
 *     (no fixed window to "fill"), but a single outlier still nudges the
 *     output rather than being fully rejected the way the median rejects it.
 *   - [Mode.NONE]: passthrough, for a clean A/B toggle without removing this
 *     class from the call site.
 *
 * Deliberately stateless with respect to anything else in the app -- takes
 * a bpm value in, returns a bpm value out. [MainActivity] owns one instance
 * per displayed metric (HR) and feeds it the metric's own already-computed
 * value each UI refresh tick.
 *
 * REAL BUG FOUND AND FIXED VIA THIS SEGMENT'S OWN ON-DEVICE A/B TEST (not
 * caught by the unit tests, which only ever fed genuinely distinct values):
 * [MainActivity] calls [smooth] once per UI refresh tick (200ms), but
 * [RealHeartRateEstimator.update] only recomputes a NEW value roughly once
 * per second (`RECOMPUTE_INTERVAL_MS`) -- so the SAME raw value was being
 * pushed into the rolling-median history ~5 times per real recompute,
 * meaning a `windowSize=5` "window" only ever spanned about ONE real
 * measurement's lifetime, not five independent ones as the class's own
 * design intended. On real device logs (`SPANDAN_SMOOTH` diagnostic,
 * 2026-09-14), this showed up as the median lagging a genuine HR change by
 * only 2-3 ticks (~400-600ms) instead of behaving like a true 5-measurement
 * median. Fixed by de-duplicating consecutive identical inputs BEFORE they
 * reach the history/EMA state below -- a repeated tick of the same
 * already-seen value is a no-op, identical to the existing null-handling
 * contract, not a new independent sample.
 */
class DisplaySmoother(
    private val mode: Mode = Mode.ROLLING_MEDIAN,
    private val windowSize: Int = DEFAULT_WINDOW_SIZE,
    private val emaAlpha: Double = DEFAULT_EMA_ALPHA
) {
    enum class Mode { NONE, ROLLING_MEDIAN, EMA }

    private val history = ArrayDeque<Double>()
    private var emaValue: Double? = null
    private var lastOutput: Double? = null
    private var lastRawInput: Double? = null

    /**
     * Feeds one new raw value through the smoother and returns the smoothed
     * value. Passing `null` (the pipeline's own "not enough data yet" signal)
     * is a no-op that returns the last smoothed OUTPUT (not merely the last
     * raw input -- for [Mode.ROLLING_MEDIAN] these differ) without touching
     * the history -- a warm-up gap should not count as "the HR just did
     * something," and should not get averaged in as if it were a real
     * reading of 0. A repeated call with the SAME raw value as last time
     * (the caller's UI-refresh tick running faster than the pipeline's own
     * recompute cadence -- see this class's own header) is likewise a no-op
     * for the same reason: it is not a new independent measurement.
     */
    fun smooth(newValue: Double?): Double? {
        if (newValue == null) {
            return lastOutput
        }
        if (newValue == lastRawInput) {
            return lastOutput
        }
        lastRawInput = newValue

        val output = when (mode) {
            Mode.NONE -> newValue

            Mode.ROLLING_MEDIAN -> {
                history.addLast(newValue)
                while (history.size > windowSize) history.removeFirst()
                median(history)
            }

            Mode.EMA -> {
                val prev = emaValue
                val next = if (prev == null) newValue else emaAlpha * newValue + (1 - emaAlpha) * prev
                emaValue = next
                next
            }
        }
        lastOutput = output
        return output
    }

    /** Discards all history -- call when starting a fresh session/window
     *  (e.g. after a long no-face gap) so a stale reading from before the
     *  gap doesn't drag down a median/EMA computed from data that no longer
     *  represents anything continuous. Not currently wired to any caller
     *  automatically -- exposed for a future session to decide whether a
     *  no-face gap should reset smoothing state; NOT resetting on every gap
     *  is this class's own current default behavior. */
    fun reset() {
        history.clear()
        emaValue = null
        lastOutput = null
        lastRawInput = null
    }

    private fun median(values: Collection<Double>): Double {
        val sorted = values.sorted()
        val n = sorted.size
        return if (n % 2 == 1) {
            sorted[n / 2]
        } else {
            (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
        }
    }

    companion object {
        /** 5 ticks at MainActivity's 1s-ish recompute cadence (~5s of history)
         *  -- short enough to still respond to a real HR change within a
         *  demo-length interaction, long enough to reject a 1-2 tick outlier.
         *  Not tuned against real device data (no device available this
         *  session) -- a reasonable starting value, flagged for the real
         *  on-device test to confirm or adjust. */
        const val DEFAULT_WINDOW_SIZE = 5

        /** alpha=0.3: ~70% of a step change is reflected within 4 ticks
         *  (1-(1-0.3)^4 = 0.76). Same "not tuned on real data" caveat as
         *  DEFAULT_WINDOW_SIZE above. */
        const val DEFAULT_EMA_ALPHA = 0.3
    }
}
