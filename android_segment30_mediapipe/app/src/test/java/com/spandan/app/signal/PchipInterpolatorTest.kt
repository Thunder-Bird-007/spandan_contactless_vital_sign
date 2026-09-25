package com.spandan.app.signal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Plain Kotlin/JUnit -- verifies [PchipInterpolator] before trusting it
 * inside [ResampleUniform]/[EnsembleAverageBeats]/[NotchDetectIEM], same
 * "verify before trusting real data" discipline as every other numeric port
 * in this project.
 */
class PchipInterpolatorTest {

    @Test
    fun reproducesKnotValuesExactly() {
        val x = doubleArrayOf(0.0, 1.0, 2.5, 4.0, 5.0)
        val y = doubleArrayOf(1.0, 3.0, 2.0, 5.0, 0.0)
        val result = PchipInterpolator.interpolate(x, y, x.copyOf())
        for (i in x.indices) {
            assertEquals("knot $i", y[i], result[i], 1e-9)
        }
    }

    @Test
    fun exactlyReproducesAStraightLine() {
        val x = DoubleArray(10) { it.toDouble() }
        val y = DoubleArray(10) { 2.0 * it + 3.0 }
        val xq = doubleArrayOf(0.5, 1.5, 3.3, 7.7, 8.9)
        val result = PchipInterpolator.interpolate(x, y, xq)
        for (i in xq.indices) {
            val expected = 2.0 * xq[i] + 3.0
            assertEquals("query $i", expected, result[i], 1e-9)
        }
    }

    @Test
    fun doesNotOvershootOnAMonotoneStepLikeSignal() {
        // A signal that rises sharply then plateaus -- a spline would
        // typically overshoot past the plateau value near the corner. PCHIP
        // must not exceed the data's own min/max anywhere.
        val x = doubleArrayOf(0.0, 1.0, 2.0, 3.0, 4.0, 5.0)
        val y = doubleArrayOf(0.0, 0.0, 10.0, 10.0, 10.0, 10.0)
        val xq = DoubleArray(200) { it * 5.0 / 199.0 }
        val result = PchipInterpolator.interpolate(x, y, xq)
        val minY = y.min()
        val maxY = y.max()
        for (v in result) {
            assertTrue("overshoot detected: $v outside [$minY,$maxY]", v >= minY - 1e-6 && v <= maxY + 1e-6)
        }
    }

    @Test
    fun clampsQueriesOutsideKnotRange() {
        val x = doubleArrayOf(0.0, 1.0, 2.0)
        val y = doubleArrayOf(5.0, 7.0, 6.0)
        val result = PchipInterpolator.interpolate(x, y, doubleArrayOf(-5.0, 10.0))
        assertEquals(5.0, result[0], 1e-9)
        assertEquals(6.0, result[1], 1e-9)
    }

    @Test
    fun interpolatesASineWaveReasonablyWell() {
        val n = 40
        val x = DoubleArray(n) { it * (2 * Math.PI) / (n - 1) }
        val y = DoubleArray(n) { Math.sin(x[it]) }
        val xq = DoubleArray(400) { it * (2 * Math.PI) / 399.0 }
        val result = PchipInterpolator.interpolate(x, y, xq)
        var maxErr = 0.0
        for (i in xq.indices) {
            val err = abs(result[i] - Math.sin(xq[i]))
            if (err > maxErr) maxErr = err
        }
        assertTrue("max interpolation error too large: $maxErr", maxErr < 0.01)
    }
}
