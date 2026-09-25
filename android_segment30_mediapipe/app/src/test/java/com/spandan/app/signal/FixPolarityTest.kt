package com.spandan.app.signal

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class FixPolarityTest {

    /** A right-skewed (fast rise, slow decay -- like a "normal" PPG systolic
     *  upstroke/diastolic decay) synthetic pulse train, repeated to cover
     *  >10s at the given fs. */
    private fun rightSkewedPulseTrain(fs: Double, durationSec: Double, periodSec: Double): DoubleArray {
        val n = (fs * durationSec).toInt()
        return DoubleArray(n) { i ->
            val t = (i / fs) % periodSec
            val frac = t / periodSec
            // Fast rise (first 20% of cycle) then slow exponential-like decay.
            if (frac < 0.2) frac / 0.2 else Math.exp(-(frac - 0.2) * 4.0)
        }
    }

    @Test
    fun doesNotFlipARightSkewedSignal() {
        val fs = 30.0
        val sig = rightSkewedPulseTrain(fs, 15.0, 0.8)
        val result = FixPolarity.apply(sig, fs)
        assertTrue("expected a right-skewed signal to have positive skewness (skew=${result.skewValue})", result.skewValue > 0.0)
        assertFalse(result.wasFlipped)
        for (i in sig.indices) org.junit.Assert.assertEquals(sig[i], result.oriented[i], 1e-9)
    }

    @Test
    fun flipsANegatedRightSkewedSignal() {
        val fs = 30.0
        val sig = rightSkewedPulseTrain(fs, 15.0, 0.8)
        val negated = DoubleArray(sig.size) { -sig[it] }
        val result = FixPolarity.apply(negated, fs)
        assertTrue(result.wasFlipped)
        for (i in sig.indices) org.junit.Assert.assertEquals(sig[i], result.oriented[i], 1e-9)
    }

    @Test
    fun throwsOnTooShortSignal() {
        val fs = 30.0
        val sig = DoubleArray((fs * 5).toInt()) { Random(1).nextDouble() } // 5s < 10s minimum
        var threw = false
        try {
            FixPolarity.apply(sig, fs)
        } catch (e: IllegalArgumentException) {
            threw = true
        }
        assertTrue(threw)
    }
}
