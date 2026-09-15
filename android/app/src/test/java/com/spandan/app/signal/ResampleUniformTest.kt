package com.spandan.app.signal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random

class ResampleUniformTest {

    @Test
    fun upsamplesIrregularlyTimedSamplesOntoAUniformHighRateGrid() {
        val durationSec = 10.0
        val f = 1.3
        val rng = Random(3)

        // Irregular timestamps (jittered around a nominal ~15Hz), same kind
        // of irregularity resampleUniform.m's own header describes for real
        // camera frame timing.
        val timestamps = mutableListOf(0.0)
        while (timestamps.last() < durationSec) {
            timestamps.add(timestamps.last() + (1.0 / 15.0) * (0.7 + rng.nextDouble() * 0.6))
        }
        val timestampsArr = timestamps.toDoubleArray()
        val sig = DoubleArray(timestampsArr.size) { sin(2 * PI * f * timestampsArr[it]) }

        val result = ResampleUniform.apply(sig, timestampsArr, targetFs = 200.0)

        assertEquals(200.0, result.targetFs, 1e-9)
        assertTrue(result.sigUniform.size > sig.size) // genuine upsampling

        // Check the resampled signal still tracks the known sine well away
        // from the very edges (PCHIP end-condition effects are largest there).
        var maxErr = 0.0
        for (i in result.timeUniform.indices) {
            val t = result.timeUniform[i]
            if (t < 0.5 || t > durationSec - 0.5) continue
            val expected = sin(2 * PI * f * t)
            maxErr = maxOf(maxErr, abs(result.sigUniform[i] - expected))
        }
        assertTrue("resampled signal drifted too far from the known sine (maxErr=$maxErr)", maxErr < 0.08)
    }

    @Test
    fun timeUniformSpansTheOriginalTimestampRange() {
        val timestamps = doubleArrayOf(0.0, 0.3, 0.9, 1.5, 2.0)
        val sig = doubleArrayOf(0.0, 1.0, 0.5, -0.5, 0.0)
        val result = ResampleUniform.apply(sig, timestamps, targetFs = 50.0)
        assertEquals(timestamps.first(), result.timeUniform.first(), 1e-9)
        assertTrue(result.timeUniform.last() <= timestamps.last() + 1e-9)
    }
}
