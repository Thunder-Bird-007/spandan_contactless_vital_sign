package com.spandan.app.signal

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/resampleUniform.m` (read directly from source
 * before writing this): resamples a pulse signal onto a uniform high-rate
 * time grid using its REAL per-sample timestamps (never assuming uniform
 * `1/fs` spacing) via [PchipInterpolator], for exactly the reason the
 * MATLAB header gives: camera frame timing is irregular, and the dicrotic
 * notch is a fine (tens-of-ms) time-domain feature that irregular-spacing-
 * as-if-uniform would smear.
 *
 * `RgbSample.timestampMs` (already real per-frame acquisition times, the
 * same field [SignalBuffer]/[RealHeartRateEstimator] use for their own
 * runtime-measured `fs`) is this port's equivalent of
 * `roi/extractROISignals.m`'s `roiTimestamps` output -- converted to
 * seconds here since MATLAB's own convention is seconds throughout.
 */
object ResampleUniform {

    const val DEFAULT_TARGET_FS = 250.0

    data class Result(val sigUniform: DoubleArray, val timeUniform: DoubleArray, val targetFs: Double)

    fun apply(sig: DoubleArray, timestampsSeconds: DoubleArray, targetFs: Double = DEFAULT_TARGET_FS): Result {
        require(sig.size == timestampsSeconds.size) { "sig and timestampsSeconds must have the same number of elements" }
        require(sig.size >= 2) { "need at least 2 samples to resample" }

        val startSec = timestampsSeconds.first()
        val endSec = timestampsSeconds.last()
        val stepSec = 1.0 / targetFs
        val numSteps = ((endSec - startSec) / stepSec).toInt() + 1
        val timeUniform = DoubleArray(numSteps) { startSec + it * stepSec }

        val sigUniform = PchipInterpolator.interpolate(timestampsSeconds, sig, timeUniform)
        return Result(sigUniform, timeUniform, targetFs)
    }
}
