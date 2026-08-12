package com.spandan.app.camera

import android.graphics.Rect

/**
 * Derives a forehead ROI (region of interest) as a fixed fractional sub-crop
 * of a detected face bounding box -- the same *concept* as the MATLAB side
 * (a fixed fractional crop, not a learned/adaptive one), so the two
 * pipelines stay conceptually comparable.
 *
 * The four fractions below are reconciled against MATLAB's validated
 * geometry: matlab/src/roi/extractROISignals.m's `computeRegionBBoxes`,
 * default/original `forehead` mode -- `clampedBBox(..., xFracLo=0.30,
 * xFracHi=0.70, yFracLo=0.10, yFracHi=0.30, ...)`. That is the exact,
 * pre-Task-N geometry Segment 6's validated HR pipeline (r=0.957) was run
 * against, so this is not an independent Android design choice -- it is a
 * direct port of MATLAB's numbers. (An earlier by-eye placeholder, TOP=0.08/
 * BOTTOM=0.30/LEFT=0.25/RIGHT=0.75, was checked here and found to actually
 * mismatch the MATLAB box -- this is a real port, not a stale TODO.)
 */
object RoiCalculator {

    private const val TOP_FRACTION = 0.10f
    private const val BOTTOM_FRACTION = 0.30f
    private const val LEFT_FRACTION = 0.30f
    private const val RIGHT_FRACTION = 0.70f

    fun foreheadRoiFrom(faceBox: Rect): Rect {
        val w = faceBox.width()
        val h = faceBox.height()
        return Rect(
            faceBox.left + (LEFT_FRACTION * w).toInt(),
            faceBox.top + (TOP_FRACTION * h).toInt(),
            faceBox.left + (RIGHT_FRACTION * w).toInt(),
            faceBox.top + (BOTTOM_FRACTION * h).toInt()
        )
    }
}
