package com.spandan.app.camera

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
 * does not modify FaceAnalyzer.kt, RoiPixelAverager.kt, or RoiCalculator.kt.
 * It duplicates FaceAnalyzer's analyze() logic (same detector config, same
 * ROI/coordinate-mapping/pixel-averaging calls, same "largest face" rule)
 * with SystemClock.elapsedRealtimeNanos() timing split into three phases:
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
 */
class ProfilingFaceAnalyzer(
    private val onResult: (FaceAnalysisResult) -> Unit
) : ImageAnalysis.Analyzer {

    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
    )

    private val frameIndex = AtomicLong(0)

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

        val detectStartNanos = SystemClock.elapsedRealtimeNanos()

        detector.process(inputImage)
            .addOnSuccessListener { faces ->
                val detectEndNanos = SystemClock.elapsedRealtimeNanos()
                val detectMs = (detectEndNanos - detectStartNanos) / 1_000_000.0

                val face = faces.maxByOrNull { it.boundingBox.width().toLong() * it.boundingBox.height() }

                if (face == null) {
                    val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                    logFrame(frameIndex.incrementAndGet(), detectMs, roiMs = 0.0, totalMs = totalMs, faceFound = false)
                    onResult(FaceAnalysisResult.NoFace)
                    imageProxy.close()
                    return@addOnSuccessListener
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
                logFrame(frameIndex.incrementAndGet(), detectMs, roiMs, totalMs, faceFound = true)
            }
            .addOnFailureListener { e ->
                val detectEndNanos = SystemClock.elapsedRealtimeNanos()
                val detectMs = (detectEndNanos - detectStartNanos) / 1_000_000.0
                Log.w(TAG, "Face detection failed for this frame", e)
                val totalMs = (SystemClock.elapsedRealtimeNanos() - callbackStartNanos) / 1_000_000.0
                logFrame(frameIndex.incrementAndGet(), detectMs, roiMs = 0.0, totalMs = totalMs, faceFound = false)
                onResult(FaceAnalysisResult.NoFace)
                imageProxy.close()
            }
    }

    private fun logFrame(idx: Long, detectMs: Double, roiMs: Double, totalMs: Double, faceFound: Boolean) {
        val otherMs = (totalMs - detectMs - roiMs).coerceAtLeast(0.0)
        detectStats.record(detectMs)
        if (faceFound) roiStats.record(roiMs)
        otherStats.record(otherMs)

        val elapsedSinceStartS = (SystemClock.elapsedRealtimeNanos() - runStartNanos) / 1_000_000_000.0
        Log.d(
            TAG,
            "SPANDAN_PROFILE idx=$idx t=%.2fs face=%b detectMs=%.2f roiMs=%.2f otherMs=%.2f totalMs=%.2f"
                .format(elapsedSinceStartS, faceFound, detectMs, roiMs, otherMs, totalMs)
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
                "other(mean=%.2f,min=%.2f,max=%.2f)ms".format(otherStats.meanMs(), otherStats.minMs, otherStats.maxMs)
        )
    }

    companion object {
        private const val TAG = "ProfilingFaceAnalyzer"
    }
}
