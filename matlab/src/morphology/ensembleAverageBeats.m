function [prototype, iqrBand, beatMatrix, stats] = ensembleAverageBeats(sig, fs, opts)
% ENSEMBLEAVERAGEBEATS Segment a pulse signal into individual cardiac
% cycles, time-align them, and coherently average — the core deliverable
% of Segment 7 Task A.
%
% Pipeline stage: Segment 7 Task A, Action 4 (NEW, additive) — runs after
% morphology/resampleUniform.m in morphology/extractMorphologyWaveform.m.
% Single-beat SNR at 30 fps is too low to show a dicrotic notch at all,
% independent of any filtering choice (see
% docs/Segment7_Task_A_Morphology_Pipeline.md, cause 3) — this function
% is the fix: average many time-aligned beats together so uncorrelated
% noise partially cancels while the (repeating, phase-locked) notch
% shape reinforces. The per-sample spread ACROSS the aligned beats
% (iqrBand below) is this project's quantitative answer to "how stable
% is the waveform beat-to-beat", which is what the supervisor asked for
% at the progress presentation — a number he can be shown, not a shape
% he has to judge by eye.
%
% Inputs:
%   sig  - 1 x N vector, a pulse signal already on a UNIFORM time grid
%          (morphology/resampleUniform.m's output) — this function
%          assumes uniform sample spacing 1/fs and reconstructs its own
%          time axis as (0:N-1)/fs accordingly.
%   fs   - scalar, sample rate of sig in Hz (morphology/resampleUniform.m's
%          targetFs, typically 250 Hz).
%   opts - (optional) struct, any subset of:
%            beatSamples            - scalar, samples per resampled beat.
%                                      Default 256.
%            systolicAnchorFraction - scalar in (0,1), target cycle
%                                      fraction for the systolic peak
%                                      after time-warping. Default 0.25.
%            durationRejectFraction - scalar, reject a raw beat if its
%                                      duration deviates from the median
%                                      inter-beat interval by more than
%                                      this fraction. Default 0.30.
%            qualityKeepFraction    - scalar in (0,1], fraction of
%                                      duration-surviving beats kept by
%                                      the correlation-based quality
%                                      gate. Default 0.25.
%            trimPercent            - scalar, percent argument passed to
%                                      trimmean() (20 -> a 10% trimmed
%                                      mean, i.e. 10% trimmed from each
%                                      tail). Default 20.
%
% Outputs:
%   prototype - struct with fields:
%                 trimmedMean - 1 x beatSamples vector,
%                               trimmean(beatMatrix, trimPercent, 1).
%                 median      - 1 x beatSamples vector,
%                               median(beatMatrix, 1).
%               Both are returned (not just one) per the Segment 7 Task A
%               brief, so scripts/run_segment7_morphology_batch.m can
%               compare them directly rather than this function silently
%               picking one.
%   iqrBand   - struct with fields:
%                 q1                 - 1 x beatSamples vector, per-sample
%                                       25th percentile across the final
%                                       (post-quality-gate) beat matrix.
%                 q3                 - 1 x beatSamples vector, per-sample
%                                       75th percentile.
%                 width              - 1 x beatSamples vector, q3 - q1 —
%                                       this IS the "beat-to-beat
%                                       stability" curve.
%                 meanWidth          - scalar, mean(width) — a single
%                                       stability number.
%                 meanWidthNormalized - scalar, meanWidth divided by the
%                                       trimmed-mean prototype's own
%                                       peak-to-peak amplitude, i.e. a
%                                       unit-free stability score
%                                       comparable across subjects/
%                                       conditions with different
%                                       absolute pulse-signal amplitudes.
%   beatMatrix - numFinalBeats x beatSamples matrix, the FINAL aligned
%                beats actually averaged into prototype (i.e. after both
%                the duration gate and the two-pass correlation quality
%                gate) — returned so callers can overlay individual
%                beats on the prototype for a sanity-check figure.
%   stats      - struct with fields: beatsFound (raw zero-crossing
%                count), beatsRejectedByDuration, beatsRejectedByQuality,
%                beatsAveraged (== size(beatMatrix, 1)), snrGainEstimate
%                (sqrt(beatsAveraged), the theoretical coherent-averaging
%                SNR improvement factor over a single beat).

if nargin < 3 || isempty(opts)
    opts = struct();
end

opts = applyDefault(opts, 'beatSamples', 256);
opts = applyDefault(opts, 'systolicAnchorFraction', 0.25);
opts = applyDefault(opts, 'durationRejectFraction', 0.30);
opts = applyDefault(opts, 'qualityKeepFraction', 0.25);
opts = applyDefault(opts, 'trimPercent', 20);

sigRow = sig(:)';
N = numel(sigRow);
timeAxis = (0:N - 1) / fs;

% --- Step 1: segment beats on the negative-going zero crossing of the
% zero-mean signal (the steepest-downslope point) -- NOT on peaks, which
% are flat/noisy near the maximum and give much worse temporal precision.
sigZeroMean = sigRow - mean(sigRow);

crossingTimes = [];
for i = 1:(N - 1)
    if sigZeroMean(i) >= 0 && sigZeroMean(i + 1) < 0
        frac = sigZeroMean(i) / (sigZeroMean(i) - sigZeroMean(i + 1));
        crossingTimes(end + 1) = timeAxis(i) + frac * (timeAxis(i + 1) - timeAxis(i)); %#ok<AGROW>
    end
end

numBeatsFound = numel(crossingTimes) - 1;

if numBeatsFound < 3
    error('ensembleAverageBeats:tooFewBeats', 'Only %d beat(s) found from negative-going zero crossings -- need at least 3 to form an ensemble average.', max(numBeatsFound, 0));
end

% --- Step 2: reject beats whose duration deviates more than
% durationRejectFraction from the median inter-beat interval.
beatDurations = diff(crossingTimes);
medianDuration = median(beatDurations);

durationOkMask = abs(beatDurations - medianDuration) / medianDuration <= opts.durationRejectFraction;
beatsRejectedByDuration = sum(~durationOkMask);

survivingBeatIdx = find(durationOkMask);
numSurviving = numel(survivingBeatIdx);

if numSurviving < 2
    error('ensembleAverageBeats:tooFewBeatsAfterDurationGate', 'Only %d beat(s) survived the duration gate -- need at least 2 to form an ensemble average.', numSurviving);
end

% --- Step 3: resample each surviving beat to beatSamples samples
% (shape-preserving pchip, same reasoning as morphology/resampleUniform.m).
beatSamples = opts.beatSamples;
beatMatrixResampled = zeros(numSurviving, beatSamples);

for rowIdx = 1:numSurviving
    k = survivingBeatIdx(rowIdx);
    t0 = crossingTimes(k);
    t1 = crossingTimes(k + 1);
    queryTimes = linspace(t0, t1, beatSamples);
    beatMatrixResampled(rowIdx, :) = interp1(timeAxis, sigRow, queryTimes, 'pchip');
end

% --- Step 4: two-anchor time warping -- stretch each beat so its
% systolic peak lands at exactly systolicAnchorFraction of the cycle.
% Single-anchor (onset-only) alignment leaves the peak wherever each
% individual beat happens to put it, which lets beat-to-beat variation
% smear the notch (which sits just after the peak) across tens of
% milliseconds and erase it from the average entirely.
targetFrac = linspace(0, 1, beatSamples);
origFrac = linspace(0, 1, beatSamples);
peakAnchorFrac = opts.systolicAnchorFraction;

beatMatrixWarped = zeros(numSurviving, beatSamples);

for rowIdx = 1:numSurviving
    beatValues = beatMatrixResampled(rowIdx, :);
    [~, peakIdx] = max(beatValues);
    peakFracOrig = origFrac(peakIdx);

    if peakFracOrig <= 0 || peakFracOrig >= 1
        % Degenerate case: peak sits at the very first/last sample, the
        % piecewise-linear warp below is undefined (divide by zero).
        % Leave this beat un-warped rather than fabricate a mapping --
        % the quality gate in Step 5 is expected to down-weight it anyway
        % since an edge-sitting peak is itself a sign of a poorly formed
        % beat.
        beatMatrixWarped(rowIdx, :) = beatValues;
        continue
    end

    newFrac = zeros(1, beatSamples);
    firstLeg = origFrac <= peakFracOrig;
    secondLeg = ~firstLeg;

    newFrac(firstLeg) = origFrac(firstLeg) * (peakAnchorFrac / peakFracOrig);
    newFrac(secondLeg) = peakAnchorFrac + (origFrac(secondLeg) - peakFracOrig) * ((1 - peakAnchorFrac) / (1 - peakFracOrig));

    beatMatrixWarped(rowIdx, :) = interp1(newFrac, beatValues, targetFrac, 'pchip');
end

% --- Step 5: two-pass quality gate -- average all surviving (warped)
% beats into a rough template, correlate each beat against it, keep the
% top qualityKeepFraction by correlation, re-average.
roughTemplate = mean(beatMatrixWarped, 1);

correlations = zeros(numSurviving, 1);
for rowIdx = 1:numSurviving
    correlations(rowIdx) = pearsonCorrRow(beatMatrixWarped(rowIdx, :), roughTemplate);
end

[~, sortOrder] = sort(correlations, 'descend');
numKeep = max(1, ceil(numSurviving * opts.qualityKeepFraction));
keepIdx = sortOrder(1:numKeep);

beatsRejectedByQuality = numSurviving - numKeep;

beatMatrix = beatMatrixWarped(keepIdx, :);

% --- Step 6: combine with BOTH a trimmed mean and a median.
prototype = struct();
prototype.trimmedMean = trimmean(beatMatrix, opts.trimPercent, 1);
prototype.median = median(beatMatrix, 1);

% --- Step 7: per-sample IQR across the final aligned beat matrix -- the
% quantitative "beat-to-beat stability" measure.
q1 = zeros(1, beatSamples);
q3 = zeros(1, beatSamples);

for colIdx = 1:beatSamples
    q1(colIdx) = localPercentile(beatMatrix(:, colIdx), 25);
    q3(colIdx) = localPercentile(beatMatrix(:, colIdx), 75);
end

iqrBand = struct();
iqrBand.q1 = q1;
iqrBand.q3 = q3;
iqrBand.width = q3 - q1;
iqrBand.meanWidth = mean(iqrBand.width);

prototypeRange = max(prototype.trimmedMean) - min(prototype.trimmedMean);
if prototypeRange > 0
    iqrBand.meanWidthNormalized = iqrBand.meanWidth / prototypeRange;
else
    iqrBand.meanWidthNormalized = NaN;
end

% --- Step 8: stats.
stats = struct();
stats.beatsFound = numBeatsFound;
stats.beatsRejectedByDuration = beatsRejectedByDuration;
stats.beatsRejectedByQuality = beatsRejectedByQuality;
stats.beatsAveraged = size(beatMatrix, 1);
stats.snrGainEstimate = sqrt(stats.beatsAveraged);

end

function opts = applyDefault(opts, fieldName, defaultValue)
if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
    opts.(fieldName) = defaultValue;
end
end

function r = pearsonCorrRow(x, y)
% Manual Pearson correlation between two row vectors of equal length,
% matching validation/computeMetrics.m's manual approach (no Statistics
% Toolbox dependency).
xc = x - mean(x);
yc = y - mean(y);
r = sum(xc .* yc) / sqrt(sum(xc.^2) * sum(yc.^2));
end

function p = localPercentile(columnData, percentile)
% Manual percentile (linear interpolation between order statistics,
% MATLAB prctile's default convention) -- avoids a hard Statistics
% Toolbox dependency for a single, simple calculation.
sortedData = sort(columnData(:));
n = numel(sortedData);

if n == 1
    p = sortedData(1);
    return
end

position = 1 + (percentile / 100) * (n - 1);
lowerIdx = floor(position);
upperIdx = ceil(position);
weight = position - lowerIdx;

p = sortedData(lowerIdx) * (1 - weight) + sortedData(upperIdx) * weight;
end
