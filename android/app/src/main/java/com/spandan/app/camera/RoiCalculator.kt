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

    // --- Exploratory pilot (Spandan Field Guide "still open" list), Action 1.
    // Feasibility prototype only -- NOT wired into the live HR pipeline (see
    // MultiRegionProfilingFaceAnalyzer.kt, a debug-only analyzer this is used
    // from). Cheek fractions ported directly from
    // matlab/src/roi/extractROISignals.m's `computeRegionBBoxes`, 'cheek'
    // mode: x:[0.10,0.35] (left) / [0.65,0.90] (right), y:[0.55,0.75] of the
    // face box -- same reconciled-against-MATLAB discipline as
    // foreheadRoiFrom's own header. Cheek (not glabella/malar) was picked
    // because Segment6_Task_N/Task_Q found forehead+cheek are the two
    // regions that are "not bad everywhere" -- glabella/malar lost to both
    // across every Task N scenario.
    private const val CHEEK_LEFT_X_LO = 0.10f
    private const val CHEEK_LEFT_X_HI = 0.35f
    private const val CHEEK_RIGHT_X_LO = 0.65f
    private const val CHEEK_RIGHT_X_HI = 0.90f
    private const val CHEEK_Y_LO = 0.55f
    private const val CHEEK_Y_HI = 0.75f

    /** Returns (leftCheekRoi, rightCheekRoi), both face-box-relative, same
     *  fractions matlab/src/roi/extractROISignals.m uses for its bilateral
     *  'cheek' roiMode. Callers pool both rects' pixels together BEFORE
     *  averaging (see RoiPixelAverager.averageRgbMultiRect), matching that
     *  file's own "concatenate-then-average" convention -- not two
     *  independent per-side means. */
    fun cheekRoisFrom(faceBox: Rect): Pair<Rect, Rect> {
        val w = faceBox.width()
        val h = faceBox.height()
        val top = faceBox.top + (CHEEK_Y_LO * h).toInt()
        val bottom = faceBox.top + (CHEEK_Y_HI * h).toInt()
        val left = Rect(
            faceBox.left + (CHEEK_LEFT_X_LO * w).toInt(),
            top,
            faceBox.left + (CHEEK_LEFT_X_HI * w).toInt(),
            bottom
        )
        val right = Rect(
            faceBox.left + (CHEEK_RIGHT_X_LO * w).toInt(),
            top,
            faceBox.left + (CHEEK_RIGHT_X_HI * w).toInt(),
            bottom
        )
        return left to right
    }
}
