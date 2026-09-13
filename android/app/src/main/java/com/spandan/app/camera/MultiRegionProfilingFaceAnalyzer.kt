package com.spandan.app.camera

import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.atomic.AtomicLong

/**
 * NEW FILE -- exploratory pilot (Spandan Field Guide "still open" list),
 * Action 1. Feasibility prototype ONLY: gated behind the [secondRegionEnabled]
 * constructor flag, never constructed by MainActivity.kt, and NOT wired into
 * the live HR pipeline (RealHeartRateEstimator/SignalBuffer never see this
 * class's output -- see the throughput-only capture script this was built
 * for). Does not modify FaceAnalyzer.kt, ProfilingFaceAnalyzer.kt,
 * RoiCalculator.kt's existing forehead default, or RoiPixelAverager.kt's
 * existing single-rect averageRgb -- purely additive.
 *
 * Same detector config/largest-face rule/timing-harness style as
 * ProfilingFaceAnalyzer.kt (Segment7_Task_G), reused here rather than
 * re-invented, per this pilot's own instructions -- but WITHOUT
 * FaceAnalyzer.kt's frame-skip logic (deliberately: this A/B test is about
 * the added cost of a second ROI crop-and-average pass, a variable that
 * should not be entangled with the separate, already-measured frame-skip
 * question).
 *
 * Per frame: detect (every frame) -> forehead ROI crop+average (roi1Ms) ->
 * IF [secondRegionEnabled], ALSO cheek ROI (left+right, pooled per
 * RoiCalculator.cheekRoisFrom / RoiPixelAverager.averageRgbMultiRect) crop+
 * average (roi2Ms, logged 0.0 when disabled) -> log one
 * SPANDAN_PROFILE_MULTIREGION line per frame. Running this class twice --
 * once with secondRegionEnabled=false, once true -- on the same device
 * gives a controlled 1-region-vs-2-region fps comparison (same detector
 * overhead both times, only the ROI stage differs).
 */
class MultiRegionProfilingFaceAnalyzer(
    private val secondRegionEnabled: Boolean
) : ImageAnalysis.Analyzer {

    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
    )

    private val frameIndex = AtomicLong(0)
    private val runStartNanos = SystemClock.elapsedRealtimeNanos()

    @ExperimentalGetImage
    override fun analyze(imageProxy: ImageProxy) {
        val callbackStartNanos = SystemClock.elapsedRealtimeNanos()

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        val inputImage = InputImage.fromMediaImage(mediaImage, rotationDegrees)

        val detectStartNanos = SystemClock.elapsedRealtimeNanos()

        detector.process(inputImage)
            .addOnSuccessListener { faces ->
                val detectEndNanos = SystemClock.elapsedRealtimeNanos()
                val detectMs = (detectEndNanos - detectStartNanos) / 1_000_000.0

                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }

                if (face == null) {
                    logFrame(detectMs, roi1Ms = 0.0, roi2Ms = 0.0, callbackStartNanos = callbackStartNanos, faceFound = false)
                    imageProxy.close()
                    return@addOnSuccessListener
                }

                val faceBoxRotated = face.boundingBox

                val roi1StartNanos = SystemClock.elapsedRealtimeNanos()
                val foreheadRoiRotated = RoiCalculator.foreheadRoiFrom(faceBoxRotated)
                val foreheadRoiSensor = CoordinateMapper.rotatedRectToSensorRect(
                    foreheadRoiRotated, rotationDegrees, imageProxy.width, imageProxy.height
                )
                RoiPixelAverager.averageRgb(imageProxy, foreheadRoiSensor)
                val roi1Ms = (SystemClock.elapsedRealtimeNanos() - roi1StartNanos) / 1_000_000.0

                var roi2Ms = 0.0
                if (secondRegionEnabled) {
                    val roi2StartNanos = SystemClock.elapsedRealtimeNanos()
                    val (cheekLeftRotated, cheekRightRotated) = RoiCalculator.cheekRoisFrom(faceBoxRotated)
                    val cheekLeftSensor = CoordinateMapper.rotatedRectToSensorRect(
                        cheekLeftRotated, rotationDegrees, imageProxy.width, imageProxy.height
                    )
                    val cheekRightSensor = CoordinateMapper.rotatedRectToSensorRect(
                        cheekRightRotated, rotationDegrees, imageProxy.width, imageProxy.height
                    )
                    RoiPixelAverager.averageRgbMultiRect(imageProxy, listOf(cheekLeftSensor, cheekRightSensor))
                    roi2Ms = (SystemClock.elapsedRealtimeNanos() - roi2StartNanos) / 1_000_000.0
                }

                logFrame(detectMs, roi1Ms, roi2Ms, callbackStartNanos, faceFound = true)
                imageProxy.close()
            }
            .addOnFailureListener { e ->
                val detectEndNanos = SystemClock.elapsedRealtimeNanos()
                val detectMs = (detectEndNanos - detectStartNanos) / 1_000_000.0
                Log.w(TAG, "Face detection failed for this frame", e)
                logFrame(detectMs, roi1Ms = 0.0, roi2Ms = 0.0, callbackStartNanos = callbackStartNanos, faceFound = false)
                imageProxy.close()
            }
    }

    private fun logFrame(detectMs: Double, roi1Ms: Double, roi2Ms: Double, callbackStartNanos: Long, faceFound: Boolean) {
        val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
        val otherMs = (totalMs - detectMs - roi1Ms - roi2Ms).coerceAtLeast(0.0)
        val elapsedSinceStartS = (SystemClock.elapsedRealtimeNanos() - runStartNanos) / 1_000_000_000.0
        Log.d(
            TAG,
            ("SPANDAN_PROFILE_MULTIREGION idx=%d t=%.2fs face=%b secondRegion=%b " +
                "detectMs=%.2f roi1Ms=%.2f roi2Ms=%.2f otherMs=%.2f totalMs=%.2f").format(
                frameIndex.incrementAndGet(), elapsedSinceStartS, faceFound, secondRegionEnabled,
                detectMs, roi1Ms, roi2Ms, otherMs, totalMs
            )
        )
    }

    companion object {
        private const val TAG = "MultiRegionProfilingFaceAnalyzer"
    }
}
