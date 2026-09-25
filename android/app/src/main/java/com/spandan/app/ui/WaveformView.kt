package com.spandan.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import com.spandan.app.R

/**
 * Segment 19 (Branch 2 morphology port) -- draws Branch 2's own filtered
 * pulse trace. Same "no external chart library" choice this project has
 * made elsewhere (a single line/fill plot doesn't justify a dependency).
 *
 * [Segment 31] Originally drew ONE ensemble-averaged cardiac cycle
 * ([signal.MorphologyWaveformEstimator.Estimate.waveform], fixed X domain
 * `[0, size-1]`) with the detected notch position marked. User feedback:
 * that read as a single static template, not "a live signal" -- wanted
 * something closer to an actual clinical PPG monitor's continuously
 * refreshing multi-cycle trace. This view now draws
 * [signal.MorphologyWaveformEstimator.Estimate.continuousWaveform] instead
 * -- the SAME selected candidate's continuous, polarity-corrected pulse
 * (real Branch 2 output, tail-windowed to the last several seconds, see
 * that field's own KDoc for why), which naturally spans several real
 * cardiac cycles. The single-beat `waveform` field and its notch position
 * still exist and are still computed (unit-tested, unchanged) -- the notch
 * DETECTION result is still surfaced via the status pill's own
 * method/confidence text next to this view; this view just no longer draws
 * a per-beat notch marker, since a single marker position doesn't map
 * cleanly onto a multi-cycle trace (which beat would it belong to?).
 *
 * Rendering: a gradient area-fill under the line (built lazily in
 * [onSizeChanged], since a [LinearGradient] shader needs real pixel
 * dimensions), and the line itself is a smoothed curve (quadratic Bezier
 * through each segment's own midpoint) instead of straight `lineTo`
 * segments. Colors are read from `colors.xml` (`accent_branch2`/
 * `accent_branch2_fill_top`/`accent_branch2_fill_bottom`) instead of
 * hard-coded hex, so the hero card's own border tint
 * ([R.drawable.bg_hero_card]) and this line share one source of truth.
 */
class WaveformView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var waveform: FloatArray = FloatArray(0)

    private val backgroundPaint = Paint().apply { color = ContextCompat.getColor(context, R.color.surface_card) }
    private val linePaint = Paint().apply {
        color = ContextCompat.getColor(context, R.color.accent_branch2)
        style = Paint.Style.STROKE
        strokeWidth = 4f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        isAntiAlias = true
    }
    private val fillPaint = Paint().apply {
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val gridPaint = Paint().apply {
        color = ContextCompat.getColor(context, R.color.surface_card_border)
        strokeWidth = 1.5f
        isAntiAlias = true
    }
    private val linePath = Path()
    private val fillPath = Path()

    private val fillTopColor = ContextCompat.getColor(context, R.color.accent_branch2_fill_top)
    private val fillBottomColor = ContextCompat.getColor(context, R.color.accent_branch2_fill_bottom)

    /** [continuousWaveform] is [signal.MorphologyWaveformEstimator.Estimate.continuousWaveform]
     *  -- see this class's own KDoc for why that field, not the older
     *  single-beat `waveform`, is what this view now draws. */
    fun update(continuousWaveform: DoubleArray?) {
        this.waveform = continuousWaveform?.let { FloatArray(it.size) { i -> it[i].toFloat() } } ?: FloatArray(0)
        postInvalidateOnAnimation()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0 && h > 0) {
            fillPaint.shader = LinearGradient(
                0f, 0f, 0f, h.toFloat(),
                fillTopColor, fillBottomColor,
                Shader.TileMode.CLAMP
            )
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), 12f, 12f, backgroundPaint)

        val points = waveform
        if (points.size < 2 || width == 0 || height == 0) return

        // Faint horizontal midline -- a reference for "is this part of the
        // trace above or below the mean."
        canvas.drawLine(0f, height / 2f, width.toFloat(), height / 2f, gridPaint)

        val minV = points.min()
        val maxV = points.max()
        val range = (maxV - minV).let { if (it < 1e-6f) 1f else it }
        val stepX = width.toFloat() / (points.size - 1)

        fun xOf(i: Int) = i * stepX
        fun yOf(i: Int) = height - ((points[i] - minV) / range) * height

        // Smoothed curve: a quadratic Bezier through each segment's own
        // midpoint (a standard cheap smoothing trick -- NOT a signal-
        // processing change, this NEVER touches the underlying `waveform`
        // data, only how the same points are connected visually).
        linePath.reset()
        linePath.moveTo(xOf(0), yOf(0))
        for (i in 1 until points.size) {
            val midX = (xOf(i - 1) + xOf(i)) / 2f
            val midY = (yOf(i - 1) + yOf(i)) / 2f
            linePath.quadTo(xOf(i - 1), yOf(i - 1), midX, midY)
        }
        linePath.lineTo(xOf(points.size - 1), yOf(points.size - 1))

        fillPath.reset()
        fillPath.addPath(linePath)
        fillPath.lineTo(xOf(points.size - 1), height.toFloat())
        fillPath.lineTo(xOf(0), height.toFloat())
        fillPath.close()

        canvas.drawPath(fillPath, fillPaint)
        canvas.drawPath(linePath, linePaint)
    }
}
