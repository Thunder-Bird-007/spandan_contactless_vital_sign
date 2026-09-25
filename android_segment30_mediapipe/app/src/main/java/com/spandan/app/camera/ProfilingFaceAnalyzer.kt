package com.spandan.app.camera

import android.content.Context
import android.graphics.Rect
import android.media.Image
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector as MediaPipeFaceDetector
import com.google.mediapipe.tasks.vision.facedetector.FaceDetectorResult
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.spandan.app.signal.RgbSample
import java.util.concurrent.atomic.AtomicLong

/**
 * NEW FILE -- Segment 7 Task G (throughput profiling). Additive only: this
 * does not modify RoiPixelAverager.kt or RoiCalculator.kt. It duplicates
 * FaceAnalyzer's analyze() logic (same detector config, same
 * ROI/coordinate-mapping/pixel-averaging calls, same "largest face" rule)
 * with SystemClock.elapsedRealtimeNanos() timing split into three phases:
 *
 * [2026-09-13] UPDATED to also mirror FaceAnalyzer.kt's Action C2 frame-skip
 * optimization (DETECT_EVERY_N_FRAMES=3, reuse lastFaceBoxRotated on the
 * frames in between) -- this file's own class doc previously said it
 * "duplicates FaceAnalyzer's analyze() logic", which had gone stale the
 * moment FaceAnalyzer.kt gained the skip logic; kept in sync here so this
 * profiler actually measures the CURRENT production code path, not the
 * pre-optimization baseline. On a skipped frame, detectMs is logged as 0.0
 * (no detector.process() call happens) and roiMs/otherMs are still real,
 * so parsing the same SPANDAN_PROFILE lines the same way still gives an
 * honest post-optimization steady-state fps.
 *
 *   1. detectMs   -- wall-clock time from calling detector.process(inputImage)
 *                    to the success/failure listener firing. This is an
 *                    ASYNCHRONOUS Task under the hood (ML Kit runs it off the
 *                    calling thread), so this measures elapsed wall time for
 *                    the whole detection round trip, not CPU-busy time on any
 *                    one thread -- the honest quantity for "how much of the
 *                    ~75ms/frame budget does detection eat," which is exactly
 *                    what the open question in android/README.md needs.
 *   2. roiMs      -- ROI-rect derivation (RoiCalculator) + coordinate mapping
 *                    (CoordinateMapper) + pixel averaging (RoiPixelAverager),
 *                    all synchronous, timed together as one "ROI + averaging"
 *                    phase (splitting rect math from the averaging loop
 *                    further would be noise -- rect math is a handful of int
 *                    ops, averaging is the only part with a pixel loop).
 *   3. otherMs    -- everything else in the callback: the analyze() call's
 *                    own setup (null checks, InputImage construction,
 *                    rotated-dimension bookkeeping) plus the onResult()
 *                    callback invocation and imageProxy.close(). Computed as
 *                    (totalMs - detectMs - roiMs), not measured with its own
 *                    timestamp pair, so it also absorbs any small scheduling
 *                    gaps between the timed sections.
 *
 * Per-frame numbers are logged at Log.d and also aggregated into running
 * min/max/count/sum per phase (dumped on demand via [dumpSummary]) so a
 * 60-second capture can be summarized without a separate host-side script,
 * though computing real mean/median/p90 from the raw per-frame Log.d lines
 * (same approach android/README.md's existing SPANDAN_TIMING diagnostic
 * used) is the more rigorous option if this is ever actually run.
 *
 * [2026-09-15] RE-SYNCED (Segment 18) to also mirror FaceAnalyzer.kt's new
 * `useMotionTracking`/[OpticalFlowFaceTracker] path -- this file had NOT yet
 * gone stale on that specific point (this update landed in the same commit
 * as FaceAnalyzer.kt's own change, not a separate catch-up), but the
 * "re-sync before trusting a capture" check this doc's own history calls
 * for was still done explicitly, not skipped, per the task brief. When
 * profiling the tracking path, [motionMs] adds a fourth timed phase (the
 * [OpticalFlowFaceTracker.track] call itself, on skipped frames only) so a
 * future capture can see its real cost alongside detectMs/roiMs/otherMs.
 *
 * [Segment 30] RE-SYNCED to mirror FaceAnalyzer.kt's new `useMediaPipeDetection`
 * path (see that class's own KDoc for the design rationale) -- when true,
 * this profiler's real (un-skipped) detection frames run MediaPipe instead
 * of ML Kit, and `detectMs` measures MediaPipe's own detectAsync-to-callback
 * wall time, directly comparable to the existing ML-Kit `detectMs` numbers
 * every prior segment's captures already used this same log format for.
 *
 * ALSO ADDS `logMediaPipeVsMlKitComparison` (a SEPARATE, independent flag --
 * see this task's own step 8 requirement: "before trusting an fps number
 * alone" for a candidate detector, check it isn't just faster-but-wrong).
 * When true, ML Kit stays the PRIMARY detector (production behavior,
 * `lastFaceBoxRotated`/trackers/ROI/onResult all driven by ML Kit exactly as
 * before, so this flag cannot itself regress the measured pipeline), and on
 * every REAL (non-skipped) ML-Kit-detection frame where ML Kit found a face,
 * MediaPipe ALSO runs on the SAME frame purely to log an IoU / center-
 * distance comparison (`SPANDAN_MEDIAPIPE_VS_MLKIT` lines) between the two
 * detectors' boxes -- see [MediaPipeVsMlKitComparator]. This intentionally
 * adds extra per-frame cost NOT reflected in `detectMs`/`totalMs` (the
 * comparison detection is timed and logged separately, and its own overhead
 * is excluded from the primary timing numbers by design -- computing
 * `totalMs`/calling `logFrame` BEFORE kicking off the comparison call, and
 * only deferring `imageProxy.close()` past it), so a capture session should
 * use EITHER `useMediaPipeDetection` (for a clean MediaPipe-only fps number)
 * OR `logMediaPipeVsMlKitComparison` (for accuracy validation against ML
 * Kit), not both at once for the same purpose.
 */
class ProfilingFaceAnalyzer(
    private val useMotionTracking: Boolean = false,
    /** [Segment 28] Mirrors FaceAnalyzer.kt's own useCroppedDetection flag --
     *  see that class's KDoc. When true, [cropStats]/`cropMs` times the
     *  combined cost of building the cropped InputImage
     *  ([CroppedDetectionStrategy.buildCroppedInputImage], NV21 extraction
     *  included) AND running detector.process() on it, on skipped-detection
     *  frames -- the one number the Segment 28 measurement protocol actually
     *  needs to know whether cropped detection is cheaper than the full-
     *  frame detectMs this file already measures on un-skipped frames. */
    private val useCroppedDetection: Boolean = false,
    private val croppedDetectionPaddingFraction: Float = 0.5f,
    private val croppedDetectionDownscaleFactor: Int = 1,
    /** [Segment 29] Mirrors FaceAnalyzer.kt's own minFaceSize -- see that
     *  class's KDoc for why 0.35 is now the promoted production default. */
    private val minFaceSize: Float = 0.35f,
    /** [Segment 29] Mirrors FaceAnalyzer.kt's own useKalmanTracking -- see
     *  that class's KDoc for why true is now the promoted production
     *  default. */
    private val useKalmanTracking: Boolean = true,
    /** [Segment 30] Mirrors FaceAnalyzer.kt's own useMediaPipeDetection --
     *  see that class's KDoc AND this file's own class KDoc "[Segment 30]"
     *  section above for the distinction from [logMediaPipeVsMlKitComparison]. */
    private val useMediaPipeDetection: Boolean = false,
    private val context: Context? = null,
    /** [Segment 30] See this file's own class KDoc "[Segment 30]" section
     *  above. Independent of [useMediaPipeDetection]. */
    private val logMediaPipeVsMlKitComparison: Boolean = false,
    private val onResult: (FaceAnalysisResult) -> Unit
) : ImageAnalysis.Analyzer {

    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setMinFaceSize(minFaceSize)
            .build()
    )

    // [Segment 30] Shared by both useMediaPipeDetection and
    // logMediaPipeVsMlKitComparison -- either one needs a real MediaPipe
    // detector instance; see FaceAnalyzer.kt's own mediaPipeDetector field
    // for why this must be conditionally, not unconditionally, constructed.
    private val mediaPipeDetector: MediaPipeFaceDetector? =
        if (useMediaPipeDetection || logMediaPipeVsMlKitComparison) {
            val ctx = requireNotNull(context) {
                "ProfilingFaceAnalyzer: context must be non-null when useMediaPipeDetection or logMediaPipeVsMlKitComparison is true"
            }
            buildMediaPipeFaceDetector(ctx)
        } else null

    // [Segment 30] Which of the two independent MediaPipe call sites
    // (runMediaPipeFpsSwapDetection vs. runMediaPipeComparison) the single
    // shared resultListener/errorListener below should route a callback to
    // -- see FaceAnalyzer.kt's own pending-state fields for why this is safe
    // as plain instance state (single-threaded analyzer, at most one
    // detectAsync call in flight at a time).
    private enum class MediaPipeCallMode { FPS_SWAP, COMPARISON }
    private var pendingMode: MediaPipeCallMode? = null
    private var pendingImageProxy: ImageProxy? = null
    private var pendingRotationDegrees = 0
    private var pendingRotatedImageWidth = 0
    private var pendingRotatedImageHeight = 0
    private var pendingCallbackStartNanos = 0L // FPS_SWAP only
    private var pendingDetectStartNanos = 0L // FPS_SWAP only
    private var pendingComparisonMlKitBoxRotated: Rect? = null // COMPARISON only
    private var pendingComparisonFrameIdx: Long = 0 // COMPARISON only

    private val motionTracker = if (useMotionTracking) OpticalFlowFaceTracker() else null
    private val kalmanTracker = if (useKalmanTracking) KalmanBoxTracker() else null

    private val frameIndex = AtomicLong(0)

    // Mirrors FaceAnalyzer.kt's own frame-skip state -- see this file's
    // class KDoc "[2026-09-13] UPDATED" note above.
    private var frameCounter = 0
    private var lastFaceBoxRotated: Rect? = null
    private var consecutiveCroppedMisses = 0 // mirrors FaceAnalyzer.kt's own field

    // Running aggregates per phase -- crude (no percentiles), intended only
    // as a live sanity check while a capture is running. The authoritative
    // numbers should come from parsing the per-frame Log.d lines below,
    // same discipline as android/README.md's SPANDAN_TIMING analysis.
    private class PhaseStats {
        var count = 0L
        var sumMs = 0.0
        var minMs = Double.MAX_VALUE
        var maxMs = 0.0

        fun record(ms: Double) {
            count++
            sumMs += ms
            if (ms < minMs) minMs = ms
            if (ms > maxMs) maxMs = ms
        }

        fun meanMs(): Double = if (count == 0L) 0.0 else sumMs / count
    }

    private val detectStats = PhaseStats()
    private val roiStats = PhaseStats()
    private val motionStats = PhaseStats()
    private val cropStats = PhaseStats() // [Segment 28]
    private var cropMissCount = 0L // [Segment 28] -- a faster-but-wrong crop shouldn't look like a win
    private val otherStats = PhaseStats()
    // [Segment 30] useMediaPipeDetection's own detectMs is recorded into the
    // SAME detectStats above (via logFrame, unchanged) -- ML Kit and
    // MediaPipe are never both the PRIMARY detector in the same session, so
    // one generic "detect" aggregate is sufficient; the flags this session
    // was run with say which detector it measures.
    private val comparisonIouStats = PhaseStats() // [Segment 30] logMediaPipeVsMlKitComparison only (values are 0.0-1.0, not ms)
    private val comparisonCenterDistanceStats = PhaseStats() // [Segment 30] logMediaPipeVsMlKitComparison only (values are px, not ms)
    private var comparisonMismatchCount = 0L // [Segment 30] one detector found a face, the other didn't
    private var comparisonSampleCount = 0L // [Segment 30]
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

        // Same rotated-dimension derivation as FaceAnalyzer.kt -- see that
        // file's comment for why InputImage's own width/height can't be
        // trusted for this. Duplicated here rather than shared because this
        // file must not import/modify FaceAnalyzer.kt's internals beyond
        // what's already public (RoiCalculator/CoordinateMapper/
        // RoiPixelAverager, which are separate files and fine to call).
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
        val forceFullFrameForReacquire = useCroppedDetection && consecutiveCroppedMisses >= MAX_CONSECUTIVE_CROPPED_MISSES
        val shouldSkipDetection = staleFaceBox != null && frameCounter % DETECT_EVERY_N_FRAMES != 0 && !forceFullFrameForReacquire

        if (shouldSkipDetection) {
            if (useCroppedDetection) {
                analyzeViaCroppedDetection(imageProxy, staleFaceBox!!, rotationDegrees, rotatedImageWidth, rotatedImageHeight, callbackStartNanos)
                return
            }
            // Reuse the last known face box (default), extrapolate it via
            // KalmanBoxTracker (useKalmanTracking=true, takes priority), or
            // re-estimate it via OpticalFlowFaceTracker (useMotionTracking=true)
            // -- same precedence as FaceAnalyzer.kt's own skip branch.
            // detectMs=0.0 logged honestly either way (not measured, because
            // detector.process() never runs on a skipped frame). Kalman's
            // predict() cost is folded into the same motionMs phase as the
            // optical-flow tracker's -- both are "skip-strategy" cost, just a
            // different technique depending on which flag is set.
            val motionStartNanos = SystemClock.elapsedRealtimeNanos()
            val kalmanPredicted = kalmanTracker?.predict()
            val boxToUse = if (kalmanPredicted != null) {
                kalmanPredicted
            } else {
                val trackedSensorRect = motionTracker?.track(imageProxy)
                if (trackedSensorRect != null) {
                    CoordinateMapper.sensorRectToRotatedRect(
                        trackedSensorRect, rotationDegrees, imageProxy.width, imageProxy.height
                    )
                } else {
                    staleFaceBox!!
                }
            }
            lastFaceBoxRotated = boxToUse
            val motionMs = (SystemClock.elapsedRealtimeNanos() - motionStartNanos) / 1_000_000.0

            val roiStartNanos = SystemClock.elapsedRealtimeNanos()

            val roiBoxRotated = RoiCalculator.foreheadRoiFrom(boxToUse)
            val roiBoxSensor = CoordinateMapper.rotatedRectToSensorRect(
                roiBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height
            )
            val rgbSample: RgbSample? = RoiPixelAverager.averageRgb(imageProxy, roiBoxSensor)

            val roiEndNanos = SystemClock.elapsedRealtimeNanos()
            val roiMs = (roiEndNanos - roiStartNanos) / 1_000_000.0

            onResult(
                FaceAnalysisResult.FaceDetected(
                    faceBoxRotated = boxToUse,
                    roiBoxRotated = roiBoxRotated,
                    rotatedImageWidth = rotatedImageWidth,
                    rotatedImageHeight = rotatedImageHeight,
                    rgbSample = rgbSample
                )
            )
            imageProxy.close()

            val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
            logFrame(frameIndex.incrementAndGet(), detectMs = 0.0, roiMs = roiMs, motionMs = motionMs, cropMs = 0.0, totalMs = totalMs, faceFound = true)
            return
        }

        if (useCroppedDetection) {
            consecutiveCroppedMisses = 0 // about to run a full-frame detection either way
        }

        if (useMediaPipeDetection) {
            runMediaPipeFpsSwapDetection(imageProxy, mediaImage, rotationDegrees, rotatedImageWidth, rotatedImageHeight, callbackStartNanos)
            return
        }

        val detectStartNanos = SystemClock.elapsedRealtimeNanos()

        detector.process(inputImage)
            .addOnSuccessListener { faces ->
                val detectEndNanos = SystemClock.elapsedRealtimeNanos()
                val detectMs = (detectEndNanos - detectStartNanos) / 1_000_000.0

                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }

                if (face == null) {
                    lastFaceBoxRotated = null
                    motionTracker?.clear()
                    kalmanTracker?.clear()
                    val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                    logFrame(frameIndex.incrementAndGet(), detectMs, roiMs = 0.0, motionMs = 0.0, cropMs = 0.0, totalMs = totalMs, faceFound = false)
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
                    kalmanTracker.predict() // advance dt=1 first, same discipline as FaceAnalyzer.kt
                    kalmanTracker.correct(face.boundingBox)
                }

                val roiStartNanos = SystemClock.elapsedRealtimeNanos()

                val faceBoxRotated = face.boundingBox
                val roiBoxRotated = RoiCalculator.foreheadRoiFrom(faceBoxRotated)
                val roiBoxSensor = CoordinateMapper.rotatedRectToSensorRect(
                    roiBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height
                )
                val rgbSample: RgbSample? = RoiPixelAverager.averageRgb(imageProxy, roiBoxSensor)

                val roiEndNanos = SystemClock.elapsedRealtimeNanos()
                val roiMs = (roiEndNanos - roiStartNanos) / 1_000_000.0

                onResult(
                    FaceAnalysisResult.FaceDetected(
                        faceBoxRotated = faceBoxRotated,
                        roiBoxRotated = roiBoxRotated,
                        rotatedImageWidth = rotatedImageWidth,
                        rotatedImageHeight = rotatedImageHeight,
                        rgbSample = rgbSample
                    )
                )
                // [Segment 30] Compute totalMs/logFrame BEFORE deciding
                // whether to kick off the comparison detection, so the
                // comparison's own extra cost never contaminates this
                // frame's primary (ML-Kit) timing numbers -- see this file's
                // own class KDoc "[Segment 30]" section.
                if (!logMediaPipeVsMlKitComparison) {
                    imageProxy.close()
                }

                val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                val thisFrameIdx = frameIndex.incrementAndGet()
                logFrame(thisFrameIdx, detectMs, roiMs, motionMs = 0.0, cropMs = 0.0, totalMs = totalMs, faceFound = true)

                if (logMediaPipeVsMlKitComparison) {
                    runMediaPipeComparison(imageProxy, mediaImage, rotationDegrees, faceBoxRotated, thisFrameIdx)
                }
            }
            .addOnFailureListener { e ->
                val detectEndNanos = SystemClock.elapsedRealtimeNanos()
                val detectMs = (detectEndNanos - detectStartNanos) / 1_000_000.0
                Log.w(TAG, "Face detection failed for this frame", e)
                lastFaceBoxRotated = null
                motionTracker?.clear()
                kalmanTracker?.clear()
                val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                logFrame(frameIndex.incrementAndGet(), detectMs, roiMs = 0.0, motionMs = 0.0, cropMs = 0.0, totalMs = totalMs, faceFound = false)
                onResult(FaceAnalysisResult.NoFace)
                imageProxy.close()
            }
    }

    /** [Segment 28] [useCroppedDetection] path -- times the combined cost of
     *  building the cropped InputImage (including NV21 extraction) AND
     *  running detector.process() on it, together as `cropMs`, since that
     *  combined cost vs. the full-frame `detectMs` is the number the
     *  Segment 28 measurement protocol actually needs. Mirrors
     *  FaceAnalyzer.kt's own trackViaCroppedDetection -- see that method for
     *  the coordinate-mapping reasoning, not repeated here. */
    @ExperimentalGetImage
    private fun analyzeViaCroppedDetection(
        imageProxy: ImageProxy,
        staleFaceBoxRotated: Rect,
        rotationDegrees: Int,
        rotatedImageWidth: Int,
        rotatedImageHeight: Int,
        callbackStartNanos: Long
    ) {
        val cropStartNanos = SystemClock.elapsedRealtimeNanos()
        val staleSensorRect = CoordinateMapper.rotatedRectToSensorRect(
            staleFaceBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height
        )
        val cropResult = CroppedDetectionStrategy.buildCroppedInputImage(
            imageProxy, staleSensorRect, rotationDegrees, croppedDetectionPaddingFraction, croppedDetectionDownscaleFactor
        )
        if (cropResult == null) {
            val cropMs = (SystemClock.elapsedRealtimeNanos() - cropStartNanos) / 1_000_000.0
            lastFaceBoxRotated = staleFaceBoxRotated
            val roiBoxRotated = RoiCalculator.foreheadRoiFrom(staleFaceBoxRotated)
            val roiBoxSensor = CoordinateMapper.rotatedRectToSensorRect(roiBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height)
            val rgbSample = RoiPixelAverager.averageRgb(imageProxy, roiBoxSensor)
            onResult(FaceAnalysisResult.FaceDetected(staleFaceBoxRotated, roiBoxRotated, rotatedImageWidth, rotatedImageHeight, rgbSample))
            imageProxy.close()
            val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
            logFrame(frameIndex.incrementAndGet(), detectMs = 0.0, roiMs = 0.0, motionMs = 0.0, cropMs = cropMs, totalMs = totalMs, faceFound = true)
            return
        }

        detector.process(cropResult.inputImage)
            .addOnSuccessListener { faces ->
                val cropMs = (SystemClock.elapsedRealtimeNanos() - cropStartNanos) / 1_000_000.0
                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }

                val roiStartNanos = SystemClock.elapsedRealtimeNanos()
                val boxToUse: Rect
                if (face == null) {
                    consecutiveCroppedMisses++
                    cropMissCount++
                    boxToUse = staleFaceBoxRotated
                } else {
                    consecutiveCroppedMisses = 0
                    val faceBoxCroppedSensor = CoordinateMapper.rotatedRectToSensorRect(
                        face.boundingBox, rotationDegrees, cropResult.rawWidth, cropResult.rawHeight
                    )
                    val faceBoxCropLocalSensor = Rect().also {
                        it.left = faceBoxCroppedSensor.left * cropResult.downscaleFactor
                        it.top = faceBoxCroppedSensor.top * cropResult.downscaleFactor
                        it.right = faceBoxCroppedSensor.right * cropResult.downscaleFactor
                        it.bottom = faceBoxCroppedSensor.bottom * cropResult.downscaleFactor
                    }
                    val faceBoxFullSensor = CroppedDetectionStrategy.remapCropRectToSensorRect(faceBoxCropLocalSensor, cropResult.cropRectSensor)
                    boxToUse = CoordinateMapper.sensorRectToRotatedRect(faceBoxFullSensor, rotationDegrees, imageProxy.width, imageProxy.height)
                }
                lastFaceBoxRotated = boxToUse

                val roiBoxRotated = RoiCalculator.foreheadRoiFrom(boxToUse)
                val roiBoxSensor = CoordinateMapper.rotatedRectToSensorRect(roiBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height)
                val rgbSample = RoiPixelAverager.averageRgb(imageProxy, roiBoxSensor)
                val roiMs = (SystemClock.elapsedRealtimeNanos() - roiStartNanos) / 1_000_000.0

                onResult(FaceAnalysisResult.FaceDetected(boxToUse, roiBoxRotated, rotatedImageWidth, rotatedImageHeight, rgbSample))
                imageProxy.close()

                val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                logFrame(frameIndex.incrementAndGet(), detectMs = 0.0, roiMs = roiMs, motionMs = 0.0, cropMs = cropMs, totalMs = totalMs, faceFound = true)
            }
            .addOnFailureListener { e ->
                val cropMs = (SystemClock.elapsedRealtimeNanos() - cropStartNanos) / 1_000_000.0
                Log.w(TAG, "Cropped face detection failed for this frame", e)
                consecutiveCroppedMisses++
                cropMissCount++
                lastFaceBoxRotated = staleFaceBoxRotated
                val roiBoxRotated = RoiCalculator.foreheadRoiFrom(staleFaceBoxRotated)
                val roiBoxSensor = CoordinateMapper.rotatedRectToSensorRect(roiBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height)
                val rgbSample = RoiPixelAverager.averageRgb(imageProxy, roiBoxSensor)
                onResult(FaceAnalysisResult.FaceDetected(staleFaceBoxRotated, roiBoxRotated, rotatedImageWidth, rotatedImageHeight, rgbSample))
                imageProxy.close()
                val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                logFrame(frameIndex.incrementAndGet(), detectMs = 0.0, roiMs = 0.0, motionMs = 0.0, cropMs = cropMs, totalMs = totalMs, faceFound = true)
            }
    }

    /** [Segment 30] [useMediaPipeDetection] path -- runs MediaPipe's
     *  FaceDetector on the full frame INSTEAD of ML Kit, timing FROM BEFORE
     *  the YUV->Bitmap conversion (see [MediaPipeImageConverter]) THROUGH to
     *  detectAsync's callback firing, as one honest combined `detectMs` --
     *  same "bundle the real cost together" discipline Segment 28's own
     *  `cropMs` already used for NV21 extraction + detection together. See
     *  FaceAnalyzer.kt's own `runMediaPipeDetection` for why the conversion
     *  is needed at all (a real on-device crash, not a style choice) and for
     *  the imageProxy-lifetime reasoning, not repeated here. */
    @ExperimentalGetImage
    private fun runMediaPipeFpsSwapDetection(
        imageProxy: ImageProxy,
        mediaImage: Image,
        rotationDegrees: Int,
        rotatedImageWidth: Int,
        rotatedImageHeight: Int,
        callbackStartNanos: Long
    ) {
        val mpDetector = mediaPipeDetector
        if (mpDetector == null) {
            lastFaceBoxRotated = null
            motionTracker?.clear()
            kalmanTracker?.clear()
            onResult(FaceAnalysisResult.NoFace)
            imageProxy.close()
            return
        }

        pendingMode = MediaPipeCallMode.FPS_SWAP
        pendingImageProxy = imageProxy
        pendingRotationDegrees = rotationDegrees
        pendingRotatedImageWidth = rotatedImageWidth
        pendingRotatedImageHeight = rotatedImageHeight
        pendingCallbackStartNanos = callbackStartNanos
        pendingDetectStartNanos = SystemClock.elapsedRealtimeNanos()

        val bitmap = MediaPipeImageConverter.yuv420ToArgb8888Bitmap(mediaImage)
        val mpImage = BitmapImageBuilder(bitmap).build()
        val processingOptions = ImageProcessingOptions.builder().setRotationDegrees(rotationDegrees).build()
        mpDetector.detectAsync(mpImage, processingOptions, imageProxy.imageInfo.timestamp / 1_000_000)
    }

    /** [Segment 30] [useMediaPipeDetection] FPS_SWAP callback handler --
     *  mirrors the ML Kit success listener's own body above (same
     *  trackers/ROI/onResult/logFrame shape), reading `detectMs` from
     *  [pendingDetectStartNanos] instead of a captured local (impossible here
     *  since MediaPipe's resultListener is registered once at construction,
     *  not per-call -- see this file's own `pendingMode` field KDoc). */
    @ExperimentalGetImage
    private fun handleFpsSwapResult(result: FaceDetectorResult) {
        val imageProxy = pendingImageProxy
        val rotationDegrees = pendingRotationDegrees
        val rotatedImageWidth = pendingRotatedImageWidth
        val rotatedImageHeight = pendingRotatedImageHeight
        val callbackStartNanos = pendingCallbackStartNanos
        val detectStartNanos = pendingDetectStartNanos
        pendingImageProxy = null
        pendingMode = null
        if (imageProxy == null) return

        val detectMs = (SystemClock.elapsedRealtimeNanos() - detectStartNanos) / 1_000_000.0

        val face = result.detections().maxByOrNull {
            val box = it.boundingBox()
            box.width().toDouble() * box.height().toDouble()
        }

        if (face == null) {
            lastFaceBoxRotated = null
            motionTracker?.clear()
            kalmanTracker?.clear()
            val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
            logFrame(frameIndex.incrementAndGet(), detectMs, roiMs = 0.0, motionMs = 0.0, cropMs = 0.0, totalMs = totalMs, faceFound = false)
            onResult(FaceAnalysisResult.NoFace)
            imageProxy.close()
            return
        }

        val faceBoxRotated = CoordinateMapper.mediaPipeSensorBoxToRotatedRect(
            face.boundingBox(), rotationDegrees, imageProxy.width, imageProxy.height
        )
        lastFaceBoxRotated = faceBoxRotated
        if (motionTracker != null) {
            val sensorRect = CoordinateMapper.rotatedRectToSensorRect(
                faceBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height
            )
            motionTracker.reset(imageProxy, sensorRect)
        }
        if (kalmanTracker != null) {
            kalmanTracker.predict()
            kalmanTracker.correct(faceBoxRotated)
        }

        val roiStartNanos = SystemClock.elapsedRealtimeNanos()
        val roiBoxRotated = RoiCalculator.foreheadRoiFrom(faceBoxRotated)
        val roiBoxSensor = CoordinateMapper.rotatedRectToSensorRect(
            roiBoxRotated, rotationDegrees, imageProxy.width, imageProxy.height
        )
        val rgbSample: RgbSample? = RoiPixelAverager.averageRgb(imageProxy, roiBoxSensor)
        val roiMs = (SystemClock.elapsedRealtimeNanos() - roiStartNanos) / 1_000_000.0

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

        val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
        logFrame(frameIndex.incrementAndGet(), detectMs, roiMs, motionMs = 0.0, cropMs = 0.0, totalMs = totalMs, faceFound = true)
    }

    /** [Segment 30] [logMediaPipeVsMlKitComparison] path -- runs MediaPipe on
     *  the SAME frame ML Kit just detected on, purely to log how far its box
     *  lands from ML Kit's own (already-emitted, already-timed) box. Does
     *  NOT touch `lastFaceBoxRotated`/trackers/`onResult` -- the primary
     *  pipeline's state was already fully advanced by the ML Kit branch
     *  before this was called. */
    @ExperimentalGetImage
    private fun runMediaPipeComparison(
        imageProxy: ImageProxy,
        mediaImage: Image,
        rotationDegrees: Int,
        mlKitBoxRotated: Rect,
        frameIdx: Long
    ) {
        val mpDetector = mediaPipeDetector
        if (mpDetector == null) {
            imageProxy.close()
            return
        }

        pendingMode = MediaPipeCallMode.COMPARISON
        pendingImageProxy = imageProxy
        pendingRotationDegrees = rotationDegrees
        pendingComparisonMlKitBoxRotated = mlKitBoxRotated
        pendingComparisonFrameIdx = frameIdx

        // See MediaPipeImageConverter's own KDoc -- MediaPipe's Android
        // packet creator rejects a raw YUV_420_888 android.media.Image
        // (confirmed via a real on-device crash), so a Bitmap conversion is
        // required here too, not just in the FPS_SWAP path above.
        val bitmap = MediaPipeImageConverter.yuv420ToArgb8888Bitmap(mediaImage)
        val mpImage = BitmapImageBuilder(bitmap).build()
        val processingOptions = ImageProcessingOptions.builder().setRotationDegrees(rotationDegrees).build()
        mpDetector.detectAsync(mpImage, processingOptions, imageProxy.imageInfo.timestamp / 1_000_000)
    }

    /** [Segment 30] [logMediaPipeVsMlKitComparison] COMPARISON callback
     *  handler -- computes and logs IoU/center-distance against the ML Kit
     *  box captured by [runMediaPipeComparison], via
     *  [MediaPipeVsMlKitComparator]. Both boxes are converted into this
     *  project's own rotated/upright space before comparing (ML Kit's
     *  already was; MediaPipe's own box goes through
     *  [CoordinateMapper.mediaPipeSensorBoxToRotatedRect] here) -- see that
     *  function's own KDoc for why comparing them in two different spaces
     *  would silently produce a meaningless number. */
    private fun handleComparisonResult(result: FaceDetectorResult) {
        val imageProxy = pendingImageProxy
        val rotationDegrees = pendingRotationDegrees
        val mlKitBoxRotated = pendingComparisonMlKitBoxRotated
        val frameIdx = pendingComparisonFrameIdx
        pendingImageProxy = null
        pendingMode = null
        pendingComparisonMlKitBoxRotated = null
        if (imageProxy == null || mlKitBoxRotated == null) {
            imageProxy?.close()
            return
        }

        comparisonSampleCount++
        val face = result.detections().maxByOrNull {
            val box = it.boundingBox()
            box.width().toDouble() * box.height().toDouble()
        }

        if (face == null) {
            comparisonMismatchCount++
            Log.d(
                TAG,
                "SPANDAN_MEDIAPIPE_VS_MLKIT idx=$frameIdx mediaPipeFoundFace=false " +
                    "mlKitBox=${rectToShortString(mlKitBoxRotated)}"
            )
            imageProxy.close()
            return
        }

        val mediaPipeBoxRotated = CoordinateMapper.mediaPipeSensorBoxToRotatedRect(
            face.boundingBox(), rotationDegrees, imageProxy.width, imageProxy.height
        )
        val iou = MediaPipeVsMlKitComparator.intersectionOverUnion(mlKitBoxRotated, mediaPipeBoxRotated)
        val centerDistancePx = MediaPipeVsMlKitComparator.centerDistance(mlKitBoxRotated, mediaPipeBoxRotated)
        comparisonIouStats.record(iou)
        comparisonCenterDistanceStats.record(centerDistancePx)

        Log.d(
            TAG,
            "SPANDAN_MEDIAPIPE_VS_MLKIT idx=$frameIdx iou=%.4f centerDistancePx=%.2f mlKitBox=%s mediaPipeBox=%s"
                .format(iou, centerDistancePx, rectToShortString(mlKitBoxRotated), rectToShortString(mediaPipeBoxRotated))
        )
        imageProxy.close()
    }

    private fun rectToShortString(r: Rect): String = "[${r.left},${r.top},${r.right},${r.bottom}]"

    /** [Segment 30] Shared LIVE_STREAM resultListener/errorListener for
     *  [mediaPipeDetector] -- routes to whichever of the two independent
     *  call sites ([runMediaPipeFpsSwapDetection]/[runMediaPipeComparison])
     *  is currently pending; see [pendingMode]'s own KDoc. */
    private fun onMediaPipeResult(result: FaceDetectorResult, input: MPImage) {
        when (pendingMode) {
            MediaPipeCallMode.FPS_SWAP -> handleFpsSwapResult(result)
            MediaPipeCallMode.COMPARISON -> handleComparisonResult(result)
            null -> Unit // stray/unexpected callback; nothing pending to close or emit
        }
    }

    private fun onMediaPipeError(e: RuntimeException) {
        Log.w(TAG, "MediaPipe face detection failed for this frame", e)
        val mode = pendingMode
        val imageProxy = pendingImageProxy
        pendingImageProxy = null
        pendingMode = null
        when (mode) {
            MediaPipeCallMode.FPS_SWAP -> {
                lastFaceBoxRotated = null
                motionTracker?.clear()
                kalmanTracker?.clear()
                onResult(FaceAnalysisResult.NoFace)
                imageProxy?.close()
            }
            MediaPipeCallMode.COMPARISON -> {
                comparisonSampleCount++
                comparisonMismatchCount++
                pendingComparisonMlKitBoxRotated = null
                imageProxy?.close()
            }
            null -> imageProxy?.close()
        }
    }

    /** [Segment 30] Builds MediaPipe's FaceDetector in LIVE_STREAM mode --
     *  see FaceAnalyzer.kt's own `buildMediaPipeFaceDetector` for the model
     *  asset itself; reuses that class's own public
     *  `MEDIAPIPE_MODEL_ASSET_PATH` constant rather than duplicating it. */
    private fun buildMediaPipeFaceDetector(context: Context): MediaPipeFaceDetector {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(FaceAnalyzer.MEDIAPIPE_MODEL_ASSET_PATH)
            .build()
        val options = MediaPipeFaceDetector.FaceDetectorOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setResultListener(::onMediaPipeResult)
            .setErrorListener(::onMediaPipeError)
            .build()
        return MediaPipeFaceDetector.createFromOptions(context, options)
    }

    private fun logFrame(idx: Long, detectMs: Double, roiMs: Double, motionMs: Double, cropMs: Double, totalMs: Double, faceFound: Boolean) {
        val otherMs = (totalMs - detectMs - roiMs - motionMs - cropMs).coerceAtLeast(0.0)
        detectStats.record(detectMs)
        if (faceFound) roiStats.record(roiMs)
        if (useMotionTracking) motionStats.record(motionMs)
        if (useCroppedDetection && cropMs > 0.0) cropStats.record(cropMs)
        otherStats.record(otherMs)

        val elapsedSinceStartS = (SystemClock.elapsedRealtimeNanos() - runStartNanos) / 1_000_000_000.0
        Log.d(
            TAG,
            "SPANDAN_PROFILE idx=$idx t=%.2fs face=%b detectMs=%.2f roiMs=%.2f motionMs=%.2f cropMs=%.2f otherMs=%.2f totalMs=%.2f"
                .format(elapsedSinceStartS, faceFound, detectMs, roiMs, motionMs, cropMs, otherMs, totalMs)
        )
    }

    /**
     * Dumps the crude running aggregates collected so far. Intended to be
     * called once after a fixed-duration capture (e.g. from a debug-only
     * button, or a timed Handler.postDelayed in whatever Activity wires this
     * analyzer in) -- see this file's class KDoc for why the per-frame
     * Log.d lines, parsed offline, are the more rigorous source of truth.
     */
    fun dumpSummary() {
        Log.i(
            TAG,
            "SPANDAN_PROFILE_SUMMARY frames=${detectStats.count} " +
                "detect(mean=%.2f,min=%.2f,max=%.2f)ms ".format(detectStats.meanMs(), detectStats.minMs, detectStats.maxMs) +
                "roi(mean=%.2f,min=%.2f,max=%.2f)ms ".format(roiStats.meanMs(), roiStats.minMs, roiStats.maxMs) +
                (if (useMotionTracking) "motion(mean=%.2f,min=%.2f,max=%.2f)ms ".format(motionStats.meanMs(), motionStats.minMs, motionStats.maxMs) else "") +
                (if (useCroppedDetection) "crop(mean=%.2f,min=%.2f,max=%.2f)ms missRate=%d/%d ".format(cropStats.meanMs(), cropStats.minMs, cropStats.maxMs, cropMissCount, cropStats.count) else "") +
                (if (useMediaPipeDetection) "[detect above is MediaPipe, not ML Kit] " else "") +
                "other(mean=%.2f,min=%.2f,max=%.2f)ms".format(otherStats.meanMs(), otherStats.minMs, otherStats.maxMs) +
                (if (logMediaPipeVsMlKitComparison) " mediaPipeVsMlKit(iouMean=%.3f,iouMin=%.3f,centerDistMeanPx=%.2f,centerDistMaxPx=%.2f,mismatches=%d/%d)"
                    .format(
                        comparisonIouStats.meanMs(), comparisonIouStats.minMs,
                        comparisonCenterDistanceStats.meanMs(), comparisonCenterDistanceStats.maxMs,
                        comparisonMismatchCount, comparisonSampleCount
                    ) else "")
        )
    }

    companion object {
        private const val TAG = "ProfilingFaceAnalyzer"

        /** Must match FaceAnalyzer.kt's own DETECT_EVERY_N_FRAMES exactly --
         *  this is a profiling mirror of that production constant, not an
         *  independent choice. */
        private const val DETECT_EVERY_N_FRAMES = 3

        /** Must match FaceAnalyzer.kt's own MAX_CONSECUTIVE_CROPPED_MISSES. */
        private const val MAX_CONSECUTIVE_CROPPED_MISSES = 3
    }
}
