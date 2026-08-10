package com.spandan.app.signal

import android.util.Log
import kotlin.math.abs

/**
 * Real HR pipeline, replacing PlaceholderVitalsEstimator.computeHeartRatePlaceholder():
 * detrend -> bandpass -> CHROM/POS -> re-filter -> FFT peak -> CHROM/POS switch -> bpm.
 *
 * Ports (in order) matlab/src/filtering/detrendSignal.m, bandpassClean.m,
 * matlab/src/pulseextraction/{chromCombine,posCombine}.m, and
 * matlab/src/heartrate/fftHeartRate.m, operating on SignalBuffer's current window.
 *
 * The displayed "LIVE" value is chosen per reading by the CHROM/POS switching rule
 * in ../../../../../../docs/Android_HR_Switching_Port_Spec.md (exact formula/threshold,
 * ported verbatim, not reinterpreted): relative_disagreement < 29.27% -> CHROM,
 * otherwise -> POS. Both raw values are still exposed via [Estimate] and Log.d'd every
 * recompute so the switch's behavior can be audited against CHROM-alone/POS-alone.
 *
 * This is a BATCH operation over the whole buffered window, not a causal/streaming
 * filter -- recomputed at most once per RECOMPUTE_INTERVAL_MS, because zero-phase
 * filtfilt requires seeing the whole window at once (same reason MATLAB's filtfilt
 * call is offline/batch, not sample-by-sample).
 *
 * SpO2 is untouched by this file -- see
 * PlaceholderVitalsEstimator.computeSpo2Placeholder(), still fake by design.
 */
class RealHeartRateEstimator {

    /**
     * [chromBpm]/[posBpm]: the raw, un-switched values (kept for auditing/logging).
     * [displayedBpm]: the value the switching rule actually selects -- this is what
     * [update] returns.
     * [relativeDisagreement]: `abs(chromBpm-posBpm) / mean(chromBpm,posBpm)`, a
     * fraction (0.0-1.0+), per the spec.
     * [usedPos]: true if the switch fired (relativeDisagreement >= SWITCH_THRESHOLD),
     * i.e. displayedBpm == posBpm for this reading.
     */
    data class Estimate(
        val chromBpm: Double,
        val posBpm: Double,
        val displayedBpm: Double,
        val relativeDisagreement: Double,
        val usedPos: Boolean
    )

    private var lastComputeMs = 0L
    private var cached: Estimate? = null

    /** Returns the latest displayed bpm (CHROM or POS, per the switching rule), or
     *  null if not enough buffered data yet (early in a session, or fs momentarily
     *  unmeasurable). */
    fun update(samples: List<RgbSample>, nowMs: Long = System.currentTimeMillis()): Double? {
        if (nowMs - lastComputeMs < RECOMPUTE_INTERVAL_MS) {
            return cached?.displayedBpm
        }
        lastComputeMs = nowMs

        if (samples.size < MIN_SAMPLES) return cached?.displayedBpm
        val windowSeconds = (samples.last().timestampMs - samples.first().timestampMs) / 1000.0
        if (windowSeconds < MIN_WINDOW_SECONDS) return cached?.displayedBpm

        // Runtime-measured fs from real sample timestamps -- never hardcoded, same
        // discipline as bandpassClean.m/fftHeartRate.m's own "frameRate must not be
        // hardcoded" notes, since on-device camera fps varies by device/lighting.
        val fs = (samples.size - 1) / windowSeconds
        if (fs <= 2.0 * HeartRateFft.HIGH_BAND_HZ) {
            Log.w(TAG, "Measured fs=$fs Hz too low for the 0.7-4Hz band; skipping this window")
            return cached?.displayedBpm
        }

        val rawR = DoubleArray(samples.size) { samples[it].red.toDouble() }
        val rawG = DoubleArray(samples.size) { samples[it].green.toDouble() }
        val rawB = DoubleArray(samples.size) { samples[it].blue.toDouble() }

        val detrendedR = BandpassFilter.detrend(rawR)
        val detrendedG = BandpassFilter.detrend(rawG)
        val detrendedB = BandpassFilter.detrend(rawB)

        val filteredR = BandpassFilter.apply(detrendedR, fs)
        val filteredG = BandpassFilter.apply(detrendedG, fs)
        val filteredB = BandpassFilter.apply(detrendedB, fs)

        val chromRaw = PulseExtraction.chromCombine(filteredR, filteredG, filteredB, rawR, rawG, rawB)
        val posRaw = PulseExtraction.posCombine(filteredR, filteredG, filteredB, rawR, rawG, rawB)

        // Re-filter after combination: combining channels can reintroduce
        // out-of-band content, same reasoning as Segment 4's explanation doc.
        val chromFiltered = BandpassFilter.apply(chromRaw, fs)
        val posFiltered = BandpassFilter.apply(posRaw, fs)

        val chromResult = HeartRateFft.estimateBpm(chromFiltered, fs)
        val posResult = HeartRateFft.estimateBpm(posFiltered, fs)

        if (chromResult == null || posResult == null) {
            Log.w(TAG, "No FFT bin fell inside 0.7-4Hz for fs=$fs n=${samples.size}; keeping last estimate")
            return cached?.displayedBpm
        }

        // CHROM/POS switch -- exact formula/threshold from
        // docs/Android_HR_Switching_Port_Spec.md section 4. Both bpm values already
        // exist above; this is a small arithmetic addition, not new DSP.
        val meanBpm = (chromResult.bpm + posResult.bpm) / 2.0
        val relativeDisagreement = if (meanBpm > 0) abs(chromResult.bpm - posResult.bpm) / meanBpm else 0.0
        val usedPos = relativeDisagreement >= SWITCH_THRESHOLD
        val displayedBpm = if (usedPos) posResult.bpm else chromResult.bpm

        Log.d(
            TAG,
            ("fs=%.2fHz n=%d window=%.1fs  HR_chrom=%.1fbpm  HR_pos=%.1fbpm  (delta=%.1fbpm)  " +
                "relative_disagreement=%.2f%%  displayed=%s (%.1fbpm)").format(
                fs, samples.size, windowSeconds, chromResult.bpm, posResult.bpm,
                chromResult.bpm - posResult.bpm, relativeDisagreement * 100.0,
                if (usedPos) "POS" else "CHROM", displayedBpm
            )
        )

        cached = Estimate(chromResult.bpm, posResult.bpm, displayedBpm, relativeDisagreement, usedPos)
        return displayedBpm
    }

    companion object {
        private const val TAG = "RealHeartRateEstimator"
        private const val RECOMPUTE_INTERVAL_MS = 1000L
        private const val MIN_WINDOW_SECONDS = 4.0
        private const val MIN_SAMPLES = 60

        /** Exact threshold from docs/Android_HR_Switching_Port_Spec.md section 3 --
         *  a natural gap measured in the 112-subject UBFC+VIPL pool's
         *  relative_disagreement distribution, not a value invented here. */
        const val SWITCH_THRESHOLD = 0.2927
    }
}
