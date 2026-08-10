package com.spandan.app.signal

/** One spatially-averaged RGB reading from the ROI, at a point in time. */
data class RgbSample(
    val timestampMs: Long,
    val red: Float,
    val green: Float,
    val blue: Float
)
