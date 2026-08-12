function [signalDetrended, detrendOrder] = detrendSignal(signalRaw, polyOrder)
% DETRENDSIGNAL Remove slow drift/trend from a raw ROI color-channel signal.
%
% Pipeline stage: Stage 2 (detrend + bandpass filter) — runs before
% bandpassClean.m to remove illumination drift and other slow, non-
% physiological trends from R(t)/G(t)/B(t) prior to bandpass filtering.
%
% Inputs:
%   signalRaw - 1 x N vector, a single raw channel signal (e.g. G(t) from
%               roi/extractROISignals.m).
%   polyOrder - scalar, optional, the polynomial order to fit and remove.
%               Defaults to 3, the order this project has used since
%               Segment 2 -- omitting this argument reproduces the exact
%               original behavior of this function (see Segment 6 Task O,
%               docs/Segment6_Task_O_Detrend_And_Adaptive_Bandpass.md, for
%               the regression check confirming this).
%
% Outputs:
%   signalDetrended - 1 x N vector, same length, with slow trend removed.
%   detrendOrder    - scalar, the polynomial order used to fit and remove
%                     the trend. Returned (not just used internally) so
%                     callers such as scripts/run_segment3_filtering_batch.m
%                     can record it alongside the filtered signal for
%                     later auditing, without needing to re-read this file.

if nargin < 2
    polyOrder = 3;
end

detrendOrder = polyOrder;
signalDetrended = detrend(signalRaw, detrendOrder);

end
