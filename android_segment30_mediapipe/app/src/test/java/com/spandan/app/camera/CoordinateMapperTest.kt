package com.spandan.app.camera

import android.graphics.Rect
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.random.Random

/**
 * Plain Kotlin/JUnit -- verifies [CoordinateMapper.sensorRectToRotatedRect]
 * (added for Segment 18's [OpticalFlowFaceTracker]) is a genuine inverse of
 * the existing, already-relied-upon [CoordinateMapper.rotatedRectToSensorRect]
 * via a round-trip property test, since no physical device was available
 * this session to verify the new function any other way -- same "verify
 * before trusting real data" discipline as every other numeric port here.
 *
 * [Segment 30] `original` below used to be built via the 4-arg
 * `Rect(l,t,r,b)` constructor, which [CroppedDetectionStrategyTest]'s own
 * header documents as a no-op (all fields stay 0) under this project's
 * plain-JUnit harness -- meaning this test ran a 0-input round trip through
 * TWO functions that (until this same migration's own fix, see
 * [CoordinateMapper]'s new `makeRect` helper) ALSO built their return value
 * via a stubbed constructor, so it passed as a double-vacuous 0-equals-0
 * coincidence. Fixing the production side alone (without fixing this test's
 * own input construction) made this test start FAILING for real -- a
 * genuinely zeroed input rect sits exactly on `clampToBounds`'s own
 * zero-area edge case, so it doesn't round-trip cleanly. `original` is now
 * built the same no-arg-plus-field-assignment way
 * [CroppedDetectionStrategyTest]'s own `rectOf` already does, so this test
 * finally exercises real random rects the way its own name always claimed.
 */
class CoordinateMapperTest {

    private fun rectOf(left: Int, top: Int, right: Int, bottom: Int): Rect {
        val r = Rect()
        r.left = left
        r.top = top
        r.right = right
        r.bottom = bottom
        return r
    }

    @Test
    fun roundTripsForAllFourRotationsOnRandomRects() {
        val rng = Random(7)
        val sensorWidth = 640
        val sensorHeight = 480

        for (rotation in listOf(0, 90, 180, 270)) {
            // The "rotated" space's own extent is swapped for 90/270 -- same
            // convention FaceAnalyzer.kt itself uses to derive rotatedImageWidth/Height.
            val rotatedWidth = if (rotation == 90 || rotation == 270) sensorHeight else sensorWidth
            val rotatedHeight = if (rotation == 90 || rotation == 270) sensorWidth else sensorHeight

            repeat(200) {
                val left = rng.nextInt(0, rotatedWidth - 10)
                val top = rng.nextInt(0, rotatedHeight - 10)
                val right = rng.nextInt(left + 1, rotatedWidth)
                val bottom = rng.nextInt(top + 1, rotatedHeight)
                val original = rectOf(left, top, right, bottom)

                val sensorRect = CoordinateMapper.rotatedRectToSensorRect(original, rotation, sensorWidth, sensorHeight)
                val roundTripped = CoordinateMapper.sensorRectToRotatedRect(sensorRect, rotation, sensorWidth, sensorHeight)

                // rotatedRectToSensorRect clamps to sensor bounds, so an
                // exact round trip is only guaranteed when the original rect
                // was already safely inside bounds (never negative/over-max
                // after mapping) -- true by construction here since we
                // generated `original` strictly inside [0, rotatedWidth/Height).
                assertEquals("rotation=$rotation left", original.left, roundTripped.left)
                assertEquals("rotation=$rotation top", original.top, roundTripped.top)
                assertEquals("rotation=$rotation right", original.right, roundTripped.right)
                assertEquals("rotation=$rotation bottom", original.bottom, roundTripped.bottom)
            }
        }
    }
}
