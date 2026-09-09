function [sigOriented, wasFlipped, skewValue] = fixPolarity(sig, frameRate)
% FIXPOLARITY Correct rPPG waveform sign using a skewness heuristic.
%
% Pipeline stage: Segment 7 Task A, Action 2 (NEW, additive) — chained
% after pulseextraction/chromCombine.m or posCombine.m in
% morphology/extractMorphologyWaveform.m. Neither chromCombine.m nor
% posCombine.m anchors output polarity: alpha = std(Xs)/std(Ys) is
% always positive (a ratio of two standard deviations), so the sign of
% the combined signal is set entirely by projection geometry and can
% flip between subjects. The existing HR path never noticed because
% heartrate/fftHeartRate.m works on FFT MAGNITUDE, which is sign-blind —
% a HR estimate is identical whether the pulse trace is inverted or not.
% Waveform morphology is NOT sign-blind: a correctly-oriented trace has
% the dicrotic notch on the diastolic (slow-decay) limb, and an inverted
% trace puts it on the wrong limb, which is exactly defect (c) from the
% Segment 7 Task A brief. See docs/Segment7_Task_A_Morphology_Pipeline.md.
%
% WHY CAMERA rPPG IS NATIVELY INVERTED: more blood in the ROI's
% microvasculature during systole means more light absorption, which
% means LESS reflected light reaches the camera. A contact pulse
% oximeter's transmitted-light PPG has the opposite convention (more
% blood -> more absorption -> less TRANSMITTED light reaching the
% detector -> that is recorded as a trough too, by convention flipped
% at the sensor level so a "normal" PPG trace still rises on systole).
% Net effect: an un-anchored camera-rPPG combination can come out either
% way depending on the CHROM/POS projection's incidental sign, which is
% why this correction step exists as a separate, explicit stage rather
% than being baked into chromCombine.m/posCombine.m's formulas.
%
% Rule: a correctly-oriented PPG waveform has a fast systolic upstroke
% followed by a slower diastolic decay, which is a right-skewed
% (positive third central moment) shape. Negating a signal negates its
% third central moment (odd order), so skewness < 0 means the trace is
% upside down, and negating it should restore the correct orientation.
% This is a heuristic over the WHOLE signal, not a per-beat decision —
% see morphology/fixPolarityByGroundTruth.m for the ground-truth-anchored
% alternative used in scripts/run_segment7_morphology_batch.m to report
% how often the two rules agree.
%
% *** CAVEAT, ADDED IN SEGMENT 7 TASK B — READ BEFORE USING THIS AS A
% DEFAULT *** Measured on all 5 locally-available UBFC DATASET_1
% subjects (Task A, `results/metrics/segment7_morphology_metrics.csv`),
% this skewness heuristic AGREED with the ground-truth-anchored rule
% (morphology/fixPolarityByGroundTruth.m) on only 3 of 5 subjects (60%).
% Critically, the heuristic did not fail randomly: it flipped ALL 5
% subjects (every one came out skewness < 0), while the ground-truth
% rule only flipped 3 of them — a systematic all-flip bias, not scatter.
% Likely explanation (a hypothesis on n=5, not a proven fact): den
% Brinker et al. (arXiv:2306.09879) found that FOREHEAD camera-PPG can
% have REVERSED asymmetry relative to the fingertip-contact PPG this
% skewness convention was originally derived from (i.e. forehead rPPG
% can show a steeper DOWNslope than upslope, the opposite of the
% "fast upstroke, slow decay" assumption this function's rule rests on).
% If that holds generally, a skewness rule imported unmodified from
% fingertip-PPG literature is systematically miscalibrated for this
% project's forehead ROI, not just noisy on small samples.
%
% Consequence: as of Segment 7 Task B,
% morphology/extractMorphologyWaveform.m and
% scripts/run_segment7_morphology_batch.m default to
% morphology/fixPolarityByGroundTruth.m instead of this function
% whenever ground-truth contact PPG is available (true for all of
% UBFC). This function is KEPT, unmodified in logic, as the documented
% fallback for contexts with no ground truth available at all (the
% eventual Android app, or a future self-collected dataset before any
% reference PPG exists for it) — see
% docs/Segment7_Task_B_Notch_Quantification.md for the full writeup.
% Do not reach for this function as a silent default without having
% read this caveat first.
%
% Inputs:
%   sig       - 1 x N vector, a pulse signal (e.g.
%               pulseextraction/chromCombine.m's output after
%               morphology/bandpassMorphology.m).
%   frameRate - scalar, sampling rate of sig in Hz. Used only to enforce
%               the minimum-duration requirement below.
%
% Outputs:
%   sigOriented - 1 x N vector, sig negated if and only if wasFlipped.
%   wasFlipped  - logical scalar, true if sig was negated.
%   skewValue   - scalar, the (biased/population) sample skewness of the
%                 ORIGINAL sig, i.e. skewness(sig), computed manually
%                 (see below) rather than via the Statistics and Machine
%                 Learning Toolbox's skewness() function, matching this
%                 project's existing convention of implementing standard
%                 statistics by hand (see
%                 validation/computeMetrics.m's manual Pearson r) so
%                 this function has no toolbox dependency beyond core
%                 MATLAB. The formula matches skewness()'s default
%                 (bias-uncorrected, g1) definition:
%                   skewness = mean((x - mean(x)).^3) / std(x, 1)^3
%                 where std(x, 1) is the population (N-denominator, not
%                 N-1) standard deviation.

minDurationSec = 10;

if numel(sig) / frameRate < minDurationSec
    error('fixPolarity:tooShort', 'sig must cover at least %.0f s of data (got %.2f s at %.2f Hz) — skewness over a shorter window is not reliable enough to anchor polarity.', minDurationSec, numel(sig) / frameRate, frameRate);
end

sigRow = sig(:)';
N = numel(sigRow);
sigMean = mean(sigRow);
sigCentered = sigRow - sigMean;

populationStd = sqrt(sum(sigCentered.^2) / N);
thirdMoment = sum(sigCentered.^3) / N;

skewValue = thirdMoment / (populationStd^3);

wasFlipped = skewValue < 0;

if wasFlipped
    sigOriented = -sig;
else
    sigOriented = sig;
end

end
