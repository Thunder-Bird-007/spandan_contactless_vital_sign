package com.spandan.app.camera

import android.graphics.RectF
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Plain Kotlin/JUnit -- verifies [CoordinateMapper.mediaPipeSensorBoxToRotatedRect]
 * ([Segment 30]) with HAND-COMPUTED expected values (not a round-trip against
 * this project's own [CoordinateMapper.sensorRectToRotatedRect], to avoid
 * merely re-deriving the same arithmetic twice).
 *
 * Kept in its OWN file rather than added to [CoordinateMapperTest] --
 * [CoordinateMapperTest] builds its `Rect`s via the 4-arg `Rect(l,t,r,b)`
 * constructor, which [CroppedDetectionStrategyTest]'s own header documents
 * as a no-op (all fields stay 0) under this project's plain-JUnit harness
 * (`isReturnDefaultValues = true`); that makes CoordinateMapperTest pass
 * vacuously today (flagged, not fixed, in Segment 28 -- out of this
 * migration's own scope to correct). This file's own [RectF] inputs are
 * built via the no-arg constructor plus direct field assignment instead --
 * plain field access is never stubbed, so this genuinely exercises the real
 * arithmetic, unlike CoordinateMapperTest's existing round-trip test.
 *
 * WRITING these tests surfaced a DEEPER version of that same gap: the 1-arg
 * `Rect(Rect)` COPY constructor [CoordinateMapper.rotatedRectToSensorRect]/
 * [CoordinateMapper.sensorRectToRotatedRect] used internally for their own
 * `0`/`else` branches is ALSO a no-op under this harness -- meaning every
 * branch of both functions returned an all-zero `Rect` regardless of
 * rotation or input, independent of how the TEST built its own inputs. This
 * was fixed at the root (both functions now build their return value via
 * [CoordinateMapper]'s own new `makeRect` no-arg-plus-field-assignment
 * helper, matching [CroppedDetectionStrategy]'s established convention) --
 * see that helper's own KDoc. Real-device behavior is unchanged (field
 * assignment either way); this only makes the functions testable for the
 * first time.
 */
class CoordinateMapperMediaPipeTest {

    private fun rectFOf(left: Float, top: Float, right: Float, bottom: Float): RectF {
        val r = RectF()
        r.left = left
        r.top = top
        r.right = right
        r.bottom = bottom
        return r
    }

    @Test
    fun rotation0_passesSensorBoxThroughUnchanged() {
        val box = rectFOf(100f, 50f, 200f, 150f)
        val result = CoordinateMapper.mediaPipeSensorBoxToRotatedRect(box, 0, sensorWidth = 640, sensorHeight = 480)

        assertEquals(100, result.left)
        assertEquals(50, result.top)
        assertEquals(200, result.right)
        assertEquals(150, result.bottom)
    }

    @Test
    fun rotation90_matchesHandComputedSensorToRotatedFormula() {
        // sensorRectToRotatedRect's own 90-degree branch:
        // Rect(sensorHeight - bottom, left, sensorHeight - top, right)
        val box = rectFOf(100f, 50f, 200f, 150f)
        val result = CoordinateMapper.mediaPipeSensorBoxToRotatedRect(box, 90, sensorWidth = 640, sensorHeight = 480)

        assertEquals(480 - 150, result.left)
        assertEquals(100, result.top)
        assertEquals(480 - 50, result.right)
        assertEquals(200, result.bottom)
    }

    @Test
    fun rotation180_matchesHandComputedSensorToRotatedFormula() {
        // Rect(sensorWidth - right, sensorHeight - bottom, sensorWidth - left, sensorHeight - top)
        val box = rectFOf(100f, 50f, 200f, 150f)
        val result = CoordinateMapper.mediaPipeSensorBoxToRotatedRect(box, 180, sensorWidth = 640, sensorHeight = 480)

        assertEquals(640 - 200, result.left)
        assertEquals(480 - 150, result.top)
        assertEquals(640 - 100, result.right)
        assertEquals(480 - 50, result.bottom)
    }

    @Test
    fun rotation270_matchesHandComputedSensorToRotatedFormula() {
        // Rect(top, sensorWidth - right, bottom, sensorWidth - left)
        val box = rectFOf(100f, 50f, 200f, 150f)
        val result = CoordinateMapper.mediaPipeSensorBoxToRotatedRect(box, 270, sensorWidth = 640, sensorHeight = 480)

        assertEquals(50, result.left)
        assertEquals(640 - 200, result.top)
        assertEquals(150, result.right)
        assertEquals(640 - 100, result.bottom)
    }

    @Test
    fun fractionalCoordinatesAreTruncatedTowardZero() {
        // RectF -> Rect conversion is `.toInt()` (truncation), not rounding.
        val box = rectFOf(100.7f, 50.9f, 200.2f, 150.4f)
        val result = CoordinateMapper.mediaPipeSensorBoxToRotatedRect(box, 0, sensorWidth = 640, sensorHeight = 480)

        assertEquals(100, result.left)
        assertEquals(50, result.top)
        assertEquals(200, result.right)
        assertEquals(150, result.bottom)
    }
}
