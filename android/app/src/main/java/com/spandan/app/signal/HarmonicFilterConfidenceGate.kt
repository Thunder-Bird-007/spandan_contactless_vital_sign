package com.spandan.app.signal

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/harmonicFilterConfidenceGate.m` (read directly
 * from source before writing this): keep [AdaptiveHarmonicFilter]'s ABPF
 * comb output wherever its OWN notch confidence already clears this
 * project's 0.3 bar; substitute [HarmonicSelectiveGaussianFilter] (alpha
 * 0.15) only where ABPF already fails. This is the MATLAB side's PRODUCTION
 * DEFAULT for Branch 2 (`opts.useConfidenceGate=true` in
 * `pipeline/estimateVitalsAndMorphology.m`, promoted Segment 14) -- the
 * design principle it encodes (never override an already-successful
 * primary result) is why [MorphologyWaveformEstimator] uses this SAME safe
 * single-fallback mode.
 *
 * NOT PORTED, DELIBERATELY: the MATLAB source's mode (b), "pick whichever of
 * several fallback candidates self-reports the highest confidence." Its own
 * header documents that mode as VERIFIED AND ACTIVELY DISCOURAGED -- tested
 * on the MATLAB side and found to produce the WORST median waveform
 * correlation of every method compared (a selection-bias artifact from
 * repeatedly picking whichever noisy candidate happens to score highest,
 * not a real gain). [select] below only ever accepts a [fallbacks] list and
 * picks the best of it BY DESIGN when the primary fails, which reproduces
 * that same discouraged mode if a caller ever passes more than one
 * candidate -- so far, no caller does ([MorphologyWaveformEstimator] always
 * passes exactly one). Flagged here rather than silently dropped: if a
 * future caller is tempted to pass several Gaussian alphas as fallbacks to
 * raise the apparent pass rate, re-read the MATLAB source's own warning
 * first.
 */
object HarmonicFilterConfidenceGate {

    data class Candidate(val signal: DoubleArray, val notchConfidence: Double, val methodLabel: String)

    data class Result(val selectedSignal: DoubleArray, val selectedMethodLabel: String, val selectedNotchConfidence: Double, val wasSubstituted: Boolean)

    /**
     * @param fallbacks one or more candidates to consider if [primary] fails
     *   the bar. [MorphologyWaveformEstimator] always passes exactly one
     *   (the safe mode) -- see this object's own KDoc for why.
     */
    fun select(
        primary: Candidate,
        fallbacks: List<Candidate>,
        confidenceThreshold: Double = 0.3
    ): Result {
        require(fallbacks.isNotEmpty()) { "at least one fallback candidate is required" }

        if (!primary.notchConfidence.isNaN() && primary.notchConfidence > confidenceThreshold) {
            return Result(primary.signal, primary.methodLabel, primary.notchConfidence, wasSubstituted = false)
        }

        val best = fallbacks.maxByOrNull { it.notchConfidence } ?: fallbacks.first()
        return Result(best.signal, best.methodLabel, best.notchConfidence, wasSubstituted = true)
    }
}
