package com.spandan.app.signal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * No device needed -- pure arithmetic on a synthetic bpm sequence, same
 * "unit-test before trusting it on real data" discipline as
 * BandpassFilterTest. Does not exercise the camera/signal pipeline at all.
 */
class DisplaySmootherTest {

    @Test
    fun `NONE mode is a pure passthrough`() {
        val s = DisplaySmoother(mode = DisplaySmoother.Mode.NONE)
        assertEquals(70.0, s.smooth(70.0)!!, 1e-9)
        assertEquals(140.0, s.smooth(140.0)!!, 1e-9)
    }

    @Test
    fun `rolling median rejects a single outlier reading`() {
        val s = DisplaySmoother(mode = DisplaySmoother.Mode.ROLLING_MEDIAN, windowSize = 5)
        // Five steady readings around 72, then one wild outlier (a single
        // bad FFT-bin read, the exact failure mode README.md documents).
        listOf(72.0, 73.0, 71.0, 72.0, 74.0).forEach { s.smooth(it) }
        val afterOutlier = s.smooth(160.0)
        // Median of {73,71,72,74,160} = 73 -- the outlier does not dominate.
        assertEquals(73.0, afterOutlier!!, 1e-9)
    }

    @Test
    fun `rolling median tracks a sustained step change within the window length`() {
        val s = DisplaySmoother(mode = DisplaySmoother.Mode.ROLLING_MEDIAN, windowSize = 5)
        // 5 DISTINCT ticks (not 5 repeats of the same value -- see the
        // "repeated identical input is a no-op" test below for why that
        // distinction matters) simulating steady ~70bpm.
        listOf(70.0, 70.2, 69.8, 70.1, 69.9).forEach { s.smooth(it) }
        // A genuine, sustained jump to ~100 across 5 more DISTINCT
        // recomputes -- after windowSize more ticks, the median should have
        // fully caught up.
        var last: Double? = null
        listOf(100.0, 100.2, 99.8, 100.1, 99.9).forEach { last = s.smooth(it) }
        assertEquals(100.0, last!!, 0.5)
    }

    @Test
    fun `repeated identical raw input is a no-op, not a new independent sample`() {
        // Real bug found via this segment's own on-device A/B test:
        // MainActivity's UI-refresh tick (200ms) runs faster than
        // RealHeartRateEstimator's own recompute cadence (~1000ms), so the
        // SAME raw bpm value gets fed to smooth() several times per real
        // measurement. Without de-duplication, a windowSize=5 "window" would
        // fill up on repeats of ONE real value instead of spanning 5
        // independent ones.
        val s = DisplaySmoother(mode = DisplaySmoother.Mode.ROLLING_MEDIAN, windowSize = 5)
        s.smooth(70.0)
        s.smooth(70.0) // same value again -- must NOT count as a 2nd sample
        s.smooth(70.0) // ...or a 3rd
        val afterRepeats = s.smooth(90.0) // one genuinely new value
        // History should now be {70.0, 90.0} (2 distinct samples), median = 80.0
        // -- NOT {70,70,70,90} (median 70) as it would be without the fix.
        assertEquals(80.0, afterRepeats!!, 1e-9)
    }

    @Test
    fun `EMA reacts smoothly and moves toward a new sustained value`() {
        val s = DisplaySmoother(mode = DisplaySmoother.Mode.EMA, emaAlpha = 0.3)
        val first = s.smooth(70.0)
        assertEquals(70.0, first!!, 1e-9) // first sample seeds the EMA exactly
        val second = s.smooth(100.0)
        // 0.3*100 + 0.7*70 = 79.0
        assertEquals(79.0, second!!, 1e-9)
    }

    @Test
    fun `null input (warm-up gap) is a no-op that does not pollute history`() {
        val s = DisplaySmoother(mode = DisplaySmoother.Mode.ROLLING_MEDIAN, windowSize = 5)
        assertNull(s.smooth(null)) // nothing seen yet -> still null
        s.smooth(70.0)
        s.smooth(72.0)
        val duringGap = s.smooth(null) // simulate a momentary no-face/low-fs gap
        assertEquals(71.0, duringGap!!, 1e-9) // last known median, unchanged by the null
        val afterGap = s.smooth(74.0)
        // History is still just {70,72,74} -- the null never got averaged in as 0.
        assertEquals(72.0, afterGap!!, 1e-9)
    }

    @Test
    fun `reset clears history for both modes`() {
        val median = DisplaySmoother(mode = DisplaySmoother.Mode.ROLLING_MEDIAN)
        median.smooth(70.0); median.smooth(72.0)
        median.reset()
        assertNull(median.smooth(null))

        val ema = DisplaySmoother(mode = DisplaySmoother.Mode.EMA)
        ema.smooth(70.0)
        ema.reset()
        assertNull(ema.smooth(null))
    }
}
