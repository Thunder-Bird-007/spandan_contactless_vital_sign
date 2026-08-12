import Foundation

/// Real port of matlab/src/pulseextraction/chromCombine.m and posCombine.m, ported
/// from android/app/.../signal/PulseExtraction.kt (read directly, plus
/// segment4_heartrate/Segment4_LineByLine_Explanation.md for the reasoning, before
/// writing this).
///
/// The one judgment call carried over exactly: both functions normalize the
/// FILTERED R/G/B channels by the RAW (pre-detrend, pre-filter) channels' own
/// temporal means, not the filtered channels' own means. A bandpass filter's job is
/// to reject the 0Hz/DC component, so mean(filtered) is near-zero and numerically
/// unusable as a brightness-normalization denominator -- see Part 0 of the
/// explanation doc. `rRaw/gRaw/bRaw` here are RgbSample's raw per-frame averages,
/// straight out of the ROI pixel averager, before the estimators' detrend+bandpass
/// step.
enum PulseExtraction {

    /// CHROM (de Haan & Jeanne, 2013), matching chromCombine.m's formula exactly:
    /// Xs = 3*Rn - 2*Gn, Ys = 1.5*Rn + Gn - 1.5*Bn, alpha = std(Xs)/std(Ys),
    /// recomputed fresh per window (never hardcoded), pulse = Xs - alpha*Ys.
    static func chromCombine(
        rFiltered: [Double], gFiltered: [Double], bFiltered: [Double],
        rRaw: [Double], gRaw: [Double], bRaw: [Double]
    ) -> [Double] {
        let meanRRaw = rRaw.average()
        let meanGRaw = gRaw.average()
        let meanBRaw = bRaw.average()

        let n = rFiltered.count
        let xs = (0..<n).map { i in
            3.0 * (rFiltered[i] / meanRRaw) - 2.0 * (gFiltered[i] / meanGRaw)
        }
        let ys = (0..<n).map { i in
            1.5 * (rFiltered[i] / meanRRaw) + (gFiltered[i] / meanGRaw) - 1.5 * (bFiltered[i] / meanBRaw)
        }

        let alpha = sampleStdDev(xs) / sampleStdDev(ys)
        return (0..<n).map { i in xs[i] - alpha * ys[i] }
    }

    /// POS (Wang et al., 2017), matching posCombine.m's whole-signal formula exactly
    /// (this project's Segment 4 brief specifies the non-windowed formula over the
    /// published algorithm's sliding-window version, same as CHROM):
    /// S1 = Gn - Bn, S2 = Gn + Bn - 2*Rn, pulse = S1 + (std(S1)/std(S2))*S2.
    static func posCombine(
        rFiltered: [Double], gFiltered: [Double], bFiltered: [Double],
        rRaw: [Double], gRaw: [Double], bRaw: [Double]
    ) -> [Double] {
        let meanRRaw = rRaw.average()
        let meanGRaw = gRaw.average()
        let meanBRaw = bRaw.average()

        let n = rFiltered.count
        let rn = (0..<n).map { rFiltered[$0] / meanRRaw }
        let gn = (0..<n).map { gFiltered[$0] / meanGRaw }
        let bn = (0..<n).map { bFiltered[$0] / meanBRaw }

        let s1 = (0..<n).map { gn[$0] - bn[$0] }
        let s2 = (0..<n).map { gn[$0] + bn[$0] - 2.0 * rn[$0] }

        let scale = sampleStdDev(s1) / sampleStdDev(s2)
        return (0..<n).map { s1[$0] + scale * s2[$0] }
    }

    /// Sample standard deviation (N-1 denominator), matching MATLAB's std() default.
    static func sampleStdDev(_ x: [Double]) -> Double {
        guard x.count >= 2 else { return 0.0 }
        let mean = x.average()
        let sumSq = x.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sumSq / Double(x.count - 1)).squareRoot()
    }
}

extension Array where Element == Double {
    func average() -> Double {
        guard !isEmpty else { return 0.0 }
        return reduce(0.0, +) / Double(count)
    }
}
