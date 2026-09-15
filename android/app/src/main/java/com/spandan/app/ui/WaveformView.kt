package com.spandan.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View

/**
 * Segment 19 (Branch 2 morphology port) -- draws ONE ensemble-averaged
 * cardiac cycle ([signal.MorphologyWaveformEstimator.Estimate.waveform],
 * `prototype.trimmedMean` in the MATLAB source's own naming), fixed X
 * domain [0, size-1] (a single beat, not a scrolling multi-second trace --
 * deliberately a different X semantic from [SignalChartView], which scrolls
 * the raw multi-second buffer). Same "no external chart library" choice as
 * [SignalChartView], for the same reason (a single line/fill plot doesn't
 * justify a dependency).
 *
 * Optionally marks the detected notch position (a vertical tick + dot) when
 * [notchDetected] is true, at [notchPositionNormalized] (0-1 fraction of the
 * cycle) -- purely a visual aid; the numeric confidence itself is surfaced
 * in the status pill text next to this view (per this task's own
 * instruction to surface the confidence VALUE, not just a yes/no), not
 * encoded into this view alone.
 */
class WaveformView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var waveform: FloatArray = FloatArray(0)
    private var notchDetected = false
    private var notchPositionNormalized = Double.NaN

    private val backgroundPaint = Paint().apply { color = Color.parseColor("#141414") }
    private val linePaint = Paint().apply {
        color = Color.parseColor("#7C4DFF") // distinct from SignalChartView's green -- a different signal, not to be confused at a glance
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
    }
    private val notchLinePaint = Paint().apply {
        color = Color.parseColor("#FFEB3B") // matches OverlayView's ROI-box yellow -- "a point of interest," same visual vocabulary
        style = Paint.Style.STROKE
        strokeWidth = 3f
        isAntiAlias = true
    }
    private val notchDotPaint = Paint().apply {
        color = Color.parseColor("#FFEB3B")
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val path = Path()

    fun update(waveform: DoubleArray?, notchDetected: Boolean, notchPositionNormalized: Double) {
        this.waveform = waveform?.let { FloatArray(it.size) { i -> it[i].toFloat() } } ?: FloatArray(0)
        this.notchDetected = notchDetected
        this.notchPositionNormalized = notchPositionNormalized
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), backgroundPaint)

        val points = waveform
        if (points.size < 2 || width == 0 || height == 0) return

        val minV = points.min()
        val maxV = points.max()
        val range = (maxV - minV).let { if (it < 1e-6f) 1f else it }

        path.reset()
        val stepX = width.toFloat() / (points.size - 1)
        for (i in points.indices) {
            val x = i * stepX
            val normalized = (points[i] - minV) / range
            val y = height - normalized * height
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        canvas.drawPath(path, linePaint)

        if (notchDetected && !notchPositionNormalized.isNaN()) {
            val notchX = (notchPositionNormalized * width).toFloat()
            canvas.drawLine(notchX, 0f, notchX, height.toFloat(), notchLinePaint)
            canvas.drawCircle(notchX, height * 0.5f, 5f, notchDotPaint)
        }
    }
}
