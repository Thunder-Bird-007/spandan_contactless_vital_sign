package com.spandan.app.camera

import android.graphics.Rect
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageProxy
import com.spandan.app.signal.RgbSample

/**
 * Spatially averages R/G/B pixel intensities inside an ROI rect, sampled
 * directly from the raw YUV_420_888 planes of a CameraX ImageProxy -- no
 * Bitmap/JPEG round-trip needed.
 *
 * This IS real, permanent code: spatial averaging is plain arithmetic, and
 * the YUV->RGB conversion below is the standard, universal BT.601 colorspace
 * formula (a physical-sensor-format conversion, not a tuned DSP parameter),
 * so fixed constants here are fine -- unlike CHROM/POS/bandpass coefficients
 * elsewhere in this project, which must stay out of this codebase until the
 * MATLAB side finalizes them.
 */
object RoiPixelAverager {

    // Skips every other pixel in each direction -- a performance knob, not a
    // signal-processing parameter. Safe to tune without touching any "real
    // algorithm" concern.
    private const val SAMPLE_STRIDE = 2

    @ExperimentalGetImage
    fun averageRgb(imageProxy: ImageProxy, roiSensorRect: Rect): RgbSample? {
        val image = imageProxy.image ?: return null
        val width = imageProxy.width
        val height = imageProxy.height

        val left = roiSensorRect.left.coerceIn(0, width - 1)
        val top = roiSensorRect.top.coerceIn(0, height - 1)
        val right = roiSensorRect.right.coerceIn(left + 1, width)
        val bottom = roiSensorRect.bottom.coerceIn(top + 1, height)
        if (right <= left || bottom <= top) return null

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        var sumR = 0L
        var sumG = 0L
        var sumB = 0L
        var count = 0

        var y = top
        while (y < bottom) {
            var x = left
            while (x < right) {
                val yIndex = y * yPlane.rowStride + x * yPlane.pixelStride
                val uvRow = y / 2
                val uvCol = x / 2
                val uIndex = uvRow * uPlane.rowStride + uvCol * uPlane.pixelStride
                val vIndex = uvRow * vPlane.rowStride + uvCol * vPlane.pixelStride

                if (yIndex < yBuffer.capacity() && uIndex < uBuffer.capacity() && vIndex < vBuffer.capacity()) {
                    val yVal = yBuffer.get(yIndex).toInt() and 0xFF
                    val uVal = (uBuffer.get(uIndex).toInt() and 0xFF) - 128
                    val vVal = (vBuffer.get(vIndex).toInt() and 0xFF) - 128

                    // Standard BT.601 YUV -> RGB.
                    val r = yVal + 1.402 * vVal
                    val g = yVal - 0.344136 * uVal - 0.714136 * vVal
                    val b = yVal + 1.772 * uVal

                    sumR += r.coerceIn(0.0, 255.0).toLong()
                    sumG += g.coerceIn(0.0, 255.0).toLong()
                    sumB += b.coerceIn(0.0, 255.0).toLong()
                    count++
                }
                x += SAMPLE_STRIDE
            }
            y += SAMPLE_STRIDE
        }

        if (count == 0) return null
        return RgbSample(
            timestampMs = System.currentTimeMillis(),
            red = sumR.toFloat() / count,
            green = sumG.toFloat() / count,
            blue = sumB.toFloat() / count
        )
    }
}
