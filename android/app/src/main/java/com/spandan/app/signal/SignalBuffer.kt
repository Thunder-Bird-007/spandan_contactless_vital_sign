package com.spandan.app.signal

/**
 * Rolling time-windowed buffer of ROI-averaged RGB samples. Real, permanent
 * code -- this is bookkeeping (drop samples older than the window),
 * independent of whichever algorithm eventually consumes the buffer.
 */
class SignalBuffer(private val windowSeconds: Double = WINDOW_DURATION_SECONDS) {

    private val samples = ArrayDeque<RgbSample>()

    @Synchronized
    fun add(sample: RgbSample) {
        samples.addLast(sample)
        val cutoffMs = sample.timestampMs - (windowSeconds * 1000).toLong()
        while (samples.isNotEmpty() && samples.first().timestampMs < cutoffMs) {
            samples.removeFirst()
        }
    }

    @Synchronized
    fun snapshot(): List<RgbSample> = samples.toList()

    @Synchronized
    fun clear() = samples.clear()

    companion object {
        /**
         * The single, tunable knob for how much wall-clock history the rolling
         * buffer keeps. Everything downstream (FFT bin resolution, on-screen
         * jitter, responsiveness to a changing HR) is a function of this one
         * number -- see android/README.md's "Diagnostic" and window-length
         * verification sections for the measurements behind the current value.
         *
         * Was 10.0 (~134 samples at the measured ~13.4Hz on-device throughput).
         * Raised to 25.0 (~335 samples) after the timing diagnostic ruled out
         * bursty/irregular sampling (CV=0.063, zero gaps >2x mean) as the cause
         * of on-screen jitter, leaving "too few samples per window" as the
         * better-supported explanation. 25s is a deliberate middle ground, not
         * an attempt to match MATLAB's ~80s/~2400-sample validated clips
         * (which would need ~3 minutes of steady holding at this throughput --
         * impractical for a live demo).
         */
        const val WINDOW_DURATION_SECONDS: Double = 25.0
    }
}
