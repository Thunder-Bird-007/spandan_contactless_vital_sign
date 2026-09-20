function [hrBpmFinal, stateHistory, gainHistory] = residualAdaptiveKalmanHR_exp(measurementBpm, qualityScore, opts)
% RESIDUALADAPTIVEKALMANHR_EXP  Segment 23 Task 7 copy of validation/residualAdaptiveKalmanHR.m
% with EXACTLY ONE change: the innovation-adaptive measurement noise uses the paper's Eq. 12
% EXPONENT form,  R_k = R0 * (1 + |innovation|^beta)   (Debnath & Kim 2026, PLOS ONE 21(1):e0340097)
% instead of the production port's DIVISION form  R0*(1 + |innovation|/beta).
% Everything else (random-walk state, init at window 1, quality-weighted R_eff = R_k/max(SQ,1e-3),
% scalar Kalman update, final-state output) is byte-for-byte the production logic.
% NOT implemented here (documented gaps vs the paper, out of this task's one-variable scope):
% Eq. 14 outlier replacement and Eq. 15-17 weighting x = x- + K*w*(z-x-) with w = max(alpha, SQ).
% opts.form = 'exponent' (default) | 'division' (reproduces production exactly, for the regression check).
if nargin < 3 || isempty(opts), opts = struct(); end
z = measurementBpm(:); sq = qualityScore(:); n = numel(z);
if numel(sq) ~= n, error('residualAdaptiveKalmanHR_exp:sizeMismatch', 'size mismatch'); end
if ~isfield(opts, 'form'), opts.form = 'exponent'; end
if ~isfield(opts, 'R0') || isempty(opts.R0), opts.R0 = var(z); if opts.R0 == 0, opts.R0 = 1; end, end
if ~isfield(opts, 'beta') || isempty(opts.beta), opts.beta = max(std(z), 1); end
if ~isfield(opts, 'Q') || isempty(opts.Q), opts.Q = 1; end
R0 = opts.R0; beta = opts.beta; Q = opts.Q; qualityFloor = 1e-3;
stateHistory = zeros(n, 1); gainHistory = zeros(n, 1);
x = z(1); P = R0; stateHistory(1) = x; gainHistory(1) = NaN;
for k = 2:n
    xPred = x; PPred = P + Q;
    innovation = z(k) - xPred;
    if strcmp(opts.form, 'exponent')
        Rk = R0 * (1 + abs(innovation) ^ beta);
    else
        Rk = R0 * (1 + abs(innovation) / beta);
    end
    RkEff = Rk / max(sq(k), qualityFloor);
    Kk = PPred / (PPred + RkEff);
    x = xPred + Kk * innovation; P = (1 - Kk) * PPred;
    stateHistory(k) = x; gainHistory(k) = Kk;
end
hrBpmFinal = x;
end
