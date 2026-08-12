function [chosenBpm, overrideFired] = selectHarmonicConsistentHR(candidateBpm, candidateMagnitude)
% SELECTHARMONICCONSISTENTHR Per-window harmonic disambiguation via
% temporal continuity, built on heartrate/windowedHeartRate.m's per-window
% top-3 candidate peaks.
%
% Pipeline stage: Stage 6 (Segment 6 Task P, Action 3). This is a
% generic, post-hoc combiner over an already-computed candidateBpm /
% candidateMagnitude matrix -- it does not touch heartrate/
% windowedHeartRate.m, heartrate/fftHeartRate.m, or any pulse-extraction
% code, and it does not recompute any FFT.
%
% Motivation: a whole-clip single FFT (and a naive per-window
% tallest-peak choice) can lock onto a harmonic of the true pulse
% frequency -- e.g. VIPL_p21/v1/forehead's CHROM estimate of ~127 bpm
% against a true 68 bpm, roughly 1.9x the real rate. A harmonic peak can
% legitimately be the tallest peak in an isolated 10-second window, but
% the true pulse rate does not jump by ~2x between two overlapping,
% temporally adjacent windows of the same clip. Constraining each
% window's choice to be consistent with its immediate predecessor uses
% that physiological continuity to break the tie in favor of the
% non-harmonic candidate when the tallest peak disagrees sharply with
% where the signal was a moment ago.
%
% Decision rule (per window w):
%   w == 1: chosenBpm(1) = candidateBpm(1, 1) -- the tallest peak, same
%           as current (non-continuity) behavior, since there is no prior
%           window to constrain against.
%   w  > 1: chosenBpm(w) = whichever of candidateBpm(w, 1:3) (this
%           window's own top-3, from windowedHeartRate.m -- NOT candidates
%           pulled from any other window) is numerically closest to
%           chosenBpm(w - 1). NaN candidate slots (fewer than 3 local
%           maxima were found in that window) are skipped. This is NOT
%           automatically the tallest peak.
%
% Inputs:
%   candidateBpm       - numWindows x 3, from windowedHeartRate.m's
%                         windowResults.candidateBpm, column 1 = tallest
%                         peak, columns 2-3 = next-tallest, NaN-padded.
%   candidateMagnitude - numWindows x 3, from windowedHeartRate.m's
%                         windowResults.candidateMagnitude. Not used by
%                         the selection rule itself (continuity looks only
%                         at candidateBpm), kept as an input purely so the
%                         function signature mirrors windowedHeartRate.m's
%                         two parallel outputs and stays easy to extend.
%
% Outputs:
%   chosenBpm     - numWindows x 1, this window's selected HR (bpm) after
%                   harmonic-continuity disambiguation.
%   overrideFired - numWindows x 1 logical, true where continuity picked
%                   a candidate OTHER than the tallest peak (column 1),
%                   i.e. where harmonic disambiguation actually changed
%                   the outcome versus naive tallest-peak selection. Always
%                   false for window 1.

numWindows = size(candidateBpm, 1);
numCandidatesPerWindow = size(candidateBpm, 2);

chosenBpm = nan(numWindows, 1);
overrideFired = false(numWindows, 1);

if numWindows == 0
    return;
end

chosenBpm(1) = candidateBpm(1, 1);
overrideFired(1) = false;

for windowIdx = 2:numWindows
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

end
