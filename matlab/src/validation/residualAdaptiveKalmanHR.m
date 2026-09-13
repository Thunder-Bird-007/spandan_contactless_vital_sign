function [hrBpmFinal, stateHistory, gainHistory] = residualAdaptiveKalmanHR(measurementBpm, qualityScore, opts)
% RESIDUALADAPTIVEKALMANHR Segment 6 Action 5 (RAKF) -- residual/quality-
% adaptive Kalman smoothing over a per-window HR measurement sequence,
% built on heartrate/windowedHeartRate.m's output -- the SAME
% prerequisite Task P/Q's continuity-based methods use, for a fair
% head-to-head comparison.
%
% Reference: Debnath & Kim, PLOS ONE 2026, 21(1):e0340097 (DWT +
% residual-adaptive Kalman filtering for rPPG HR). This file implements
% only the RAKF half of that paper (the DWT half is
% filtering/waveletDenoise.m, Segment 8 Action 4, a separate file).
% IMPORTANT HONESTY NOTE: this implements the MECHANISM the paper
% describes (random-walk state model, residual-adaptive measurement-noise
% covariance, signal-quality-weighted update) as summarized in this
% project's handoff -- it is NOT a verbatim reproduction of the paper's
% own Eq. 9-18 (not independently available to check numeric constants
% against), the same distinction this project already draws for
% morphology/adaptiveHarmonicFilter.m ("a direct port" only where the
% source was actually read). Treat the exact R0/beta/Q defaults below as
% this implementation's own reasonable, data-derived choices, not values
% copied from the paper.
%
% Model:
%   State (random walk):     x_k = x_{k-1} + w_k,  w_k ~ N(0, Q)
%   Measurement:              z_k = x_k + v_k,      v_k ~ N(0, R_k)
%   Residual-adaptive R_k:    e_k = z_k - x_k^predicted (innovation)
%                              R_k = R0 * (1 + |e_k| / beta)
%                              -- a measurement far from the current
%                              prediction is trusted LESS (inflated
%                              noise), the direct "residual-adaptive"
%                              mechanism named in the brief.
%   Quality-weighted update:  R_k_effective = R_k / max(qualityScore(k), eps)
%                              -- a low windowedHeartRate.m quality score
%                              (spectral energy spread across many bins,
%                              not concentrated in one peak) further
%                              inflates the effective noise, so a
%                              confidently-wrong window (Task Q's p21
%                              failure mode: a clean-looking harmonic)
%                              is NOT specially protected by this
%                              mechanism -- unlike Task Q's anchor choice,
%                              RAKF has no way to know a window's peak is
%                              a harmonic rather than the true rate; it
%                              only knows how far that window's answer is
%                              from the running estimate and how spectrally
%                              clean that window looked. This is stated
%                              up front as a predicted limitation to check
%                              against Task Q's own p21 finding, not
%                              assumed to be fixed by this filter.
%   Standard scalar Kalman update (gain/covariance) from there.
%
% Inputs:
%   measurementBpm - numWindows x 1, the raw per-window HR measurement
%                    sequence (heartrate/windowedHeartRate.m's
%                    windowResults.candidateBpm(:,1), i.e. each window's
%                    own tallest peak -- the same raw input Task P/Q's
%                    naive-windowed baseline averages, so this function's
%                    output is directly comparable to that baseline and
%                    to the continuity-based methods built on the same
%                    windows).
%   qualityScore   - numWindows x 1, heartrate/windowedHeartRate.m's
%                    windowResults.qualityScore.
%   opts           - (optional) struct, any subset of:
%                      R0   - scalar, base measurement-noise variance
%                             (bpm^2). Default: var(measurementBpm) (the
%                             sequence's own empirical spread -- a
%                             data-derived floor, not a hardcoded
%                             constant, matching this project's standing
%                             no-hardcoded-threshold discipline).
%                      beta - scalar, residual-adaptivity scale (bpm).
%                             Default: max(std(measurementBpm), 1) (also
%                             data-derived; floored at 1 bpm so a
%                             near-constant measurement sequence doesn't
%                             produce a degenerate beta near 0).
%                      Q    - scalar, process noise variance (bpm^2) per
%                             5-second hop. Default: 1 (a small, physically
%                             plausible per-hop HR drift budget -- real
%                             HR does not typically jump more than ~1 bpm
%                             variance in 5 seconds at rest; NOT re-derived
%                             from the paper, this implementation's own
%                             reasonable choice, stated as such).
%
% Outputs:
%   hrBpmFinal   - scalar, the filter's FINAL state estimate x_N (after
%                  processing every window) -- this subject's RAKF HR.
%   stateHistory - numWindows x 1, the filtered state x_k after each
%                  window (for diagnostic plotting).
%   gainHistory  - numWindows x 1, the Kalman gain K_k applied at each
%                  window (for diagnostic plotting -- high gain means the
%                  filter trusted that window's measurement heavily).

if nargin < 3 || isempty(opts)
    opts = struct();
end

measurementBpmRow = measurementBpm(:);
qualityScoreRow = qualityScore(:);
numWindows = numel(measurementBpmRow);

if numel(qualityScoreRow) ~= numWindows
    error('residualAdaptiveKalmanHR:sizeMismatch', 'measurementBpm and qualityScore must have the same number of elements.');
end

if ~isfield(opts, 'R0') || isempty(opts.R0)
    opts.R0 = var(measurementBpmRow);
    if opts.R0 == 0
        opts.R0 = 1; % degenerate constant-sequence guard
    end
end

if ~isfield(opts, 'beta') || isempty(opts.beta)
    opts.beta = max(std(measurementBpmRow), 1);
end

if ~isfield(opts, 'Q') || isempty(opts.Q)
    opts.Q = 1;
end

R0 = opts.R0;
beta = opts.beta;
Q = opts.Q;
qualityFloor = 1e-3;

stateHistory = zeros(numWindows, 1);
gainHistory = zeros(numWindows, 1);

% --- Initialize at window 1's own measurement (no prior to filter
% against yet), same "window 1 has no predecessor" convention Task P/Q's
% own continuity methods use. ---
x = measurementBpmRow(1);
P = R0;
stateHistory(1) = x;
gainHistory(1) = NaN; % no update performed at window 1

for k = 2:numWindows
    % --- Predict (random walk: state itself doesn't move, only its
    % uncertainty grows). ---
    xPred = x;
    PPred = P + Q;

    % --- Residual-adaptive + quality-weighted measurement noise. ---
    innovation = measurementBpmRow(k) - xPred;
    Rk = R0 * (1 + abs(innovation) / beta);
    RkEffective = Rk / max(qualityScoreRow(k), qualityFloor);

    % --- Standard scalar Kalman update. ---
    Kk = PPred / (PPred + RkEffective);
    x = xPred + Kk * innovation;
    P = (1 - Kk) * PPred;

    stateHistory(k) = x;
    gainHistory(k) = Kk;
end

hrBpmFinal = x;

end
