package com.spandan.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View

/**
 * Minimal scrolling line chart of the raw buffered green-channel signal.
 * No external chart library -- this is intentionally a plain Canvas draw so
 * the skeleton doesn't carry a dependency whose only job is a single line
 * plot. Auto-scales Y to the current buffer's min/max each frame (so it's a
 * *shape* sanity check, not a calibrated amplitude reading).
 */
class SignalChartView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var values: List<Float> = emptyList()

    private val backgroundPaint = Paint().apply { color = Color.parseColor("#141414") }
    private val linePaint = Paint().apply {
        color = Color.parseColor("#00C853")
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
    }
    private val path = Path()

    fun updateValues(newValues: List<Float>) {
        values = newValues
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), backgroundPaint)

        val points = values
        if (points.size < 2 || width == 0 || height == 0) return

        val minV = points.min()
        val maxV = points.max()
        val range = (maxV - minV).let { if (it < 1e-3f) 1f else it }

        path.reset()
        val stepX = width.toFloat() / (points.size - 1)
        for (i in points.indices) {
            val x = i * stepX
            val normalized = (points[i] - minV) / range
            val y = height - normalized * height
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        canvas.drawPath(path, linePaint)
    }
}
