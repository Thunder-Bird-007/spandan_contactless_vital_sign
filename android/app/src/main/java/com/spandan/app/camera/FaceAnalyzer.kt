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
    /** Segment 18, Workstream 1 -- OFF by default (this project's standing
     *  "evidence before promotion" convention). When true, skipped-detection
     *  frames re-estimate the face box via [OpticalFlowFaceTracker] instead
     *  of freezing it; see that class's own KDoc for the full rationale and
     *  honest no-device-this-session caveat. When false (default), the code
     *  path below is IDENTICAL to before this flag existed -- [motionTracker]
     *  is null, [trackViaMotionEstimate] immediately returns null, and
     *  `boxToUse` is always `staleFaceBox`, byte-for-byte the prior
     *  behavior. */
    private val useMotionTracking: Boolean = false,
    private val onResult: (FaceAnalysisResult) -> Unit
) : ImageAnalysis.Analyzer {

    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
    )

    private val motionTracker = if (useMotionTracking) OpticalFlowFaceTracker() else null

    // --- Segment 7 Task G's own Action C2 proposal (android/docs/
    // Segment7_Task_G_Throughput_Profiling.md section 3), now implemented:
    // ML Kit detector.process() measured at ~98.5% of per-frame cost
    // (71.84ms of 72.91ms mean, real on-device capture, Galaxy A35) --
    // running it only every DETECT_EVERY_N_FRAMES-th frame and reusing the
    // last known face box on the frames in between is the doc's own
    // proposed lever. Bounded staleness: at N=3 and the measured ~72.9ms
    // real-detection cost, the face box can go up to ~2*72.9=146ms stale
    // between real detections (frames 2/3 of each cycle skip; frame 1 is
    // always fresh) -- well under normal head-motion speed for a forehead
    // ROI, same reasoning the doc's own sketch used. No new dependency
    // (no optical-flow/KLT tracker -- matlab/docs/Segment7_Task_D_Landmark_
    // ROI.md already found a KLT-tracked ROI net-regresses accuracy, a
    // caution against reaching for a heavier tracker here too, quoted
    // directly from the doc's own sketch).
    private var frameCounter = 0
    private var lastFaceBoxRotated: Rect? = null

    @ExperimentalGetImage
    override fun analyze(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val rotationDegrees = imageProxy.imageInfo.rotationDegrees

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

        frameCounter++
        val staleFaceBox = lastFaceBoxRotated
        val shouldSkipDetection = staleFaceBox != null && frameCounter % DETECT_EVERY_N_FRAMES != 0

        if (shouldSkipDetection) {
            // Default (useMotionTracking=false): reuse the last known face
            // box entirely -- no detector.process() call this frame, the
            // ~98.5%-of-cost operation Task G measured. When useMotionTracking
            // is true, try to re-estimate the box's position first (see
            // OpticalFlowFaceTracker's own KDoc); fall back to the frozen box
            // on any null (never worse than the default).
            val boxToUse = trackViaMotionEstimate(imageProxy, rotationDegrees) ?: staleFaceBox!!
            lastFaceBoxRotated = boxToUse
            emitFaceDetected(boxToUse, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
            imageProxy.close()
            return
        }

        val inputImage = InputImage.fromMediaImage(mediaImage, rotationDegrees)

        detector.process(inputImage)
            .addOnSuccessListener { faces ->
                // Always take the largest detected face, not faces[0] -- a
                // lesson carried over from the MATLAB side (segment2), where
                // picking the first Viola-Jones box instead of the largest
                // caused a real false-positive bug.
                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }

                if (face == null) {
                    lastFaceBoxRotated = null
                    motionTracker?.clear()
                    onResult(FaceAnalysisResult.NoFace)
                    imageProxy.close()
                    return@addOnSuccessListener
                }

                lastFaceBoxRotated = face.boundingBox
                if (motionTracker != null) {
                    val sensorRect = CoordinateMapper.rotatedRectToSensorRect(
                        face.boundingBox, rotationDegrees, imageProxy.width, imageProxy.height
                    )
                    motionTracker.reset(imageProxy, sensorRect)
                }
                emitFaceDetected(face.boundingBox, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
                imageProxy.close()
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "Face detection failed for this frame", e)
                lastFaceBoxRotated = null
                motionTracker?.clear()
                onResult(FaceAnalysisResult.NoFace)
                imageProxy.close()
            }
    }

    /** [useMotionTracking] path only -- returns an updated ROTATED-space
     *  face box from [OpticalFlowFaceTracker], or null (no tracker, no
     *  reference yet, or tracking failed this frame) for the caller to fall
     *  back to the frozen last-known box. */
    @ExperimentalGetImage
    private fun trackViaMotionEstimate(imageProxy: ImageProxy, rotationDegrees: Int): Rect? {
        val tracker = motionTracker ?: return null
        val trackedSensorRect = tracker.track(imageProxy) ?: return null
        return CoordinateMapper.sensorRectToRotatedRect(
            trackedSensorRect, rotationDegrees, imageProxy.width, imageProxy.height
        )
    }

    /** Shared ROI/coordinate-mapping/averaging tail for both a fresh detection
     *  and a reused (skipped-detection) face box -- identical math either
     *  way, just a different source for [faceBoxRotated]. */
    @ExperimentalGetImage
    private fun emitFaceDetected(
        faceBoxRotated: Rect,
        rotationDegrees: Int,
        rotatedImageWidth: Int,
        rotatedImageHeight: Int,
        imageProxy: ImageProxy
    ) {
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
    }

    companion object {
        private const val TAG = "FaceAnalyzer"

        /** Run real ML Kit detection on every Nth frame; reuse the last known
         *  face box on the frames in between. N=3 per Segment 7 Task G's own
         *  proposal range (N=2 or 3) -- see this class's own comment above
         *  for the staleness-bound reasoning. */
        private const val DETECT_EVERY_N_FRAMES = 3
    }
}
