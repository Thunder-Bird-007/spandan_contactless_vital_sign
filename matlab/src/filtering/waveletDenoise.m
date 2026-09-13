function [sigDenoised, thresholdUsed, sigmaEstimate] = waveletDenoise(sig, waveletName, numLevels)
% WAVELETDENOISE Segment 8 (post-review follow-up), Action 4. Discrete
% wavelet transform (DWT) wavelet-shrinkage denoising via Donoho-Johnstone
% universal soft-thresholding.
%
% Pipeline stage: Branch 1 (production HR), an ADDITIVE OPTIONAL pre-step
% ahead of filtering/detrendSignal.m + filtering/bandpassClean.m -- NOT a
% replacement for either. Neither of those files, nor
% pulseextraction/chromCombine.m, pulseextraction/posCombine.m, or
% heartrate/fftHeartRate.m, is modified by this file's existence; a
% caller must explicitly insert a call to this function to use it (see
% scripts/run_segment8_task4_wavelet_ablation_batch.m for the ablation
% this was written for).
%
% Reference: Debnath & Kim, "..." PLOS ONE 2026, 21(1):e0340097 (DWT +
% residual-adaptive Kalman filtering for rPPG HR). This file implements
% only the DWT wavelet-shrinkage half of that paper (their RAKF half is
% validation/residualAdaptiveKalmanHR.m, Segment 6 Action 5, a separate
% file).
%
% WHY THIS IS EXPECTED NOT TO CARRY THE SAME HARMONIC-LOCK RISK AS
% morphology/adaptiveHarmonicFilter.m (stated as an expectation to be
% CONFIRMED by the ablation this file was written for, not assumed --
% see the batch script's own numbers): adaptiveHarmonicFilter.m needs a
% pre-estimated cardiac fundamental f0 and keeps only narrow bins around
% f0 and its harmonics -- if f0 is estimated wrong, the filter locks onto
% and reinforces the WRONG frequency (the documented Branch 1 HR
% regression that keeps Branch 1 and Branch 2 deliberately separate,
% see docs/Spandan_Final_Pipeline_Report.md). Wavelet shrinkage has no
% such dependency: it thresholds detail coefficients based purely on
% their own statistical distribution (the finest level's MAD), with no
% frequency target and no f0 estimate anywhere in the computation -- so
% there is no mechanism by which it could "lock onto" a wrong frequency
% the way a harmonic comb can.
%
% Method (Donoho-Johnstone universal soft-thresholding):
%   1. Decompose sig via numLevels-level DWT (wavedec, waveletName).
%   2. Estimate noise sigma from the FINEST-level (level 1) detail
%      coefficients' median absolute deviation:
%        sigma = median(abs(d1)) / 0.6745
%      (0.6745 is the standard MAD-to-sigma correction factor for a
%      Gaussian distribution -- the classic Donoho & Johnstone 1994
%      "WaveShrink" convention, not something re-derived here.)
%   3. Universal threshold: T = sigma * sqrt(2 * log(n)), n = numel(sig).
%   4. Soft-threshold EVERY level's detail coefficients (not just the
%      finest level -- sigma is estimated from level 1 only, per the
%      brief, but the resulting single threshold T is applied uniformly
%      across all decomposition levels, the standard single-threshold
%      universal-shrinkage convention): d -> sign(d) .* max(abs(d) - T, 0).
%   5. Leave the coarsest-level approximation coefficients untouched.
%   6. Reconstruct via inverse DWT (waverec).
%
% Inputs:
%   sig         - 1 x N vector, a raw or detrended per-frame trace (e.g.
%                 roi/extractROISignals.m's R/G/B output, BEFORE
%                 filtering/detrendSignal.m -- this function does its own
%                 statistically-driven denoising and is not a substitute
%                 for detrendSignal.m's own baseline-wander removal, so
%                 the batch this was written for calls waveletDenoise.m
%                 THEN detrendSignal.m THEN bandpassClean.m, in that
%                 order, matching this file's own "ahead of" framing
%                 above).
%   waveletName - (optional) string/char, wavelet family for wavedec/
%                 waverec. Default 'db4' (Daubechies-4, a common,
%                 reasonably compact choice for physiological signals;
%                 not re-derived/tuned here, just a standard default).
%   numLevels   - (optional) scalar, DWT decomposition depth. Default 3
%                 (matches this project's own smoke-test convention and
%                 keeps the coarsest approximation band well below the
%                 cardiac fundamental for typical video frame rates
%                 ~25-30 Hz over a >=3-level decomposition).
%
% Outputs:
%   sigDenoised    - 1 x N vector, the wavelet-shrinkage-denoised signal
%                    (same length as sig; wavedec/waverec's own internal
%                    padding is handled transparently by the toolbox and
%                    does not change the returned length).
%   thresholdUsed  - scalar, T, the universal threshold actually applied.
%   sigmaEstimate  - scalar, the MAD-based noise sigma estimate.

if nargin < 2 || isempty(waveletName)
    waveletName = 'db4';
end

if nargin < 3 || isempty(numLevels)
    numLevels = 3;
end

sigRow = sig(:)';
n = numel(sigRow);

[coeffs, bookkeeping] = wavedec(sigRow, numLevels, waveletName);

% --- Step 2: noise sigma from the FINEST-level (level 1) detail
% coefficients' MAD -- the standard Donoho-Johnstone convention. ---
d1 = detcoef(coeffs, bookkeeping, 1);
sigmaEstimate = median(abs(d1)) / 0.6745;

% --- Step 3: universal threshold. ---
thresholdUsed = sigmaEstimate * sqrt(2 * log(n));

% --- Step 4: soft-threshold every level's detail coefficients (leave the
% final-level approximation coefficients, at the head of `coeffs`,
% untouched -- bookkeeping(1) gives their count). ---
coeffsThresholded = coeffs;
approxLength = bookkeeping(1);

detailStart = approxLength + 1;
for levelPos = numLevels:-1:1
    levelLength = bookkeeping(numLevels - levelPos + 2);
    detailEnd = detailStart + levelLength - 1;

    levelDetail = coeffsThresholded(detailStart:detailEnd);
    levelDetailSoft = sign(levelDetail) .* max(abs(levelDetail) - thresholdUsed, 0);
    coeffsThresholded(detailStart:detailEnd) = levelDetailSoft;

    detailStart = detailEnd + 1;
end

% --- Step 6: reconstruct. ---
sigDenoised = waverec(coeffsThresholded, bookkeeping, waveletName);

% wavedec/waverec's internal padding can occasionally return a
% reconstruction 1 sample longer/shorter than the input for certain
% (n, numLevels, wavelet) combinations -- trim/pad defensively to
% guarantee callers always get back exactly N samples, matching every
% other filtering/*.m function's own length-preserving contract.
if numel(sigDenoised) > n
    sigDenoised = sigDenoised(1:n);
elseif numel(sigDenoised) < n
    sigDenoised = [sigDenoised, repmat(sigDenoised(end), 1, n - numel(sigDenoised))];
end

end
