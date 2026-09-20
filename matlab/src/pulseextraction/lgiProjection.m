function pulseSignal = lgiProjection(R, G, B)
% LGIPROJECTION Local-Group-Invariance projection step (LGI, projection only).
%
% Segment 22 (NEW, additive), Stage 4 of the brief: the projection half of
% Pilz, Zaunseder, Krajewski & Blazek (2018), "Local Group Invariance for
% Heart Rate Estimation from Face Videos in the Wild", CVPR Workshops. The
% state-space HR tracker is NOT implemented (brief: only if this alone does
% not help). Formulation follows the common reference form (pyVHR's LGI):
%   X = [R; G; B] (3 x T, raw, uncentered)
%   s = first left singular vector of X (dominant skin/illumination direction)
%   P = I - s*s'
%   BVP = second row of P*X (green row of the projected signal)
%
% NOTE for readers: s is nearly the temporal-mean direction that
% cpaceProjection.m (Segment 11) already projects out, so this is expected to
% behave like cPACE Stage 1 + a single green row, NOT like CHROM/POS
% (no chrominance ratio combination). Segment 11/15 already evaluated
% cPACE Stage 1 ahead of CHROM/POS and did not adopt it.
%
% Inputs: R, G, B - 1 x N raw (optionally wavelet-denoised) traces.
% Output: pulseSignal - 1 x N (still needs detrend + bandpass, as production).

X = [R(:)'; G(:)'; B(:)'];
[U, ~, ~] = svd(X, 'econ');
s = U(:, 1);
Y = (eye(3) - s * s') * X;
pulseSignal = Y(2, :);
end
