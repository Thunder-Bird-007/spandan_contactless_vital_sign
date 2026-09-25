package com.spandan.app.signal

import org.jtransforms.fft.DoubleFFT_1D
import kotlin.math.hypot

/**
 * Real port of matlab/src/heartrate/fftHeartRate.m (read directly from source
 * before writing this): FFT magnitude spectrum -> restrict to the 0.7-4Hz
 * physiological band (masking BEFORE peak search, matching the MATLAB source's
 * explicit safety-net comment -- a global max could otherwise land outside the
 * valid band) -> peak bin -> Hz -> bpm.
 *
 * frameRate/fs is always the caller's runtime-measured value -- never hardcoded,
 * same as MATLAB's `freqResolution = frameRate / signalLength`.
 */
object HeartRateFft {

    const val LOW_BAND_HZ = 0.7
    const val HIGH_BAND_HZ = 4.0

    data class Result(val bpm: Double, val peakFreqHz: Double)

    /** Returns null if no FFT bin falls inside the 0.7-4Hz band for this fs/window
     *  length (mirrors fftHeartRate.m's `error('fftHeartRate:emptyBand', ...)`,
     *  translated to a soft null since this runs live on-device rather than as an
     *  offline batch script). */
    fun estimateBpm(pulseSignal: DoubleArray, fs: Double): Result? {
        val n = pulseSignal.size
        if (n < 4) return null

        val complexData = DoubleArray(2 * n)
        for (i in 0 until n) complexData[2 * i] = pulseSignal[i]
        DoubleFFT_1D(n.toLong()).complexForward(complexData)

        // fft() of a real signal is symmetric -- keep only 0Hz..Nyquist, same as
        // fftHeartRate.m's `numPositiveBins = floor(signalLength/2) + 1`.
        val numPositiveBins = n / 2 + 1
        val freqResolution = fs / n

        var peakFreqHz = -1.0
        var peakMag = -1.0
        for (k in 0 until numPositiveBins) {
            val freq = k * freqResolution
            if (freq < LOW_BAND_HZ || freq > HIGH_BAND_HZ) continue
            val mag = hypot(complexData[2 * k], complexData[2 * k + 1])
            if (mag > peakMag) {
                peakMag = mag
                peakFreqHz = freq
            }
        }
        if (peakFreqHz < 0.0) return null

        return Result(bpm = peakFreqHz * 60.0, peakFreqHz = peakFreqHz)
    }
}
