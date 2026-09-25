package com.spandan.app.camera

import android.graphics.Rect
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage

/**
 * [Segment 28] Camera-throughput candidate #2 (alongside the Segment 18
 * [OpticalFlowFaceTracker], allocation-fixed above): on a skipped-detection
 * frame, run REAL ML Kit detection on a small, padded crop around the last
 * known face box instead of either freezing the box or guessing its motion.
 * A smaller [InputImage] should cost detector.process() less than the
 * full-frame call FaceAnalyzer.kt's un-skipped frames already pay -- this is
 * an ADDITIONAL lever, not a replacement for the existing frame-skip
 * (DETECT_EVERY_N_FRAMES) or motion-tracking gates.
 *
 * Two independent, testable pieces:
 *  1. Pure crop-rect / coordinate math ([paddedCropRect], [remapCropRectToSensorRect])
 *     -- no Android Image dependency, unit-tested the way
 *     [CoordinateMapperTest] tests [CoordinateMapper]'s own rect math.
 *  2. NV21 extraction from an [ImageProxy]'s YUV_420_888 planes for just the
 *     crop region ([extractCroppedNv21]) -- Android-dependent, so not
 *     directly unit-testable, but small and reuses the same rowStride/
 *     pixelStride-aware plane access [RoiPixelAverager]/[OpticalFlowFaceTracker]
 *     already use.
 *
 * HONEST STATUS: like [OpticalFlowFaceTracker], this compiles and its pure
 * math is unit-tested, but the NV21 extraction and the ML-Kit-on-a-crop
 * round trip were NOT exercised on a physical device this session -- none
 * was attached. See `android/docs/Segment28_Throughput_Improvement.md`.
 * Gated behind [FaceAnalyzer]'s `useCroppedDetection` constructor flag,
 * default `false`, same "off by default, evidence before promotion"
 * convention as every other unproven lever in this file's neighborhood.
 */
object CroppedDetectionStrategy {

    /**
     * Pads [lastKnownSensorRect] by [paddingFraction] of its own width/height
     * on every side, then clamps to `[0, sensorWidth) x [0, sensorHeight)`.
     * Pure integer rect math -- no image access, no rotation handling (the
     * crop is computed and sampled entirely in SENSOR space, same space
     * [OpticalFlowFaceTracker] already tracks in).
     */
    fun paddedCropRect(lastKnownSensorRect: Rect, paddingFraction: Float, sensorWidth: Int, sensorHeight: Int): Rect {
        require(paddingFraction >= 0f) { "paddingFraction must be >= 0" }
        require(sensorWidth > 0 && sensorHeight > 0) { "sensorWidth/sensorHeight must be positive" }

        // Field arithmetic (right-left/bottom-top), not Rect.width()/height():
        // those methods are stubbed to return 0 under this project's plain-
        // JUnit unit test harness (android/app/build.gradle.kts's
        // isReturnDefaultValues=true), same convention CoordinateMapper
        // already follows throughout for exactly this reason.
        val padX = ((lastKnownSensorRect.right - lastKnownSensorRect.left) * paddingFraction).toInt()
        val padY = ((lastKnownSensorRect.bottom - lastKnownSensorRect.top) * paddingFraction).toInt()

        val left = (lastKnownSensorRect.left - padX).coerceIn(0, sensorWidth - 1)
        val top = (lastKnownSensorRect.top - padY).coerceIn(0, sensorHeight - 1)
        val right = (lastKnownSensorRect.right + padX).coerceIn(left + 1, sensorWidth)
        val bottom = (lastKnownSensorRect.bottom + padY).coerceIn(top + 1, sensorHeight)

        // YUV 4:2:0 chroma subsampling needs an even origin and even extent
        // for the crop to line up on whole chroma cells (see
        // extractCroppedNv21's own header) -- round the origin DOWN to even
        // (only grows the crop, preserving containment of the original box)
        // and the extent UP to even (rounding the extent down instead could
        // shrink the crop's right/bottom edge back inside the original box
        // whenever padding truncates to 0px on a box with an odd edge).
        // Finally clamp to the sensor bounds, themselves rounded down to
        // even so the returned rect is never larger than the actual buffer.
        val evenLeft = left and 1.inv()
        val evenTop = top and 1.inv()
        val extentXCeil = ((right - evenLeft) + 1) and 1.inv()
        val extentYCeil = ((bottom - evenTop) + 1) and 1.inv()
        val evenRight = (evenLeft + extentXCeil).coerceAtLeast(evenLeft + 2).coerceAtMost(sensorWidth and 1.inv())
        val evenBottom = (evenTop + extentYCeil).coerceAtLeast(evenTop + 2).coerceAtMost(sensorHeight and 1.inv())

        return makeRect(evenLeft, evenTop, evenRight, evenBottom)
    }

    /**
     * Maps a rect detected inside the cropped sub-image's own SENSOR space
     * (i.e. after undoing the crop's rotation via [CoordinateMapper], not
     * the raw rotated-space box ML Kit returns) back into the full frame's
     * sensor space, by offsetting by [cropRectSensor]'s own origin. The pure
     * inverse of "sample this sub-rect out of the full sensor buffer."
     */
    fun remapCropRectToSensorRect(detectedInCropSensorSpace: Rect, cropRectSensor: Rect): Rect {
        return makeRect(
            detectedInCropSensorSpace.left + cropRectSensor.left,
            detectedInCropSensorSpace.top + cropRectSensor.top,
            detectedInCropSensorSpace.right + cropRectSensor.left,
            detectedInCropSensorSpace.bottom + cropRectSensor.top
        )
    }

    /** Builds a [Rect] via the no-arg constructor plus direct field
     *  assignment, NOT the 4-arg `Rect(l,t,r,b)` constructor -- that
     *  constructor's body is stubbed to a no-op (leaving all fields at 0)
     *  under this project's plain-JUnit unit test harness
     *  (android/app/build.gradle.kts's `isReturnDefaultValues = true`),
     *  confirmed by direct probe; the no-arg constructor + field writes are
     *  plain field access, never stubbed, and behave identically to the
     *  4-arg constructor on a real device. Existing code elsewhere in this
     *  package (e.g. [CoordinateMapper]) predates this finding and still
     *  uses the 4-arg constructor -- out of this file's scope to change,
     *  but worth knowing its own unit test does not actually exercise its
     *  rect math as a result. */
    private fun makeRect(left: Int, top: Int, right: Int, bottom: Int): Rect {
        val r = Rect()
        r.left = left
        r.top = top
        r.right = right
        r.bottom = bottom
        return r
    }

    /** Result of [buildCroppedInputImage]: the [InputImage] to feed ML Kit,
     *  plus [cropRectSensor] (the exact, even-aligned region it was sampled
     *  from, needed to remap ML Kit's result back to full-frame space),
     *  [downscaleFactor] actually used (>=1; ML Kit's returned face box is
     *  in the DOWNSCALED crop's own coordinate space and must be scaled back
     *  up by this factor before [remapCropRectToSensorRect]), and
     *  [rawWidth]/[rawHeight] -- the RAW (unrotated) pixel dimensions of the
     *  buffer actually handed to [inputImage] (i.e. already divided by
     *  [downscaleFactor]), needed as the `sensorWidth`/`sensorHeight`
     *  arguments to [CoordinateMapper.rotatedRectToSensorRect] when undoing
     *  ML Kit's rotation on the returned face box -- the caller must not
     *  recompute these itself from [cropRectSensor], since that invites
     *  exactly the kind of off-by-rotation mismatch [CoordinateMapper]'s own
     *  KDoc warns about. */
    data class CroppedInputImageResult(
        val inputImage: InputImage,
        val cropRectSensor: Rect,
        val downscaleFactor: Int,
        val rawWidth: Int,
        val rawHeight: Int
    )

    /**
     * Builds an [InputImage] for ML Kit covering only a padded region around
     * [lastKnownSensorRect], optionally subsampled by [downscaleFactor] (1 =
     * no downscale; 2 = every other row/column, i.e. quarter the pixel
     * count) -- both a smaller crop AND a coarser sample should each reduce
     * detector.process() cost, and this lets both be measured together or
     * separately. Returns null if the padded crop is too small to be worth
     * detecting on, or if the image has no planes.
     */
    @ExperimentalGetImage
    fun buildCroppedInputImage(
        imageProxy: ImageProxy,
        lastKnownSensorRect: Rect,
        rotationDegrees: Int,
        paddingFraction: Float,
        downscaleFactor: Int = 1
    ): CroppedInputImageResult? {
        require(downscaleFactor >= 1) { "downscaleFactor must be >= 1" }

        val cropRect = paddedCropRect(lastKnownSensorRect, paddingFraction, imageProxy.width, imageProxy.height)
        val cropWidth = cropRect.right - cropRect.left
        val cropHeight = cropRect.bottom - cropRect.top
        if (cropWidth < MIN_CROP_DIM_PX || cropHeight < MIN_CROP_DIM_PX) return null

        val nv21 = extractCroppedNv21(imageProxy, cropRect, downscaleFactor) ?: return null
        val outWidth = cropWidth / downscaleFactor
        val outHeight = cropHeight / downscaleFactor

        val inputImage = InputImage.fromByteArray(
            nv21,
            outWidth,
            outHeight,
            rotationDegrees,
            InputImage.IMAGE_FORMAT_NV21
        )
        return CroppedInputImageResult(inputImage, cropRect, downscaleFactor, outWidth, outHeight)
    }

    /**
     * Extracts an NV21 (Y plane, then interleaved V/U at half resolution)
     * byte array covering exactly [cropRectSensor] out of [imageProxy]'s
     * YUV_420_888 planes, optionally subsampled by [downscaleFactor] (stride
     * skipping, not a box average -- a performance knob, not a signal-
     * processing parameter, same framing [RoiPixelAverager.SAMPLE_STRIDE]
     * already uses). [cropRectSensor] must already have an even origin and
     * even extent (guaranteed by [paddedCropRect]) so chroma sampling lines
     * up on whole 2x2 cells; this function does not re-check that beyond
     * requiring it be even, since [paddedCropRect] is the only intended
     * caller of this path.
     *
     * Same rowStride/pixelStride-aware plane indexing convention as
     * [RoiPixelAverager.averageRgb] and [OpticalFlowFaceTracker.sampleGridInto]
     * -- YUV_420_888 planes are NOT guaranteed contiguous, so a raw
     * `System.arraycopy` off the backing buffers would be wrong on some
     * devices.
     */
    @ExperimentalGetImage
    fun extractCroppedNv21(imageProxy: ImageProxy, cropRectSensor: Rect, downscaleFactor: Int = 1): ByteArray? {
        val image = imageProxy.image ?: return null
        val srcLeft = cropRectSensor.left
        val srcTop = cropRectSensor.top
        val srcWidth = cropRectSensor.right - cropRectSensor.left
        val srcHeight = cropRectSensor.bottom - cropRectSensor.top
        require(srcLeft % 2 == 0 && srcTop % 2 == 0) { "cropRectSensor must have an even origin" }
        require(srcWidth % 2 == 0 && srcHeight % 2 == 0) { "cropRectSensor must have an even extent" }

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        val outWidth = srcWidth / downscaleFactor
        val outHeight = srcHeight / downscaleFactor
        if (outWidth < 2 || outHeight < 2) return null

        // NV21 layout: outWidth*outHeight Y bytes, then interleaved
        // V,U,V,U... at (outWidth/2)*(outHeight/2) chroma-cell resolution.
        val ySize = outWidth * outHeight
        val chromaSize = (outWidth / 2) * (outHeight / 2) * 2
        val out = ByteArray(ySize + chromaSize)

        val pixelStridePx = downscaleFactor
        for (oy in 0 until outHeight) {
            val sy = srcTop + oy * pixelStridePx
            if (sy < 0 || sy >= imageProxy.height) return null
            val rowBase = oy * outWidth
            for (ox in 0 until outWidth) {
                val sx = srcLeft + ox * pixelStridePx
                if (sx < 0 || sx >= imageProxy.width) return null
                val yIndex = sy * yPlane.rowStride + sx * yPlane.pixelStride
                if (yIndex < 0 || yIndex >= yBuffer.capacity()) return null
                out[rowBase + ox] = yBuffer.get(yIndex)
            }
        }

        var chromaWriteIdx = ySize
        val outChromaWidth = outWidth / 2
        val outChromaHeight = outHeight / 2
        for (ocy in 0 until outChromaHeight) {
            // Each output chroma cell maps back to a source pixel position
            // (sx, sy) = (srcLeft + 2*ocx*downscaleFactor, srcTop + 2*ocy*downscaleFactor),
            // then to that source pixel's own 2x2-subsampled UV cell
            // (sx/2, sy/2) -- consistent with RoiPixelAverager's uvRow=y/2,
            // uvCol=x/2 convention.
            val sy = srcTop + (2 * ocy * pixelStridePx)
            if (sy < 0 || sy >= imageProxy.height) return null
            val uvRow = sy / 2
            for (ocx in 0 until outChromaWidth) {
                val sx = srcLeft + (2 * ocx * pixelStridePx)
                if (sx < 0 || sx >= imageProxy.width) return null
                val uvCol = sx / 2
                val uIndex = uvRow * uPlane.rowStride + uvCol * uPlane.pixelStride
                val vIndex = uvRow * vPlane.rowStride + uvCol * vPlane.pixelStride
                if (uIndex < 0 || uIndex >= uBuffer.capacity() || vIndex < 0 || vIndex >= vBuffer.capacity()) return null
                out[chromaWriteIdx] = vBuffer.get(vIndex)
                out[chromaWriteIdx + 1] = uBuffer.get(uIndex)
                chromaWriteIdx += 2
            }
        }

        return out
    }

    /** Below this many sensor pixels per axis, a crop is too small for ML
     *  Kit's detector to be worth calling on (and too small to be a
     *  meaningful chroma-aligned NV21 buffer). */
    private const val MIN_CROP_DIM_PX = 32
}
