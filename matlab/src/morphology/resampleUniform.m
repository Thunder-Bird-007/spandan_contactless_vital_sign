function [sigUniform, timeUniform, targetFs] = resampleUniform(sig, sigTimestamps, targetFs)
% RESAMPLEUNIFORM Resample a pulse signal onto a uniform high-rate time
% grid using its REAL per-frame timestamps.
%
% Pipeline stage: Segment 7 Task A, Action 3 (NEW, additive) — chained
% after morphology/fixPolarity.m in morphology/extractMorphologyWaveform.m,
% ahead of morphology/ensembleAverageBeats.m. Webcam frame timing is
% irregular (dropped/late frames, USB/driver jitter), so treating
% roi/extractROISignals.m's output as if it were sampled at a constant
% 1/frameRate spacing smears fine time-domain features — the dicrotic
% notch is exactly this kind of fine feature, a few tens of milliseconds
% wide. This function takes the REAL timestamps
% (roi/extractROISignals.m's roiTimestamps output) rather than assuming
% uniform spacing, and resamples onto a uniform, much higher-rate grid
% so morphology/ensembleAverageBeats.m's beat segmentation and
% two-anchor time warping have fine enough time resolution to work with.
%
% 'pchip' (shape-preserving piecewise cubic Hermite interpolation), NOT
% 'spline', is used deliberately: cubic splines can overshoot between
% samples near a sharp feature (exactly what the dicrotic notch is),
% which would FABRICATE a fake notch-like ripple that was never in the
% original signal. pchip is monotonicity-preserving between input
% samples and does not overshoot, so any notch that appears after this
% step reflects the input data, not an interpolation artifact.
%
% Inputs:
%   sig           - 1 x N vector, a pulse signal (e.g.
%                   pulseextraction/chromCombine.m's output after
%                   morphology/bandpassMorphology.m and
%                   morphology/fixPolarity.m).
%   sigTimestamps - 1 x N vector, seconds, sig's own real per-sample
%                   acquisition times (roi/extractROISignals.m's
%                   roiTimestamps output for the same subject — NOT
%                   (0:N-1)/frameRate, which would assume the uniform
%                   spacing this function exists to avoid assuming).
%   targetFs      - (optional) scalar, Hz, the uniform grid's sample
%                   rate. Defaults to 250 Hz, comfortably above any
%                   webcam frame rate this project uses (so this is
%                   genuinely upsampling, not decimating) and a round
%                   number that keeps morphology/ensembleAverageBeats.m's
%                   256-sample-per-beat resampling well within a single
%                   cardiac cycle's worth of samples even at a fast HR.
%
% Outputs:
%   sigUniform  - 1 x M vector, sig resampled onto timeUniform.
%   timeUniform - 1 x M vector, seconds, the uniform time grid actually
%                 used, spanning [sigTimestamps(1), sigTimestamps(end)].
%   targetFs    - scalar, Hz, the sample rate actually used (echoes the
%                 input if given, otherwise the 250 Hz default) so
%                 callers can record it without re-stating the default.

if nargin < 3 || isempty(targetFs)
    targetFs = 250;
end

sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';

if numel(sigRow) ~= numel(sigTimestampsRow)
    error('resampleUniform:sizeMismatch', 'sig and sigTimestamps must have the same number of elements.');
end

timeUniform = sigTimestampsRow(1):(1 / targetFs):sigTimestampsRow(end);
sigUniform = interp1(sigTimestampsRow, sigRow, timeUniform, 'pchip');

end
