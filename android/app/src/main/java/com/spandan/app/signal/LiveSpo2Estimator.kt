package com.spandan.app.signal

import android.util.Log

/**
 * Live, on-device SpO2 estimator. Independent of RealHeartRateEstimator.kt --
 * does not read from, call into, or modify it. Only already-existing, already-
 * validated shared filter utilities are reused ([BandpassFilter],
 * [PulseExtraction.sampleStdDev]), not any HR-specific state.
 *
 * Two-stage port, both stages read directly from MATLAB source before writing
 * this (not from memory/description):
 *
 * 1. **Ratio-of-ratios R** (matlab/src/spo2/ratioOfRatios.m, formula ported
 *    exactly): `DC_R = mean(R_raw)`, `DC_B = mean(B_raw)`,
 *    `AC_R = std(R_filtered)`, `AC_B = std(B_filtered)`,
 *    `R = (AC_R/DC_R) / (AC_B/DC_B)`. The MATLAB function also accepts
 *    `G_filtered`/`G_raw` in its signature but never uses them in the formula
 *    itself -- matched here simply by this function not taking a G parameter
 *    at all, rather than porting an unused argument.
 *
 * 2. **Linear calibration** (matlab/docs/SpO2_Final_Calibration_Spec.md
 *    "Production coefficients", `A = 96.47630625`, `B = -0.4159452784`, fit on
 *    the full 112-subject UBFC+VIPL pool, no LOSO holdout -- a "what the
 *    deployed formula's numbers would be" snapshot; see that doc's own caveat
 *    and SpO2_Final_Report_Section.md for the actual validated LOSO accuracy).
 *    Applied here directly to the live, **uncentered** R -- Task R
 *    (matlab/docs/Segment6_Task_R_Phone_SpO2_Centering.md) found phone-camera
 *    device-specific R centering is statistically a wash against the
 *    uncentered production formula once known fault-code subjects are
 *    excluded (1.2609 vs 1.2590 MAE), so this build deliberately skips any
 *    centering step rather than invent an unvalidated one. This also
 *    supersedes an earlier plan to add a startup "Calibrating..."
 *    session-relative-baseline period -- not implemented, not needed.
 *
 *    **Sign-convention note, flagged rather than silently applied:** the
 *    calibration's own defining function, matlab/src/spo2/calibrateSpO2.m
 *    line 51, is `spo2Est = A - B * R` (its KDoc: "SpO2 = A - B*R ... SpO2
 *    falls as R rises"). With `B` already negative, `A - B*R` expands to
 *    `A + 0.4159452784*R`, i.e. **`A minus B times R`, not `A plus B times
 *    R`** (those give opposite-sign results here since `B` is negative).
 *    [update] implements `CALIBRATION_A - CALIBRATION_B * R` to match
 *    `calibrateSpO2.m` exactly.
 *
 * No startup "Calibrating..." state: produces a value from the first tick
 * with enough buffered samples, same warm-up timing discipline as
 * RealHeartRateEstimator.update().
 */
class LiveSpo2Estimator {

    private var lastComputeMs = 0L
    private var cachedSpo2: Double? = null

    /** Segment 16 Task 1/3 -- see [EstimatorStatus]'s own KDoc. Purely
     *  additive, same contract as [RealHeartRateEstimator.lastStatus]. */
    var lastStatus: EstimatorStatus = EstimatorStatus.WARMING_UP
        private set

    /**
     * Segment 16 Task 2 -- the per-channel perfusion index (PI = AC/DC, the
     * same quantity `ratioOfRatios.m`'s R formula already divides through by)
     * from the most recent successful computation, exposed for logging/
     * future thresholding. NOT currently used to gate [lastStatus] beyond
     * the existing hard near-zero guard below -- see
     * docs/Segment16_Task2_SpO2_Research_and_Audit.md for why a graded
     * numeric cutoff was not added this session (no real device capture
     * available to derive a defensible threshold from; recent literature,
     * e.g. arXiv:2607.08001, uses perfusion index as a calibration/quality
     * signal but on a different modality -- wrist IR/red contact PPG, not
     * facial RGB rPPG -- so its own numeric thresholds do not transfer
     * directly). Null until the first successful computation.
     */
    var lastPerfusionIndexRed: Double? = null
        private set
    var lastPerfusionIndexBlue: Double? = null
        private set

    /** Returns the latest clamped SpO2 percentage, or null if not enough
     *  buffered data yet (mirrors RealHeartRateEstimator.update()'s warm-up
     *  behavior: returns the last cached value rather than a fabricated one
     *  while a window is too short/too sparse to trust). */
    fun update(samples: List<RgbSample>, nowMs: Long = System.currentTimeMillis()): Double? {
        if (nowMs - lastComputeMs < RECOMPUTE_INTERVAL_MS) {
            return cachedSpo2
        }
        lastComputeMs = nowMs

        if (samples.size < MIN_SAMPLES) {
            lastStatus = EstimatorStatus.WARMING_UP
            return cachedSpo2
        }
        val windowSeconds = (samples.last().timestampMs - samples.first().timestampMs) / 1000.0
        if (windowSeconds < MIN_WINDOW_SECONDS) {
            lastStatus = EstimatorStatus.WARMING_UP
            return cachedSpo2
        }

        // Runtime-measured fs from real sample timestamps -- never hardcoded, same
        // discipline as RealHeartRateEstimator/BandpassFilter/HeartRateFft.
        val fs = (samples.size - 1) / windowSeconds
        if (fs <= 2.0 * BandpassFilter.HIGH_HZ) {
            Log.w(TAG, "Measured fs=$fs Hz too low for the 0.7-4Hz band; skipping this window")
            lastStatus = EstimatorStatus.LOW_SIGNAL_QUALITY
            return cachedSpo2
        }

        val rawR = DoubleArray(samples.size) { samples[it].red.toDouble() }
        val rawB = DoubleArray(samples.size) { samples[it].blue.toDouble() }

        // AC needs the bandpass-filtered trace (pulsatile amplitude); DC needs the
        // RAW trace (a bandpass filter's whole point is to remove the 0Hz/DC
        // component, so mean(filtered) is not a usable DC value) -- same reasoning
        // ratioOfRatios.m documents, and the same detrend->bandpass chain
        // BandpassFilter already validates for the HR pipeline.
        val filteredR = BandpassFilter.apply(BandpassFilter.detrend(rawR), fs)
        val filteredB = BandpassFilter.apply(BandpassFilter.detrend(rawB), fs)

        val dcR = rawR.average()
        val dcB = rawB.average()
        val acR = PulseExtraction.sampleStdDev(filteredR)
        val acB = PulseExtraction.sampleStdDev(filteredB)

        if (dcR == 0.0 || dcB == 0.0 || acB == 0.0) {
            // Degenerate window (e.g. a completely flat/black ROI) -- fail soft
            // rather than divide by zero / propagate NaN to the UI.
            Log.w(TAG, "Degenerate DC/AC value (dcR=$dcR dcB=$dcB acB=$acB); skipping this window")
            lastStatus = EstimatorStatus.LOW_SIGNAL_QUALITY
            return cachedSpo2
        }

        // Perfusion index per channel (Segment 16 Task 2) -- the same AC/DC
        // terms ratioOfRatios.m's R already divides through by, exposed here
        // as their own values rather than only the combined ratio. See this
        // class's own KDoc above for why this is logged/exposed but not yet
        // used as a graded confidence threshold.
        lastPerfusionIndexRed = acR / dcR
        lastPerfusionIndexBlue = acB / dcB

        // ratioOfRatios.m: R = (AC_R/DC_R) / (AC_B/DC_B)
        val ratioOfRatios = (acR / dcR) / (acB / dcB)

        // calibrateSpO2.m: SpO2 = A - B*R (see class KDoc's sign-convention note).
        val rawSpo2 = CALIBRATION_A - CALIBRATION_B * ratioOfRatios

        // Clamp to a physiologically plausible display range -- stated explicitly,
        // same transparency standard as elsewhere in this app. Real pulse-oximetry
        // SpO2 cannot exceed 100%; this project's own validated ground-truth range
        // (SpO2_Final_Report_Section.md, known VIPL sensor-fault subjects excluded)
        // is 87.28-99%, so 90-100% is deliberately a little wider than that observed
        // range -- room for real signal noise on live camera data without silently
        // accepting the specific fault-code values this project has already
        // identified as sensor faults, not real readings (e.g. 44%, 103.79%).
        val clampedSpo2 = rawSpo2.coerceIn(90.0, 100.0)

        Log.d(
            TAG,
            "R=%.4f rawSpo2=%.2f%% clampedSpo2=%.2f%% fs=%.2fHz n=%d PI_red=%.4f PI_blue=%.4f".format(
                ratioOfRatios, rawSpo2, clampedSpo2, fs, samples.size, lastPerfusionIndexRed, lastPerfusionIndexBlue
            )
        )

        cachedSpo2 = clampedSpo2
        lastStatus = EstimatorStatus.OK
        return clampedSpo2
    }

    companion object {
        private const val TAG = "LiveSpo2Estimator"

        // Mirrors RealHeartRateEstimator's window/warm-up timing (same SignalBuffer
        // window feeds both estimators) for a consistent UI update cadence -- defined
        // independently here, not read from RealHeartRateEstimator, per this class's
        // independence requirement.
        private const val RECOMPUTE_INTERVAL_MS = 1000L
        private const val MIN_WINDOW_SECONDS = 4.0
        private const val MIN_SAMPLES = 60

        /**
         * matlab/docs/SpO2_Final_Calibration_Spec.md "Production coefficients":
         * full 112-subject (UBFC N=5 + VIPL N=107) pool fit, no LOSO holdout.
         * matlab/docs/Segment6_Task_R_Phone_SpO2_Centering.md is the evidence that a
         * phone-camera-specific centering offset was checked and found unnecessary
         * for this device (statistically a wash vs. the uncentered fit once
         * fault-code subjects are excluded) -- that is why these constants are
         * applied directly below with no centering step, not an oversight.
         */
        const val CALIBRATION_A = 96.47630625
        const val CALIBRATION_B = -0.4159452784
    }
}
