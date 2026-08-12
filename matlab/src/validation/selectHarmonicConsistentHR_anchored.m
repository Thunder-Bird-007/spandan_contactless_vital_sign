function [chosenBpm, overrideFired, anchorWindowIdx] = selectHarmonicConsistentHR_anchored(candidateBpm, candidateMagnitude, qualityScore)
% SELECTHARMONICCONSISTENTHR_ANCHORED Per-window harmonic disambiguation
% via temporal continuity, anchored at the clip's HIGHEST-quality window
% instead of always starting at window 1.
%
% Pipeline stage: Stage 6 (Segment 6 Task Q, Part 1). Sits alongside
% validation/selectHarmonicConsistentHR.m -- that function is NOT
% modified, both remain independently callable. This is a generic,
% post-hoc combiner over an already-computed candidateBpm /
% candidateMagnitude / qualityScore matrix (all three from
% heartrate/windowedHeartRate.m) -- it does not touch
% heartrate/windowedHeartRate.m, heartrate/fftHeartRate.m, or any
% pulse-extraction code, and it does not recompute any FFT.
%
% Motivation (Task P's diagnosed flaw): selectHarmonicConsistentHR.m
% always anchors its continuity chain at window 1, keeping window 1's
% tallest peak unconditionally. Window 1 has no way to know whether it is
% ALREADY harmonic-confused -- if the tallest peak in window 1 happens to
% be a harmonic of the true rate, every later window is pulled toward
% that wrong anchor, since the closest-to-previous rule only ever looks
% one step back. Task P found this is the dominant driver of the
% pool-level regression (60/107 subjects changed, MAE/RMSE/r all worse
% than naive windowed). This function anchors instead at whichever window
% has the HIGHEST windowedHeartRate.m quality score in the clip -- the
% window whose spectrum is most concentrated in one dominant peak, and
% therefore the window least likely to itself be harmonic-confused -- and
% propagates continuity OUTWARD from that anchor in both directions
% (forward through later windows, backward through earlier ones), instead
% of only ever running forward from window 1.
%
% Decision rule:
%   anchorWindowIdx = argmax(qualityScore) -- ties broken by the LOWEST
%       window index (MATLAB's max() default), matching this project's
%       existing tie-break discipline of preferring the earlier/simpler
%       choice when two candidates are exactly equal.
%   chosenBpm(anchorWindowIdx) = candidateBpm(anchorWindowIdx, 1) -- the
%       anchor keeps its OWN tallest peak, same as window 1 does in the
%       original (non-anchored) rule, since the anchor has no prior
%       window to constrain against either.
%   Forward pass, windowIdx = anchorWindowIdx+1 .. numWindows: same
%       closest-to-previous-chosen-bpm rule as selectHarmonicConsistentHR.m,
%       using chosenBpm(windowIdx - 1) as the reference, applied
%       independently of the backward pass.
%   Backward pass, windowIdx = anchorWindowIdx-1 .. 1 (descending): same
%       closest-to-previous-chosen-bpm rule, but "previous" here means the
%       neighbor already decided closer to the anchor, i.e.
%       chosenBpm(windowIdx + 1), applied independently of the forward
%       pass.
%   Both passes pick from the window's OWN top-3 candidates (never
%   borrowed from another window), NaN candidate slots skipped, same as
%   the original rule.
%
% Inputs:
%   candidateBpm       - numWindows x 3, from windowedHeartRate.m's
%                         windowResults.candidateBpm, column 1 = tallest
%                         peak, columns 2-3 = next-tallest, NaN-padded.
%   candidateMagnitude - numWindows x 3, from windowedHeartRate.m's
%                         windowResults.candidateMagnitude. Not used by
%                         the selection rule itself, kept as an input
%                         purely so the function signature mirrors
%                         selectHarmonicConsistentHR.m's and stays easy to
%                         extend.
%   qualityScore       - numWindows x 1, from windowedHeartRate.m's
%                         windowResults.qualityScore, used ONLY to pick
%                         the anchor window.
%
% Outputs:
%   chosenBpm       - numWindows x 1, this window's selected HR (bpm)
%                     after anchored harmonic-continuity disambiguation.
%   overrideFired   - numWindows x 1 logical, true where continuity picked
%                     a candidate OTHER than the tallest peak (column 1).
%                     Always false at the anchor window itself.
%   anchorWindowIdx - scalar, the window index the continuity chain was
%                     anchored at (the highest-quality-score window).

numWindows = size(candidateBpm, 1);
numCandidatesPerWindow = size(candidateBpm, 2);

chosenBpm = nan(numWindows, 1);
overrideFired = false(numWindows, 1);
anchorWindowIdx = 0;

if numWindows == 0
    return;
end

[~, anchorWindowIdx] = max(qualityScore);

chosenBpm(anchorWindowIdx) = candidateBpm(anchorWindowIdx, 1);
overrideFired(anchorWindowIdx) = false;

for windowIdx = (anchorWindowIdx + 1):numWindows
    previousChosenBpm = chosenBpm(windowIdx - 1);

    bestCandidateIdx = 0;
    bestDistance = Inf;

    for candidateIdx = 1:numCandidatesPerWindow
        thisCandidateBpm = candidateBpm(windowIdx, candidateIdx);

        if isnan(thisCandidateBpm)
            continue;
        end

        thisDistance = abs(thisCandidateBpm - previousChosenBpm);

        if thisDistance < bestDistance
            bestDistance = thisDistance;
            bestCandidateIdx = candidateIdx;
        end
    end

    chosenBpm(windowIdx) = candidateBpm(windowIdx, bestCandidateIdx);

    if bestCandidateIdx ~= 1
        overrideFired(windowIdx) = true;
    else
        overrideFired(windowIdx) = false;
    end
end

for windowIdx = (anchorWindowIdx - 1):-1:1
    nextChosenBpm = chosenBpm(windowIdx + 1);

    bestCandidateIdx = 0;
    bestDistance = Inf;

    for candidateIdx = 1:numCandidatesPerWindow
        thisCandidateBpm = candidateBpm(windowIdx, candidateIdx);

        if isnan(thisCandidateBpm)
            continue;
        end

        thisDistance = abs(thisCandidateBpm - nextChosenBpm);

        if thisDistance < bestDistance
            bestDistance = thisDistance;
            bestCandidateIdx = candidateIdx;
        end
    end

    chosenBpm(windowIdx) = candidateBpm(windowIdx, bestCandidateIdx);

    if bestCandidateIdx ~= 1
        overrideFired(windowIdx) = true;
    else
        overrideFired(windowIdx) = false;
    end
end

end
