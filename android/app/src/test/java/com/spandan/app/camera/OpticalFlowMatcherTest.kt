package com.spandan.app.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import kotlin.random.Random

/**
 * Plain Kotlin/JUnit, no Android device needed -- verifies the pure block-
 * matching math ([OpticalFlowMatcher]) before trusting it inside
 * [OpticalFlowFaceTracker] on real camera data, same "verify before trusting
 * real data" discipline as BandpassFilterTest/WaveletDenoiseTest.
 */
class OpticalFlowMatcherTest {

    private fun buildRamp(width: Int, height: Int): IntArray =
        IntArray(width * height) { idx ->
            val x = idx % width
            val y = idx / width
            // A textured (non-flat) synthetic pattern -- checkerboard-ish
            // ramp, so block matching has real structure to lock onto.
            (x * 7 + y * 13) % 256
        }

    /** Builds a `refW x refH` search image padded by `maxOffset` on every
     *  side, where the region at grid-offset (dx, dy) from center exactly
     *  equals [reference] -- i.e. the ground-truth answer is (dx, dy). */
    private fun buildShiftedSearch(reference: IntArray, refW: Int, refH: Int, maxOffset: Int, dx: Int, dy: Int, fill: (Int, Int) -> Int): IntArray {
        val searchW = refW + 2 * maxOffset
        val searchH = refH + 2 * maxOffset
        val search = IntArray(searchW * searchH) { idx ->
            val x = idx % searchW
            val y = idx / searchW
            fill(x, y)
        }
        // Stamp `reference` at the shifted location (center + dx, center + dy).
        for (j in 0 until refH) {
            for (i in 0 until refW) {
                val sx = maxOffset + dx + i
                val sy = maxOffset + dy + j
                if (sx in 0 until searchW && sy in 0 until searchH) {
                    search[sy * searchW + sx] = reference[j * refW + i]
                }
            }
        }
        return search
    }

    @Test
    fun findsExactShiftWhenPatternTranslatedWithNoNoise() {
        val refW = 12
        val refH = 12
        val maxOffset = 5
        val reference = buildRamp(refW, refH)

        for (dx in -3..3 step 2) {
            for (dy in -3..3 step 2) {
                val search = buildShiftedSearch(reference, refW, refH, maxOffset, dx, dy) { x, y -> (x * 3 + y * 5) % 256 }
                val result = OpticalFlowMatcher.bestOffset(reference, refW, refH, search, maxOffset)
                assertEquals("dx mismatch for true shift ($dx,$dy)", dx, result?.first)
                assertEquals("dy mismatch for true shift ($dx,$dy)", dy, result?.second)
            }
        }
    }

    @Test
    fun toleratesSmallNoiseAndStillFindsShift() {
        val refW = 14
        val refH = 14
        val maxOffset = 6
        val reference = buildRamp(refW, refH)
        val rng = Random(42)

        val trueDx = 4
        val trueDy = -2
        val search = buildShiftedSearch(reference, refW, refH, maxOffset, trueDx, trueDy) { x, y -> (x * 3 + y * 5) % 256 }
        // Add small noise (+/-3) to every cell.
        val noisySearch = IntArray(search.size) { idx -> (search[idx] + rng.nextInt(-3, 4)).coerceIn(0, 255) }

        val result = OpticalFlowMatcher.bestOffset(reference, refW, refH, noisySearch, maxOffset)
        assertEquals(trueDx, result?.first)
        assertEquals(trueDy, result?.second)
    }

    @Test
    fun returnsNullForFlatReferencePatch() {
        val refW = 10
        val refH = 10
        val maxOffset = 4
        val flatReference = IntArray(refW * refH) { 128 } // uniform -- no texture to match
        val searchW = refW + 2 * maxOffset
        val searchH = refH + 2 * maxOffset
        val search = IntArray(searchW * searchH) { 128 }

        assertNull(OpticalFlowMatcher.bestOffset(flatReference, refW, refH, search, maxOffset))
    }

    @Test
    fun zeroSearchRadiusStillMatchesIdenticalPatches() {
        val refW = 8
        val refH = 8
        val reference = buildRamp(refW, refH)
        val result = OpticalFlowMatcher.bestOffset(reference, refW, refH, reference.copyOf(), 0)
        assertEquals(0, result?.first)
        assertEquals(0, result?.second)
    }
}
