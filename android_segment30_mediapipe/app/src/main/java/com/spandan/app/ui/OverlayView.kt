package com.spandan.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

/**
 * Draws the live face-detection box and the smaller ROI sub-box on top of
 * the camera preview. Coordinates are expected to already be in this view's
 * own pixel space (see CoordinateMapper.rotatedRectToViewRect) -- this class
 * only draws, it doesn't do any coordinate math itself.
 */
class OverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var faceRect: RectF? = null
    private var roiRect: RectF? = null

    private val facePaint = Paint().apply {
        color = Color.parseColor("#4CAF50") // green
        style = Paint.Style.STROKE
        strokeWidth = 6f
        isAntiAlias = true
    }

    private val roiPaint = Paint().apply {
        color = Color.parseColor("#FFEB3B") // yellow
        style = Paint.Style.STROKE
        strokeWidth = 5f
        isAntiAlias = true
    }

    /** Pass null for both to clear the overlay (e.g. when no face is found). */
    fun update(face: RectF?, roi: RectF?) {
        faceRect = face
        roiRect = roi
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        faceRect?.let { canvas.drawRect(it, facePaint) }
        roiRect?.let { canvas.drawRect(it, roiPaint) }
    }
}
