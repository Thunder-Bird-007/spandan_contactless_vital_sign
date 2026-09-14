function [pulseSignal, seedHz, eigVec, eigRatio, diagStruct] = cpaceEigenExtract(Rc, Gc, Bc, frameRate, bw)
% CPACEEIGENEXTRACT cPACE Stage 2 -- phase-optimal eigenvector extraction
% in the chrominance plane, per Kaur, Lakshminarayanan & Saini (2026).
%
% Pipeline stage: Segment 15 Task 1 (NEW, additive) -- an OPTIONAL stage
% callers may insert AFTER pulseextraction/cpaceProjection.m (Segment 11
% Task 1's Stage 1) and BEFORE cpaceHomodyneNormalize.m (this segment's
% Task 2 / Stage 3). Does not modify cpaceProjection.m or any DO-NOT-TOUCH
% production file -- it only consumes cpaceProjection.m's own output.
%
% Reference: Kaur, G., Lakshminarayanan, V. & Saini, S.S. (2026). "Missed
% isochromatic cardiac pulsation in remote photoplethysmography: detection,
% impact, and removal." Biomedical Optics Express 17(7):3832,
% doi:10.1364/BOE.599752 -- Section 4.2 ("Stage 2: phase-optimal
% eigenvector in the chrominance plane") for the method, Supplement 1
% Table S2 for the exact default parameter values used below. Both the
% main paper PDF and its Supplement 1 PDF are checked into this project's
% Research Paper/ folder and were read directly (not paraphrased from a
% secondary summary) to write this function.
%
% SCOPE NOTE -- READ BEFORE RELYING ON THIS AS "the paper's cPACE Stage 2":
% Section 4.2 of the paper actually describes a TWO-CANDIDATE multi-ROI
% consensus scheme -- candidate (i) "cPACE-v1" (always the dominant
% eigenvector, what this function implements) and candidate (ii)
% "cPACE-absorption" (the eigenvector with the larger projection onto the
% hemoglobin-absorption direction) -- with the final choice made per
% recording by whichever candidate yields the higher cross-ROI PLV. Table
% S2 (Supplement 1) itself only lists "Dominant (largest eigenvalue)" and
% does not mention the second candidate or the consensus step at all, so
% Table S2 alone is incomplete on this point. This function deliberately
% implements ONLY the dominant-eigenvector candidate (cPACE-v1) -- a
% project-level decision (not a paper-accuracy claim) made because (a) the
% consensus step needs multiple simultaneously-recorded ROIs per subject,
% which this project has cached for only a 20-subject VIPL v1/source1 pool
% (validation/computeCrossROIPLV.m's own pool), not the full 100-subject
% evaluation pool, and (b) it keeps this function's selection rule simple
% and auditable. See docs/Segment15_Task1_cPACE_Eigen_Extract.md for the
% full discussion. Do not describe this function's output as "the full
% cPACE method" without that caveat.
%
% METHOD (paper's Eq. 8-9 context, Table S2 "Stage 2/4" rows):
%   1. Cardiac-band preprocessing: Rc/Gc/Bc (already q_hat-projected, zero
%      mean by construction -- see cpaceProjection.m) are bandpass
%      filtered to 0.7-3.0 Hz with a 4th-order zero-phase Butterworth
%      filter (Table S2 "Cardiac frequency band" + "Bandpass filter
%      order" rows, Stage 1). NOTE: this is a SEPARATE filter from
%      filtering/bandpassClean.m (which is 0.7-4.0 Hz, order 2, built for
%      the CHROM/POS pipeline) -- reusing bandpassClean.m here would
%      silently substitute the paper's own specified band/order with a
%      different one, so this function implements its own, matching Table
%      S2 exactly, without touching bandpassClean.m.
%      Table S2's "Temporal normalization: per-channel mean division" row
%      is deliberately NOT applied here: Rc/Gc/Bc are already exactly
%      zero-mean (cpaceProjection.m's own guarantee), so dividing by their
%      own mean would divide by (numerically) zero. This mirrors the
%      caller-facing rule cpaceProjection.m's own header already
%      documents for chromCombine.m/posCombine.m's RRaw/GRaw/BRaw
%      argument.
%      Call this cardiac-band-preprocessed, still-3-channel signal x_c(t)
%      (the paper's own notation).
%   2. Seed frequency: green channel PSD peak within the cardiac band
%      (0.7-3.0 Hz), from a single FFT over the full recording (Table S2
%      "Seed source" / "Seed estimation FFT length" rows), computed on
%      x_c(t)'s green component.
%   3. Eigen-window bandpass: x_c(t) is separately bandpass filtered
%      around the seed frequency with a +/-bw Hz window (default bw =
%      0.30 Hz, Table S2 "Eigen-window half-width") using a 2nd-order
%      zero-phase Butterworth filter (this project's general narrowband
%      convention, e.g. filtering/bandpassClean.m's own 2nd-order choice)
%      -- USED ONLY to estimate the covariance/eigenvector below, per
%      Table S2's own note "Narrowband filter around seed for
%      covariance". Call this X_bp.
%   4. Covariance: Sigma = (1/T) * X_bp' * X_bp (Table S2 "Covariance
%      computation" row; paper's Eq. 8), a 3x3 matrix (rank <= 2 since
%      x_c(t), and therefore X_bp, has no energy along q_hat by
%      construction).
%   5. Eigendecompose Sigma; take the eigenvector with the LARGEST
%      eigenvalue as the cardiac direction v1 (Table S2 "Eigenvector
%      selected" row) -- no second candidate, no absorption-direction
%      geometry, no consensus voting, per the SCOPE NOTE above.
%   6. Project X_bp (the SAME seed+/-bw narrowband signal from step 3,
%      NOT the wider 0.7-3.0 Hz x_c(t) from step 1) onto v1 to get the
%      scalar cardiac waveform s(t) = v1' * X_bp.
%
%      IMPLEMENTATION NOTE -- this deviates from a first literal reading
%      of the paper's own s(t) = v1^T x_c(t) (Section 4.3, first
%      sentence), which names the wider x_c(t), and was corrected here
%      after empirical testing on Spandan's real 100-subject pool
%      (docs/Segment15_Task4_Evaluation.md): projecting the WIDE
%      (0.7-3.0 Hz) x_c(t) onto v1 and feeding that into
%      cpaceHomodyneNormalize.m's Hilbert transform produced a severe HR
%      MAE regression (~16 BPM vs. production's ~7.9 BPM), because a
%      2.3 Hz-wide signal is not close enough to monocomponent for
%      Hilbert instantaneous phase to be meaningful -- exactly the
%      narrowband precondition this project's own
%      validation/computeCrossROIPLV.m already documents in its own
%      header ("Hilbert instantaneous phase is only meaningful for a
%      signal that is already close to monocomponent"). Using the
%      already-narrowband X_bp instead (the same signal v1 was derived
%      from via PCA, a standard dominant-principal-component score) is
%      internally consistent, satisfies that precondition, and is what
%      is actually implemented and evaluated. Table S2 itself is silent
%      on which of the two signals feeds Stage 5, so this is a resolved
%      ambiguity, not a knowing deviation from an unambiguous spec.
%
% Inputs:
%   Rc, Gc, Bc - 1 x N vectors, q_hat-projected RGB traces, EXACTLY
%                cpaceProjection.m's Rc/Gc/Bc output (raw, pre-detrend,
%                pre-bandpass -- do not pre-filter before calling this).
%   frameRate  - scalar, sampling rate in Hz.
%   bw         - (optional) scalar, eigen-window half-width in Hz.
%                Defaults to 0.30 (Table S2's default). Segment 15 Task 3
%                sweeps this over {0.15, 0.30, 0.50} -- see
%                docs/Segment15_Task3_Hyperparameter_Sweep.md.
%
% Outputs:
%   pulseSignal - 1 x N vector, the scalar cardiac waveform s(t) =
%                 v1' * X_bp (the narrowband seed+/-bw signal -- see the
%                 IMPLEMENTATION NOTE in step 6 above for why this is
%                 X_bp and not the wider x_c(t)).
%   seedHz      - scalar, the estimated seed frequency (Hz), for
%                 provenance/reuse by cpaceHomodyneNormalize.m.
%   eigVec      - 3 x 1 vector, the selected (dominant) eigenvector v1.
%   eigRatio    - scalar, lambda1 / lambda2 (largest / second-largest
%                 eigenvalue of Sigma) -- a numerical sanity check
%                 (should be >> 1 when the cardiac direction genuinely
%                 dominates the chrominance-plane variance; the paper's
%                 own Fig. 4 reports an example ratio of ~392) and a
%                 useful per-subject diagnostic for Task 3/4's evaluation.
%   diagStruct  - struct with fields eigVals (3x1, ascending, from eig()),
%                 xCardiacBand (3xN, the x_c(t) used in step 6), for
%                 callers/scripts that want to inspect intermediate
%                 signals without recomputing them.

if nargin < 5 || isempty(bw)
    bw = 0.30;
end

Rc = Rc(:)';
Gc = Gc(:)';
Bc = Bc(:)';

N = numel(Rc);
if numel(Gc) ~= N || numel(Bc) ~= N
    error('cpaceEigenExtract:sizeMismatch', 'Rc, Gc, Bc must be the same length.');
end
if N < 10
    error('cpaceEigenExtract:tooShort', 'Need at least 10 samples, got %d.', N);
end

nyquistHz = frameRate / 2;

% --- Step 1: cardiac-band preprocessing (Table S2 Stage 1: 0.7-3.0 Hz,
% order 4, zero-phase). Own filter, NOT filtering/bandpassClean.m. ---
cardiacLowHz = 0.7;
cardiacHighHz = 3.0;
cardiacOrder = 4;
[bCard, aCard] = butter(cardiacOrder, [cardiacLowHz, cardiacHighHz] / nyquistHz, 'bandpass');
Rcb = filtfilt(bCard, aCard, Rc);
Gcb = filtfilt(bCard, aCard, Gc);
Bcb = filtfilt(bCard, aCard, Bc);
xCardiacBand = [Rcb; Gcb; Bcb]; % 3 x N, this is x_c(t)

% --- Step 2: seed frequency from green channel PSD peak, single FFT
% over the full recording, restricted to the cardiac band. ---
fftG = fft(Gcb);
numPositiveBins = floor(N / 2) + 1;
freqAxis = (0:numPositiveBins - 1) * (frameRate / N);
magG = abs(fftG(1:numPositiveBins));
bandMask = freqAxis >= cardiacLowHz & freqAxis <= cardiacHighHz;
if ~any(bandMask)
    error('cpaceEigenExtract:noBandBins', 'No FFT bins fall inside the 0.7-3.0 Hz cardiac band -- recording too short or frameRate too low.');
end
freqInBand = freqAxis(bandMask);
magInBand = magG(bandMask);
[~, peakIdx] = max(magInBand);
seedHz = freqInBand(peakIdx);

% --- Step 3: eigen-window bandpass around the seed, +/- bw Hz, 2nd-order
% zero-phase (this project's general narrowband-filter convention). ---
lowEigHz = max(seedHz - bw, 0.01);
highEigHz = min(seedHz + bw, nyquistHz * 0.98);
if lowEigHz >= highEigHz
    error('cpaceEigenExtract:badEigenWindow', 'Eigen-window [%.3f, %.3f] Hz is empty/inverted for seed=%.3f Hz, bw=%.3f Hz, fs=%.1f Hz.', lowEigHz, highEigHz, seedHz, bw, frameRate);
end
eigOrder = 2;
[bEig, aEig] = butter(eigOrder, [lowEigHz, highEigHz] / nyquistHz, 'bandpass');
Xbp = [filtfilt(bEig, aEig, Rcb); filtfilt(bEig, aEig, Gcb); filtfilt(bEig, aEig, Bcb)]; % 3 x N

% --- Step 4: covariance Sigma = (1/T) * X_bp' * X_bp (3x3, X_bp as T x 3). ---
Xbp3 = Xbp'; % N x 3
Sigma = (Xbp3' * Xbp3) / N;
Sigma = (Sigma + Sigma') / 2; % symmetrize away float round-off before eig()

% --- Step 5: dominant eigenvector = cardiac direction. ---
[eigVecs, eigValsMat] = eig(Sigma);
eigVals = diag(eigValsMat); % ascending order, MATLAB convention
[eigValsSorted, sortIdx] = sort(eigVals, 'descend');
eigVecsSorted = eigVecs(:, sortIdx);
eigVec = eigVecsSorted(:, 1);
lambda1 = eigValsSorted(1);
lambda2 = eigValsSorted(2);
if lambda2 > 0
    eigRatio = lambda1 / lambda2;
else
    eigRatio = Inf;
end

% --- Step 6: project the NARROWBAND signal X_bp (not the wider
% cardiac-band x_c(t)) onto v1 -- see IMPLEMENTATION NOTE above. ---
pulseSignal = (eigVec' * Xbp); % 1 x N

diagStruct = struct();
diagStruct.eigVals = eigVals;
diagStruct.xCardiacBand = xCardiacBand;

end
