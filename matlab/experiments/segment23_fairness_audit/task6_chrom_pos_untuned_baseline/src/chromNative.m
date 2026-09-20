function S = chromNative(R, G, B, fs, bandHz)
% CHROMNATIVE CHROM per de Haan & Jeanne, IEEE TBME 2013, in its windowed overlap-add form.
% PARAMETER PROVENANCE (stated honestly): the primary paper is paywalled/unreadable from this
% environment [BLOCKED]. Structure/values used: Xs=3Rn-2Gn, Ys=1.5Rn+Gn-1.5Bn, alpha=std(Xf)/std(Yf),
% S=Xf-alpha*Yf (these match the project's own chromCombine.m and the POS paper's description);
% 1.6 s Hann-weighted windows with 50% overlap-add and a Butterworth band-pass on Xs/Ys per window
% are taken from the McDuff iphys-toolbox reference implementation (a SECONDARY source, VERIFIED-INDEX
% quality) -- its 3rd-order filter is used. Default band = 40-240 BPM (0.667-4 Hz), the generic
% pulse-rate range stated by the POS paper (primary, Sec. V); bandHz=[0.7 2.5] reproduces
% iphys's literal cutoffs (secondary, internally inconsistent with its own '40-240 BPM' comment).
% Skin-tone standardisation is realised as per-window mean normalisation (Rn=R/mean(R)-1), the
% common white-balanced form; the paper's fixed constants [0.7682 0.5121 0.3841] are not used.
if nargin < 5 || isempty(bandHz), bandHz = [40 240] / 60; end
C = [R(:)'; G(:)'; B(:)']; N = size(C, 2);
l = ceil(1.6 * fs); if mod(l, 2), l = l + 1; end
hop = l / 2; win = hann(l)';
[b, a] = butter(3, bandHz / (fs / 2));
S = zeros(1, N);
for m = 1:hop:(N - l + 1)
    e = m + l - 1;
    W = C(:, m:e);
    Cn = W ./ mean(W, 2) - 1;
    Xs = 3 * Cn(1, :) - 2 * Cn(2, :);
    Ys = 1.5 * Cn(1, :) + Cn(2, :) - 1.5 * Cn(3, :);
    Xf = filtfilt(b, a, Xs); Yf = filtfilt(b, a, Ys);
    sy = std(Yf); if sy == 0, continue, end
    S(m:e) = S(m:e) + (Xf - (std(Xf) / sy) * Yf) .* win;
end
end
