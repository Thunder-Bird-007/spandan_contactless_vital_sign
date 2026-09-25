package com.spandan.app.camera

import android.graphics.Rect
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageProxy

/**
 * Segment 18, Workstream 1 -- a lightweight, OFF-BY-DEFAULT alternative to
 * [FaceAnalyzer]'s plain "freeze and reuse the last known face box" between
 * real ML Kit detections (the `DETECT_EVERY_N_FRAMES = 3` skip Segment 7
 * Task G measured and adopted: 13.44 -> 21.40fps steady-state). Instead of
 * holding the box perfectly still for up to 2 skipped frames while the face
 * may have actually moved, this re-estimates its position each skipped
 * frame via a coarse luma-patch centroid shift (brute-force SAD block match,
 * [OpticalFlowMatcher]) on a heavily downsampled Y-plane patch.
 *
 * Deliberately NOT a KLT/optical-flow-library tracker: `matlab/docs/
 * Segment7_Task_D_Landmark_ROI.md` already found a KLT-tracked ROI
 * net-REGRESSES the MATLAB pipeline's accuracy (4/5 -> 2/5 subjects above
 * the notch-confidence bar) -- a direct caution, on this project's own data,
 * against reaching for a heavier tracker here too. This is intentionally
 * the simplest thing that could plausibly help: one small SAD search per
 * skipped frame, no new dependency, no per-frame allocation beyond two small
 * IntArrays.
 *
 * Tracking happens entirely in SENSOR-space pixel coordinates (the only
 * space the Y-plane buffer actually lives in); [CoordinateMapper]'s existing
 * `rotatedRectToSensorRect` and the new `sensorRectToRotatedRect` (added
 * alongside this file) convert at the [FaceAnalyzer] boundary.
 *
 * HONEST STATUS: this class compiles and is unit-tested at the pure-math
 * layer ([OpticalFlowMatcher] -- synthetic shifted patches, no Android
 * dependency), but the Android-specific parts below (YUV plane indexing,
 * the coordinate round-trip) were NOT exercised on a physical device this
 * session -- none was attached in this environment. See
 * `android/docs/Segment18_Camera_Throughput_And_Buffer_Window.md` for the
 * full caveat. Gated behind [FaceAnalyzer]'s `useMotionTracking` constructor
 * flag, default `false` -- this project's standing "off-by-default,
 * evidence before promotion" convention (`useConfidenceGate`,
 * `useWaveletDenoise`, etc.), because there is no on-device A/B evidence
 * for this one yet.
 *
 * [Segment 28] `track()` used to allocate two fresh `IntArray`s (the search
 * window sample and the post-shift resample) on EVERY skipped frame --
 * flagged in `Segment18_Camera_Throughput_And_Buffer_Window.md` as a likely
 * contributor to this tracker measuring slower than the plain frozen-box
 * baseline. [searchScratch] and [resampleScratch] are now class-level
 * buffers reused across calls (reallocated only if the grid size actually
 * changes, which it does not while tracking the same face box dimensions
 * between resets). [referencePatch]'s own backing array is likewise reused
 * in place via `System.arraycopy` rather than reassigned to the scratch
 * buffer -- keeping the scratch buffers un-aliased from the committed
 * reference patch means a sample that fails partway through (returns
 * `false`) can never corrupt the last-known-good reference.
 */
class OpticalFlowFaceTracker {

    private var referencePatch: IntArray? = null
    private var referenceSensorRect: Rect? = null
    private var searchScratch: IntArray? = null
    private var resampleScratch: IntArray? = null

    /** Discards any reference patch (e.g. after a NoFace frame) so the next
     *  real detection starts a clean tracking cycle. */
    fun clear() {
        referencePatch = null
        referenceSensorRect = null
    }

    /** Call on every REAL ML Kit detection to (re)anchor tracking at the
     *  fresh, ground-truth box -- bounds any drift to at most the 1-2
     *  skipped frames between real detections, never longer. */
    @ExperimentalGetImage
    fun reset(imageProxy: ImageProxy, faceBoxSensor: Rect) {
        referenceSensorRect = Rect(faceBoxSensor)
        val cols = faceBoxSensor.width() / STRIDE_PX
        val rows = faceBoxSensor.height() / STRIDE_PX
        if (cols < MIN_GRID_DIM || rows < MIN_GRID_DIM) {
            referencePatch = null
            return
        }
        val buf = obtainBuffer(referencePatch, cols * rows)
        referencePatch = if (sampleGridInto(imageProxy, faceBoxSensor.left, faceBoxSensor.top, cols, rows, buf)) buf else null
    }

    /**
     * Call on a skipped-detection frame. Returns an updated SENSOR-space
     * face box, or null if tracking isn't possible this frame (no reference
     * yet, the search window ran off-frame, or the reference patch was too
     * flat to match -- see [OpticalFlowMatcher]). Callers should fall back
     * to the last known box on null: this can never be worse than the
     * pre-existing frozen-box behavior, only occasionally a no-op instead of
     * an improvement.
     */
    @ExperimentalGetImage
    fun track(imageProxy: ImageProxy): Rect? {
        val refPatch = referencePatch ?: return null
        val refRect = referenceSensorRect ?: return null

        val cols = refRect.width() / STRIDE_PX
        val rows = refRect.height() / STRIDE_PX
        if (cols < MIN_GRID_DIM || rows < MIN_GRID_DIM) return null

        val searchLeft = refRect.left - SEARCH_RADIUS_GRID * STRIDE_PX
        val searchTop = refRect.top - SEARCH_RADIUS_GRID * STRIDE_PX
        val searchCols = cols + 2 * SEARCH_RADIUS_GRID
        val searchRows = rows + 2 * SEARCH_RADIUS_GRID
        val searchRight = searchLeft + searchCols * STRIDE_PX
        val searchBottom = searchTop + searchRows * STRIDE_PX

        if (searchLeft < 0 || searchTop < 0 || searchRight > imageProxy.width || searchBottom > imageProxy.height) {
            return null // search window ran off-frame -- fall back rather than sample garbage
        }

        val searchBuf = obtainBuffer(searchScratch, searchCols * searchRows)
        searchScratch = searchBuf
        if (!sampleGridInto(imageProxy, searchLeft, searchTop, searchCols, searchRows, searchBuf)) return null

        val offset = OpticalFlowMatcher.bestOffset(refPatch, cols, rows, searchBuf, SEARCH_RADIUS_GRID) ?: return null

        val dxPx = offset.first * STRIDE_PX
        val dyPx = offset.second * STRIDE_PX
        val newRect = Rect(refRect.left + dxPx, refRect.top + dyPx, refRect.right + dxPx, refRect.bottom + dyPx)

        // Incremental re-anchoring at the newly found position -- bounds
        // per-step error to one grid search rather than compounding drift
        // in a fixed direction. Still open-loop between real detections (no
        // sanity check against ML Kit beyond the next real detection, which
        // always arrives within 2 frames at N=3) -- a real, stated limit,
        // not verified against ground truth on-device this session.
        val resampleBuf = obtainBuffer(resampleScratch, cols * rows)
        resampleScratch = resampleBuf
        if (!sampleGridInto(imageProxy, newRect.left, newRect.top, cols, rows, resampleBuf)) return null

        val newRefBuf = obtainBuffer(referencePatch, cols * rows)
        System.arraycopy(resampleBuf, 0, newRefBuf, 0, resampleBuf.size)
        referencePatch = newRefBuf
        referenceSensorRect = newRect

        return newRect
    }

    /** Returns [existing] unchanged if it already has exactly [size]
     *  elements, otherwise a fresh [IntArray] of that size -- the
     *  reallocation path only fires when the tracked box's grid dimensions
     *  actually change (e.g. a new [reset] at a different face size), never
     *  on a steady-state skipped frame. */
    private fun obtainBuffer(existing: IntArray?, size: Int): IntArray =
        if (existing != null && existing.size == size) existing else IntArray(size)

    /** Samples a [cols] x [rows] luma grid at [STRIDE_PX] pixel spacing,
     *  starting at ([left], [top]) in sensor pixel coordinates, into the
     *  caller-supplied [out] buffer (must be exactly `cols * rows` long) --
     *  same Y-plane indexing convention as [RoiPixelAverager.averageRgb]
     *  (rowStride/pixelStride, not assumed-contiguous rows), Y-plane only
     *  since motion tracking needs no chroma. Returns false (leaving [out]
     *  possibly partially written) if any sampled cell falls outside the
     *  image bounds -- callers must not trust [out] on a false return. */
    @ExperimentalGetImage
    private fun sampleGridInto(imageProxy: ImageProxy, left: Int, top: Int, cols: Int, rows: Int, out: IntArray): Boolean {
        val image = imageProxy.image ?: return false
        val yPlane = image.planes[0]
        val yBuffer = yPlane.buffer
        for (j in 0 until rows) {
            val y = top + j * STRIDE_PX
            if (y < 0 || y >= imageProxy.height) return false
            for (i in 0 until cols) {
                val x = left + i * STRIDE_PX
                if (x < 0 || x >= imageProxy.width) return false
                val idx = y * yPlane.rowStride + x * yPlane.pixelStride
                if (idx < 0 || idx >= yBuffer.capacity()) return false
                out[j * cols + i] = yBuffer.get(idx).toInt() and 0xFF
            }
        }
        return true
    }

    companion object {
        /** Pixel spacing between sampled luma cells -- a performance knob
         *  (like [RoiPixelAverager]'s own `SAMPLE_STRIDE`), not a signal-
         *  processing parameter. */
        private const val STRIDE_PX = 8

        /** Search radius in GRID cells (so +/- 32px at STRIDE_PX=8) --
         *  generous relative to the ~150-225ms/2-3-frame staleness window
         *  this is meant to correct, comparable to normal head-motion speed
         *  for a forehead ROI (same bound FaceAnalyzer's own KDoc already
         *  reasons about for the plain frozen-box case). */
        private const val SEARCH_RADIUS_GRID = 4

        /** Below this many grid cells per axis, block matching has too few
         *  samples to be meaningful -- bail out rather than match noise. */
        private const val MIN_GRID_DIM = 6
    }
}
