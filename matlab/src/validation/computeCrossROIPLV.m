function [plvMean, pairwiseTable] = computeCrossROIPLV(regionSignals, regionNames)
% COMPUTECROSSROIPLV Cross-ROI phase-locking value -- a rPPG fidelity
% metric that needs NO ground truth at all.
%
% Pipeline stage: Segment 11 Task 1 (NEW, additive; promoted from a Task 3
% Action 2 one-off computation inline in
% scripts/run_segment10_task3_tier0_diagnostics.m into this standing,
% reusable validation/ function). Does not modify, and is independent of,
% any pulse-extraction file -- it operates on whatever pulse signal(s) the
% caller already produced (CHROM, POS, or any other combiner), so it is
% reusable well beyond the two conditions this task itself compares.
%
% USE THIS WHEN NO GROUND-TRUTH PPG WAVEFORM IS AVAILABLE for a subject.
% Every other fidelity metric in this project (Task 1's waveform
% correlation, notch-confidence-vs-GT, etc.) requires a real contact-PPG
% ground truth, which this project has for only 100 of its subjects
% (Segment 7 Task K's pool). Any subject with Segment 6 Task N's cached
% multi-region ROI traces (forehead/glabella/malar/cheek) can get a
% fidelity estimate from THIS function instead, with no GT at all.
%
% RATIONALE (Kaur, Lakshminarayanan & Saini, Biomed. Opt. Express
% 17(7):3832, 2026): ROIs sharing a common arterial supply receive the
% cardiac pulse at a fixed phase relationship set by pulse transit time
% within the arterial tree. Independently-extracted pulse signals from
% different face regions of the same subject should therefore be
% phase-locked at the cardiac frequency if the extraction is faithful to
% the true underlying pulse; loss of phase-locking indicates noise,
% motion, or algorithmic distortion swamping the true cardiac signal in at
% least one region.
%
% VALIDATION ON SPANDAN'S OWN DATA (Segment 10 Task 3 Action 2, n=20 VIPL
% v1/source1 subjects with all four Task N regions cached): mean cross-ROI
% PLV correlates with Task 1's own GT-referenced waveform correlation at
% r=0.571 (CHROM) / 0.632 (POS) -- see
% docs/Segment10_Task3_Tier0_Diagnostics.md Action 2 for the full result.
% This is evidence the metric tracks true fidelity, not a proof it is
% equivalent to a GT-referenced measurement -- treat it as a useful proxy,
% not a replacement, per that doc's own caveats.
%
% METHOD: instantaneous phase per region via the Hilbert transform
% (`hilbert`, Signal Processing Toolbox), then PLV between every pair of
% regions as |mean(exp(i*(phase_A - phase_B)))| over the full recording,
% averaged across all pairs for the single summary score. Callers should
% pass an already narrowband-ish pulse signal (this project's convention:
% filtering/bandpassClean.m's 0.7-4Hz output, i.e. AFTER detrend + bandpass
% + CHROM/POS combination + a second bandpass -- exactly Branch 1's own
% pulseChromFiltered/pulsePosFiltered), since Hilbert instantaneous phase is
% only meaningful for a signal that is already close to monocomponent.
%
% Inputs:
%   regionSignals - 1 x R cell array (R >= 2), each cell a 1 x N (or N x 1)
%                   pulse signal for one ROI region. All regions must be
%                   the SAME length and SAME sampling rate (same subject,
%                   same recording) -- this function does not resample or
%                   time-align them; that is the caller's responsibility
%                   (Task N's cached per-region traces already share one
%                   timeline since they come from the same video).
%   regionNames   - (optional) 1 x R cell array of strings/chars naming
%                   each entry in regionSignals, for the output table's
%                   readability. Defaults to {'region1', 'region2', ...}.
%
% Outputs:
%   plvMean       - scalar in [0, 1], the mean PLV across all
%                   nchoosek(R, 2) region pairs. Higher = more phase-locked
%                   = higher inferred fidelity. This project's own
%                   observed range (Task 3 Action 2, n=20): 0.126-0.508.
%   pairwiseTable - table, one row per region pair, columns `regionA`,
%                   `regionB`, `plv` -- the per-pair breakdown behind
%                   plvMean, so a caller can check whether one specific
%                   region is dragging the average down rather than a
%                   uniformly weak signal.

numRegions = numel(regionSignals);
if numRegions < 2
    error('computeCrossROIPLV:tooFewRegions', 'Need at least 2 regions to compute a cross-ROI PLV (got %d).', numRegions);
end

if nargin < 2 || isempty(regionNames)
    regionNames = arrayfun(@(k) sprintf('region%d', k), 1:numRegions, 'UniformOutput', false);
end
if numel(regionNames) ~= numRegions
    error('computeCrossROIPLV:nameMismatch', 'regionNames must have the same length as regionSignals.');
end

refLen = numel(regionSignals{1});
phases = cell(1, numRegions);
for r = 1:numRegions
    sig = regionSignals{r}(:)';
    if numel(sig) ~= refLen
        error('computeCrossROIPLV:lengthMismatch', 'Region "%s" has %d samples, expected %d (all regions must match region 1).', regionNames{r}, numel(sig), refLen);
    end
    phases{r} = angle(hilbert(sig));
end

pairIdx = nchoosek(1:numRegions, 2);
numPairs = size(pairIdx, 1);

regionA = cell(numPairs, 1);
regionB = cell(numPairs, 1);
plvVals = nan(numPairs, 1);

for p = 1:numPairs
    a = pairIdx(p, 1);
    b = pairIdx(p, 2);
    regionA{p} = regionNames{a};
    regionB{p} = regionNames{b};
    plvVals(p) = abs(mean(exp(1i * (phases{a} - phases{b}))));
end

pairwiseTable = table(regionA, regionB, plvVals, 'VariableNames', {'regionA', 'regionB', 'plv'});
plvMean = mean(plvVals);

end
