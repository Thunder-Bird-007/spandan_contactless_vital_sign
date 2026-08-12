function [hrBpmNaive, windowResults] = windowedHeartRate(pulseSignal, frameRate)
% WINDOWEDHEARTRATE Split a pulse signal into overlapping windows and run
% per-window FFT peak-search, returning each window's top-3 candidate
% peaks and a data-derived window-quality score.
%
% Pipeline stage: Stage 6 (Segment 6 Task P), a NEW entry point sitting
% alongside heartrate/fftHeartRate.m, NOT a modification of it. Both
% harmonic disambiguation (Task P Action 3) and signal-quality gating
% (Task P Action 2) need the clip split into shorter windows before they
% can do anything, so this function builds that shared prerequisite once.
% heartrate/fftHeartRate.m itself is untouched and remains callable for
% anything that still wants a single whole-clip FFT.
%
% Windowing choice (stated explicitly, not left implicit): 10-second
% windows, 50% overlap (5-second hop). 10 seconds is long enough to
% resolve the 0.7-4 Hz cardiac band at typical VIPL-HR frame rates
% (~15-30 fps -> 150-300 samples per window) while still being short
% enough that a single motion/lighting artifact does not spoil the whole
% clip's estimate. 50% overlap means every interior second of the clip is
% covered by two windows, smoothing the transition from one window's
% dominant frequency to the next -- this matters for Task P Action 3,
% which walks window-to-window and needs consecutive windows to actually
% overlap in what they're looking at.
%
% This function does NOT apply quality gating (Task P Action 2) and does
% NOT apply harmonic-continuity peak selection (Task P Action 3) -- both
% are separate steps built on top of this one's output (see
% validation/computeWindowQualityThreshold.m,
% validation/aggregateGatedWindowHR.m, and
% validation/selectHarmonicConsistentHR.m). This function only produces,
% per window: the top-3 candidate peaks (frequency + magnitude) using the
% SAME peak-search logic as fftHeartRate.m (same 0.7-4 Hz band, same
% magnitude spectrum, same FFT), and a window-quality score.
%
% Inputs:
%   pulseSignal - 1 x N vector, the SAME filtered pulse signal
%                 fftHeartRate.m already receives (CHROM/POS combined
%                 output, or a single filtered color channel).
%   frameRate   - scalar, sampling rate in Hz.
%
% Outputs:
%   hrBpmNaive    - scalar, a naive windowed baseline: the mean, across
%                   all windows, of each window's OWN tallest peak (no
%                   quality gating, no harmonic continuity). This exists
%                   so callers/reports have a clean three-way comparison:
%                   whole-clip single FFT (fftHeartRate.m) vs. this naive
%                   windowed-and-averaged baseline vs. the full
%                   gating+continuity pipeline built on windowResults.
%   windowResults - struct with fields:
%                     windowLengthSec   - scalar, 10 (stated above).
%                     overlapFraction   - scalar, 0.5 (stated above).
%                     hopSec            - scalar, 5.
%                     numWindows        - scalar, number of windows.
%                     windowStartSec    - numWindows x 1, each window's
%                                         start time in seconds.
%                     candidateFreqHz   - numWindows x 3, top-3 candidate
%                                         peak frequencies per window,
%                                         sorted by magnitude descending
%                                         (column 1 = tallest peak). NaN
%                                         where fewer than 3 local maxima
%                                         exist in-band.
%                     candidateBpm      - numWindows x 3, candidateFreqHz
%                                         converted to bpm.
%                     candidateMagnitude - numWindows x 3, each
%                                         candidate's FFT magnitude.
%                     qualityScore      - numWindows x 1, ratio of the
%                                         top peak's magnitude to the sum
%                                         of all in-band spectral energy
%                                         for that window. High for a
%                                         clean single-dominant-peak
%                                         window, low for a window whose
%                                         energy is spread across many
%                                         frequencies.

windowLengthSec = 10;
overlapFraction = 0.5;
hopSec = windowLengthSec * (1 - overlapFraction);

windowLengthSamples = round(windowLengthSec * frameRate);
hopSamples = round(hopSec * frameRate);

numSamples = length(pulseSignal);

if numSamples < windowLengthSamples
    error('windowedHeartRate:signalTooShort', 'Signal has %d samples but a %d-second window at %g Hz needs %d samples.', numSamples, windowLengthSec, frameRate, windowLengthSamples);
end

numWindows = floor((numSamples - windowLengthSamples) / hopSamples) + 1;

lowBandHz = 0.7;
highBandHz = 4.0;

windowStartSec = zeros(numWindows, 1);
candidateFreqHz = nan(numWindows, 3);
candidateBpm = nan(numWindows, 3);
candidateMagnitude = nan(numWindows, 3);
qualityScore = zeros(numWindows, 1);

for windowIdx = 1:numWindows
    startSample = (windowIdx - 1) * hopSamples + 1;
    endSample = startSample + windowLengthSamples - 1;
    windowSignal = pulseSignal(startSample:endSample);

    windowStartSec(windowIdx) = (startSample - 1) / frameRate;

    windowSignalLength = length(windowSignal);
    fftResult = fft(windowSignal);

    numPositiveBins = floor(windowSignalLength / 2) + 1;
    fftPositive = fftResult(1:numPositiveBins);

    freqResolution = frameRate / windowSignalLength;
    freqSpectrum = (0:numPositiveBins - 1) * freqResolution;
    powerSpectrum = abs(fftPositive);

    bandMask = freqSpectrum >= lowBandHz & freqSpectrum <= highBandHz;
    freqInBand = freqSpectrum(bandMask);
    powerInBand = powerSpectrum(bandMask);

    if isempty(freqInBand)
        error('windowedHeartRate:emptyBand', 'No FFT bins fall inside the 0.7-4 Hz band for window %d -- window too short for the given frameRate.', windowIdx);
    end

    numBinsInBand = numel(powerInBand);
    isLocalMax = false(1, numBinsInBand);

    for binIdx = 1:numBinsInBand
        leftOk = (binIdx == 1) || (powerInBand(binIdx) >= powerInBand(binIdx - 1));
        rightOk = (binIdx == numBinsInBand) || (powerInBand(binIdx) >= powerInBand(binIdx + 1));

        if leftOk && rightOk
            isLocalMax(binIdx) = true;
        end
    end

    localMaxFreq = freqInBand(isLocalMax);
    localMaxPower = powerInBand(isLocalMax);

    [sortedPower, sortIdx] = sort(localMaxPower, 'descend');
    sortedFreq = localMaxFreq(sortIdx);

    numCandidates = min(3, numel(sortedPower));

    for candidateIdx = 1:numCandidates
        candidateFreqHz(windowIdx, candidateIdx) = sortedFreq(candidateIdx);
        candidateMagnitude(windowIdx, candidateIdx) = sortedPower(candidateIdx);
        candidateBpm(windowIdx, candidateIdx) = sortedFreq(candidateIdx) * 60;
    end

    topPeakMagnitude = sortedPower(1);
    sumInBandEnergy = sum(powerInBand);
    qualityScore(windowIdx) = topPeakMagnitude / sumInBandEnergy;
end

windowResults = struct();
windowResults.windowLengthSec = windowLengthSec;
windowResults.overlapFraction = overlapFraction;
windowResults.hopSec = hopSec;
windowResults.numWindows = numWindows;
windowResults.windowStartSec = windowStartSec;
windowResults.candidateFreqHz = candidateFreqHz;
windowResults.candidateBpm = candidateBpm;
windowResults.candidateMagnitude = candidateMagnitude;
windowResults.qualityScore = qualityScore;

hrBpmNaive = mean(candidateBpm(:, 1));

end
