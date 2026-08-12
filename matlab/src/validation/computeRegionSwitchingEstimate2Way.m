function [HR_switched, selectedRegion] = computeRegionSwitchingEstimate2Way(HR_forehead, HR_cheek)
% COMPUTEREGIONSWITCHINGESTIMATE2WAY Per-subject region-selection
% estimator between exactly two independent per-region HR estimates --
% forehead and cheek only -- using ONLY cross-region agreement, no ground
% truth.
%
% Pipeline stage: Stage 6 (validation), Task Q Part 2. Narrows
% validation/computeRegionSwitchingEstimate.m's 4-region switching rule
% down to the two regions Task N found were NOT "bad everywhere"
% (glabella and malar lost to forehead and cheek across all four Task N
% scenarios -- docs/Segment6_Task_N_Multi_Region_ROI.md Section 5b). This
% is a generic, post-hoc combiner -- it does not touch
% roi/extractROISignals.m, filtering/detrendSignal.m,
% filtering/bandpassClean.m, pulseextraction/chromCombine.m, or
% heartrate/fftHeartRate.m, and it does not recompute any HR estimate. It
% only combines two vectors of already-computed per-region HR values.
% validation/computeRegionSwitchingEstimate.m is NOT modified -- both
% remain independently callable.
%
% Decision rule, LITERALLY the same design as the 4-region switcher (per
% this task's brief): take the candidate regions' HR estimates, compute
% their median, and select the region whose estimate has the smallest
% absolute distance to that median. Ties broken forehead over cheek (same
% tie-break priority order the 4-region switcher uses, restricted to
% these two regions).
%
% ** IMPORTANT, discovered while implementing this function, reported
% here rather than silently worked around: applying the 4-region
% design's exact rule to only TWO candidates is a near-degenerate case,
% not a coding bug. In exact real-number arithmetic, for any two numbers
% a and b, median([a, b]) == mean([a, b]) == m, and the distance from a
% to m, abs(a - m) = abs((a - b) / 2), is EXACTLY equal to the distance
% from b to m, abs(b - m) = abs((b - a) / 2) -- the argmin-to-median rule
% would always tie, and the tie-break (forehead over cheek) would always
% win. An earlier version of this comment claimed that IEEE 754 floating
% point preserves this exactly (reasoning that negation only flips a sign
% bit) -- that reasoning was WRONG and was falsified by running this
% function on real data (see
% docs/Segment6_Task_Q_Anchored_Continuity_And_2Way_Switching.md Part 2):
% cheek was selected on 15-20% of subjects in every scenario, not 0%. The
% actual floating-point behavior: m is computed as fl(a + b) / 2, and
% dividing by 2 is exact in binary floating point, but the ADDITION
% fl(a + b) itself can round when a and b are not exactly representable
% together (which real-valued bpm estimates like these essentially always
% are) -- that single rounding step is enough to nudge one distance a
% hair below the other, breaking the theoretical exact tie. The practical
% upshot is unchanged in spirit even though the literal "always exactly
% forehead" claim was wrong: this rule is a de facto near-coin-flip
% between forehead and cheek whenever the two roughly agree (both
% candidates sit almost exactly equidistant from their own mean, by
% construction, for ANY two-candidate input), decided by sub-epsilon
% floating-point rounding noise in most cases rather than by any real
% per-subject signal -- it happens to land on forehead 80-85% of the time
% on this project's data (see the report above) simply because the
% tie-break favors forehead whenever the rounding noise doesn't happen to
% tip the other way, not because it is meaningfully discriminating
% between the two regions.
%
% Inputs:
%   HR_forehead, HR_cheek - vectors, per-subject HR estimate (bpm) for
%       each region, both the same length and in the same subject order.
%
% Outputs:
%   HR_switched    - vector, same length/order as HR_forehead, the
%                    selected HR estimate per subject. Per the degeneracy
%                    above, this is identical to HR_forehead for every
%                    element.
%   selectedRegion - cell array of char, same length/order as
%                    HR_forehead, either 'forehead' or 'cheek' per
%                    subject. Per the degeneracy above, this is
%                    'forehead' for every element.

HR_forehead = HR_forehead(:);
HR_cheek = HR_cheek(:);

if numel(HR_forehead) ~= numel(HR_cheek)
    error('computeRegionSwitchingEstimate2Way:sizeMismatch', 'HR_forehead and HR_cheek must have the same number of elements.');
end

numSubjects = numel(HR_forehead);
HR_switched = zeros(numSubjects, 1);
selectedRegion = cell(numSubjects, 1);

regionNames = {'forehead', 'cheek'};

for i = 1:numSubjects
    regionValues = [HR_forehead(i), HR_cheek(i)];
    medianHR = median(regionValues);
    distances = abs(regionValues - medianHR);
    minDistance = min(distances);
    bestRegionIdx = find(distances == minDistance, 1);

    HR_switched(i) = regionValues(bestRegionIdx);
    selectedRegion{i} = regionNames{bestRegionIdx};
end

end
