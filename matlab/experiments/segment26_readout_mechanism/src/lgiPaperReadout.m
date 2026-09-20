function hrBpm = lgiPaperReadout(sig, fs, bandHz)
% LGIPAPERREADOUT The HR read-out Pilz et al. (CVPR-W 2018, Sec. 4 Experiments) ACTUALLY used to benchmark
% LGI against ICA/SSR/POS: "band-filtered in the range between 0.5 and 2.0 Hz ... standard Fourier based
% spectral method with windows size of 256 samples and overlap of 90 percent. A maximum peak energy
% criterion is applied over the spectral traces". Per-clip scalar HR = median of the per-window peaks
% (the paper reports spectrogram traces, not a scalar; the median is this task's choice).
% Deviation in the estimator's favour: 4x zero-padded FFT (paper: bare 256-sample FFT, ~7 bpm bins at 30 fps).
if nargin < 3 || isempty(bandHz), bandHz = [0.5 2.0]; end
[b, a] = butter(2, bandHz / (fs / 2));
x = filtfilt(b, a, sig(:)');
L = 256; hop = round(0.1 * L); N = numel(x);
if N < L, L = N; hop = max(1, round(0.1 * L)); end
nfft = 4 * 256; hw = hann(L)';
freqs = (0:nfft/2) * fs / nfft; m = freqs >= bandHz(1) & freqs <= bandHz(2);
pk = [];
for s = 1:hop:(N - L + 1)
    seg = x(s:s + L - 1) .* hw; F = abs(fft(seg - mean(seg), nfft)); F = F(1:nfft/2 + 1);
    fm = freqs(m); Fm = F(m); [~, i] = max(Fm); pk(end + 1) = fm(i); %#ok<AGROW>
end
hrBpm = 60 * median(pk);
end
