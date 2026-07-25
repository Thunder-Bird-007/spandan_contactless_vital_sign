function signalDetrended = detrendSignal(signalRaw)
% DETRENDSIGNAL Remove slow drift/trend from a raw ROI color-channel signal.
%
% Pipeline stage: Stage 2 (detrend + bandpass filter) — runs before
% bandpassClean.m to remove illumination drift and other slow, non-
% physiological trends from R(t)/G(t)/B(t) prior to bandpass filtering.
%
% Inputs:
%   signalRaw - 1 x N vector, a single raw channel signal (e.g. G(t) from
%               roi/extractROISignals.m).
%
% Outputs:
%   signalDetrended - 1 x N vector, same length, with slow trend removed.

error('Not implemented yet — see docs/');

end
