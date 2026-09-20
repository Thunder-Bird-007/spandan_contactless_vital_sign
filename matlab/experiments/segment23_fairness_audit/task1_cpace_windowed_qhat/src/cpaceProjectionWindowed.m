function [Rc, Gc, Bc, info] = cpaceProjectionWindowed(R, G, B, fs, winSec, hopSec)
% CPACEPROJECTIONWINDOWED Segment 23 Task 1 variant of pulseextraction/cpaceProjection.m in which
% q_hat = normalised temporal mean of (R,G,B) is re-estimated PER SLIDING WINDOW (default 10 s window,
% 5 s hop, windowedHeartRate.m's convention) instead of once over the whole clip. Each window's
% samples are projected with P_w = I - q_w q_w'; overlapping windows are cross-faded with a sin^2
% weight and normalised by the weight sum (partition of unity), giving one continuous corrected trace.
% Clips shorter than one window fall back to the single global estimate (flagged in info.fallback).
% NOTE: Kaur et al.'s Table S2 lists q_hat as a per-ROI "unit vector along temporal mean of (R,G,B)"
% and describes it as the "(static) mean skin reflectance direction"; it does NOT specify a
% sliding-window q_hat. This function tests the fairness hypothesis, not a paper-native form.
if nargin < 5, winSec = 10; end
if nargin < 6, hopSec = 5; end
X = [R(:)'; G(:)'; B(:)']; N = size(X, 2);
L = round(winSec * fs); hop = max(1, round(hopSec * fs));
info.fallback = false; info.numWindows = 0; info.angleDeg = [];
if N < L
    [Rc, Gc, Bc] = cpaceProjection(R, G, B); info.fallback = true; return
end
starts = 1:hop:(N - L + 1);
if starts(end) + L - 1 < N, starts(end + 1) = N - L + 1; end
acc = zeros(3, N); wsum = zeros(1, N);
w = sin(pi * ((1:L) - 0.5) / L) .^ 2;
axis0 = [1; 1; 1] / sqrt(3); ang = zeros(1, numel(starts));
for k = 1:numel(starts)
    idx = starts(k):(starts(k) + L - 1);
    q = mean(X(:, idx), 2); q = q / norm(q);
    Y = X(:, idx) - q * (q' * X(:, idx));
    acc(:, idx) = acc(:, idx) + Y .* w;
    wsum(idx) = wsum(idx) + w;
    ang(k) = acosd(max(-1, min(1, dot(q, axis0))));
end
Xc = acc ./ wsum;
Rc = Xc(1, :); Gc = Xc(2, :); Bc = Xc(3, :);
info.numWindows = numel(starts); info.angleDeg = ang;
end
