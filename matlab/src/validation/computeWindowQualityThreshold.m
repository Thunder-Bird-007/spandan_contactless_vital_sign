function [qualityThreshold, diagnostics] = computeWindowQualityThreshold(pooledQualityScores)
% COMPUTEWINDOWQUALITYTHRESHOLD Data-derived low-quality cutoff for
% heartrate/windowedHeartRate.m's per-window quality score, found from a
% natural gap in the score distribution.
%
% Pipeline stage: Stage 6 (Segment 6 Task P, Action 2, threshold half).
% This is a generic, post-hoc threshold finder over an already-computed
% pooled vector of quality scores -- it does not touch
% heartrate/windowedHeartRate.m and does not recompute any FFT. No
% quality cutoff is hardcoded anywhere in this project's Task P code; this
% function is the one place that decides it, and it decides it from the
% data's own distribution, same discipline as
% run_segment6_task_i_agreement.m's 29.27% relative-disagreement
% threshold (see that script's "Threshold justification" section for the
% same largest-gap-vs-second-largest-gap reasoning applied here).
%
% Method: sort the pooled quality scores ascending, compute the gap
% between every pair of consecutive sorted values, and take the LARGEST
% gap as the natural knee separating a low-quality cluster from a
% high-quality cluster -- UNLESS that largest gap isolates only a single
% score at one end of the distribution (a lone outlier, too small a
% sample to generalize a cutoff from), in which case the SECOND-largest
% gap is used instead, exactly as run_segment6_task_i_agreement.m does.
%
% Inputs:
%   pooledQualityScores - vector, windowedHeartRate.m's
%                          windowResults.qualityScore values POOLED across
%                          every window of every subject being processed
%                          in the current run (not just one clip) -- a
%                          single clip's handful of windows is too few
%                          points to find a reliable knee in.
%
% Outputs:
%   qualityThreshold - scalar, the chosen cutoff. A window with
%                       qualityScore >= qualityThreshold is kept; a window
%                       with qualityScore < qualityThreshold is treated as
%                       low-quality (see validation/aggregateGatedWindowHR.m
%                       for how that is then used to exclude windows).
%   diagnostics      - struct with fields: n, minScore, medianScore,
%                       maxScore, largestGapValue, largestGapLowerBound,
%                       usedSecondLargestGap (logical, true if the
%                       lone-outlier fallback fired), chosenGapValue.

pooledQualityScores = pooledQualityScores(:);
sortedScores = sort(pooledQualityScores);
n = numel(sortedScores);

if n < 3
    error('computeWindowQualityThreshold:tooFewScores', 'Need at least 3 pooled quality scores to find a natural gap, got %d.', n);
end

numGaps = n - 1;
gapValues = zeros(numGaps, 1);

for i = 1:numGaps
    gapValues(i) = sortedScores(i + 1) - sortedScores(i);
end

[largestGapValue, largestGapPos] = max(gapValues);
numAboveLargestGap = n - largestGapPos;
numAtOrBelowLargestGap = largestGapPos;

usedSecondLargestGap = false;

if numAboveLargestGap <= 1 || numAtOrBelowLargestGap <= 1
    gapValuesForSecondPass = gapValues;
    gapValuesForSecondPass(largestGapPos) = -Inf;
    [secondLargestGapValue, secondLargestGapPos] = max(gapValuesForSecondPass);

    chosenGapPos = secondLargestGapPos;
    chosenGapValue = secondLargestGapValue;
    usedSecondLargestGap = true;
else
    chosenGapPos = largestGapPos;
    chosenGapValue = largestGapValue;
end

qualityThreshold = sortedScores(chosenGapPos + 1);

diagnostics = struct();
diagnostics.n = n;
diagnostics.minScore = sortedScores(1);
diagnostics.medianScore = median(sortedScores);
diagnostics.maxScore = sortedScores(end);
diagnostics.largestGapValue = largestGapValue;
diagnostics.largestGapLowerBound = sortedScores(largestGapPos);
diagnostics.usedSecondLargestGap = usedSecondLargestGap;
diagnostics.chosenGapValue = chosenGapValue;

end
