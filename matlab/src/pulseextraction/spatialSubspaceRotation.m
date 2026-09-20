function pulseSignal = spatialSubspaceRotation(Cseq, frameRate, strideFrames, winSec)
% SPATIALSUBSPACEROTATION Pulse signal via 2SR (Spatial Subspace Rotation).
%
% Segment 22 (NEW, additive) -- an ALTERNATIVE combiner alongside
% pulseextraction/chromCombine.m and posCombine.m. Replaces neither.
%
% Reference: Wang, W., Stuijk, S. & de Haan, G. (2016). "A Novel Algorithm
% for Remote Photoplethysmography: Spatial Subspace Rotation." IEEE TBME
% 63(9):1974-1984. Structure follows the authors' public reference MATLAB
% (github.com/partofthestars/Spatial-Subspace-Rotation, SpatialSubspaceRotation.m),
% generalised from its stride-1 frame pairs to a configurable stride l.
%
% METHOD: per frame t, the 3x3 skin-pixel correlation matrix C_t is
% eigendecomposed (U_t, Lambda_t, descending). With tau = t - l:
%   R  = [u_t1' * u_tau2 , u_t1' * u_tau3]            (rotation of the skin
%                                                      axis into the orthogonal plane)
%   S  = [sqrt(L_t1/L_tau2), sqrt(L_t1/L_tau3)]       (scale change)
%   SRb = (S .* R) * [u_tau2' ; u_tau3']              (1x3 back-projection, RGB)
% then per sliding window: p = SRb(:,1) - (std(SRb(:,1))/std(SRb(:,2))) * SRb(:,2),
% mean-removed, overlap-added. (The reference's tuning step, unchanged.)
%
% Deviation from the reference, stated: eigenvector sign is arbitrary, and
% u_t1 enters R linearly, so an unfixed sign flips that sample's sign at
% random. u_t1 (the skin-mean axis) is fixed to have positive component sum;
% the reference does not do this.
%
% No normalization by temporal means, no detrend/wavelet needed here: 2SR
% consumes pixel statistics directly. Callers apply bandpassClean.m then
% fftHeartRate.m to the output exactly as for CHROM/POS.
%
% Inputs:
%   Cseq         - 3 x 3 x T per-frame pixel correlation matrices
%                  (roi/extractROICovariance.m).
%   frameRate    - Hz.
%   strideFrames - l, frames between the two subspaces compared. Default
%                  round(frameRate) (~1 s; paper default is 20 frames @ 20 fps).
%   winSec       - tuning/overlap-add window, seconds. Default 3 (reference).
%
% Output:
%   pulseSignal - 1 x (T - l) vector. The first l frames have no partner
%                 subspace and are dropped, not zero-padded, so the FFT is
%                 not fed a synthetic flat lead-in. Sampling rate unchanged.

T = size(Cseq, 3);
if nargin < 3 || isempty(strideFrames), strideFrames = round(frameRate); end
if nargin < 4 || isempty(winSec), winSec = 3; end
l = max(1, round(strideFrames));
if T <= l + 4
    error('spatialSubspaceRotation:tooShort', 'Only %d frames for stride %d.', T, l);
end

U = zeros(3, 3, T);
Lam = zeros(3, T);
for t = 1:T
    [V, D] = eig((Cseq(:, :, t) + Cseq(:, :, t)') / 2);
    [d, order] = sort(diag(D), 'descend');
    V = V(:, order);
    if sum(V(:, 1)) < 0, V(:, 1) = -V(:, 1); end
    U(:, :, t) = V;
    Lam(:, t) = max(d, eps);
end

n = T - l;
SRb = zeros(n, 3);
for k = 1:n
    t = k + l;
    tau = k;
    u1 = U(:, 1, t);
    Rr = [u1' * U(:, 2, tau), u1' * U(:, 3, tau)];
    Ss = [sqrt(Lam(1, t) / Lam(2, tau)), sqrt(Lam(1, t) / Lam(3, tau))];
    SRb(k, :) = (Ss .* Rr) * [U(:, 2, tau)'; U(:, 3, tau)'];
end

w = min(n, max(8, round(winSec * frameRate)));
pulseSignal = zeros(1, n);
for s = 1:(n - w + 1)
    idx = s:(s + w - 1);
    sd2 = std(SRb(idx, 2));
    if sd2 == 0, sig = 1; else, sig = std(SRb(idx, 1)) / sd2; end
    p = SRb(idx, 1) - sig * SRb(idx, 2);
    pulseSignal(idx) = pulseSignal(idx) + (p - mean(p))';
end

end
