package com.spandan.app.signal

import kotlin.math.sqrt

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/fixPolarity.m` (read directly from source before
 * writing this): corrects rPPG waveform sign using a skewness heuristic.
 * NEITHER `fixPolarityByGroundTruth.m` NOR `estimateLagPolarityByGroundTruth.m`
 * is ported here -- both are ground-truth-anchored and explicitly excluded
 * from this task's brief as "not usable live" (Android has no contact-PPG
 * reference to anchor against, ever). This heuristic function IS the one
 * MATLAB itself falls back to for exactly this no-ground-truth case (see
 * `pipeline/estimateVitalsAndMorphology.m`'s own `useGroundTruth` branch and
 * `scripts/run_spandan_interactive.m`'s Segment 17 note that Cases 2/3
 * already use this same skewness rule for no-ground-truth input) -- so
 * [MorphologyWaveformEstimator] always uses this path, never a conditional.
 *
 * CARRIED-OVER CAVEAT, stated in the MATLAB source's own header and
 * repeated here rather than silently dropped: measured on all 5 UBFC
 * DATASET_1 subjects, this heuristic agreed with the ground-truth-anchored
 * rule on only 3/5 (60%) -- and it did not fail randomly, it flipped ALL 5
 * subjects (a systematic all-flip bias, not scatter), a plausible
 * consequence of forehead camera-PPG having reversed asymmetry relative to
 * the fingertip-contact PPG this convention was originally derived from
 * (den Brinker et al., arXiv:2306.09879). This is a real, known limitation
 * of the ONLY polarity method Android can use live, not fixed by this port.
 */
object FixPolarity {

    data class Result(val oriented: DoubleArray, val wasFlipped: Boolean, val skewValue: Double)

    private const val MIN_DURATION_SEC = 10.0

    /** @throws IllegalArgumentException if [sig] covers less than 10s at
     *  [frameRate] -- matches `fixPolarity.m`'s own hard error exactly
     *  (skewness over a shorter window is not reliable enough to anchor
     *  polarity); [MorphologyWaveformEstimator] should already be gating on
     *  a comparable minimum window before calling this. */
    fun apply(sig: DoubleArray, frameRate: Double): Result {
        require(sig.size / frameRate >= MIN_DURATION_SEC) {
            "sig must cover at least ${MIN_DURATION_SEC}s of data (got ${sig.size / frameRate}s at ${frameRate}Hz)"
        }

        val n = sig.size
        val mean = sig.average()
        var sumSq = 0.0
        var sumCube = 0.0
        for (v in sig) {
            val c = v - mean
            sumSq += c * c
            sumCube += c * c * c
        }
        val populationStd = sqrt(sumSq / n)
        val thirdMoment = sumCube / n
        val skewValue = thirdMoment / (populationStd * populationStd * populationStd)

        val wasFlipped = skewValue < 0.0
        val oriented = if (wasFlipped) DoubleArray(n) { -sig[it] } else sig.copyOf()
        return Result(oriented, wasFlipped, skewValue)
    }
}
