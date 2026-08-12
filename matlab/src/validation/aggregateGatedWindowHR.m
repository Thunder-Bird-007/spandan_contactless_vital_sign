function [finalHrBpm, numUsed, numExcluded, allWindowsExcludedFallback] = aggregateGatedWindowHR(chosenBpm, qualityScore, qualityThreshold)
% AGGREGATEGATEDWINDOWHR Quality-gate a clip's per-window HR choices and
% collapse the surviving windows into one final per-clip HR estimate.
%
% Pipeline stage: Stage 6 (Segment 6 Task P, Action 2, gating half). This
% is a generic, post-hoc combiner over an already-computed per-window
% chosenBpm/qualityScore pair -- it does not touch
% heartrate/windowedHeartRate.m, validation/selectHarmonicConsistentHR.m,
% or validation/computeWindowQualityThreshold.m, and does not recompute
% any FFT.
%
% Design decision -- EXCLUDE, not downweight: a window's quality score is
% low when its spectral energy is spread across many frequencies rather
% than concentrated in one dominant peak, which this project treats as
% "this window's HR reading is close to arbitrary noise," not "this
% window's HR reading is a fainter, partially-trustworthy version of the
% true rate." Downweighting still lets that near-arbitrary value pull the
% weighted average away from the true rate every time it disagrees with
% the clean windows; hard exclusion keeps the final estimate built only
% from windows whose own spectrum says they actually found a dominant
% pulse frequency. This mirrors the confidence-gating precedent already
% in this project (run_segment6_task_i_agreement.m Part 3c excludes
% low-confidence subjects outright rather than downweighting them).
%
% Inputs:
%   chosenBpm        - numWindows x 1, one HR value per window (e.g. from
%                       validation/selectHarmonicConsistentHR.m, or the
%                       naive tallest-peak-per-window column of
%                       windowedHeartRate.m's windowResults.candidateBpm).
%   qualityScore      - numWindows x 1, from windowedHeartRate.m's
%                       windowResults.qualityScore, same window order as
%                       chosenBpm.
%   qualityThreshold  - scalar, from
%                       validation/computeWindowQualityThreshold.m. A
%                       window is KEPT when qualityScore >=
%                       qualityThreshold.
%
% Outputs:
%   finalHrBpm                 - scalar, mean of chosenBpm across the
%                                 kept (>= threshold) windows.
%   numUsed                    - scalar, number of windows kept.
%   numExcluded                - scalar, number of windows excluded.
%   allWindowsExcludedFallback - logical, true if every window in this
%                                 clip fell below qualityThreshold. When
%                                 true, finalHrBpm falls back to the mean
%                                 of ALL windows (excluding none) rather
%                                 than returning NaN, and the caller
%                                 should disp() this so it is visible
%                                 which clips hit the fallback.

chosenBpm = chosenBpm(:);
qualityScore = qualityScore(:);

if numel(chosenBpm) ~= numel(qualityScore)
    error('aggregateGatedWindowHR:sizeMismatch', 'chosenBpm and qualityScore must have the same number of elements.');
end

numWindows = numel(chosenBpm);
keepMask = false(numWindows, 1);

for windowIdx = 1:numWindows
    if qualityScore(windowIdx) >= qualityThreshold
        keepMask(windowIdx) = true;
    end
end

numUsed = sum(keepMask);
numExcluded = numWindows - numUsed;

if numUsed == 0
    allWindowsExcludedFallback = true;
    finalHrBpm = mean(chosenBpm);
else
    allWindowsExcludedFallback = false;
    finalHrBpm = mean(chosenBpm(keepMask));
end

end
