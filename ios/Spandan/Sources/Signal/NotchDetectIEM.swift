import Foundation

/// Dicrotic-notch detection via the Iterative Envelope Mean (IEM) method
/// (Pal, Rudas, Kim, Chiang, Barney & Cannesson, Comput Biol Med 254:108283,
/// 2024, PMC11323035). Direct port of
/// android/app/.../signal/NotchDetectIEM.kt (read directly before writing
/// this), itself a port of `matlab/src/morphology/notchDetectIEM.m`.
/// Operates on `EnsembleAverageBeats`'s `prototype.trimmedMean` output (a
/// single beatSamples-length cycle), NOT a raw multi-beat signal.
///
/// CARRIED OVER FROM THE MATLAB SOURCE, STATED PLAINLY: `confidence` clips
/// at 1.0 -- a subject whose true ratio exceeds 1 reads identically to
/// every other subject past that ceiling, a resolution floor/ceiling
/// artifact, not a real tie. `confidenceRaw` (unclipped) is the value that
/// actually carries ranking information and must be surfaced in the UI too,
/// not just a pass/fail against the 0.3 bar.
///
/// BOUNDARY-HANDLING DEVIATION FROM MATLAB, STATED EXPLICITLY (same
/// discipline the Android port's own header uses): the Savitzky-Golay
/// smoothing step here refits a fresh local polynomial least-squares window
/// at every sample (including near the edges, using the nearest fully
/// in-bounds window) instead of matching `sgolayfilt`'s exact boundary
/// coefficients. This runs only on a small (beatSamples, typically 256)
/// prototype, so the extra per-sample refit cost is negligible.
enum NotchDetectIEM {

    struct Result {
        let detected: Bool
        let positionNormalized: Double
        let depth: Double
        let confidence: Double
        let confidenceRaw: Double
    }

    private static let betaStopThreshold = 0.1
    private static let maxIterations = 20
    private static let sgPolyOrder = 4
    private static let sgFrameLen = 25
    private static let minGapSec = 0.1

    /// Returns nil if `prototype` is constant (matches the MATLAB source's
    /// own `error('notchDetectIEM:flatSignal', ...)`, adapted to Swift's
    /// Optional convention).
    static func apply(_ prototype: [Double], fs: Double) -> Result? {
        let n = prototype.count
        let protoMax = prototype.max()!
        let protoMin = prototype.min()!
        let protoRange = protoMax - protoMin
        guard protoRange > 0.0 else { return nil } // "prototype is constant -- cannot normalize or detect a notch."
        let protoNorm = prototype.map { ($0 - protoMin) / protoRange }

        var frameLen = min(sgFrameLen, n)
        if frameLen % 2 == 0 { frameLen -= 1 }
        frameLen = max(frameLen, sgPolyOrder + 1 + (sgPolyOrder + 1) % 2)
        frameLen = min(frameLen, n - (1 - n % 2))

        var currentSignal = protoNorm
        var previousResidualVar = variance(currentSignal)
        var finalResidual = currentSignal

        for _ in 0..<maxIterations {
            let smoothed = savitzkyGolay(currentSignal, order: sgPolyOrder, windowLength: frameLen)
            let firstDeriv = gradient(smoothed)
            let secondDeriv = gradient(firstDeriv)

            var upperAnchors: Set<Int> = [0, n - 1]
            var lowerAnchors: Set<Int> = [0, n - 1]
            for i in 0..<(n - 1) {
                if secondDeriv[i] >= 0.0 && secondDeriv[i + 1] < 0.0 {
                    upperAnchors.insert(i)
                } else if secondDeriv[i] < 0.0 && secondDeriv[i + 1] >= 0.0 {
                    lowerAnchors.insert(i)
                }
            }

            let fullGrid = (0..<n).map { Double($0) }
            let upperAnchorsSorted = upperAnchors.sorted()
            let lowerAnchorsSorted = lowerAnchors.sorted()
            let upperEnvelope = PchipInterpolator.interpolate(
                upperAnchorsSorted.map { Double($0) },
                upperAnchorsSorted.map { currentSignal[$0] },
                fullGrid
            )
            let lowerEnvelope = PchipInterpolator.interpolate(
                lowerAnchorsSorted.map { Double($0) },
                lowerAnchorsSorted.map { currentSignal[$0] },
                fullGrid
            )

            let meanEnvelope = (0..<n).map { (upperEnvelope[$0] + lowerEnvelope[$0]) / 2.0 }
            let residual = (0..<n).map { currentSignal[$0] - meanEnvelope[$0] }
            let residualVar = variance(residual)
            finalResidual = residual

            if abs(previousResidualVar - residualVar) < betaStopThreshold { break }
            previousResidualVar = residualVar
            currentSignal = residual
        }

        var peakIdx = 0
        var peakVal = protoNorm[0]
        for i in 1..<n where protoNorm[i] > peakVal { peakVal = protoNorm[i]; peakIdx = i }

        let minGapSamples = max(Int((minGapSec * fs).rounded()), 1)
        let searchStart = peakIdx + minGapSamples
        let loStart = max(searchStart, 1)

        var notchDetected = false
        var notchIdx = -1
        var i0 = loStart
        while i0 <= n - 2 {
            let isLocalMin = finalResidual[i0 - 1] > finalResidual[i0] && finalResidual[i0] < finalResidual[i0 + 1]
            if isLocalMin && finalResidual[i0] < 0.0 {
                notchDetected = true
                notchIdx = i0
                break
            }
            i0 += 1
        }

        guard notchDetected else {
            return Result(detected: false, positionNormalized: Double.nan, depth: Double.nan, confidence: 0.0, confidenceRaw: 0.0)
        }

        let positionNormalized = Double(notchIdx) / Double(n - 1)
        var shoulderValue = protoNorm[peakIdx]
        for i in peakIdx...notchIdx where protoNorm[i] > shoulderValue { shoulderValue = protoNorm[i] }
        let depth = (shoulderValue - protoNorm[notchIdx]) / ((protoNorm.max() ?? 0.0) - (protoNorm.min() ?? 0.0))

        let residualStd = PulseExtraction.sampleStdDev(finalResidual)
        let confidenceRaw = abs(finalResidual[notchIdx]) / (residualStd + 2.2e-16)
        let confidence = min(1.0, confidenceRaw)

        return Result(detected: true, positionNormalized: positionNormalized, depth: depth, confidence: confidence, confidenceRaw: confidenceRaw)
    }

    /// Population variance (N denominator). MATLAB's plain `var(x)` call
    /// defaults to SAMPLE variance (N-1) -- a small, stated deviation
    /// (negligible at this prototype's typical N=256, and this value only
    /// feeds the iteration STOP threshold, not the notch
    /// location/depth/confidence math, none of which uses variance).
    private static func variance(_ x: [Double]) -> Double {
        let m = x.reduce(0.0, +) / Double(x.count)
        var s = 0.0
        for v in x { let d = v - m; s += d * d }
        return s / Double(x.count)
    }

    /// Numerical gradient, matching MATLAB's `gradient(x)` with unit
    /// spacing: central difference interior, one-sided at both ends.
    private static func gradient(_ x: [Double]) -> [Double] {
        let n = x.count
        var g = [Double](repeating: 0.0, count: n)
        if n == 1 { return g }
        g[0] = x[1] - x[0]
        g[n - 1] = x[n - 1] - x[n - 2]
        for i in 1..<(n - 1) { g[i] = (x[i + 1] - x[i - 1]) / 2.0 }
        return g
    }

    /// Savitzky-Golay smoothing (polynomial order `order`, window
    /// `windowLength`, odd): refits a fresh local least-squares polynomial
    /// window at every sample -- see this file's own "BOUNDARY-HANDLING
    /// DEVIATION" note for why this differs from MATLAB's exact
    /// `sgolayfilt` edge convention.
    private static func savitzkyGolay(_ x: [Double], order: Int, windowLength: Int) -> [Double] {
        let n = x.count
        let m = (windowLength - 1) / 2
        var out = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            let winStart = min(max(i - m, 0), max(0, n - windowLength))
            let actualLen = min(windowLength, n)
            let coeffs = polyfitLeastSquares(windowLen: actualLen, order: order) { k in x[winStart + k] }
            let tEval = Double(i - winStart)
            out[i] = evalPoly(coeffs, tEval)
        }
        return out
    }

    /// Least-squares fit of a degree-`order` polynomial (ascending-power
    /// coefficients) to `windowLen` points at integer positions
    /// `t = 0..windowLen-1`, values from `valueAt`. Small, local helper
    /// (order is always 4 here) -- not shared with `BandpassFilter`'s own
    /// private polyfit.
    private static func polyfitLeastSquares(windowLen: Int, order: Int, valueAt: (Int) -> Double) -> [Double] {
        let effectiveOrder = min(order, windowLen - 1)
        let mSize = effectiveOrder + 1
        var ata = [[Double]](repeating: [Double](repeating: 0.0, count: mSize), count: mSize)
        var aty = [Double](repeating: 0.0, count: mSize)
        for k in 0..<windowLen {
            let yVal = valueAt(k)
            var powers = [Double](repeating: 0.0, count: mSize)
            var p = 1.0
            for c in 0..<mSize { powers[c] = p; p *= Double(k) }
            for r in 0..<mSize {
                aty[r] += powers[r] * yVal
                for c in 0..<mSize { ata[r][c] += powers[r] * powers[c] }
            }
        }
        let solved = solveLinearSystem(ata, aty)
        if effectiveOrder == order { return solved }
        // Pad with zeros for unused higher-order terms (only possible on a
        // pathologically short window -- not expected for a 256-sample prototype).
        return (0..<(order + 1)).map { $0 < solved.count ? solved[$0] : 0.0 }
    }

    private static func solveLinearSystem(_ a: [[Double]], _ bVec: [Double]) -> [Double] {
        let n = bVec.count
        var mat = (0..<n).map { i -> [Double] in
            var row = a[i]
            row.append(bVec[i])
            return row
        }
        for col in 0..<n {
            var pivotRow = col
            for r in (col + 1)..<n where abs(mat[r][col]) > abs(mat[pivotRow][col]) { pivotRow = r }
            mat.swapAt(col, pivotRow)
            let pivotVal = mat[col][col]
            if abs(pivotVal) < 1e-12 { continue }
            for c in col...n { mat[col][c] /= pivotVal }
            for r in 0..<n where r != col {
                let factor = mat[r][col]
                for c in col...n { mat[r][c] -= factor * mat[col][c] }
            }
        }
        return (0..<n).map { mat[$0][n] }
    }

    private static func evalPoly(_ coeffsAscending: [Double], _ t: Double) -> Double {
        var result = 0.0
        var p = 1.0
        for c in coeffsAscending { result += c * p; p *= t }
        return result
    }
}
