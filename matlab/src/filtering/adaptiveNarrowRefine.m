function [hrRefined, signalNarrowFiltered, filterOrder] = adaptiveNarrowRefine(signalDetrended, frameRate, roughHrBpm)
% ADAPTIVENARROWREFINE Two-stage adaptive bandpass refinement, Pass 2.
%
% Pipeline stage: Stage 2b (OPTIONAL, additive) — runs AFTER the existing
% Pass 1 pipeline (filtering/detrendSignal.m -> filtering/bandpassClean.m
% -> pulseextraction/chromCombine.m or posCombine.m ->
% heartrate/fftHeartRate.m) has already produced a rough HR estimate. This
% function is a NEW, separate file, not a modification to
% bandpassClean.m -- the existing wide-band (0.7-4 Hz) filter stays
% completely untouched and every existing script that calls it is
% unaffected. Segment 6 Task O introduced this function; see
% docs/Segment6_Task_O_Detrend_And_Adaptive_Bandpass.md for the
% original-vs-refined comparison run against the v1 VIPL-HR pool.
%
% Pass 2 logic: build a narrow Butterworth bandpass centered on the rough
% HR estimate, +/- 15 bpm (converted to Hz), using the same filtfilt
% zero-phase approach as bandpassClean.m, apply it to the ALREADY-
% detrended signal (the same input bandpassClean.m itself would have
% received), then call heartrate/fftHeartRate.m again on the narrow-
% filtered result for a refined HR estimate.
%
% The narrow band is clamped to stay inside fftHeartRate.m's own 0.7-4 Hz
% search band. Without this clamp, a rough estimate near the edge of the
% physiological range (e.g. 45 bpm -0.25 Hz -> below 0.7 Hz) could produce
% a narrow band that falls entirely outside 0.7-4 Hz, which would make
% fftHeartRate.m raise fftHeartRate:emptyBand on a perfectly valid signal.
% Clamping keeps this function's own physiological band assumption
% identical to fftHeartRate.m's, rather than introducing a second,
% inconsistent one.
%
% Inputs:
%   signalDetrended - 1 x N vector, the ALREADY-detrended signal (output
%                     of filtering/detrendSignal.m), NOT the wide-band
%                     filtered signal -- Pass 2 builds its own bandpass
%                     from the detrended signal directly, same starting
%                     point bandpassClean.m itself uses.
%   frameRate       - scalar, sampling rate of the signal in Hz.
%   roughHrBpm      - scalar, the Pass 1 HR estimate (bpm) to center the
%                     narrow band on.
%
% Outputs:
%   hrRefined            - scalar, refined HR estimate (bpm) from
%                           fftHeartRate.m run on the narrow-filtered
%                           signal.
%   signalNarrowFiltered - 1 x N vector, the narrow-bandpass-filtered
%                           signal, returned for plotting/debugging.
%   filterOrder          - scalar, the Butterworth order passed to
%                           butter() (same convention as
%                           bandpassClean.m's filterOrder output).

filterOrder = 2;
halfWidthHz = 15 / 60;
lowBandHz = 0.7;
highBandHz = 4.0;

roughHrHz = roughHrBpm / 60;
lowCutoffHz = roughHrHz - halfWidthHz;
highCutoffHz = roughHrHz + halfWidthHz;

if lowCutoffHz < lowBandHz
    lowCutoffHz = lowBandHz;
end

if highCutoffHz > highBandHz
    highCutoffHz = highBandHz;
end

nyquistHz = frameRate / 2;
lowCutoffNormalized = lowCutoffHz / nyquistHz;
highCutoffNormalized = highCutoffHz / nyquistHz;

[filterCoeffB, filterCoeffA] = butter(filterOrder, [lowCutoffNormalized, highCutoffNormalized], 'bandpass');
signalNarrowFiltered = filtfilt(filterCoeffB, filterCoeffA, signalDetrended);

[hrRefined, ~, ~] = fftHeartRate(signalNarrowFiltered, frameRate);

end
