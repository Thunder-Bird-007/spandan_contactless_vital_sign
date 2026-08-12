function [HR_switched, selectedRegion] = computeRegionSwitchingEstimate(HR_forehead, HR_glabella, HR_malar, HR_cheek)
% COMPUTEREGIONSWITCHINGESTIMATE Per-subject region-selection estimator
% across four independent per-region HR estimates, using ONLY cross-region
% agreement -- no ground truth.
%
% Pipeline stage: Stage 6 (validation), Task N. Same spirit as
% validation/computeSwitchingEstimate.m (Task J's CHROM/POS disagreement
% -gated switch), generalized to select among four regions
% (roi/extractROISignals.m's forehead/glabella/malar/cheek modes) instead
% of choosing between two methods. This is a generic, post-hoc combiner
% -- it does not touch roi/extractROISignals.m, filtering/detrendSignal.m,
% filtering/bandpassClean.m, pulseextraction/chromCombine.m, or
% heartrate/fftHeartRate.m, and it does not recompute any HR estimate. It
% only combines four vectors of already-computed per-region HR values.
%
% Decision rule (per subject i), stated explicitly per this task's design
% constraint that ground truth is unavailable at real inference time:
%   HR_all(i, :) = [HR_forehead(i), HR_glabella(i), HR_malar(i), HR_cheek(i)]
%   medianHR(i)  = median(HR_all(i, :))
%   selectedRegion(i) = the region whose HR estimate has the SMALLEST
%       absolute distance to medianHR(i), i.e.
%       argmin_region |HR_region(i) - medianHR(i)|.
%   HR_switched(i) = HR_all(i, selectedRegion(i))
%
% "Or full consensus if all four roughly agree" (this task's other stated
% starting-rule option) collapses into the SAME rule above without a
% special case: when all four regions roughly agree, every region is
% close to the median and whichever one happens to be closest is picked
% -- since they roughly agree, the choice barely matters to the resulting
% HR_switched value. No separate consensus branch was added, to avoid a
% second, unstated threshold choice on top of the argmin-to-median rule.
%
% Tie-break: if two or more regions are equally close to the median (an
% exact tie in floating point), forehead is preferred, then glabella,
% then malar, then cheek -- in that fixed priority order. This order was
% chosen because forehead is this project's only previously-validated
% region (see docs/Segment6_Task_N_Multi_Region_ROI.md Action 0); it is
% not a claim that forehead is more accurate in general, only the
% deterministic tie-break used when the agreement-only rule above cannot
% otherwise distinguish the regions.
%
% Ground truth is NOT used anywhere in this function -- see
% computeRegionAgreement.m for the companion cross-region spread metric,
% and scripts/run_segment6_task_n_multi_region_batch.m Action 5 for where
% ground truth is finally used, afterward, only to check whether this
% agreement-based choice tracks real accuracy.
%
% Inputs:
%   HR_forehead, HR_glabella, HR_malar, HR_cheek - vectors, per-subject HR
%       estimate (bpm) for each region, all the same length and in the
%       same subject order.
%
% Outputs:
%   HR_switched    - vector, same length/order as HR_forehead, the
%                    selected HR estimate per subject.
%   selectedRegion - cell array of char, same length/order as
%                    HR_forehead, one of 'forehead', 'glabella', 'malar',
%                    'cheek' per subject, naming which region was
%                    selected.

HR_forehead = HR_forehead(:);
HR_glabella = HR_glabella(:);
HR_malar = HR_malar(:);
HR_cheek = HR_cheek(:);

numSubjectsForehead = numel(HR_forehead);
numSubjectsGlabella = numel(HR_glabella);
numSubjectsMalar = numel(HR_malar);
numSubjectsCheek = numel(HR_cheek);

if numSubjectsForehead ~= numSubjectsGlabella || numSubjectsForehead ~= numSubjectsMalar || numSubjectsForehead ~= numSubjectsCheek
    error('computeRegionSwitchingEstimate:sizeMismatch', 'HR_forehead, HR_glabella, HR_malar, and HR_cheek must all have the same number of elements.');
end

numSubjects = numSubjectsForehead;
HR_switched = zeros(numSubjects, 1);
selectedRegion = cell(numSubjects, 1);

regionNames = {'forehead', 'glabella', 'malar', 'cheek'};

for i = 1:numSubjects
    regionValues = [HR_forehead(i), HR_glabella(i), HR_malar(i), HR_cheek(i)];
    medianHR = median(regionValues);
    distances = abs(regionValues - medianHR);
    minDistance = min(distances);
    bestRegionIdx = find(distances == minDistance, 1);

    HR_switched(i) = regionValues(bestRegionIdx);
    selectedRegion{i} = regionNames{bestRegionIdx};
end

end
