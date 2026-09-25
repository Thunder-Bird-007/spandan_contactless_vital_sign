package com.spandan.app.camera

import android.graphics.Rect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * Plain Kotlin/JUnit -- verifies [CroppedDetectionStrategy]'s pure rect math
 * ([CroppedDetectionStrategy.paddedCropRect] and
 * [CroppedDetectionStrategy.remapCropRectToSensorRect]), the way
 * [CoordinateMapperTest] tests [CoordinateMapper]'s own rect math. Does NOT
 * touch [CroppedDetectionStrategy.extractCroppedNv21] or
 * [CroppedDetectionStrategy.buildCroppedInputImage], which need a real
 * [androidx.camera.core.ImageProxy] and are not exercised here -- see that
 * class's own "HONEST STATUS" note.
 *
 * IMPORTANT: every [Rect] fed INTO the code under test here is built via
 * [rectOf] below, never the 4-arg `Rect(l,t,r,b)` constructor directly --
 * that constructor's body is stubbed to a no-op (leaving every field at 0)
 * under this project's plain-JUnit unit test harness
 * (android/app/build.gradle.kts's `isReturnDefaultValues = true`), confirmed
 * by direct probe. Using it here would make every test pass vacuously (both
 * sides of every comparison silently zeroed) without ever exercising the
 * real arithmetic -- the same latent gap [CoordinateMapperTest] has today.
 * [Rect]s coming back OUT of the code under test are fine to read fields
 * from directly (plain field access is never stubbed); only [Rect.equals]
 * is avoided on those too, for the same reason.
 */
class CroppedDetectionStrategyTest {

    private fun rectOf(left: Int, top: Int, right: Int, bottom: Int): Rect {
        val r = Rect()
        r.left = left
        r.top = top
        r.right = right
        r.bottom = bottom
        return r
    }

    @Test
    fun paddedCropRect_padsBySpecifiedFractionWhenFarFromBounds() {
        val box = rectOf(200, 150, 300, 250) // 100x100
        val result = CroppedDetectionStrategy.paddedCropRect(box, 0.5f, sensorWidth = 1000, sensorHeight = 1000)

        // Expected pad = 50px each side -> [150,100,350,300), then rounded to even (already even here).
        assertEquals(150, result.left)
        assertEquals(100, result.top)
        assertEquals(350, result.right)
        assertEquals(300, result.bottom)
    }

    @Test
    fun paddedCropRect_clampsToSensorBoundsNearEdges() {
        val box = rectOf(0, 0, 50, 50)
        val result = CroppedDetectionStrategy.paddedCropRect(box, 1.0f, sensorWidth = 640, sensorHeight = 480)

        assertTrue("left must stay >= 0", result.left >= 0)
        assertTrue("top must stay >= 0", result.top >= 0)
        assertTrue("right must stay <= sensorWidth", result.right <= 640)
        assertTrue("bottom must stay <= sensorHeight", result.bottom <= 480)
    }

    @Test
    fun paddedCropRect_clampsAtFarEdge() {
        val box = rectOf(600, 440, 640, 480)
        val result = CroppedDetectionStrategy.paddedCropRect(box, 1.0f, sensorWidth = 640, sensorHeight = 480)

        assertTrue(result.right <= 640)
        assertTrue(result.bottom <= 480)
        assertTrue(result.left >= 0)
        assertTrue(result.top >= 0)
    }

    @Test
    fun paddedCropRect_alwaysReturnsEvenOriginAndExtent() {
        val rng = Random(11)
        repeat(500) {
            val left = rng.nextInt(0, 600)
            val top = rng.nextInt(0, 440)
            val right = rng.nextInt(left + 1, 640)
            val bottom = rng.nextInt(top + 1, 480)
            val paddingFraction = rng.nextFloat() * 2f

            val result = CroppedDetectionStrategy.paddedCropRect(rectOf(left, top, right, bottom), paddingFraction, 640, 480)

            assertEquals("left must be even", 0, result.left % 2)
            assertEquals("top must be even", 0, result.top % 2)
            assertEquals("width must be even", 0, (result.right - result.left) % 2)
            assertEquals("height must be even", 0, (result.bottom - result.top) % 2)
            assertTrue("must stay within sensor bounds", result.left >= 0 && result.top >= 0 && result.right <= 640 && result.bottom <= 480)
            assertTrue("must have positive area", result.right > result.left && result.bottom > result.top)
        }
    }

    @Test
    fun paddedCropRect_alwaysContainsTheOriginalBox() {
        // Padding should never shrink below the original box, only grow (then clamp).
        val rng = Random(13)
        repeat(200) {
            val left = rng.nextInt(50, 500)
            val top = rng.nextInt(50, 350)
            val right = rng.nextInt(left + 1, 550)
            val bottom = rng.nextInt(top + 1, 400)
            val box = rectOf(left, top, right, bottom)

            val result = CroppedDetectionStrategy.paddedCropRect(box, 0.25f, 640, 480)

            // Original box is far from sensor edges here (>=50px margin at
            // 0.25 padding of a <=500px box, i.e. <=125px pad), so no
            // clamping should have kicked in and containment must hold
            // exactly (up to the even-rounding this function always applies).
            assertTrue("result.left <= box.left", result.left <= box.left)
            assertTrue("result.top <= box.top", result.top <= box.top)
            assertTrue("result.right >= box.right", result.right >= box.right)
            assertTrue("result.bottom >= box.bottom", result.bottom >= box.bottom)
        }
    }

    @Test
    fun remapCropRectToSensorRect_offsetsByCropOrigin() {
        val cropRect = rectOf(100, 80, 300, 260)
        val detectedInCrop = rectOf(10, 20, 60, 70)

        val result = CroppedDetectionStrategy.remapCropRectToSensorRect(detectedInCrop, cropRect)

        assertEquals(110, result.left)
        assertEquals(100, result.top)
        assertEquals(160, result.right)
        assertEquals(150, result.bottom)
    }

    @Test
    fun remapCropRectToSensorRect_zeroOriginCropIsIdentity() {
        val cropRect = rectOf(0, 0, 400, 400)
        val detectedInCrop = rectOf(5, 5, 55, 55)

        val result = CroppedDetectionStrategy.remapCropRectToSensorRect(detectedInCrop, cropRect)

        // Field-by-field, not assertEquals(Rect, Rect) -- Rect.equals() is
        // also stubbed under this project's plain-JUnit harness.
        assertEquals(detectedInCrop.left, result.left)
        assertEquals(detectedInCrop.top, result.top)
        assertEquals(detectedInCrop.right, result.right)
        assertEquals(detectedInCrop.bottom, result.bottom)
    }

    @Test
    fun cropThenRemap_roundTripsAPointBackToItsOriginalSensorPosition() {
        // A face box fully inside the padded crop, remapped back, should
        // recover exactly the same sensor-space rect it started from.
        val rng = Random(17)
        repeat(200) {
            val lastKnownLeft = rng.nextInt(50, 400)
            val lastKnownTop = rng.nextInt(50, 300)
            val lastKnownRight = rng.nextInt(lastKnownLeft + 20, lastKnownLeft + 100)
            val lastKnownBottom = rng.nextInt(lastKnownTop + 20, lastKnownTop + 100)
            val lastKnown = rectOf(lastKnownLeft, lastKnownTop, lastKnownRight, lastKnownBottom)

            val cropRect = CroppedDetectionStrategy.paddedCropRect(lastKnown, 0.3f, 640, 480)

            // Simulate "ML Kit found the face exactly where it was" in the
            // crop's own local coordinate space.
            val detectedInCropSpace = rectOf(
                lastKnown.left - cropRect.left,
                lastKnown.top - cropRect.top,
                lastKnown.right - cropRect.left,
                lastKnown.bottom - cropRect.top
            )

            val remapped = CroppedDetectionStrategy.remapCropRectToSensorRect(detectedInCropSpace, cropRect)

            assertEquals(lastKnown.left, remapped.left)
            assertEquals(lastKnown.top, remapped.top)
            assertEquals(lastKnown.right, remapped.right)
            assertEquals(lastKnown.bottom, remapped.bottom)
        }
    }
}
