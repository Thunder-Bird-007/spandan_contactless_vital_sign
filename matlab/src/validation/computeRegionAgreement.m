function relativeSpread = computeRegionAgreement(HR_forehead, HR_glabella, HR_malar, HR_cheek)
% COMPUTEREGIONAGREEMENT Per-subject relative spread across four
% independent per-region HR estimates from the same underlying video.
%
% Pipeline stage: Stage 6 (validation), Task N. Same spirit as
% validation/computeAgreementConfidence.m (Task I's CHROM/POS agreement
% metric), generalized from a 2-way comparison to a 4-way one across
% ROI/extractROISignals.m's four region modes (forehead, glabella, malar,
% cheek). This is a generic, post-hoc agreement metric -- it does not
% touch roi/extractROISignals.m, filtering/detrendSignal.m,
% filtering/bandpassClean.m, pulseextraction/chromCombine.m, or
% heartrate/fftHeartRate.m, and it does not recompute any HR estimate. It
% only compares four vectors of already-computed per-region HR values.
%
% Motivation (see docs/Segment6_Task_N_Multi_Region_ROI.md's design
% constraint): ground truth HR is not available at real inference time,
% so any region-selection rule must be decidable from the video signal
% alone. Just as Task I found CHROM/POS disagreement to be a real,
% ground-truth-free proxy for CHROM's per-subject error, this function
% turns four independent same-subject HR estimates into a single
% per-subject spread number that computeRegionSwitchingEstimate.m can act
% on without ever looking at ground truth.
%
% Formula (per subject i), using the FULL four-region set for the median,
% not just a pairwise comparison:
%   HR_all(i, :)       = [HR_forehead(i), HR_glabella(i), HR_malar(i), HR_cheek(i)]
%   medianHR(i)         = median(HR_all(i, :))
%   relativeSpread(i)   = (max(HR_all(i, :)) - min(HR_all(i, :))) / medianHR(i)
%
% relativeSpread is the full range (max - min) across all four regions,
% normalized by the cross-region median, expressed as a FRACTION (not a
% percentage) of that median -- the direct 4-way analogue of Task I's
% abs(HR_chrom - HR_pos)/mean([...]) 2-way formula. Range rather than
% e.g. standard deviation was chosen because it directly answers "how far
% could a single wrong region estimate be from the group," which is
% exactly what computeRegionSwitchingEstimate.m needs to reason about.
% Thresholding this into a low-confidence flag, or picking which region
% to trust, is a separate, explicit step (see
% computeRegionSwitchingEstimate.m and
% scripts/run_segment6_task_n_multi_region_batch.m) so that choice stays
% visible at the call site rather than buried in this function, same
% discipline as computeAgreementConfidence.m.
%
% Inputs:
%   HR_forehead, HR_glabella, HR_malar, HR_cheek - vectors, per-subject HR
%       estimate (bpm) for each region, all the same length and in the
%       same subject order.
%
% Outputs:
%   relativeSpread - vector, same length/order as HR_forehead, the
%                    fraction (not percentage) of cross-region spread for
%                    each subject.

HR_forehead = HR_forehead(:);
HR_glabella = HR_glabella(:);
HR_malar = HR_malar(:);
HR_cheek = HR_cheek(:);

numSubjectsForehead = numel(HR_forehead);
numSubjectsGlabella = numel(HR_glabella);
numSubjectsMalar = numel(HR_malar);
numSubjectsCheek = numel(HR_cheek);

if numSubjectsForehead ~= numSubjectsGlabella || numSubjectsForehead ~= numSubjectsMalar || numSubjectsForehead ~= numSubjectsCheek
    error('computeRegionAgreement:sizeMismatch', 'HR_forehead, HR_glabella, HR_malar, and HR_cheek must all have the same number of elements.');
end

numSubjects = numSubjectsForehead;
relativeSpread = zeros(numSubjects, 1);

for i = 1:numSubjects
    regionValues = [HR_forehead(i), HR_glabella(i), HR_malar(i), HR_cheek(i)];
    medianHR = median(regionValues);
    rangeHR = max(regionValues) - min(regionValues);
    relativeSpread(i) = rangeHR / medianHR;
end

end
