package com.spandan.app.camera

import android.graphics.Rect
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
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
                imageProxy.close()

                val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                logFrame(frameIndex.incrementAndGet(), detectMs, roiMs, motionMs = 0.0, cropMs = 0.0, totalMs = totalMs, faceFound = true)
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
                "other(mean=%.2f,min=%.2f,max=%.2f)ms".format(otherStats.meanMs(), otherStats.minMs, otherStats.maxMs)
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
