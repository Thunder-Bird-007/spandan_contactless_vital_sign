function [hrBpm, muMean, freqs, muHist] = lgiStateSpaceTracker(sig, fs, opts)
% LGISTATESPACETRACKER Frequency-state Markov-chain / Gaussian-mixture HR tracker in the form of
% Pilz, Zaunseder, Krajewski & Blazek (CVPR-W 2018) Sec. 3 "The Model Space": the pulse is a stochastic
% harmonic oscillator (Eq. 25-27, dx/dt = F0(theta) x + L e, c = H x) whose frequency theta is a latent
% variable on a DISCRETE grid Omega = {theta_1..theta_S} forming a Markov chain with transition matrix Pi
% (Eq. 28-31); the solution is a Gaussian-mixture approximation of the joint posterior of (theta, x).
% Implemented as an interacting-multiple-model (IMM) bank: one Kalman filter per frequency state, weights
% updated by the innovation likelihoods and re-mixed through Pi every `mixHopSec`.
% PAPER GAPS (stated, not hidden): the paper gives NO numeric state grid, Pi, oscillator noise or
% observation noise, no window/hop for this model, and its own benchmark (Sec. 4) does NOT use this
% tracker -- it reads HR with a 256-sample / 90%-overlap FFT peak-pick (see lgiPaperReadout.m). All
% values below are therefore this implementation's own PRE-DECLARED choices, fixed before any result.
%   grid 0.7-3.0 Hz step 0.025 | Pi_ij ~ exp(-(f_i-f_j)^2/(2*0.05^2)) + 1e-3, row-normalised, applied
%   every 0.5 s | measurement noise r=0.3 (signal z-scored) | oscillator noise Q=0.005*diag(1,w^2)/sample.
% Output HR = argmax of the posterior state probability averaged over time after a 3 s burn-in.
if nargin < 3, opts = struct(); end
if ~isfield(opts, 'df'), opts.df = 0.025; end
if ~isfield(opts, 'fLo'), opts.fLo = 0.7; end
if ~isfield(opts, 'fHi'), opts.fHi = 3.0; end
if ~isfield(opts, 'sigmaPi'), opts.sigmaPi = 0.05; end
if ~isfield(opts, 'r'), opts.r = 0.3; end
if ~isfield(opts, 'qs'), opts.qs = 0.005; end
if ~isfield(opts, 'mixHopSec'), opts.mixHopSec = 0.5; end
if ~isfield(opts, 'burnSec'), opts.burnSec = 3; end
y = sig(:)'; y = (y - mean(y)) / std(y); N = numel(y);
freqs = opts.fLo:opts.df:opts.fHi; S = numel(freqs);
dt = 1 / fs; w = 2 * pi * freqs;
% discrete resonator per state: x = [c; dc/dt]
a11 = cos(w * dt); a12 = sin(w * dt) ./ w; a21 = -w .* sin(w * dt); a22 = cos(w * dt);
q11 = opts.qs * ones(1, S); q22 = opts.qs * w .^ 2;
[Fi, Fj] = meshgrid(freqs, freqs);
Pi = exp(-(Fi - Fj) .^ 2 / (2 * opts.sigmaPi ^ 2)) + 1e-3; Pi = Pi ./ sum(Pi, 2);   % Pi(i,j)=P(theta_j|theta_i)
x1 = zeros(1, S); x2 = zeros(1, S);
p11 = ones(1, S); p12 = zeros(1, S); p22 = w .^ 2;
mu = ones(1, S) / S;
mixHop = max(1, round(opts.mixHopSec * fs));
muHist = zeros(N, S, 'single'); logL = zeros(1, S);
for t = 1:N
    % predict
    nx1 = a11 .* x1 + a12 .* x2; nx2 = a21 .* x1 + a22 .* x2;
    % P' = A P A' + Q  (symmetric 2x2)
    ap11 = a11 .* p11 + a12 .* p12; ap12 = a11 .* p12 + a12 .* p22;
    ap21 = a21 .* p11 + a22 .* p12; ap22 = a21 .* p12 + a22 .* p22;
    np11 = ap11 .* a11 + ap12 .* a12 + q11;
    np12 = ap11 .* a21 + ap12 .* a22;
    np22 = ap21 .* a21 + ap22 .* a22 + q22;
    % update with scalar observation y = x1 + v
    Sv = np11 + opts.r; nu = y(t) - nx1;
    k1 = np11 ./ Sv; k2 = np12 ./ Sv;
    x1 = nx1 + k1 .* nu; x2 = nx2 + k2 .* nu;
    p11 = (1 - k1) .* np11; p12 = np12 - k1 .* np12; p22 = np22 - k2 .* np12;
    ll = -0.5 * (log(2 * pi * Sv) + nu .^ 2 ./ Sv);
    logL = logL + ll;
    % weights: mu_s propto mu_s * L_s (renormalised each sample)
    lm = log(mu + 1e-300) + ll; lm = lm - max(lm); mu = exp(lm); mu = mu / sum(mu);
    if mod(t, mixHop) == 0
        % IMM mixing through Pi
        c = mu * Pi; c = max(c, 1e-300);            % predicted mode prob
        M = (Pi .* mu(:)) ./ c;                       % M(i,j) = P(theta_i | theta_j)
        m1 = x1 * M; m2 = x2 * M;
        d1 = x1(:) - m1; d2 = x2(:) - m2;
        np11m = sum(M .* (p11(:) + d1 .^ 2), 1); np12m = sum(M .* (p12(:) + d1 .* d2), 1); np22m = sum(M .* (p22(:) + d2 .^ 2), 1);
        x1 = m1; x2 = m2; p11 = np11m; p12 = np12m; p22 = np22m; mu = c / sum(c);
    end
    muHist(t, :) = single(mu);
end
b = min(N, round(opts.burnSec * fs) + 1);
muMean = mean(double(muHist(b:end, :)), 1);
[~, ix] = max(muMean); hrBpm = 60 * freqs(ix);
end
