package com.spandan.app.signal

import android.util.Log

/**
 * Segment 19 -- Branch 2 (waveform morphology / dicrotic notch) live
 * orchestrator, mirroring `matlab/src/pipeline/estimateVitalsAndMorphology.m`'s
 * own Branch 2 sequence (read directly from source before writing this):
 * detrend -> shared f0 from a wide-band CHROM pulse -> [AdaptiveHarmonicFilter]
 * (ABPF) per channel, forced onto that shared f0 -> [PulseExtraction.chromCombine] ->
 * [FixPolarity] (heuristic -- Android has no contact-PPG ground truth, ever;
 * `fixPolarityByGroundTruth.m`/`estimateLagPolarityByGroundTruth.m` are
 * explicitly NOT ported, per this task's own brief) -> [ResampleUniform] ->
 * [EnsembleAverageBeats] -> [NotchDetectIEM], with [opts.useConfidenceGate]
 * (default true, matching the MATLAB production default since Segment 14)
 * substituting [HarmonicSelectiveGaussianFilter] (alpha 0.15) via
 * [HarmonicFilterConfidenceGate] wherever ABPF's own notch confidence fails
 * this project's 0.3 bar.
 *
 * Reads from the SAME [RgbSample] window Branch 1's [RealHeartRateEstimator]
 * already consumes -- both estimators run independently side by side on
 * [MainActivity]'s [SignalBuffer] snapshot, neither reads or modifies the
 * other's state, matching Branch 1/Branch 2's deliberate MATLAB-side
 * separation (`estimateVitalsAndMorphology.m`'s own header: the wide-band/
 * harmonic-comb filtering Branch 2 needs measurably hurts Branch 1's HR
 * accuracy -- a documented harmonic-lock case, one VIPL subject's CHROM
 * jumped 69.4->140.8bpm under it -- so the two branches must never share a
 * filter choice).
 *
 * SEGMENT 18 INTERACTION, STATED PLAINLY (this task's own brief flags this):
 * the wide 0.5-8Hz band needs fs comfortably above 16Hz under Nyquist. This
 * app's measured on-device throughput (13.44-21.40fps depending on the
 * frame-skip optimization) sits at or below that margin, not comfortably
 * above it -- so [MorphologyBandpassFilter.pick] is consulted every window
 * to fall back to 'mid' (needs fs>12Hz) when 'wide' isn't admissible, and
 * the window is skipped ([EstimatorStatus.LOW_SIGNAL_QUALITY]) if even
 * 'mid' isn't. The real fs this ran at is always the caller's own
 * runtime-measured value (never hardcoded, same discipline [BandpassFilter]
 * already uses) and is exposed on [Estimate.fs] so a caller can report it
 * alongside any on-device result.
 *
 * FAIL-SOFT LAYER (deliberate divergence from a pure port, stated
 * explicitly): [EnsembleAverageBeats.apply] and [FixPolarity.apply] can
 * throw on a bad window (too few beats, too-short signal) -- MATLAB's own
 * offline batch scripts never hit this because they only ever process
 * clean, pre-vetted UBFC/VIPL clips. This live estimator, running on
 * uncontrolled camera data, catches those and reports
 * [EstimatorStatus.LOW_SIGNAL_QUALITY] instead of crashing -- the same
 * "ported function stays MATLAB-faithful, the live orchestrator adds the
 * fail-soft layer" split [RealHeartRateEstimator] already uses around
 * [BandpassFilter]/[HeartRateFft].
 *
 * HONEST STATUS: unit-tested at every stage (see each ported file's own
 * test), but this orchestrator itself was NOT exercised on a physical
 * device this session -- none was attached in this environment. See
 * `android/docs/Segment19_Branch2_Morphology_Port.md`.
 */
class MorphologyWaveformEstimator(
    private val useConfidenceGate: Boolean = true
) {

    data class Estimate(
        val notchDetected: Boolean,
        val notchPositionNormalized: Double,
        val notchDepth: Double,
        /** Clipped to [0,1] -- see [NotchDetectIEM]'s own KDoc for why this
         *  alone is a near-useless gate at scale; surface [notchConfidenceRaw]
         *  in the UI too, per this task's own instruction. */
        val notchConfidence: Double,
        /** UNCLIPPED -- the value that actually carries ranking information
         *  once [notchConfidence] clips at 1.0. */
        val notchConfidenceRaw: Double,
        val harmonicMethodUsed: String, // "adaptiveHarmonic" or "gaussian015"
        val gateSubstituted: Boolean,
        val waveform: DoubleArray, // prototype.trimmedMean -- 1 ensemble-averaged cardiac cycle
        /** [Segment 31] The SAME selected candidate's (ABPF or Gaussian,
         *  whichever [harmonicMethodUsed] names) continuous, polarity-
         *  corrected, uniformly-resampled pulse (`resampled.sigUniform` in
         *  [computeNotch] -- i.e. [ResampleUniform]'s own output, the SAME
         *  signal [EnsembleAverageBeats] then chops into individual beats to
         *  build [waveform] above) -- tail-windowed to the last
         *  [CONTINUOUS_DISPLAY_SECONDS] seconds. Real Branch 2 output (post
         *  ABPF/Gaussian harmonic filtering + CHROM combine + polarity fix),
         *  NOT raw/Branch-1 data, and spans several real cardiac cycles
         *  (typically 8-13 at a resting 60-100bpm over an 8s window) --
         *  added so the UI can show a multi-cycle scrolling trace ("like a
         *  PPG monitor") instead of one averaged beat. */
        val continuousWaveform: DoubleArray,
        val fs: Double, // the real, runtime-measured fs this estimate ran at
        val bandModeUsed: MorphologyBandpassFilter.BandMode
    )

    private var lastComputeMs = 0L
    private var cached: Estimate? = null

    /** Names WHY the last [update] call did/didn't produce a value -- same
     *  shared enum [RealHeartRateEstimator]/[LiveSpo2Estimator] already use
     *  (Segment 16), not a new convention. */
    var lastStatus: EstimatorStatus = EstimatorStatus.WARMING_UP
        private set

    fun update(samples: List<RgbSample>, nowMs: Long = System.currentTimeMillis()): Estimate? {
        if (nowMs - lastComputeMs < RECOMPUTE_INTERVAL_MS) {
            return cached
        }
        lastComputeMs = nowMs

        if (samples.size < MIN_SAMPLES) {
            lastStatus = EstimatorStatus.WARMING_UP
            return cached
        }
        val windowSeconds = (samples.last().timestampMs - samples.first().timestampMs) / 1000.0
        if (windowSeconds < MIN_WINDOW_SECONDS) {
            lastStatus = EstimatorStatus.WARMING_UP
            return cached
        }

        val fs = (samples.size - 1) / windowSeconds

        val bandMode = MorphologyBandpassFilter.pick(fs)
        if (bandMode == null) {
            Log.w(TAG, "Measured fs=$fs Hz too low for even MID band (0.6-6.0Hz); skipping this window")
            lastStatus = EstimatorStatus.LOW_SIGNAL_QUALITY
            return cached
        }

        val rawR = DoubleArray(samples.size) { samples[it].red.toDouble() }
        val rawG = DoubleArray(samples.size) { samples[it].green.toDouble() }
        val rawB = DoubleArray(samples.size) { samples[it].blue.toDouble() }
        val timestampsSeconds = DoubleArray(samples.size) { samples[it].timestampMs / 1000.0 }

        val detrendedR = BandpassFilter.detrend(rawR)
        val detrendedG = BandpassFilter.detrend(rawG)
        val detrendedB = BandpassFilter.detrend(rawB)

        try {
            // --- Shared f0 from a wide/mid-band CHROM pulse (matches
            // estimateVitalsAndMorphology.m's own "estimate f0 once from
            // Branch 2's OWN wide-band CHROM pulse" design exactly).
            val wideR = MorphologyBandpassFilter.apply(detrendedR, fs, bandMode).filtered
            val wideG = MorphologyBandpassFilter.apply(detrendedG, fs, bandMode).filtered
            val wideB = MorphologyBandpassFilter.apply(detrendedB, fs, bandMode).filtered
            val pulseWide = PulseExtraction.chromCombine(wideR, wideG, wideB, rawR, rawG, rawB)
            val sharedF0Hz = HeartRateFft.estimateBpm(pulseWide, fs)?.bpm?.div(60.0)
            if (sharedF0Hz == null) {
                Log.w(TAG, "No FFT bin fell inside 0.7-4Hz for the shared f0 estimate; skipping this window")
                lastStatus = EstimatorStatus.LOW_SIGNAL_QUALITY
                return cached
            }

            // --- ABPF comb, forced onto the shared f0 across all 3 channels.
            val abpfR = AdaptiveHarmonicFilter.apply(detrendedR, fs, NUM_HARMONICS, sharedF0Hz).filtered
            val abpfG = AdaptiveHarmonicFilter.apply(detrendedG, fs, NUM_HARMONICS, sharedF0Hz).filtered
            val abpfB = AdaptiveHarmonicFilter.apply(detrendedB, fs, NUM_HARMONICS, sharedF0Hz).filtered
            val pulseAbpf = PulseExtraction.chromCombine(abpfR, abpfG, abpfB, rawR, rawG, rawB)

            var harmonicMethodUsed = "adaptiveHarmonic"
            var gateSubstituted = false

            val abpfNotch = computeNotch(pulseAbpf, fs, timestampsSeconds)
                ?: run { lastStatus = EstimatorStatus.LOW_SIGNAL_QUALITY; return cached }

            var finalNotch = abpfNotch

            if (useConfidenceGate && abpfNotch.confidence <= CONFIDENCE_GATE_BAR) {
                val gauR = HarmonicSelectiveGaussianFilter.apply(detrendedR, fs, NUM_HARMONICS, sharedF0Hz, GAUSSIAN_ALPHA).filtered
                val gauG = HarmonicSelectiveGaussianFilter.apply(detrendedG, fs, NUM_HARMONICS, sharedF0Hz, GAUSSIAN_ALPHA).filtered
                val gauB = HarmonicSelectiveGaussianFilter.apply(detrendedB, fs, NUM_HARMONICS, sharedF0Hz, GAUSSIAN_ALPHA).filtered
                val pulseGaussian = PulseExtraction.chromCombine(gauR, gauG, gauB, rawR, rawG, rawB)

                val gaussianNotch = computeNotch(pulseGaussian, fs, timestampsSeconds)
                if (gaussianNotch != null) {
                    val gateResult = HarmonicFilterConfidenceGate.select(
                        primary = HarmonicFilterConfidenceGate.Candidate(pulseAbpf, abpfNotch.confidence, "adaptiveHarmonic"),
                        fallbacks = listOf(HarmonicFilterConfidenceGate.Candidate(pulseGaussian, gaussianNotch.confidence, "gaussian015"))
                    )
                    if (gateResult.wasSubstituted) {
                        harmonicMethodUsed = "gaussian015"
                        gateSubstituted = true
                        finalNotch = gaussianNotch
                    }
                    // else: ABPF stays selected -- gateResult still reports it,
                    // but abpfNotch (already computed) is identical, no need
                    // to recompute anything.
                }
                // If the Gaussian candidate itself failed (too-short/too-few-
                // beats window), the gate never gets a chance to run -- stay
                // on ABPF's own result, which already succeeded above. This
                // is a deliberate asymmetry from the MATLAB source (which
                // assumes the fallback path always succeeds on offline data):
                // a live camera window can make the FALLBACK candidate fail
                // where the PRIMARY didn't, and there's nothing better to do
                // than keep the primary in that case.
            }

            val estimate = Estimate(
                notchDetected = finalNotch.detected,
                notchPositionNormalized = finalNotch.positionNormalized,
                notchDepth = finalNotch.depth,
                notchConfidence = finalNotch.confidence,
                notchConfidenceRaw = finalNotch.confidenceRaw,
                harmonicMethodUsed = harmonicMethodUsed,
                gateSubstituted = gateSubstituted,
                waveform = finalNotch.waveform,
                continuousWaveform = finalNotch.continuousWaveform,
                fs = fs,
                bandModeUsed = bandMode
            )

            Log.d(
                TAG,
                ("fs=%.2fHz band=%s method=%s substituted=%b notchDetected=%b " +
                    "notchConf=%.3f notchConfRaw=%.3f").format(
                    fs, bandMode, harmonicMethodUsed, gateSubstituted,
                    estimate.notchDetected, estimate.notchConfidence, estimate.notchConfidenceRaw
                )
            )

            cached = estimate
            lastStatus = EstimatorStatus.OK
            return estimate
        } catch (e: IllegalStateException) {
            // EnsembleAverageBeats.apply's own "too few beats" guards --
            // real signal-quality problems on live camera data, not a bug.
            Log.w(TAG, "Branch 2 window rejected: ${e.message}")
            lastStatus = EstimatorStatus.LOW_SIGNAL_QUALITY
            return cached
        } catch (e: IllegalArgumentException) {
            // FixPolarity's too-short guard / NotchDetectIEM's flat-signal guard.
            Log.w(TAG, "Branch 2 window rejected: ${e.message}")
            lastStatus = EstimatorStatus.LOW_SIGNAL_QUALITY
            return cached
        }
    }

    private data class NotchWithWaveform(
        val detected: Boolean,
        val positionNormalized: Double,
        val depth: Double,
        val confidence: Double,
        val confidenceRaw: Double,
        val waveform: DoubleArray,
        val continuousWaveform: DoubleArray // [Segment 31] tail-windowed resampled.sigUniform -- see Estimate.continuousWaveform's own KDoc
    )

    /** [FixPolarity] -> [ResampleUniform] -> [EnsembleAverageBeats] ->
     *  [NotchDetectIEM], exactly matching `estimateVitalsAndMorphology.m`'s
     *  own per-candidate sequence (the same four calls it makes once for
     *  ABPF and, conditionally, again for the Gaussian fallback). Returns
     *  null if [EnsembleAverageBeats] can't find enough beats in THIS
     *  particular candidate signal (see [update]'s own try/catch for the
     *  primary-path case; this function is also called for the fallback
     *  candidate, where a null here just means the gate keeps the primary). */
    private fun computeNotch(pulse: DoubleArray, fs: Double, timestampsSeconds: DoubleArray): NotchWithWaveform? {
        return try {
            val polarity = FixPolarity.apply(pulse, fs)
            val resampled = ResampleUniform.apply(polarity.oriented, timestampsSeconds)
            val beats = EnsembleAverageBeats.apply(resampled.sigUniform, resampled.targetFs)
            val hrBpmUsed = HeartRateFft.estimateBpm(resampled.sigUniform, resampled.targetFs)?.bpm ?: return null
            val effectiveFsHz = beats.prototype.trimmedMean.size * (hrBpmUsed / 60.0)
            val notch = NotchDetectIEM.apply(beats.prototype.trimmedMean, effectiveFsHz)

            // [Segment 31] Tail-window resampled.sigUniform to the last
            // CONTINUOUS_DISPLAY_SECONDS -- the full window can be up to
            // SignalBuffer.WINDOW_DURATION_SECONDS (25s) long, which at a
            // resting HR would cram 25-40+ cycles into one view; a shorter
            // recent slice reads like an actual monitor trace, not a dense
            // scribble, and naturally shows MORE cycles at a higher HR and
            // fewer at a lower one, exactly like a real device would.
            val displaySamples = (resampled.targetFs * CONTINUOUS_DISPLAY_SECONDS).toInt().coerceAtMost(resampled.sigUniform.size)
            val continuousWaveform = resampled.sigUniform.copyOfRange(resampled.sigUniform.size - displaySamples, resampled.sigUniform.size)

            NotchWithWaveform(notch.detected, notch.positionNormalized, notch.depth, notch.confidence, notch.confidenceRaw, beats.prototype.trimmedMean, continuousWaveform)
        } catch (e: IllegalStateException) {
            null
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    companion object {
        private const val TAG = "MorphologyWaveformEstimator"

        /** Heavier per-window cost than Branch 1 (harmonic-comb FFT/IFFT x3
         *  channels, plus a conditional second pass, plus Savitzky-Golay
         *  smoothing inside NotchDetectIEM) -- recomputed less often than
         *  [RealHeartRateEstimator]'s 1000ms. Not tuned against a real
         *  on-device CPU budget this session (no device attached); revisit
         *  if a future on-device capture shows this competing with camera
         *  throughput. */
        private const val RECOMPUTE_INTERVAL_MS = 2000L
        private const val MIN_WINDOW_SECONDS = 10.0 // FixPolarity's own minimum
        private const val MIN_SAMPLES = 60

        private const val NUM_HARMONICS = 6
        private const val GAUSSIAN_ALPHA = 0.15 // this project's own validated value, not the paper's 0.5
        private const val CONFIDENCE_GATE_BAR = 0.3

        /** [Segment 31] How many of the most recent seconds of the
         *  continuous, resampled pulse to expose via
         *  [Estimate.continuousWaveform] -- see that field's own KDoc.
         *  8 seconds is an arbitrary, unmeasured choice (no on-device
         *  accuracy/readability A-B done this session): long enough to show
         *  several real cycles even at a slow resting HR (~8-10 at 60-75bpm),
         *  short enough that a fast HR (~120bpm) doesn't cram in so many
         *  cycles the trace becomes unreadable. Revisit if a future capture
         *  suggests otherwise. */
        private const val CONTINUOUS_DISPLAY_SECONDS = 8.0
    }
}
