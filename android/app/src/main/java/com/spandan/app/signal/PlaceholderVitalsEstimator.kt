package com.spandan.app.signal

import kotlin.math.sin

/**
 * ============================================================================
 *  PLACEHOLDER MATH -- NOT A REAL ALGORITHM. DO NOT TRUST THESE NUMBERS.
 * ============================================================================
 *
 * Everything in this file stands in for the real DSP pipeline that will
 * eventually live here:
 *   - detrending + bandpass filtering   -> matlab/src/filtering/
 *   - CHROM / POS combination           -> matlab/src/pulseextraction/
 *   - FFT-based HR estimation           -> matlab/src/heartrate/
 *   - ratio-of-ratios + calibrated SpO2 -> matlab/src/spo2/
 *
 * None of that has been ported here on purpose: the MATLAB side hasn't run
 * its formal LOSO validation (Segment 6) yet, so there are no finalized
 * filter coefficients, CHROM/POS formulas, or calibration constants to port.
 * This file exists purely so the rest of the app (camera -> ROI -> buffer ->
 * UI) can be built, run, and demoed end-to-end without waiting on that.
 *
 * When Segment 6 finalizes the MATLAB pipeline, replace this file's
 * contents (and only this file's contents -- callers just want a bpm and a
 * %SpO2 number, the interface doesn't need to change).
 */
object PlaceholderVitalsEstimator {

    private const val BASELINE_HR_BPM = 75.0

    /**
     * Fake HR: a naive zero-crossing count on the RAW (unfiltered!) buffered
     * green channel, blended with a slow sine drift so the number visibly
     * reacts to the incoming signal without being total noise when the
     * crossing count is degenerate. This is NOT how real PPG HR estimation
     * works -- no detrending, no bandpass, no CHROM/POS, no FFT -- it is only
     * meant to prove the camera -> ROI -> buffer -> UI pipeline moves data
     * end to end.
     */
    fun computeHeartRatePlaceholder(buffer: List<RgbSample>, elapsedSeconds: Double): Double {
        val drift = BASELINE_HR_BPM + 6.0 * sin(elapsedSeconds / 8.0)
        if (buffer.size < 4) return drift.coerceIn(60.0, 90.0)

        val greens = buffer.map { it.green }
        val mean = greens.average()
        var crossings = 0
        for (i in 1 until greens.size) {
            if (greens[i - 1] - mean < 0 && greens[i] - mean >= 0) crossings++
        }

        val windowSeconds = (buffer.last().timestampMs - buffer.first().timestampMs) / 1000.0
        val naiveBpm = if (windowSeconds > 0.5) (crossings / windowSeconds) * 60.0 else drift

        val blended = if (naiveBpm in 40.0..180.0) 0.5 * naiveBpm + 0.5 * drift else drift
        return blended.coerceIn(60.0, 90.0)
    }

    /**
     * Fake SpO2: a pure time-based dummy oscillation, not derived from the
     * signal at all. Real implementation needs an R/B ratio-of-ratios plus a
     * calibration fit (matlab/src/spo2/ratioOfRatios.m + calibrateSpO2.m),
     * neither of which exists in finalized form yet.
     */
    fun computeSpo2Placeholder(elapsedSeconds: Double): Double {
        return (97.0 + 1.5 * sin(elapsedSeconds / 15.0)).coerceIn(94.0, 99.0)
    }
}
