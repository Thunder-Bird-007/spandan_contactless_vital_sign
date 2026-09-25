package com.spandan.app.signal

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Plain Kotlin/JUnit test, no Android device needed. Feeds a synthetic sine at a
 * known in-band frequency (1.2Hz, ~72bpm) and a known out-of-band frequency (0.2Hz)
 * through BandpassFilter and confirms the in-band component survives with roughly
 * unity gain while the out-of-band component is substantially attenuated -- the
 * same "verify before trusting on real data" discipline the MATLAB side applied
 * (Hoffman dataset sanity check) before trusting bandpassClean.m on real subjects.
 */
class BandpassFilterTest {

    /** Quadrature (sine/cosine correlation) amplitude estimate of a single frequency
     *  component in `signal`, used only to score filter output -- not part of the
     *  shipped pipeline. */
    private fun sineAmplitude(signal: DoubleArray, freqHz: Double, fs: Double): Double {
        val n = signal.size
        var sumCos = 0.0
        var sumSin = 0.0
        for (i in 0 until n) {
            val t = i / fs
            sumCos += signal[i] * cos(2 * PI * freqHz * t)
            sumSin += signal[i] * sin(2 * PI * freqHz * t)
        }
        return 2.0 / n * sqrt(sumCos * sumCos + sumSin * sumSin)
    }

    @Test
    fun inBandSinePassesWhileOutOfBandSineIsAttenuated() {
        val fs = 30.0
        val durationSeconds = 10.0
        val n = (fs * durationSeconds).toInt()

        val inBandHz = 1.2      // ~72 bpm, inside the 0.7-4Hz passband
        val outOfBandHz = 0.2   // well below the 0.7Hz low cutoff

        val input = DoubleArray(n) { i ->
            val t = i / fs
            sin(2 * PI * inBandHz * t) + sin(2 * PI * outOfBandHz * t)
        }

        val output = BandpassFilter.apply(input, fs)

        val inBandIn = sineAmplitude(input, inBandHz, fs)
        val outOfBandIn = sineAmplitude(input, outOfBandHz, fs)
        val inBandOut = sineAmplitude(output, inBandHz, fs)
        val outOfBandOut = sineAmplitude(output, outOfBandHz, fs)

        println(
            "BandpassFilterTest: in-band(${inBandHz}Hz) in=$inBandIn out=$inBandOut " +
                "gain=${inBandOut / inBandIn}"
        )
        println(
            "BandpassFilterTest: out-of-band(${outOfBandHz}Hz) in=$outOfBandIn out=$outOfBandOut " +
                "gain=${outOfBandOut / outOfBandIn}"
        )

        assertTrue("amplitude estimator sanity check on raw input", inBandIn > 0.8)
        assertTrue("in-band signal should pass with roughly unity gain", inBandOut > 0.5 * inBandIn)
        assertTrue("out-of-band signal should be substantially attenuated", outOfBandOut < 0.25 * outOfBandIn)
        assertTrue("in-band should dominate out-of-band after filtering", inBandOut > 3.0 * outOfBandOut)
    }
}
