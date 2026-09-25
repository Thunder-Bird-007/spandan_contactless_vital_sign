package com.spandan.app.camera

import android.graphics.Rect
import android.graphics.RectF

/**
 * Coordinate-space plumbing between three different frames of reference that
 * show up in a CameraX + ML Kit pipeline:
 *
 *  1. The raw sensor buffer (ImageProxy width/height, YUV_420_888 planes) --
 *     what we need to index into for pixel averaging.
 *  2. The "rotated" (upright) image ML Kit's face detector works in. Face
 *     boxes come back in this space, but NOTE: InputImage.fromMediaImage(...)
 *     .width/.height do NOT report this space's dimensions -- they report
 *     the raw, unrotated sensor-buffer dimensions unchanged, regardless of
 *     rotationDegrees (confirmed on-device; see FaceAnalyzer.kt, which
 *     derives the true rotated width/height itself by swapping the raw
 *     sensor dimensions for 90/270 rather than trusting InputImage's
 *     getters). Callers of this object must pass the true rotated
 *     width/height, not InputImage's.
 *  3. On-screen view coordinates, for drawing the overlay on top of a
 *     PreviewView.
 *
 * None of this is DSP -- it's just geometry -- but getting it wrong either
 * crashes (out-of-bounds plane reads) or silently misaligns the ROI overlay,
 * so it's worth its own file with real derivations rather than ad hoc code
 * inline in the analyzer.
 */
object CoordinateMapper {

    /**
     * Maps a rect from ML Kit's rotated-image space back into the raw sensor
     * buffer's space, so [RoiPixelAverager] can index the correct pixels.
     * Derived by hand for all four rotation values; only empirically
     * exercised for the default front-camera-portrait case (rotationDegrees
     * = 90) since that's what this app runs -- see android/README.md for the
     * "not yet verified on a real device" caveat.
     */
    fun rotatedRectToSensorRect(
        rect: Rect,
        rotationDegrees: Int,
        sensorWidth: Int,
        sensorHeight: Int
    ): Rect {
        val normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        val mapped = when (normalizedRotation) {
            0 -> makeRect(rect.left, rect.top, rect.right, rect.bottom)
            180 -> makeRect(
                sensorWidth - rect.right, sensorHeight - rect.bottom,
                sensorWidth - rect.left, sensorHeight - rect.top
            )
            90 -> makeRect(
                rect.top, sensorHeight - rect.right,
                rect.bottom, sensorHeight - rect.left
            )
            270 -> makeRect(
                sensorWidth - rect.bottom, rect.left,
                sensorWidth - rect.top, rect.right
            )
            else -> makeRect(rect.left, rect.top, rect.right, rect.bottom)
        }
        return clampToBounds(mapped, sensorWidth, sensorHeight)
    }

    /**
     * The mathematical inverse of [rotatedRectToSensorRect]: maps a rect
     * FROM the raw sensor buffer's space back INTO ML Kit's rotated-image
     * space. Added for Segment 18's [OpticalFlowFaceTracker], which tracks
     * face-box motion directly on sensor-space luma pixels (that's the only
     * space the Y-plane data lives in) and needs to hand the result back to
     * [FaceAnalyzer] as a rotated-space [Rect] (the space every other part
     * of the pipeline -- [RoiCalculator], the overlay -- already expects).
     *
     * Derived by hand from [rotatedRectToSensorRect]'s own four branches
     * (solve each branch's equations for the rotated-space coordinates
     * given the sensor-space ones) -- verified by a round-trip property
     * test ([CoordinateMapperTest]: forward then inverse returns the
     * original rect, for random rects at all four rotation values), the
     * same "verify before trusting" discipline as every other numeric port
     * in this project, since no physical device was available this session
     * to verify it any other way.
     *
     * `sensorWidth`/`sensorHeight` are the RAW sensor buffer's dimensions
     * (same convention as [rotatedRectToSensorRect]'s own parameters of the
     * same name -- NOT the rotated width/height).
     */
    fun sensorRectToRotatedRect(
        rect: Rect,
        rotationDegrees: Int,
        sensorWidth: Int,
        sensorHeight: Int
    ): Rect {
        val normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        return when (normalizedRotation) {
            0 -> makeRect(rect.left, rect.top, rect.right, rect.bottom)
            180 -> makeRect(
                sensorWidth - rect.right, sensorHeight - rect.bottom,
                sensorWidth - rect.left, sensorHeight - rect.top
            )
            90 -> makeRect(
                sensorHeight - rect.bottom, rect.left,
                sensorHeight - rect.top, rect.right
            )
            270 -> makeRect(
                rect.top, sensorWidth - rect.right,
                rect.bottom, sensorWidth - rect.left
            )
            else -> makeRect(rect.left, rect.top, rect.right, rect.bottom)
        }
    }

    /**
     * [Segment 30] Maps a MediaPipe FaceDetector `Detection.boundingBox()`
     * RectF into the SAME rotated/upright [Rect] convention ML Kit's
     * `Face.getBoundingBox()` already returns, so a MediaPipe-sourced box can
     * flow through the rest of this pipeline (RoiCalculator, the overlay,
     * KalmanBoxTracker, ...) completely unchanged.
     *
     * MediaPipe's `Detection.boundingBox()` convention is the OPPOSITE of ML
     * Kit's: confirmed by reading Google's own official mediapipe-samples
     * repo (examples/object_detection/android's OverlayView.kt), which
     * applies its OWN rotation matrix to the box AFTER detection -- around
     * `outputWidth`/`outputHeight`, which that sample sets to the MPImage's
     * own `input.width`/`input.height`, i.e. the RAW, UNROTATED buffer
     * dimensions passed into `detectAsync` (same convention as this object's
     * `sensorWidth`/`sensorHeight` parameters elsewhere). Passing
     * `ImageProcessingOptions.setRotationDegrees()` only rotates what the
     * detector MODEL itself sees for inference -- it does NOT rotate the
     * returned coordinates back. ML Kit's `InputImage.fromMediaImage(image,
     * rotationDegrees)`, by contrast, returns `face.boundingBox()` already in
     * the rotated/upright space -- this is exactly the gap
     * [rotatedRectToSensorRect]'s own KDoc warns a caller not to assume away.
     *
     * Implemented as a trivial RectF-to-Rect conversion followed by the
     * EXISTING [sensorRectToRotatedRect] -- no new rotation math needed, since
     * a MediaPipe box already IS a "sensor-space" rect by this object's own
     * terminology.
     *
     * HONEST STATUS: derived from reading Google's own sample source, not yet
     * independently confirmed against a real face on this project's own
     * device. See FaceAnalyzer's `useMediaPipeDetection` /
     * ProfilingFaceAnalyzer's `logMediaPipeVsMlKitComparison` on-device
     * validation and `android_segment30_mediapipe/docs/
     * Segment30_MediaPipe_Migration.md` for whether this held up.
     */
    fun mediaPipeSensorBoxToRotatedRect(
        boundingBoxSensor: RectF,
        rotationDegrees: Int,
        sensorWidth: Int,
        sensorHeight: Int
    ): Rect {
        val sensorRect = Rect()
        sensorRect.left = boundingBoxSensor.left.toInt()
        sensorRect.top = boundingBoxSensor.top.toInt()
        sensorRect.right = boundingBoxSensor.right.toInt()
        sensorRect.bottom = boundingBoxSensor.bottom.toInt()
        return sensorRectToRotatedRect(sensorRect, rotationDegrees, sensorWidth, sensorHeight)
    }

    private fun clampToBounds(r: Rect, width: Int, height: Int): Rect {
        val left = r.left.coerceIn(0, width - 1)
        val top = r.top.coerceIn(0, height - 1)
        val right = r.right.coerceIn(left + 1, width)
        val bottom = r.bottom.coerceIn(top + 1, height)
        return makeRect(left, top, right, bottom)
    }

    /**
     * [Segment 30] Builds a [Rect] via the no-arg constructor plus direct
     * field assignment, NOT the 4-arg `Rect(l,t,r,b)` constructor (or the
     * 1-arg copy constructor `Rect(Rect)`, which [rotatedRectToSensorRect]/
     * [sensorRectToRotatedRect] used to call directly). [CroppedDetectionStrategyTest]'s
     * own header already documented the 4-arg constructor as a no-op under
     * this project's plain-JUnit harness (`isReturnDefaultValues = true`);
     * writing THIS function's own new unit tests
     * ([CoordinateMapperMediaPipeTest]) surfaced that the 1-arg copy
     * constructor is ALSO stubbed the same way -- every branch of both
     * functions above returned an all-zero [Rect] under test, independent of
     * rotation or input, which is a deeper version of the gap Segment 28
     * flagged (that segment only found the TEST's own input construction was
     * vacuous; this means the PRODUCTION functions themselves were never
     * actually exercisable by ANY unit test, not just the existing one).
     * Fixed here at the root (matching [CroppedDetectionStrategy]'s own
     * `makeRect` convention) rather than worked around in the new caller,
     * since [rotatedRectToSensorRect]/[sensorRectToRotatedRect] are shared,
     * actively-relied-upon production code -- field assignment behaves
     * IDENTICALLY on a real device either way (this only changes what is
     * testable, not what runs), so this is not a behavior change.
     */
    private fun makeRect(left: Int, top: Int, right: Int, bottom: Int): Rect {
        val r = Rect()
        r.left = left
        r.top = top
        r.right = right
        r.bottom = bottom
        return r
    }

    /**
     * Maps a rect from the rotated-image coordinate space into on-screen view
     * pixel coordinates, matching a PreviewView using ScaleType.FIT_CENTER
     * (uniform scale, letterboxed, never cropped) plus the horizontal mirror
     * CameraX applies automatically for the front camera preview.
     */
    fun rotatedRectToViewRect(
        rect: Rect,
        srcWidth: Int,
        srcHeight: Int,
        viewWidth: Int,
        viewHeight: Int,
        isFrontCamera: Boolean
    ): RectF {
        if (srcWidth <= 0 || srcHeight <= 0 || viewWidth <= 0 || viewHeight <= 0) return RectF()

        val scale = minOf(viewWidth.toFloat() / srcWidth, viewHeight.toFloat() / srcHeight)
        val offsetX = (viewWidth - srcWidth * scale) / 2f
        val offsetY = (viewHeight - srcHeight * scale) / 2f

        return if (isFrontCamera) {
            RectF(
                offsetX + (srcWidth - rect.right) * scale,
                offsetY + rect.top * scale,
                offsetX + (srcWidth - rect.left) * scale,
                offsetY + rect.bottom * scale
            )
        } else {
            RectF(
                offsetX + rect.left * scale,
                offsetY + rect.top * scale,
                offsetX + rect.right * scale,
                offsetY + rect.bottom * scale
            )
        }
    }
}
