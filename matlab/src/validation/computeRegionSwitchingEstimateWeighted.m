function [HR_switched, selectedRegion, usedStandout] = computeRegionSwitchingEstimateWeighted(HR_forehead, HR_glabella, HR_malar, HR_cheek)
% COMPUTEREGIONSWITCHINGESTIMATEWEIGHTED Exploratory pilot (Spandan Field
% Guide "still open" list), Action 3. NEW function ALONGSIDE (does not
% replace) validation/computeRegionSwitchingEstimate.m and
% computeRegionSwitchingEstimate2Way.m -- both remain unchanged and
% independently callable. Ground truth is NOT used anywhere in this
% function, same no-leakage discipline as the two functions above.
%
% Motivation (see docs/Segment6_Task_N_Multi_Region_ROI.md Section 5): the
% existing 4-region switcher picks forehead 70-80% of the time regardless
% of scenario (argmin distance-to-unweighted-median-of-four), which is why
% it under-performs the best single region in 2 of 4 scenarios (v1, v4) --
% it mostly just inherits forehead's own error pattern and only
% occasionally substitutes a noisier glabella/malar estimate. This pilot
% tries two changes to the DECISION RULE only (no change to
% roi/extractROISignals.m's region geometry or any upstream HR
% computation):
%
%   (a) STANDOUT CHECK FIRST. If one region is already clearly closer to
%       the OTHER THREE regions' own median than the overall four-region
%       spread would suggest is coincidental, just take it directly --
%       don't force a vote when there's nothing to vote about. For each
%       region i: otherMedian_i = median of the other three regions'
%       values; d_i = |HR_i - otherMedian_i|. spread = max(HR_all) -
%       min(HR_all) (the four-region range). If spread > 0 and
%       min(d_i)/spread < STANDOUT_RATIO, that region is a "clear
%       standout" and is selected directly. STANDOUT_RATIO = 0.15 is a
%       CHOSEN threshold for this pilot (not derived from this project's
%       own data distribution) -- stated explicitly as a design choice to
%       revisit, not a validated cutoff.
%   (b) WEIGHTED FALLBACK VOTE. When no standout exists, don't fall back
%       to the unweighted argmin-to-median-of-four rule (that is exactly
%       the rule that picks forehead 70-80% of the time per the doc's own
%       Section 4 counts). Instead compute a WEIGHTED center that leans
%       toward forehead and cheek -- the two regions Task N/Q found are
%       "not bad everywhere" (glabella/malar lost to forehead/cheek across
%       all four Task N scenarios, per
%       computeRegionSwitchingEstimate2Way.m's own header) -- by
%       duplicating forehead and cheek's values in the list the median is
%       taken over: weightedList = [forehead, forehead, cheek, cheek,
%       glabella, malar], weightedCenter = median(weightedList) (mean of
%       the 3rd/4th sorted values of that 6-element list). The region
%       actually selected is still whichever of the four ORIGINAL
%       estimates lands closest to that weighted center (same
%       argmin-distance selection structure as the existing switcher,
%       just against a different center point) -- so the output is always
%       one of the four real per-region HR values, never an interpolated
%       number, same contract as computeRegionSwitchingEstimate.m.
%
% Tie-break (both branches): forehead, then cheek, then glabella, then
% malar -- reordered from the original function's forehead>glabella>
% malar>cheek priority to put cheek second, matching this pilot's own
% forehead/cheek-favoring premise; only matters on an exact tie, which is
% rare with real bpm values (same floating-point-rounding observation
% computeRegionSwitchingEstimate2Way.m's header already documents).
%
% Inputs:
%   HR_forehead, HR_glabella, HR_malar, HR_cheek - vectors, per-subject HR
%       estimate (bpm) for each region, all the same length and in the
%       same subject order (identical contract to
%       computeRegionSwitchingEstimate.m).
%
% Outputs:
%   HR_switched    - vector, same length/order as HR_forehead, the
%                    selected HR estimate per subject.
%   selectedRegion - cell array of char, same length/order as
%                    HR_forehead, one of 'forehead', 'glabella', 'malar',
%                    'cheek' per subject.
%   usedStandout   - logical vector, same length/order as HR_forehead,
%                    true where the standout branch (a) fired for that
%                    subject, false where the weighted-vote fallback (b)
%                    fired instead -- kept so the two branches' behavior
%                    can be audited separately, not just the combined
%                    result.

HR_forehead = HR_forehead(:);
HR_glabella = HR_glabella(:);
HR_malar = HR_malar(:);
HR_cheek = HR_cheek(:);

numSubjectsForehead = numel(HR_forehead);
numSubjectsGlabella = numel(HR_glabella);
numSubjectsMalar = numel(HR_malar);
numSubjectsCheek = numel(HR_cheek);

if numSubjectsForehead ~= numSubjectsGlabella || numSubjectsForehead ~= numSubjectsMalar || numSubjectsForehead ~= numSubjectsCheek
    error('computeRegionSwitchingEstimateWeighted:sizeMismatch', 'HR_forehead, HR_glabella, HR_malar, and HR_cheek must all have the same number of elements.');
end

STANDOUT_RATIO = 0.15;

numSubjects = numSubjectsForehead;
HR_switched = zeros(numSubjects, 1);
selectedRegion = cell(numSubjects, 1);
usedStandout = false(numSubjects, 1);

% Tie-break priority: forehead, cheek, glabella, malar (see header).
regionNames = {'forehead', 'cheek', 'glabella', 'malar'};

for i = 1:numSubjects
    valForehead = HR_forehead(i);
    valGlabella = HR_glabella(i);
    valMalar = HR_malar(i);
    valCheek = HR_cheek(i);

    regionValuesInPriorityOrder = [valForehead, valCheek, valGlabella, valMalar];
    allValues = [valForehead, valGlabella, valMalar, valCheek];
    spread = max(allValues) - min(allValues);

    % --- (a) Standout check: each region's distance to the OTHER THREE's
    % own median. ---
    otherMedianForehead = median([valGlabella, valMalar, valCheek]);
    otherMedianCheek = median([valForehead, valGlabella, valMalar]);
    otherMedianGlabella = median([valForehead, valMalar, valCheek]);
    otherMedianMalar = median([valForehead, valGlabella, valCheek]);

    distToOthersInPriorityOrder = [
        abs(valForehead - otherMedianForehead), ...
        abs(valCheek - otherMedianCheek), ...
        abs(valGlabella - otherMedianGlabella), ...
        abs(valMalar - otherMedianMalar)
    ];

    [minDist, minDistIdx] = min(distToOthersInPriorityOrder);

    if spread > 0 && (minDist / spread) < STANDOUT_RATIO
        HR_switched(i) = regionValuesInPriorityOrder(minDistIdx);
        selectedRegion{i} = regionNames{minDistIdx};
        usedStandout(i) = true;
        continue
    end

    % --- (b) No standout: weighted-vote fallback, forehead/cheek
    % double-weighted. ---
    weightedList = [valForehead, valForehead, valCheek, valCheek, valGlabella, valMalar];
    weightedCenter = median(weightedList);

    distToWeightedCenter = abs(regionValuesInPriorityOrder - weightedCenter);
    minDistanceWeighted = min(distToWeightedCenter);
    bestRegionIdx = find(distToWeightedCenter == minDistanceWeighted, 1);

    HR_switched(i) = regionValuesInPriorityOrder(bestRegionIdx);
    selectedRegion{i} = regionNames{bestRegionIdx};
    usedStandout(i) = false;
end

end
