function relativeDisagreement = computeAgreementConfidence(HR_chrom, HR_pos)
% COMPUTEAGREEMENTCONFIDENCE Per-subject relative disagreement between two
% independent HR estimates from the same underlying signal.
%
% Pipeline stage: Stage 6 (validation), Task I. This is a generic,
% post-hoc agreement metric -- it does not touch pulseextraction/
% chromCombine.m, pulseextraction/posCombine.m, or heartrate/
% fftHeartRate.m, and it does not recompute any HR estimate. It only
% compares two vectors of already-computed HR values.
%
% Motivation: Segment6_Refinement_Notes.md Task H1 found that on the
% worst-error subject p21, CHROM misread the true rate by roughly 2x
% (a harmonic-confusion pattern) while POS read the same underlying
% signal correctly. When two independently-derived estimates of the same
% physiological signal diverge sharply, that divergence is itself a
% usable low-confidence signal, even without knowing which estimate (if
% either) is correct. This function only computes the raw per-subject
% disagreement; thresholding it into a low-confidence flag is a separate,
% explicit step (see scripts/run_segment6_task_i_agreement.m) so the
% threshold choice stays visible rather than buried in this function.
%
% Formula (per subject i):
%   relativeDisagreement(i) = abs(HR_chrom(i) - HR_pos(i)) / mean([HR_chrom(i), HR_pos(i)])
%
% Inputs:
%   HR_chrom - vector, CHROM HR estimate (bpm) per subject.
%   HR_pos   - vector, POS HR estimate (bpm) per subject, same order as
%              HR_chrom.
%
% Outputs:
%   relativeDisagreement - vector, same length/order as HR_chrom, the
%                          fraction (not percentage) of disagreement
%                          between the two estimates for each subject.

HR_chrom = HR_chrom(:);
HR_pos = HR_pos(:);

if numel(HR_chrom) ~= numel(HR_pos)
    error('computeAgreementConfidence:sizeMismatch', 'HR_chrom and HR_pos must have the same number of elements.');
end

numSubjects = numel(HR_chrom);
relativeDisagreement = zeros(numSubjects, 1);

for i = 1:numSubjects
    pairMean = mean([HR_chrom(i), HR_pos(i)]);
    relativeDisagreement(i) = abs(HR_chrom(i) - HR_pos(i)) / pairMean;
end

end
