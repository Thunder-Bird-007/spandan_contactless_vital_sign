package com.spandan.app.camera

import kotlin.math.abs

/**
 * Segment 18, Workstream 1 -- pure integer-grid block matching, no Android
 * dependency at all (unit-testable with plain JUnit, unlike the ImageProxy-
 * touching [OpticalFlowFaceTracker] that calls this). Brute-force
 * sum-of-absolute-differences (SAD) search: this project's own prior finding
 * on the MATLAB side (`matlab/docs/Segment7_Task_D_Landmark_ROI.md`, a
 * KLT-tracked ROI net-regressing accuracy) was a reason to keep this
 * deliberately simple rather than reach for a heavier tracker (optical
 * flow/Lucas-Kanade libraries, a new OpenCV dependency) -- SAD block
 * matching over a small search radius on a heavily downsampled patch is
 * cheap enough to run every skipped frame without materially competing with
 * ML Kit's own ~72ms/frame detection cost.
 */
object OpticalFlowMatcher {

    /** Luma variance floor (0-255 scale) below which [reference] is treated
     *  as too flat/uniform to match reliably -- a blank or saturated patch
     *  can "match" any offset equally well, so reporting a confident-looking
     *  offset there would be worse than just falling back to the frozen
     *  last-known box. */
    private const val MIN_REFERENCE_VARIANCE = 4.0

    /**
     * Finds the integer grid offset (dx, dy), each in
     * `[-maxOffset, maxOffset]`, at which [search] best matches [reference]
     * (lowest SAD per compared cell).
     *
     * [reference] must be exactly `refW * refH` cells. [search] must be
     * exactly `(refW + 2*maxOffset) * (refH + 2*maxOffset)` cells, sampled
     * on the SAME grid stride as [reference] and centered on the same
     * nominal location -- i.e. [search] is [reference]'s own patch location
     * padded by `maxOffset` grid cells on every side. Matching grid stride
     * across both arrays is the caller's responsibility ([OpticalFlowFaceTracker]
     * samples both at the same pixel stride); this function is pure integer-
     * grid arithmetic with no notion of physical pixel spacing.
     *
     * Returns null if [reference] is too flat to match reliably (see
     * [MIN_REFERENCE_VARIANCE]) -- callers should fall back to the last
     * known position on null, never worse than not tracking at all.
     */
    fun bestOffset(reference: IntArray, refW: Int, refH: Int, search: IntArray, maxOffset: Int): Pair<Int, Int>? {
        require(refW > 0 && refH > 0) { "refW/refH must be positive" }
        require(reference.size == refW * refH) { "reference size ${reference.size} != refW*refH ${refW * refH}" }
        require(maxOffset >= 0) { "maxOffset must be >= 0" }
        val searchW = refW + 2 * maxOffset
        val searchH = refH + 2 * maxOffset
        require(search.size == searchW * searchH) { "search size ${search.size} != expected ${searchW * searchH}" }

        val refMean = reference.average()
        var refVariance = 0.0
        for (v in reference) { val d = v - refMean; refVariance += d * d }
        refVariance /= reference.size
        if (refVariance < MIN_REFERENCE_VARIANCE) return null

        var bestSad = Long.MAX_VALUE
        var bestDx = 0
        var bestDy = 0
        for (dy in -maxOffset..maxOffset) {
            for (dx in -maxOffset..maxOffset) {
                var sad = 0L
                for (j in 0 until refH) {
                    val searchRowBase = (j + dy + maxOffset) * searchW + (dx + maxOffset)
                    val refRowBase = j * refW
                    for (i in 0 until refW) {
                        sad += abs(reference[refRowBase + i] - search[searchRowBase + i])
                    }
                }
                if (sad < bestSad) {
                    bestSad = sad
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        return bestDx to bestDy
    }
}
