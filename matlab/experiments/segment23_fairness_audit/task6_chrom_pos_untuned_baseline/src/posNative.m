function H = posNative(R, G, B, fs)
% POSNATIVE POS exactly per Wang, den Brinker, Stuijk, de Haan, IEEE TBME 2017 (Algorithm 1),
% read from the TUE preprint: l = 32 frames @20fps = 1.6 s (scaled to fs), per-window temporal
% normalisation C/mu(C), projection [0 1 -1; -2 1 1], h = S1 + sigma(S1)/sigma(S2)*S2, zero-mean
% overlap-add with the window sliding ONE frame. NO band-pass, NO detrend ("even the commonly used
% band-pass filtering is not used" -- paper Sec. IV.B). Input = RAW ROI-mean traces.
C = [R(:)'; G(:)'; B(:)']; N = size(C, 2);
l = round(1.6 * fs); H = zeros(1, N);
P = [0 1 -1; -2 1 1];
for n = l:N
    m = n - l + 1;
    W = C(:, m:n);
    Cn = W ./ mean(W, 2);
    S = P * Cn;
    s2 = std(S(2, :));
    if s2 == 0, continue, end
    h = S(1, :) + (std(S(1, :)) / s2) * S(2, :);
    H(m:n) = H(m:n) + (h - mean(h));
end
end
