package com.spandan.app.signal

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/notchDetectIEM.m` (read directly from source
 * before writing this): dicrotic-notch detection via the Iterative
 * Envelope Mean (IEM) method (Pal, Rudas, Kim, Chiang, Barney & Cannesson,
 * Comput Biol Med 254:108283, 2024, PMC11323035). Operates on
 * [EnsembleAverageBeats]'s `prototype.trimmedMean` output (a single
 * beatSamples-length cycle), NOT a raw multi-beat signal.
 *
 * CARRIED OVER FROM THE MATLAB SOURCE, STATED PLAINLY (its own header):
 * `confidence` clips at 1.0 -- a subject whose true ratio exceeds 1 reads
 * identically to every other subject past that ceiling, a resolution
 * floor/ceiling artifact, not a real tie. This is exactly why this task's
 * brief says to surface [Result.confidenceRaw] (unclipped) in the UI, not
 * just a pass/fail against the 0.3 bar -- [confidence]'s own boolean
 * [detected] output is a near-useless gate at pool scale (the MATLAB side's
 * own Segment 10 Task 1 found 100/100 subjects "detected" -- the 0.3
 * confidence bar is what actually carries information).
 *
 * BOUNDARY-HANDLING DEVIATION FROM MATLAB, STATED EXPLICITLY (same
 * discipline [WaveletDenoise.kt]'s header already uses for its own
 * boundary difference): the Savitzky-Golay smoothing step here refits a
 * fresh local polynomial least-squares window at every sample (including
 * near the edges, using the nearest fully in-bounds window rather than
 * MATLAB's own specific edge convention) instead of matching `sgolayfilt`'s
 * exact boundary coefficients. This runs only on a small (beatSamples,
 * typically 256) prototype, so the extra per-sample refit cost is
 * negligible; exact bit-for-bit match to MATLAB was not required, only a
 * real Savitzky-Golay smooth, verified against a synthetic notch waveform
 * in [NotchDetectIEMTest] before trusting it on real prototypes.
 */
object NotchDetectIEM {

    data class Result(
        val detected: Boolean,
        val positionNormalized: Double,
        val depth: Double,
        val confidence: Double,
        val confidenceRaw: Double
    )

    private const val BETA_STOP_THRESHOLD = 0.1
    private const val MAX_ITERATIONS = 20
    private const val SG_POLY_ORDER = 4
    private const val SG_FRAME_LEN = 25
    private const val MIN_GAP_SEC = 0.1

    /** @throws IllegalArgumentException if [prototype] is constant (matches
     *  `notchDetectIEM.m`'s own `error('notchDetectIEM:flatSignal', ...)`). */
    fun apply(prototype: DoubleArray, fs: Double): Result {
        val n = prototype.size
        val protoMax = prototype.max()
        val protoMin = prototype.min()
        val protoRange = protoMax - protoMin
        require(protoRange > 0.0) { "prototype is constant -- cannot normalize or detect a notch." }
        val protoNorm = DoubleArray(n) { (prototype[it] - protoMin) / protoRange }

        var frameLen = min(SG_FRAME_LEN, n)
        if (frameLen % 2 == 0) frameLen -= 1
        frameLen = max(frameLen, SG_POLY_ORDER + 1 + (SG_POLY_ORDER + 1) % 2)
        frameLen = min(frameLen, n - (1 - n % 2))

        var currentSignal = protoNorm.copyOf()
        var previousResidualVar = variance(currentSignal)
        var finalResidual = currentSignal.copyOf()

        for (iter in 0 until MAX_ITERATIONS) {
            val smoothed = savitzkyGolay(currentSignal, SG_POLY_ORDER, frameLen)
            val firstDeriv = gradient(smoothed)
            val secondDeriv = gradient(firstDeriv)

            val upperAnchors = sortedSetOf(0, n - 1)
            val lowerAnchors = sortedSetOf(0, n - 1)
            for (i in 0 until n - 1) {
                if (secondDeriv[i] >= 0.0 && secondDeriv[i + 1] < 0.0) {
                    upperAnchors.add(i)
                } else if (secondDeriv[i] < 0.0 && secondDeriv[i + 1] >= 0.0) {
                    lowerAnchors.add(i)
                }
            }

            val fullGrid = DoubleArray(n) { it.toDouble() }
            val upperEnvelope = PchipInterpolator.interpolate(
                upperAnchors.map { it.toDouble() }.toDoubleArray(),
                upperAnchors.map { currentSignal[it] }.toDoubleArray(),
                fullGrid
            )
            val lowerEnvelope = PchipInterpolator.interpolate(
                lowerAnchors.map { it.toDouble() }.toDoubleArray(),
                lowerAnchors.map { currentSignal[it] }.toDoubleArray(),
                fullGrid
            )

            val meanEnvelope = DoubleArray(n) { (upperEnvelope[it] + lowerEnvelope[it]) / 2.0 }
            val residual = DoubleArray(n) { currentSignal[it] - meanEnvelope[it] }
            val residualVar = variance(residual)
            finalResidual = residual

            if (abs(previousResidualVar - residualVar) < BETA_STOP_THRESHOLD) break
            previousResidualVar = residualVar
            currentSignal = residual
        }

        var peakIdx = 0
        var peakVal = protoNorm[0]
        for (i in 1 until n) if (protoNorm[i] > peakVal) { peakVal = protoNorm[i]; peakIdx = i }

        val minGapSamples = max(Math.round(MIN_GAP_SEC * fs).toInt(), 1)
        val searchStart = peakIdx + minGapSamples
        val loStart = max(searchStart, 1)

        var notchDetected = false
        var notchIdx = -1
        var i0 = loStart
        while (i0 <= n - 2) {
            val isLocalMin = finalResidual[i0 - 1] > finalResidual[i0] && finalResidual[i0] < finalResidual[i0 + 1]
            if (isLocalMin && finalResidual[i0] < 0.0) {
                notchDetected = true
                notchIdx = i0
                break
            }
            i0++
        }

        if (!notchDetected) return Result(detected = false, positionNormalized = Double.NaN, depth = Double.NaN, confidence = 0.0, confidenceRaw = 0.0)

        val positionNormalized = notchIdx / (n - 1.0)
        var shoulderValue = protoNorm[peakIdx]
        for (i in peakIdx..notchIdx) if (protoNorm[i] > shoulderValue) shoulderValue = protoNorm[i]
        val depth = (shoulderValue - protoNorm[notchIdx]) / (protoNorm.max() - protoNorm.min())

        val residualStd = PulseExtraction.sampleStdDev(finalResidual)
        val confidenceRaw = abs(finalResidual[notchIdx]) / (residualStd + 2.2e-16)
        val confidence = min(1.0, confidenceRaw)

        return Result(detected = true, positionNormalized = positionNormalized, depth = depth, confidence = confidence, confidenceRaw = confidenceRaw)
    }

    /** Population variance (N denominator). MATLAB's plain `var(x)` call in
     *  `notchDetectIEM.m` defaults to SAMPLE variance (N-1) -- a small,
     *  stated deviation (negligible at this prototype's typical N=256, and
     *  this value only feeds the iteration STOP threshold, not the notch
     *  location/depth/confidence math below, none of which uses variance). */
    private fun variance(x: DoubleArray): Double {
        val m = x.average()
        var s = 0.0
        for (v in x) { val d = v - m; s += d * d }
        return s / x.size
    }

    /** Numerical gradient, matching MATLAB's `gradient(x)` with unit
     *  spacing: central difference interior, one-sided at both ends. */
    private fun gradient(x: DoubleArray): DoubleArray {
        val n = x.size
        val g = DoubleArray(n)
        if (n == 1) return g
        g[0] = x[1] - x[0]
        g[n - 1] = x[n - 1] - x[n - 2]
        for (i in 1 until n - 1) g[i] = (x[i + 1] - x[i - 1]) / 2.0
        return g
    }

    /** Savitzky-Golay smoothing (polynomial order [order], window
     *  [windowLength], odd): refits a fresh local least-squares polynomial
     *  window at every sample -- see this file's class KDoc "BOUNDARY-
     *  HANDLING DEVIATION" note for why this differs from MATLAB's exact
     *  `sgolayfilt` edge convention. */
    private fun savitzkyGolay(x: DoubleArray, order: Int, windowLength: Int): DoubleArray {
        val n = x.size
        val m = (windowLength - 1) / 2
        val out = DoubleArray(n)
        for (i in 0 until n) {
            val winStart = (i - m).coerceIn(0, max(0, n - windowLength))
            val actualLen = min(windowLength, n)
            val coeffs = polyfitLeastSquares(actualLen, order) { k -> x[winStart + k] }
            val tEval = (i - winStart).toDouble()
            out[i] = evalPoly(coeffs, tEval)
        }
        return out
    }

    /** Least-squares fit of a degree-[order] polynomial (ascending-power
     *  coefficients) to `windowLen` points at integer positions
     *  `t = 0..windowLen-1`, values from [valueAt]. Small, local helper
     *  (order is always 4 here) -- not shared with [BandpassFilter]'s own
     *  private polyfit, which is not accessible from this file. */
    private fun polyfitLeastSquares(windowLen: Int, order: Int, valueAt: (Int) -> Double): DoubleArray {
        val effectiveOrder = min(order, windowLen - 1)
        val mSize = effectiveOrder + 1
        val ata = Array(mSize) { DoubleArray(mSize) }
        val aty = DoubleArray(mSize)
        for (k in 0 until windowLen) {
            val yVal = valueAt(k)
            val powers = DoubleArray(mSize)
            var p = 1.0
            for (c in 0 until mSize) { powers[c] = p; p *= k.toDouble() }
            for (r in 0 until mSize) {
                aty[r] += powers[r] * yVal
                for (c in 0 until mSize) ata[r][c] += powers[r] * powers[c]
            }
        }
        val solved = solveLinearSystem(ata, aty)
        if (effectiveOrder == order) return solved
        // Pad with zeros for unused higher-order terms (only possible on a
        // pathologically short window -- not expected for a 256-sample prototype).
        return DoubleArray(order + 1) { if (it < solved.size) solved[it] else 0.0 }
    }

    private fun solveLinearSystem(a: Array<DoubleArray>, bVec: DoubleArray): DoubleArray {
        val n = bVec.size
        val mat = Array(n) { i -> DoubleArray(n + 1) { j -> if (j < n) a[i][j] else bVec[i] } }
        for (col in 0 until n) {
            var pivotRow = col
            for (r in col + 1 until n) if (abs(mat[r][col]) > abs(mat[pivotRow][col])) pivotRow = r
            val tmp = mat[col]; mat[col] = mat[pivotRow]; mat[pivotRow] = tmp
            val pivotVal = mat[col][col]
            if (abs(pivotVal) < 1e-12) continue
            for (c in col until n + 1) mat[col][c] /= pivotVal
            for (r in 0 until n) {
                if (r == col) continue
                val factor = mat[r][col]
                for (c in col until n + 1) mat[r][c] -= factor * mat[col][c]
            }
        }
        return DoubleArray(n) { i -> mat[i][n] }
    }

    private fun evalPoly(coeffsAscending: DoubleArray, t: Double): Double {
        var result = 0.0
        var p = 1.0
        for (c in coeffsAscending) { result += c * p; p *= t }
        return result
    }
}
