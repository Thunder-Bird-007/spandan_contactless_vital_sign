package com.spandan.app.signal

import kotlin.math.sqrt

/**
 * Real port of matlab/src/pulseextraction/chromCombine.m and posCombine.m (read
 * directly from source, plus segment4_heartrate/Segment4_LineByLine_Explanation.md
 * for the reasoning, before writing this).
 *
 * The one judgment call carried over exactly: both functions normalize the
 * FILTERED R/G/B channels by the RAW (pre-detrend, pre-filter) channels' own
 * temporal means, not the filtered channels' own means. A bandpass filter's job is
 * to reject the 0Hz/DC component, so mean(filtered) is near-zero and numerically
 * unusable as a brightness-normalization denominator -- see Part 0 of the
 * explanation doc. `rRaw/gRaw/bRaw` here are RgbSample's raw per-frame averages,
 * straight out of the ROI pixel averager, before RealHeartRateEstimator's
 * detrend+bandpass step.
 */
object PulseExtraction {

    /** CHROM (de Haan & Jeanne, 2013), matching chromCombine.m's formula exactly:
     *  Xs = 3*Rn - 2*Gn, Ys = 1.5*Rn + Gn - 1.5*Bn, alpha = std(Xs)/std(Ys)
     *  recomputed fresh per window (never hardcoded), pulse = Xs - alpha*Ys. */
    fun chromCombine(
        rFiltered: DoubleArray,
        gFiltered: DoubleArray,
        bFiltered: DoubleArray,
        rRaw: DoubleArray,
        gRaw: DoubleArray,
        bRaw: DoubleArray
    ): DoubleArray {
        val meanRRaw = rRaw.average()
        val meanGRaw = gRaw.average()
        val meanBRaw = bRaw.average()

        val n = rFiltered.size
        val xs = DoubleArray(n) { i ->
            3.0 * (rFiltered[i] / meanRRaw) - 2.0 * (gFiltered[i] / meanGRaw)
        }
        val ys = DoubleArray(n) { i ->
            1.5 * (rFiltered[i] / meanRRaw) + (gFiltered[i] / meanGRaw) - 1.5 * (bFiltered[i] / meanBRaw)
        }

        val alpha = sampleStdDev(xs) / sampleStdDev(ys)
        return DoubleArray(n) { i -> xs[i] - alpha * ys[i] }
    }

    /** POS (Wang et al., 2017), matching posCombine.m's whole-signal formula exactly
     *  (this project's Segment 4 brief specifies the non-windowed formula over the
     *  published algorithm's sliding-window version, same as CHROM -- see the
     *  explanation doc; `frameRate` is therefore not needed here, matching the
     *  MATLAB source's own note that it's unused by the current formula):
     *  S1 = Gn - Bn, S2 = Gn + Bn - 2*Rn, pulse = S1 + (std(S1)/std(S2))*S2. */
    fun posCombine(
        rFiltered: DoubleArray,
        gFiltered: DoubleArray,
        bFiltered: DoubleArray,
        rRaw: DoubleArray,
        gRaw: DoubleArray,
        bRaw: DoubleArray
    ): DoubleArray {
        val meanRRaw = rRaw.average()
        val meanGRaw = gRaw.average()
        val meanBRaw = bRaw.average()

        val n = rFiltered.size
        val rn = DoubleArray(n) { i -> rFiltered[i] / meanRRaw }
        val gn = DoubleArray(n) { i -> gFiltered[i] / meanGRaw }
        val bn = DoubleArray(n) { i -> bFiltered[i] / meanBRaw }

        val s1 = DoubleArray(n) { i -> gn[i] - bn[i] }
        val s2 = DoubleArray(n) { i -> gn[i] + bn[i] - 2.0 * rn[i] }

        val scale = sampleStdDev(s1) / sampleStdDev(s2)
        return DoubleArray(n) { i -> s1[i] + scale * s2[i] }
    }

    /** Sample standard deviation (N-1 denominator), matching MATLAB's std() default. */
    fun sampleStdDev(x: DoubleArray): Double {
        if (x.size < 2) return 0.0
        val mean = x.average()
        val sumSq = x.sumOf { (it - mean) * (it - mean) }
        return sqrt(sumSq / (x.size - 1))
    }
}
