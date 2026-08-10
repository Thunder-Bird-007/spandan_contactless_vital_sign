function [HR_switched, usedPos] = computeSwitchingEstimate(HR_chrom, HR_pos, disagreementThreshold)
% COMPUTESWITCHINGESTIMATE Per-subject switching estimator between two
% independent HR estimates, gated by CHROM/POS relative disagreement.
%
% Pipeline stage: Stage 6 (validation), Task J. This is a generic,
% post-hoc combiner -- it does not touch pulseextraction/chromCombine.m,
% pulseextraction/posCombine.m, or heartrate/fftHeartRate.m, and it does
% not recompute any HR estimate. It only combines two vectors of
% already-computed HR values.
%
% Motivation: Segment6_Refinement_Notes.md Task I found that relative
% disagreement between CHROM and POS is a real, moderate predictor of
% CHROM error (Pearson r = +0.588 across the full N=112 pool) and derived
% a data-driven low-confidence threshold of 29.27% relative disagreement
% from a natural gap in the sorted disagreement distribution. Task I also
% found that, at the full pool, POS has lower MAE/RMSE than CHROM
% overall, while CHROM is slightly more accurate specifically on the
% subjects where the two methods already agree. This function turns that
% finding into a per-subject decision rule: trust CHROM when the two
% methods agree, fall back to POS when they diverge beyond the threshold.
%
% The threshold value itself is NOT hardcoded in this function -- it must
% be passed in by the caller, sourced from Task I's stored 29.27% value
% (see docs/Segment6_Refinement_Notes.md Task I Section 1 and
% scripts/run_segment6_task_i_agreement.m). This keeps the threshold
% choice visible at the call site rather than buried in this function.
%
% Decision rule (per subject i), using the SAME relative-disagreement
% formula as computeAgreementConfidence.m:
%   relativeDisagreement(i) = abs(HR_chrom(i) - HR_pos(i)) / mean([HR_chrom(i), HR_pos(i)])
%   if relativeDisagreement(i) < disagreementThreshold
%       HR_switched(i) = HR_chrom(i)
%   else
%       HR_switched(i) = HR_pos(i)
%   end
%
% Inputs:
%   HR_chrom              - vector, CHROM HR estimate (bpm) per subject.
%   HR_pos                - vector, POS HR estimate (bpm) per subject,
%                            same order as HR_chrom.
%   disagreementThreshold - scalar, the relative-disagreement cutoff as a
%                            FRACTION (not percentage), e.g. 0.2927 for
%                            Task I's 29.27% threshold. Passed explicitly
%                            by the caller, not hardcoded here.
%
% Outputs:
%   HR_switched - vector, same length/order as HR_chrom, the switched HR
%                 estimate per subject (either HR_chrom(i) or HR_pos(i)).
%   usedPos     - logical vector, same length/order as HR_chrom, true for
%                 subjects where HR_pos was selected (the switch fired),
%                 false where HR_chrom was kept.

HR_chrom = HR_chrom(:);
HR_pos = HR_pos(:);

if numel(HR_chrom) ~= numel(HR_pos)
    error('computeSwitchingEstimate:sizeMismatch', 'HR_chrom and HR_pos must have the same number of elements.');
end

numSubjects = numel(HR_chrom);
HR_switched = zeros(numSubjects, 1);
usedPos = false(numSubjects, 1);

for i = 1:numSubjects
    pairMean = mean([HR_chrom(i), HR_pos(i)]);
    relativeDisagreement = abs(HR_chrom(i) - HR_pos(i)) / pairMean;

    if relativeDisagreement < disagreementThreshold
        HR_switched(i) = HR_chrom(i);
        usedPos(i) = false;
    else
        HR_switched(i) = HR_pos(i);
        usedPos(i) = true;
    end
end

end
