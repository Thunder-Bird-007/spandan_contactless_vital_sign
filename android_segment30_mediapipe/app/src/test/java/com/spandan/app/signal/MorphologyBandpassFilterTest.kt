package com.spandan.app.signal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

class MorphologyBandpassFilterTest {

    private fun rms(x: DoubleArray): Double = sqrt(x.sumOf { it * it } / x.size)

    @Test
    fun wideModeRetainsAHigherHarmonicThatWouldFallOutsideBranch1Band() {
        val fs = 60.0
        val n = (fs * 20).toInt()
        // f0=1.5Hz (90bpm); its 3rd harmonic (4.5Hz) is OUTSIDE BandpassFilter's
        // 0.7-4Hz band but INSIDE MorphologyBandpassFilter's wide 0.5-8Hz band.
        val f0 = 1.5
        val thirdHarmonicHz = 3 * f0
        val signal = DoubleArray(n) { i -> sin(2 * PI * thirdHarmonicHz * i / fs) }

        val wideResult = MorphologyBandpassFilter.apply(signal, fs, MorphologyBandpassFilter.BandMode.WIDE)
        val narrowResult = BandpassFilter.apply(signal, fs) // Branch 1's own 0.7-4Hz filter

        val wideRms = rms(wideResult.filtered)
        val narrowRms = rms(narrowResult)

        assertTrue("wide mode should preserve most of a 4.5Hz tone (rms=$wideRms)", wideRms > 0.5)
        assertTrue("narrow 0.7-4Hz mode should heavily attenuate a 4.5Hz tone (rms=$narrowRms)", narrowRms < 0.3)
    }

    @Test
    fun isAdmissibleMatchesNyquistGuard() {
        assertTrue(MorphologyBandpassFilter.isAdmissible(30.0, MorphologyBandpassFilter.BandMode.WIDE)) // Nyquist=15 > 8
        assertFalse(MorphologyBandpassFilter.isAdmissible(15.0, MorphologyBandpassFilter.BandMode.WIDE)) // Nyquist=7.5 < 8
        assertTrue(MorphologyBandpassFilter.isAdmissible(15.0, MorphologyBandpassFilter.BandMode.MID)) // Nyquist=7.5 > 6
        assertFalse(MorphologyBandpassFilter.isAdmissible(11.0, MorphologyBandpassFilter.BandMode.MID)) // Nyquist=5.5 < 6
    }

    @Test
    fun pickPrefersWideThenMidThenNull() {
        assertEquals(MorphologyBandpassFilter.BandMode.WIDE, MorphologyBandpassFilter.pick(30.0))
        assertEquals(MorphologyBandpassFilter.BandMode.MID, MorphologyBandpassFilter.pick(14.0)) // Nyquist=7: wide inadmissible, mid ok
        assertNull(MorphologyBandpassFilter.pick(10.0)) // Nyquist=5: neither admissible
    }

    @Test
    fun applyThrowsWhenModeInadmissibleForFs() {
        var threw = false
        try {
            MorphologyBandpassFilter.apply(DoubleArray(200) { it.toDouble() }, 14.0, MorphologyBandpassFilter.BandMode.WIDE)
        } catch (e: IllegalArgumentException) {
            threw = true
        }
        assertTrue("expected apply() to reject an inadmissible mode/fs combination", threw)
    }
}
