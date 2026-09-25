package com.spandan.app.signal

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.exp

class NotchDetectIEMTest {

    /** Builds a synthetic 256-point beat prototype: fast systolic rise to a
     *  peak at frac=0.25, slower decay, with a real dicrotic-notch-shaped
     *  dip carved into the decay limb around frac=0.45. */
    private fun buildPrototypeWithNotch(notchDepthAmplitude: Double): DoubleArray {
        val n = 256
        return DoubleArray(n) { i ->
            val frac = i / (n - 1.0)
            val base = if (frac < 0.25) frac / 0.25 else exp(-(frac - 0.25) * 3.0)
            val notchCenter = 0.45
            val notch = notchDepthAmplitude * exp(-((frac - notchCenter) * 20.0) * ((frac - notchCenter) * 20.0))
            base - notch
        }
    }

    @Test
    fun detectsARealNotchAfterTheSystolicPeak() {
        val prototype = buildPrototypeWithNotch(notchDepthAmplitude = 0.15)
        val fs = 256.0 // one full 256-sample cycle spanning 1 real second

        val result = NotchDetectIEM.apply(prototype, fs)

        assertTrue("expected a notch to be detected on a prototype with a real carved-in dip", result.detected)
        assertTrue("notch position should fall after the systolic peak (frac>0.25)", result.positionNormalized > 0.25)
        assertTrue("notch position should be well before the cycle's end", result.positionNormalized < 0.8)
        assertTrue("expected a positive notch depth", result.depth > 0.0)
        assertTrue("expected a positive confidence", result.confidence > 0.0)
        assertTrue("confidence must stay within [0,1]", result.confidence <= 1.0)
        assertTrue("confidenceRaw must be >= confidence (confidence is the clipped version)", result.confidenceRaw >= result.confidence)
    }

    @Test
    fun aSmoothMonotoneDecayProducesAWellFormedResultEitherWay() {
        // No carved-in dip at all -- a pure fast-rise/slow-decay shape. Per
        // the MATLAB source's own documented caveat (its header, and the
        // real pooled finding in `matlab/docs/Segment10_Task1_Waveform_
        // Fidelity_Audit.md`: 100/100 subjects "detected" at pool scale),
        // IEM's boolean `detected` output is a near-useless gate even on
        // real data -- it can and does fire on smooth curves too, with a
        // self-reported confidence that is not required to be low. This
        // test therefore does NOT assert detected==false or a low
        // confidence (that would be asserting a property the real
        // algorithm doesn't promise); it only checks the result is
        // well-formed (no crash, confidence bounds respected).
        val prototype = buildPrototypeWithNotch(notchDepthAmplitude = 0.0)
        val fs = 256.0
        val result = NotchDetectIEM.apply(prototype, fs)
        assertTrue(result.confidence in 0.0..1.0)
        assertTrue(result.confidenceRaw >= 0.0)
        if (!result.detected) {
            assertTrue(result.confidence == 0.0 && result.confidenceRaw == 0.0)
        }
    }

    @Test
    fun throwsOnAConstantPrototype() {
        val flat = DoubleArray(256) { 0.5 }
        var threw = false
        try {
            NotchDetectIEM.apply(flat, 256.0)
        } catch (e: IllegalArgumentException) {
            threw = true
        }
        assertTrue(threw)
    }
}
