package com.spandan.app.signal

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.sqrt

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/ensembleAverageBeats.m` (read directly from source
 * before writing this): segments a pulse signal into individual cardiac
 * cycles on the negative-going zero crossing (steepest downslope, better
 * temporal precision than a peak-based split), duration-gates them,
 * resamples each to a fixed sample count via [PchipInterpolator], time-warps
 * each so its systolic peak lands at a common cycle fraction (so beat-to-
 * beat peak jitter doesn't smear the notch across the average), keeps the
 * top-correlation fraction against a rough template, and coherently
 * averages (trimmed mean + median) -- the core deliverable this project's
 * whole Branch 2 exists for.
 *
 * @throws IllegalStateException on too few beats/survivors -- matching
 *   `ensembleAverageBeats.m`'s own hard `error(...)` calls exactly. This is
 *   a faithful, unsoftened port; [MorphologyWaveformEstimator] (the live
 *   caller) is responsible for catching this and failing soft (treating it
 *   as a signal-quality problem, not crashing), the same "ported function
 *   stays MATLAB-faithful, the live orchestrator adds the fail-soft layer"
 *   split [RealHeartRateEstimator] already uses around [BandpassFilter]/
 *   [HeartRateFft].
 */
object EnsembleAverageBeats {

    data class Options(
        val beatSamples: Int = 256,
        val systolicAnchorFraction: Double = 0.25,
        val durationRejectFraction: Double = 0.30,
        val qualityKeepFraction: Double = 0.25,
        val trimPercent: Double = 20.0
    )

    data class Prototype(val trimmedMean: DoubleArray, val median: DoubleArray)
    data class IqrBand(val q1: DoubleArray, val q3: DoubleArray, val width: DoubleArray, val meanWidth: Double, val meanWidthNormalized: Double)
    data class Stats(val beatsFound: Int, val beatsRejectedByDuration: Int, val beatsRejectedByQuality: Int, val beatsAveraged: Int, val snrGainEstimate: Double)
    data class Result(val prototype: Prototype, val iqrBand: IqrBand, val beatMatrix: Array<DoubleArray>, val stats: Stats)

    fun apply(sig: DoubleArray, fs: Double, opts: Options = Options()): Result {
        val n = sig.size
        val timeAxis = DoubleArray(n) { it / fs }

        // --- Step 1: negative-going zero crossings of the zero-mean signal.
        val mean = sig.average()
        val zeroMean = DoubleArray(n) { sig[it] - mean }

        val crossingTimes = mutableListOf<Double>()
        for (i in 0 until n - 1) {
            if (zeroMean[i] >= 0.0 && zeroMean[i + 1] < 0.0) {
                val frac = zeroMean[i] / (zeroMean[i] - zeroMean[i + 1])
                crossingTimes.add(timeAxis[i] + frac * (timeAxis[i + 1] - timeAxis[i]))
            }
        }

        val numBeatsFound = crossingTimes.size - 1
        check(numBeatsFound >= 3) {
            "Only ${maxOf(numBeatsFound, 0)} beat(s) found from negative-going zero crossings -- need at least 3 to form an ensemble average."
        }

        // --- Step 2: duration gate.
        val beatDurations = DoubleArray(numBeatsFound) { crossingTimes[it + 1] - crossingTimes[it] }
        val medianDuration = median(beatDurations)

        val survivingBeatIdx = beatDurations.indices.filter { i ->
            kotlin.math.abs(beatDurations[i] - medianDuration) / medianDuration <= opts.durationRejectFraction
        }
        val beatsRejectedByDuration = numBeatsFound - survivingBeatIdx.size
        check(survivingBeatIdx.size >= 2) {
            "Only ${survivingBeatIdx.size} beat(s) survived the duration gate -- need at least 2 to form an ensemble average."
        }

        // --- Step 3: resample each surviving beat to beatSamples via PCHIP.
        val beatSamples = opts.beatSamples
        val numSurviving = survivingBeatIdx.size
        val beatMatrixResampled = Array(numSurviving) { DoubleArray(beatSamples) }

        for (rowIdx in 0 until numSurviving) {
            val k = survivingBeatIdx[rowIdx]
            val t0 = crossingTimes[k]
            val t1 = crossingTimes[k + 1]
            val queryTimes = DoubleArray(beatSamples) { i -> t0 + (t1 - t0) * i / (beatSamples - 1) }
            beatMatrixResampled[rowIdx] = PchipInterpolator.interpolate(timeAxis, sig, queryTimes)
        }

        // --- Step 4: two-anchor time warp -- align the systolic peak to
        // systolicAnchorFraction of the cycle.
        val targetFrac = DoubleArray(beatSamples) { it.toDouble() / (beatSamples - 1) }
        val origFrac = targetFrac
        val peakAnchorFrac = opts.systolicAnchorFraction

        val beatMatrixWarped = Array(numSurviving) { DoubleArray(beatSamples) }
        for (rowIdx in 0 until numSurviving) {
            val beatValues = beatMatrixResampled[rowIdx]
            var peakIdx = 0
            var peakVal = beatValues[0]
            for (i in 1 until beatSamples) if (beatValues[i] > peakVal) { peakVal = beatValues[i]; peakIdx = i }
            val peakFracOrig = origFrac[peakIdx]

            if (peakFracOrig <= 0.0 || peakFracOrig >= 1.0) {
                // Degenerate: peak at the very first/last sample -- the
                // piecewise-linear warp below is undefined. Leave unwarped
                // rather than fabricate a mapping; the quality gate (Step 5)
                // is expected to down-weight it anyway.
                beatMatrixWarped[rowIdx] = beatValues.copyOf()
                continue
            }

            val newFrac = DoubleArray(beatSamples)
            for (i in 0 until beatSamples) {
                newFrac[i] = if (origFrac[i] <= peakFracOrig) {
                    origFrac[i] * (peakAnchorFrac / peakFracOrig)
                } else {
                    peakAnchorFrac + (origFrac[i] - peakFracOrig) * ((1.0 - peakAnchorFrac) / (1.0 - peakFracOrig))
                }
            }
            beatMatrixWarped[rowIdx] = PchipInterpolator.interpolate(newFrac, beatValues, targetFrac)
        }

        // --- Step 5: two-pass quality gate.
        val roughTemplate = DoubleArray(beatSamples) { col ->
            var s = 0.0
            for (rowIdx in 0 until numSurviving) s += beatMatrixWarped[rowIdx][col]
            s / numSurviving
        }

        val correlations = DoubleArray(numSurviving) { pearsonCorr(beatMatrixWarped[it], roughTemplate) }
        val sortOrder = (0 until numSurviving).sortedByDescending { correlations[it] }
        val numKeep = maxOf(1, ceil(numSurviving * opts.qualityKeepFraction).toInt())
        val keepIdx = sortOrder.take(numKeep)
        val beatsRejectedByQuality = numSurviving - numKeep

        val beatMatrix = Array(numKeep) { beatMatrixWarped[keepIdx[it]] }

        // --- Step 6: trimmed mean + median.
        val trimmedMean = DoubleArray(beatSamples) { col -> trimmedMeanOfColumn(beatMatrix, col, opts.trimPercent) }
        val medianRow = DoubleArray(beatSamples) { col -> median(DoubleArray(beatMatrix.size) { r -> beatMatrix[r][col] }) }

        // --- Step 7: per-sample IQR.
        val q1 = DoubleArray(beatSamples)
        val q3 = DoubleArray(beatSamples)
        for (col in 0 until beatSamples) {
            val columnData = DoubleArray(beatMatrix.size) { r -> beatMatrix[r][col] }.also { it.sort() }
            q1[col] = percentile(columnData, 25.0)
            q3[col] = percentile(columnData, 75.0)
        }
        val width = DoubleArray(beatSamples) { q3[it] - q1[it] }
        val meanWidth = width.average()
        val prototypeRange = (trimmedMean.max() - trimmedMean.min())
        val meanWidthNormalized = if (prototypeRange > 0.0) meanWidth / prototypeRange else Double.NaN

        val stats = Stats(
            beatsFound = numBeatsFound,
            beatsRejectedByDuration = beatsRejectedByDuration,
            beatsRejectedByQuality = beatsRejectedByQuality,
            beatsAveraged = beatMatrix.size,
            snrGainEstimate = sqrt(beatMatrix.size.toDouble())
        )

        return Result(
            prototype = Prototype(trimmedMean, medianRow),
            iqrBand = IqrBand(q1, q3, width, meanWidth, meanWidthNormalized),
            beatMatrix = beatMatrix,
            stats = stats
        )
    }

    private fun median(x: DoubleArray): Double {
        val sorted = x.copyOf().also { it.sort() }
        val n = sorted.size
        return if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    /** Linear-interpolation-between-order-statistics percentile, matching
     *  `ensembleAverageBeats.m`'s own manual `localPercentile` (MATLAB
     *  `prctile`'s default convention). [sortedAscending] must already be sorted. */
    private fun percentile(sortedAscending: DoubleArray, p: Double): Double {
        val n = sortedAscending.size
        if (n == 1) return sortedAscending[0]
        val position = (p / 100.0) * (n - 1)
        val lower = floor(position).toInt()
        val upper = ceil(position).toInt()
        val weight = position - lower
        return sortedAscending[lower] * (1.0 - weight) + sortedAscending[upper] * weight
    }

    /** Column-wise trimmed mean, matching MATLAB's `trimmean(X, percent, 1)`:
     *  removes `percent`% of values total (half from each tail) before averaging. */
    private fun trimmedMeanOfColumn(matrix: Array<DoubleArray>, col: Int, trimPercent: Double): Double {
        val values = DoubleArray(matrix.size) { matrix[it][col] }.also { it.sort() }
        val n = values.size
        val trimEachSide = Math.round(n * (trimPercent / 100.0) / 2.0).toInt()
        if (2 * trimEachSide >= n) return values.average() // degenerate: trimming everything -- fall back to plain mean
        var sum = 0.0
        var count = 0
        for (i in trimEachSide until n - trimEachSide) { sum += values[i]; count++ }
        return sum / count
    }

    /** Manual Pearson correlation, matching `ensembleAverageBeats.m`'s own
     *  manual `pearsonCorrRow` (no Statistics Toolbox dependency there either). */
    private fun pearsonCorr(x: DoubleArray, y: DoubleArray): Double {
        val mx = x.average()
        val my = y.average()
        var num = 0.0
        var sxx = 0.0
        var syy = 0.0
        for (i in x.indices) {
            val dx = x[i] - mx
            val dy = y[i] - my
            num += dx * dy
            sxx += dx * dx
            syy += dy * dy
        }
        return num / sqrt(sxx * syy)
    }
}
