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
    /** [Segment 28] OFF by default, same convention as [useMotionTracking].
     *  When true, skipped-detection frames run REAL ML Kit detection on a
     *  small, padded crop around the last known box ([CroppedDetectionStrategy])
     *  instead of freezing the box or estimating its motion -- a smaller
     *  [com.google.mlkit.vision.common.InputImage] should cost less than the
     *  full-frame detection un-skipped frames already pay. Takes priority
     *  over [useMotionTracking] on a skipped frame when both are true (not a
     *  measured combination -- just an arbitrary precedence so the two don't
     *  race). See [CroppedDetectionStrategy]'s own "HONEST STATUS" note: not
     *  exercised on a physical device this session. */
    private val useCroppedDetection: Boolean = false,
    private val croppedDetectionPaddingFraction: Float = 0.5f,
    private val croppedDetectionDownscaleFactor: Int = 1,
    /** [Segment 29] PROMOTED TO DEFAULT (0.35, up from ML Kit's own default
     *  of 0.1) after real on-device measurement (Galaxy A35): cut mean real-
     *  detection cost ~87-90ms -> ~19-25ms (a ~4x reduction, not a noise-band
     *  effect -- baseline was bracketed before/after and stayed at ~88-90ms)
     *  and raised steady-state fps ~18.5-19 -> ~23.7-23.84, with 0-1 missed-
     *  face frames out of ~1000 at both normal and increased camera distance.
     *  Google's own docs note a larger value lets the detector skip pyramid
     *  levels and run faster, at the cost of missing smaller/more distant
     *  faces -- this project's own measurement above is the evidence that
     *  cost is acceptable at 0.35 for this app's expected usage distance,
     *  not just Google's general guidance taken on faith. See
     *  android/docs/Segment29_MinFaceSize_And_Kalman.md for the full capture
     *  data and caveats (distance range was NOT exhaustively swept). */
    private val minFaceSize: Float = 0.35f,
    /** [Segment 29] PROMOTED TO DEFAULT after real on-device measurement:
     *  effectively free (mean predict() cost 0.03-0.04ms, max ~3ms across
     *  two captures -- even cheaper than [OpticalFlowFaceTracker]'s SAD
     *  matching) and composes cleanly with the [minFaceSize] promotion above
     *  (combined capture matched the fps of minFaceSize alone). A different
     *  risk class from [useMotionTracking] and [useCroppedDetection]: never
     *  reads pixel content, only extrapolates box geometry, so it cannot
     *  inherit the skin-texture/lighting drift failure mode
     *  `matlab/docs/Segment7_Task_D_Landmark_ROI.md` documented for a
     *  KLT-tracked ROI. HONEST CAVEAT: its positional-accuracy benefit (vs.
     *  the plain frozen box) was validated only against synthetic motion in
     *  [KalmanBoxTrackerTest], not against real ground-truth face positions
     *  -- promoted on "measurably free, plausible upside, no measured
     *  downside," not on a validated accuracy win. Takes priority over
     *  [useMotionTracking] on a skipped frame when both are true (arbitrary
     *  precedence, the two were never measured together); [useCroppedDetection]
     *  still takes priority over both. */
    private val useKalmanTracking: Boolean = true,
    private val onResult: (FaceAnalysisResult) -> Unit
) : ImageAnalysis.Analyzer {

    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setMinFaceSize(minFaceSize)
            .build()
    )

    private val motionTracker = if (useMotionTracking) OpticalFlowFaceTracker() else null
    private val kalmanTracker = if (useKalmanTracking) KalmanBoxTracker() else null

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

    // [Segment 28] useCroppedDetection path only -- consecutive skipped
    // frames where the cropped-region detection found no face. Once this
    // hits maxConsecutiveCroppedMisses, the NEXT skipped frame forces a
    // full-frame detection instead of another crop attempt, so a subject
    // who moved out of the cropped region (or left and re-entered frame)
    // gets reacquired rather than staying stuck missing indefinitely.
    private var consecutiveCroppedMisses = 0

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

        // [Segment 28] Once the cropped-detection path has missed too many
        // times in a row, force a full-frame detection this frame instead of
        // trying the crop again -- the subject may have moved out of the
        // cropped region entirely (or left and re-entered frame), and only a
        // full-frame detection can reacquire them.
        val forceFullFrameForReacquire = useCroppedDetection && consecutiveCroppedMisses >= MAX_CONSECUTIVE_CROPPED_MISSES
        val shouldSkipDetection = staleFaceBox != null && frameCounter % DETECT_EVERY_N_FRAMES != 0 && !forceFullFrameForReacquire

        if (shouldSkipDetection) {
            if (useCroppedDetection) {
                trackViaCroppedDetection(imageProxy, staleFaceBox!!, rotationDegrees, rotatedImageWidth, rotatedImageHeight)
                return
            }
            // Default (both useMotionTracking and useKalmanTracking false):
            // reuse the last known face box entirely -- no detector.process()
            // call this frame, the ~98.5%-of-cost operation Task G measured.
            // useKalmanTracking takes priority over useMotionTracking when
            // both are true (see this class's own KDoc); fall back to the
            // frozen box on any null (never worse than the default).
            val boxToUse = kalmanTracker?.predict() ?: trackViaMotionEstimate(imageProxy, rotationDegrees) ?: staleFaceBox!!
            lastFaceBoxRotated = boxToUse
            emitFaceDetected(boxToUse, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
            imageProxy.close()
            return
        }

        if (useCroppedDetection) {
            consecutiveCroppedMisses = 0 // about to run a full-frame detection either way
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
                    kalmanTracker?.clear()
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
                if (kalmanTracker != null) {
                    // predict() first, THEN correct() -- keeps the filter's
                    // internal dt=1-per-frame time base consistent whether
                    // this frame's box came from a real detection or (on
                    // skipped frames) extrapolation. See KalmanBoxTracker's
                    // own KDoc.
                    kalmanTracker.predict()
                    kalmanTracker.correct(face.boundingBox)
                }
                emitFaceDetected(face.boundingBox, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
                imageProxy.close()
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "Face detection failed for this frame", e)
                lastFaceBoxRotated = null
                motionTracker?.clear()
                kalmanTracker?.clear()
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

    /** [useCroppedDetection] path only -- runs REAL ML Kit detection on a
     *  small padded crop around [staleFaceBoxRotated] instead of freezing
     *  the box or estimating its motion. Replaces the caller's own
     *  synchronous skip-branch return, so it closes [imageProxy] itself on
     *  every path (sync fallback or either async listener). */
    @ExperimentalGetImage
    private fun trackViaCroppedDetection(
        imageProxy: ImageProxy,
        staleFaceBoxRotated: Rect,
        rotationDegrees: Int,
        rotatedImageWidth: Int,
        rotatedImageHeight: Int
    ) {
        val staleSensorRect = CoordinateMapper.rotatedRectToSensorRect(
            staleFaceBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height
        )
        val cropResult = CroppedDetectionStrategy.buildCroppedInputImage(
            imageProxy, staleSensorRect, rotationDegrees, croppedDetectionPaddingFraction, croppedDetectionDownscaleFactor
        )
        if (cropResult == null) {
            // Crop too small or no image planes -- fall back to the frozen
            // box, same as the default (no-tracking) skip path.
            lastFaceBoxRotated = staleFaceBoxRotated
            emitFaceDetected(staleFaceBoxRotated, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
            imageProxy.close()
            return
        }

        detector.process(cropResult.inputImage)
            .addOnSuccessListener { faces ->
                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }

                if (face == null) {
                    consecutiveCroppedMisses++
                    lastFaceBoxRotated = staleFaceBoxRotated
                    emitFaceDetected(staleFaceBoxRotated, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
                    imageProxy.close()
                    return@addOnSuccessListener
                }
                consecutiveCroppedMisses = 0

                // face.boundingBox is in the cropped buffer's own ROTATED
                // space. Undo that rotation using the SMALL buffer's own raw
                // dimensions (cropResult.rawWidth/rawHeight, NOT
                // imageProxy.width/height) to land in the small buffer's own
                // sensor space, scale back up by the downscale factor to the
                // full-res crop's local sensor coordinates, offset by the
                // crop's own sensor-space origin to land in the FULL frame's
                // sensor space, then convert to the full frame's rotated
                // space for the rest of the pipeline (RoiCalculator, the
                // overlay, etc. all expect that space).
                val faceBoxCroppedSensor = CoordinateMapper.rotatedRectToSensorRect(
                    face.boundingBox, rotationDegrees, cropResult.rawWidth, cropResult.rawHeight
                )
                val faceBoxCropLocalSensor = scaleRect(faceBoxCroppedSensor, cropResult.downscaleFactor)
                val faceBoxFullSensor = CroppedDetectionStrategy.remapCropRectToSensorRect(
                    faceBoxCropLocalSensor, cropResult.cropRectSensor
                )
                val faceBoxFullRotated = CoordinateMapper.sensorRectToRotatedRect(
                    faceBoxFullSensor, rotationDegrees, imageProxy.width, imageProxy.height
                )

                lastFaceBoxRotated = faceBoxFullRotated
                emitFaceDetected(faceBoxFullRotated, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
                imageProxy.close()
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "Cropped face detection failed for this frame", e)
                consecutiveCroppedMisses++
                lastFaceBoxRotated = staleFaceBoxRotated
                emitFaceDetected(staleFaceBoxRotated, rotationDegrees, rotatedImageWidth, rotatedImageHeight, imageProxy)
                imageProxy.close()
            }
    }

    /** Scales every edge of [rect] by [factor] -- used to undo
     *  [CroppedDetectionStrategy.buildCroppedInputImage]'s downscaling
     *  before offsetting back into full-sensor space. Field arithmetic, not
     *  a 4-arg `Rect(...)` construction -- see [CroppedDetectionStrategy]'s
     *  own note on why that constructor is unsafe under this project's unit
     *  test harness (irrelevant to this specific call site, which only ever
     *  runs on a real device, but kept consistent regardless). */
    private fun scaleRect(rect: Rect, factor: Int): Rect {
        val r = Rect()
        r.left = rect.left * factor
        r.top = rect.top * factor
        r.right = rect.right * factor
        r.bottom = rect.bottom * factor
        return r
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

        /** [useCroppedDetection] path only -- consecutive misses tolerated
         *  before forcing a full-frame reacquisition detection. Arbitrary,
         *  unmeasured choice (no device this session): small enough that a
         *  subject who has actually left the cropped region gets reacquired
         *  within roughly one detection cycle at DETECT_EVERY_N_FRAMES=3,
         *  large enough to tolerate one or two spurious misses without
         *  discarding an otherwise-good crop. */
        private const val MAX_CONSECUTIVE_CROPPED_MISSES = 3
    }
}
