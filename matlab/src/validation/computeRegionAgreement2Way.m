function relativeSpread = computeRegionAgreement2Way(HR_forehead, HR_cheek)
% COMPUTEREGIONAGREEMENT2WAY Per-subject relative spread between exactly
% two independent per-region HR estimates -- forehead and cheek only.
%
% Pipeline stage: Stage 6 (validation), Task Q Part 2. Narrows
% validation/computeRegionAgreement.m's 4-region agreement metric down to
% the two regions Task N found NOT "bad everywhere" (glabella and malar
% were worse than forehead and cheek across all four Task N scenarios --
% see docs/Segment6_Task_N_Multi_Region_ROI.md Section 5b). This is a
% generic, post-hoc agreement metric -- it does not touch
% roi/extractROISignals.m, filtering/detrendSignal.m,
% filtering/bandpassClean.m, pulseextraction/chromCombine.m, or
% heartrate/fftHeartRate.m, and it does not recompute any HR estimate. It
% only compares two vectors of already-computed per-region HR values.
% validation/computeRegionAgreement.m is NOT modified -- both remain
% independently callable.
%
% Formula, per subject i):
%   relativeSpread(i) = abs(HR_forehead(i) - HR_cheek(i)) / mean([HR_forehead(i), HR_cheek(i)])
%
% This is algebraically the SAME formula as computeRegionAgreement.m's
% (max - min) / median specialized down to exactly two values: for two
% numbers a and b, median([a, b]) == mean([a, b]), and
% max([a, b]) - min([a, b]) == abs(a - b), so the two formulas agree
% exactly, not just in spirit. It is also the same 2-way disagreement
% formula validation/computeAgreementConfidence.m and
% validation/computeSwitchingEstimate.m already use for CHROM/POS (Task
% I/J), applied here to forehead/cheek instead.
%
% Inputs:
%   HR_forehead, HR_cheek - vectors, per-subject HR estimate (bpm) for
%       each region, both the same length and in the same subject order.
%
% Outputs:
%   relativeSpread - vector, same length/order as HR_forehead, the
%                    fraction (not percentage) of forehead/cheek spread
%                    for each subject.

HR_forehead = HR_forehead(:);
HR_cheek = HR_cheek(:);

if numel(HR_forehead) ~= numel(HR_cheek)
    error('computeRegionAgreement2Way:sizeMismatch', 'HR_forehead and HR_cheek must have the same number of elements.');
end

numSubjects = numel(HR_forehead);
relativeSpread = zeros(numSubjects, 1);

for i = 1:numSubjects
    pairMean = mean([HR_forehead(i), HR_cheek(i)]);
    relativeSpread(i) = abs(HR_forehead(i) - HR_cheek(i)) / pairMean;
end

end
