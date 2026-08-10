package com.spandan.app.camera

import android.graphics.Rect
import android.util.Log
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.spandan.app.signal.RgbSample

/** Result of analyzing one camera frame. */
sealed class FaceAnalysisResult {
    object NoFace : FaceAnalysisResult()

    data class FaceDetected(
        val faceBoxRotated: Rect,
        val roiBoxRotated: Rect,
        val rotatedImageWidth: Int,
        val rotatedImageHeight: Int,
        val rgbSample: RgbSample?
    ) : FaceAnalysisResult()
}

/**
 * CameraX ImageAnalysis.Analyzer that runs ML Kit face detection on the live
 * stream (via InputImage.fromMediaImage -- no per-frame Bitmap conversion
 * needed for detection), derives the placeholder forehead ROI, and spatially
 * averages RGB inside it. Real, permanent plumbing -- everything here stays
 * even after the real DSP algorithm is ported in.
 */
class FaceAnalyzer(
    private val onResult: (FaceAnalysisResult) -> Unit
) : ImageAnalysis.Analyzer {

    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
    )

    @ExperimentalGetImage
    override fun analyze(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        val inputImage = InputImage.fromMediaImage(mediaImage, rotationDegrees)

        // InputImage.fromMediaImage(...).width/height report the RAW,
        // unrotated sensor-buffer dimensions -- NOT swapped for 90/270
        // rotation, despite that being an easy assumption to make (and the
        // one this file used to make; confirmed wrong on-device: measured
        // inputImage=640x480 identical to imageProxy=640x480 at
        // rotationDegrees=270). Face.getBoundingBox(), on the other hand, IS
        // returned in the rotated/upright coordinate space. So the rotated
        // image's true width/height for 90/270 must be derived by swapping
        // the raw sensor dimensions ourselves.
        val rotatedImageWidth: Int
        val rotatedImageHeight: Int
        if (rotationDegrees == 90 || rotationDegrees == 270) {
            rotatedImageWidth = imageProxy.height
            rotatedImageHeight = imageProxy.width
        } else {
            rotatedImageWidth = imageProxy.width
            rotatedImageHeight = imageProxy.height
        }

        detector.process(inputImage)
            .addOnSuccessListener { faces ->
                // Always take the largest detected face, not faces[0] -- a
                // lesson carried over from the MATLAB side (segment2), where
                // picking the first Viola-Jones box instead of the largest
                // caused a real false-positive bug.
                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }

                if (face == null) {
                    onResult(FaceAnalysisResult.NoFace)
                    imageProxy.close()
                    return@addOnSuccessListener
                }

                val faceBoxRotated = face.boundingBox
                val roiBoxRotated = RoiCalculator.foreheadRoiFrom(faceBoxRotated)

                val roiBoxSensor = CoordinateMapper.rotatedRectToSensorRect(
                    roiBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height
                )
                val rgbSample = RoiPixelAverager.averageRgb(imageProxy, roiBoxSensor)

                onResult(
                    FaceAnalysisResult.FaceDetected(
                        faceBoxRotated = faceBoxRotated,
                        roiBoxRotated = roiBoxRotated,
                        rotatedImageWidth = rotatedImageWidth,
                        rotatedImageHeight = rotatedImageHeight,
                        rgbSample = rgbSample
                    )
                )
                imageProxy.close()
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "Face detection failed for this frame", e)
                onResult(FaceAnalysisResult.NoFace)
                imageProxy.close()
            }
    }

    companion object {
        private const val TAG = "FaceAnalyzer"
    }
}
