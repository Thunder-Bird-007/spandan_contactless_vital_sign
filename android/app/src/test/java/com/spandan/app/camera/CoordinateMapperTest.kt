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
 */
class CoordinateMapperTest {

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
                val original = Rect(left, top, right, bottom)

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
