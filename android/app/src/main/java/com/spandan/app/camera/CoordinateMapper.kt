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
            0 -> Rect(rect)
            180 -> Rect(
                sensorWidth - rect.right, sensorHeight - rect.bottom,
                sensorWidth - rect.left, sensorHeight - rect.top
            )
            90 -> Rect(
                rect.top, sensorHeight - rect.right,
                rect.bottom, sensorHeight - rect.left
            )
            270 -> Rect(
                sensorWidth - rect.bottom, rect.left,
                sensorWidth - rect.top, rect.right
            )
            else -> Rect(rect)
        }
        return clampToBounds(mapped, sensorWidth, sensorHeight)
    }

    private fun clampToBounds(r: Rect, width: Int, height: Int): Rect {
        val left = r.left.coerceIn(0, width - 1)
        val top = r.top.coerceIn(0, height - 1)
        val right = r.right.coerceIn(left + 1, width)
        val bottom = r.bottom.coerceIn(top + 1, height)
        return Rect(left, top, right, bottom)
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
