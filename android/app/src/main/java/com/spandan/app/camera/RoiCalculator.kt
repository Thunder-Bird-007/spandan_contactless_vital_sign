package com.spandan.app.camera

import android.graphics.Rect

/**
 * Derives a forehead/cheek ROI (region of interest) as a fixed fractional
 * sub-crop of a detected face bounding box -- the same *concept* as the
 * MATLAB side (a fixed fractional crop, not a learned/adaptive one), so the
 * two pipelines stay conceptually comparable.
 *
 * The exact fractions below are a PLACEHOLDER. They were picked by eye
 * (a forehead band, horizontally centered, avoiding eyebrows/hairline) and
 * have not been reconciled against the MATLAB implementation.
 *
 * TODO: confirm/replace these fractions against
 * matlab/src/roi/extractROISignals.m once that is finalized. Whoever does
 * that should just edit the four constants below -- nothing else in this
 * file (or its callers) needs to change.
 */
object RoiCalculator {

    private const val TOP_FRACTION = 0.08f
    private const val BOTTOM_FRACTION = 0.30f
    private const val LEFT_FRACTION = 0.25f
    private const val RIGHT_FRACTION = 0.75f

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
