function [sigOriented, wasFlipped] = fixPolarityByGroundTruth(sig, sigTimestamps, gtPPG, gtTimestamps)
% FIXPOLARITYBYGROUNDTRUTH Correct rPPG waveform sign against the UBFC
% contact-PPG ground truth, via cross-correlation.
%
% Pipeline stage: Segment 7 Task A, Action 2 (NEW, additive) — NOT part
% of morphology/extractMorphologyWaveform.m's chain (that uses the
% heuristic morphology/fixPolarity.m only, since a real deployment has
% no contact-PPG ground truth to check against). This function exists
% so scripts/run_segment7_morphology_batch.m can report how often
% fixPolarity.m's skewness heuristic AGREES with the answer a ground-
% truth-anchored rule would have given — that agreement rate is itself
% one of the Action 6 deliverables (see
% docs/Segment7_Task_A_Morphology_Pipeline.md), not just a debugging
% aid.
%
% Rule (per the Segment 7 Task A brief): resample the ground-truth
% contact-PPG onto the rPPG signal's own timestamps, then compare the
% peak cross-correlation achieved by sig against sig negated:
%   pick sign(max(xcorr(rppg, gtPPG))) vs sign(max(xcorr(-rppg, gtPPG)))
% i.e. flip sig if and only if negating it yields a HIGHER peak
% cross-correlation with the ground-truth trace at some lag. Both
% signals are zero-meaned first so xcorr compares waveform SHAPE, not
% DC offset (uninformative here since both are already
% detrended/bandpassed in the caller's pipeline anyway).
%
% Inputs:
%   sig           - 1 x N vector, a pulse signal (e.g.
%                   pulseextraction/chromCombine.m's output after
%                   morphology/bandpassMorphology.m).
%   sigTimestamps - 1 x N vector, seconds, sig's own per-sample
%                   acquisition times (roi/extractROISignals.m's
%                   roiTimestamps output for the same subject).
%   gtPPG         - vector, io/loadGroundTruth.m's gt.ppg for the same
%                   subject (raw contact-PPG waveform, its own native
%                   sample rate — UBFC DATASET_1's pulse-oximeter runs
%                   at ~62 Hz, asynchronous with video, see
%                   io/loadGroundTruth.m).
%   gtTimestamps  - vector, seconds, gt.timestamp for the same subject
%                   (same length as gtPPG).
%
% Outputs:
%   sigOriented - 1 x N vector, sig negated if and only if wasFlipped.
%   wasFlipped  - logical scalar, true if sig was negated.

sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';
gtPPGRow = gtPPG(:)';
gtTimestampsRow = gtTimestamps(:)';

overlapLowSec = max(sigTimestampsRow(1), gtTimestampsRow(1));
overlapHighSec = min(sigTimestampsRow(end), gtTimestampsRow(end));

if overlapHighSec <= overlapLowSec
    error('fixPolarityByGroundTruth:noOverlap', 'sigTimestamps and gtTimestamps do not overlap in time — cannot align rPPG and ground-truth PPG.');
end

overlapMask = sigTimestampsRow >= overlapLowSec & sigTimestampsRow <= overlapHighSec;

sigOverlap = sigRow(overlapMask);
sigTimestampsOverlap = sigTimestampsRow(overlapMask);

gtResampled = interp1(gtTimestampsRow, gtPPGRow, sigTimestampsOverlap, 'pchip');

sigZeroMean = sigOverlap - mean(sigOverlap);
gtZeroMean = gtResampled - mean(gtResampled);

xcorrPositive = xcorr(sigZeroMean, gtZeroMean);
xcorrNegative = xcorr(-sigZeroMean, gtZeroMean);

maxPositive = max(xcorrPositive);
maxNegative = max(xcorrNegative);

wasFlipped = maxNegative > maxPositive;

if wasFlipped
    sigOriented = -sig;
else
    sigOriented = sig;
end

end
