import Foundation

/// Segments a pulse signal into individual cardiac cycles on the negative-
/// going zero crossing (steepest downslope, better temporal precision than
/// a peak-based split), duration-gates them, resamples each to a fixed
/// sample count via `PchipInterpolator`, time-warps each so its systolic
/// peak lands at a common cycle fraction (so beat-to-beat peak jitter
/// doesn't smear the notch across the average), keeps the top-correlation
/// fraction against a rough template, and coherently averages (trimmed mean
/// + median) -- the core deliverable Branch 2 exists for. Direct port of
/// android/app/.../signal/EnsembleAverageBeats.kt (read directly before
/// writing this), itself a port of
/// `matlab/src/morphology/ensembleAverageBeats.m`.
///
/// Returns nil on too few beats/survivors (the Android port throws
/// `IllegalStateException` here, matching the MATLAB source's own hard
/// `error(...)` calls exactly; this Swift port uses the Optional
/// convention instead -- `MorphologyWaveformEstimator`, the live caller, is
/// responsible for treating nil as a signal-quality problem, not a crash,
/// the same "ported function stays MATLAB-faithful, the live orchestrator
/// adds the fail-soft layer" split `RealHeartRateEstimator` already uses).
enum EnsembleAverageBeats {

    struct Options {
        var beatSamples = 256
        var systolicAnchorFraction = 0.25
        var durationRejectFraction = 0.30
        var qualityKeepFraction = 0.25
        var trimPercent = 20.0
    }

    struct Prototype {
        let trimmedMean: [Double]
        let median: [Double]
    }
    struct IqrBand {
        let q1: [Double]
        let q3: [Double]
        let width: [Double]
        let meanWidth: Double
        let meanWidthNormalized: Double
    }
    struct Stats {
        let beatsFound: Int
        let beatsRejectedByDuration: Int
        let beatsRejectedByQuality: Int
        let beatsAveraged: Int
        let snrGainEstimate: Double
    }
    struct Result {
        let prototype: Prototype
        let iqrBand: IqrBand
        let beatMatrix: [[Double]]
        let stats: Stats
    }

    static func apply(_ sig: [Double], fs: Double, opts: Options = Options()) -> Result? {
        let n = sig.count
        let timeAxis = (0..<n).map { Double($0) / fs }

        // --- Step 1: negative-going zero crossings of the zero-mean signal.
        let mean = sig.reduce(0.0, +) / Double(n)
        let zeroMean = sig.map { $0 - mean }

        var crossingTimes: [Double] = []
        for i in 0..<(n - 1) {
            if zeroMean[i] >= 0.0 && zeroMean[i + 1] < 0.0 {
                let frac = zeroMean[i] / (zeroMean[i] - zeroMean[i + 1])
                crossingTimes.append(timeAxis[i] + frac * (timeAxis[i + 1] - timeAxis[i]))
            }
        }

        let numBeatsFound = crossingTimes.count - 1
        guard numBeatsFound >= 3 else { return nil } // "need at least 3 to form an ensemble average"

        // --- Step 2: duration gate.
        let beatDurations = (0..<numBeatsFound).map { crossingTimes[$0 + 1] - crossingTimes[$0] }
        let medianDuration = median(beatDurations)

        let survivingBeatIdx = beatDurations.indices.filter { i in
            abs(beatDurations[i] - medianDuration) / medianDuration <= opts.durationRejectFraction
        }
        let beatsRejectedByDuration = numBeatsFound - survivingBeatIdx.count
        guard survivingBeatIdx.count >= 2 else { return nil } // "need at least 2 to form an ensemble average"

        // --- Step 3: resample each surviving beat to beatSamples via PCHIP.
        let beatSamples = opts.beatSamples
        let numSurviving = survivingBeatIdx.count
        var beatMatrixResampled = [[Double]](repeating: [Double](repeating: 0.0, count: beatSamples), count: numSurviving)

        for rowIdx in 0..<numSurviving {
            let k = survivingBeatIdx[rowIdx]
            let t0 = crossingTimes[k]
            let t1 = crossingTimes[k + 1]
            let queryTimes = (0..<beatSamples).map { i in t0 + (t1 - t0) * Double(i) / Double(beatSamples - 1) }
            beatMatrixResampled[rowIdx] = PchipInterpolator.interpolate(timeAxis, sig, queryTimes)
        }

        // --- Step 4: two-anchor time warp -- align the systolic peak to
        // systolicAnchorFraction of the cycle.
        let targetFrac = (0..<beatSamples).map { Double($0) / Double(beatSamples - 1) }
        let origFrac = targetFrac
        let peakAnchorFrac = opts.systolicAnchorFraction

        var beatMatrixWarped = [[Double]](repeating: [Double](repeating: 0.0, count: beatSamples), count: numSurviving)
        for rowIdx in 0..<numSurviving {
            let beatValues = beatMatrixResampled[rowIdx]
            var peakIdx = 0
            var peakVal = beatValues[0]
            for i in 1..<beatSamples where beatValues[i] > peakVal { peakVal = beatValues[i]; peakIdx = i }
            let peakFracOrig = origFrac[peakIdx]

            if peakFracOrig <= 0.0 || peakFracOrig >= 1.0 {
                // Degenerate: peak at the very first/last sample -- the
                // piecewise-linear warp below is undefined. Leave unwarped
                // rather than fabricate a mapping; the quality gate (Step 5)
                // is expected to down-weight it anyway.
                beatMatrixWarped[rowIdx] = beatValues
                continue
            }

            var newFrac = [Double](repeating: 0.0, count: beatSamples)
            for i in 0..<beatSamples {
                if origFrac[i] <= peakFracOrig {
                    newFrac[i] = origFrac[i] * (peakAnchorFrac / peakFracOrig)
                } else {
                    newFrac[i] = peakAnchorFrac + (origFrac[i] - peakFracOrig) * ((1.0 - peakAnchorFrac) / (1.0 - peakFracOrig))
                }
            }
            beatMatrixWarped[rowIdx] = PchipInterpolator.interpolate(newFrac, beatValues, targetFrac)
        }

        // --- Step 5: two-pass quality gate.
        var roughTemplate = [Double](repeating: 0.0, count: beatSamples)
        for col in 0..<beatSamples {
            var s = 0.0
            for rowIdx in 0..<numSurviving { s += beatMatrixWarped[rowIdx][col] }
            roughTemplate[col] = s / Double(numSurviving)
        }

        let correlations = (0..<numSurviving).map { pearsonCorr(beatMatrixWarped[$0], roughTemplate) }
        let sortOrder = (0..<numSurviving).sorted { correlations[$0] > correlations[$1] }
        let numKeep = max(1, Int((Double(numSurviving) * opts.qualityKeepFraction).rounded(.up)))
        let keepIdx = Array(sortOrder.prefix(numKeep))
        let beatsRejectedByQuality = numSurviving - numKeep

        let beatMatrix = keepIdx.map { beatMatrixWarped[$0] }

        // --- Step 6: trimmed mean + median.
        let trimmedMean = (0..<beatSamples).map { col in trimmedMeanOfColumn(beatMatrix, col: col, trimPercent: opts.trimPercent) }
        let medianRow = (0..<beatSamples).map { col in median(beatMatrix.map { $0[col] }) }

        // --- Step 7: per-sample IQR.
        var q1 = [Double](repeating: 0.0, count: beatSamples)
        var q3 = [Double](repeating: 0.0, count: beatSamples)
        for col in 0..<beatSamples {
            let columnData = beatMatrix.map { $0[col] }.sorted()
            q1[col] = percentile(columnData, 25.0)
            q3[col] = percentile(columnData, 75.0)
        }
        let width = (0..<beatSamples).map { q3[$0] - q1[$0] }
        let meanWidth = width.reduce(0.0, +) / Double(width.count)
        let prototypeRange = (trimmedMean.max() ?? 0.0) - (trimmedMean.min() ?? 0.0)
        let meanWidthNormalized = prototypeRange > 0.0 ? meanWidth / prototypeRange : Double.nan

        let stats = Stats(
            beatsFound: numBeatsFound,
            beatsRejectedByDuration: beatsRejectedByDuration,
            beatsRejectedByQuality: beatsRejectedByQuality,
            beatsAveraged: beatMatrix.count,
            snrGainEstimate: Double(beatMatrix.count).squareRoot()
        )

        return Result(
            prototype: Prototype(trimmedMean: trimmedMean, median: medianRow),
            iqrBand: IqrBand(q1: q1, q3: q3, width: width, meanWidth: meanWidth, meanWidthNormalized: meanWidthNormalized),
            beatMatrix: beatMatrix,
            stats: stats
        )
    }

    private static func median(_ x: [Double]) -> Double {
        let sorted = x.sorted()
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    /// Linear-interpolation-between-order-statistics percentile, matching
    /// the MATLAB source's own manual `localPercentile` (MATLAB `prctile`'s
    /// default convention). `sortedAscending` must already be sorted.
    private static func percentile(_ sortedAscending: [Double], _ p: Double) -> Double {
        let n = sortedAscending.count
        if n == 1 { return sortedAscending[0] }
        let position = (p / 100.0) * Double(n - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let weight = position - Double(lower)
        return sortedAscending[lower] * (1.0 - weight) + sortedAscending[upper] * weight
    }

    /// Column-wise trimmed mean, matching MATLAB's `trimmean(X, percent, 1)`:
    /// removes `percent`% of values total (half from each tail) before averaging.
    private static func trimmedMeanOfColumn(_ matrix: [[Double]], col: Int, trimPercent: Double) -> Double {
        let values = matrix.map { $0[col] }.sorted()
        let n = values.count
        let trimEachSide = Int((Double(n) * (trimPercent / 100.0) / 2.0).rounded())
        if 2 * trimEachSide >= n { return values.reduce(0.0, +) / Double(n) } // degenerate: trimming everything -- fall back to plain mean
        var sum = 0.0
        var count = 0
        for i in trimEachSide..<(n - trimEachSide) { sum += values[i]; count += 1 }
        return sum / Double(count)
    }

    /// Manual Pearson correlation, matching the MATLAB source's own manual
    /// `pearsonCorrRow` (no Statistics Toolbox dependency there either).
    private static func pearsonCorr(_ x: [Double], _ y: [Double]) -> Double {
        let mx = x.reduce(0.0, +) / Double(x.count)
        let my = y.reduce(0.0, +) / Double(y.count)
        var num = 0.0
        var sxx = 0.0
        var syy = 0.0
        for i in x.indices {
            let dx = x[i] - mx
            let dy = y[i] - my
            num += dx * dy
            sxx += dx * dx
            syy += dy * dy
        }
        return num / (sxx * syy).squareRoot()
    }
}
