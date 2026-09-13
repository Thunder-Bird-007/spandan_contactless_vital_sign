function [pulseNormalized, envelope, envelopeSlow, instPhase] = cpaceHomodyneNormalize(pulseSignal, frameRate, fenv, kappa)
% CPACEHOMODYNENORMALIZE cPACE Stage 3 -- homodyne amplitude
% normalization, per Kaur, Lakshminarayanan & Saini (2026).
%
% Pipeline stage: Segment 15 Task 2 (NEW, additive) -- an OPTIONAL stage
% callers insert AFTER cpaceEigenExtract.m (this segment's Task 1 /
% Stage 2). Does not modify any DO-NOT-TOUCH production file -- it only
% consumes cpaceEigenExtract.m's own scalar pulseSignal output.
%
% STRUCTURAL NOTE (do not skip this stage): the paper's own ablation
% (main text Section 5.2 "cPACE-no-homodyne") found Stage 2 alone, without
% this Stage 3, performs catastrophically worse than POS -- this is a
% structural pairing, not an optional refinement. Segment 15's evaluation
% (docs/Segment15_Task4_Evaluation.md) only ever tests the combined
% Stage1+2+3 pipeline for this reason.
%
% Reference: Kaur, G., Lakshminarayanan, V. & Saini, S.S. (2026). "Missed
% isochromatic cardiac pulsation in remote photoplethysmography: detection,
% impact, and removal." Biomedical Optics Express 17(7):3832,
% doi:10.1364/BOE.599752 -- Section 4.3 ("Stage 3: in-band noise
% suppression"), Eq. 9, and Supplement 1 Table S2 ("Stage 5: Homodyne
% envelope" rows) for the exact default parameters below. Both PDFs are
% checked into this project's Research Paper/ folder and were read
% directly for this implementation.
%
% METHOD:
%   The paper's Eq. 9 (main text, kappa implicit = 1):
%     s_clean(t) = (A(t) / A_slow(t)) * cos(phi(t))
%   where A(t)/phi(t) are the Hilbert-transform instantaneous
%   envelope/phase of the (re-)bandpass-filtered pulseSignal, and
%   A_slow(t) is A(t) lowpass-filtered at fenv = 0.30 Hz to isolate the
%   slow respiratory/vasomotor amplitude modulation.
%
%   Table S2 (Supplement 1) separately lists a "Gate exponent kappa"
%   parameter, default value 2, "Stage 5: Homodyne envelope", described
%   as an "Exponent applied to envelope magnitude" -- a parameter Eq. 9's
%   own printed form in the main text does not show. This function
%   therefore implements the GENERALIZED form
%     gate(t)     = (A(t) / A_slow(t))^kappa
%     s_clean(t)  = gate(t) * cos(phi(t))
%   which reduces EXACTLY to the main text's Eq. 9 at kappa = 1, and
%   matches Table S2's own default (kappa = 2) -- the value the
%   supplement states "produce[s] all results reported in the main
%   paper". This is the most literal reading of the two source documents
%   together that is consistent with both; it is an interpretation (the
%   main text does not itself show the exponent), documented here rather
%   than silently assumed. See docs/Segment15_Task2_cPACE_Homodyne.md.
%
%   Steps:
%     1. Re-bandpass pulseSignal to the cardiac band (0.7-3.0 Hz, 4th
%        order zero-phase Butterworth -- same Table S2 Stage 1 band/order
%        cpaceEigenExtract.m uses) per Section 4.3's own description
%        ("The signal after projection to the cardiac direction is
%        bandpass filtered to the cardiac band"). In practice this is
%        close to a no-op since pulseSignal is already a linear
%        combination of channels cpaceEigenExtract.m already
%        cardiac-band-filtered, but it is applied for literal fidelity to
%        the paper's own described sequence.
%     2. Hilbert transform -> analytic signal -> envelope A(t) = abs(.),
%        phase phi(t) = angle(.).
%     3. Lowpass A(t) at fenv Hz (2nd-order zero-phase Butterworth, this
%        project's general lowpass convention) -> A_slow(t).
%     4. Demodulate: gate(t) = (A(t) ./ A_slow(t)) .^ kappa; reconstruct
%        s_clean(t) = gate(t) .* cos(phi(t)).
%
% Inputs:
%   pulseSignal - 1 x N vector, cpaceEigenExtract.m's scalar cardiac
%                 waveform output (or any comparable scalar pulse signal).
%   frameRate   - scalar, sampling rate in Hz.
%   fenv        - (optional) scalar, envelope lowpass cutoff in Hz.
%                 Defaults to 0.30 (Table S2's default). Per this
%                 segment's Task 3 brief, the paper's own sweep found
%                 negligible sensitivity to this parameter (0.03-0.18 BPM
%                 MAE swing over {0.15,0.30,0.50,0.70} Hz) -- not
%                 re-swept here for that reason.
%   kappa       - (optional) scalar, gate exponent. Defaults to 2
%                 (Table S2's default). Per this segment's Task 3 brief,
%                 the paper's own sweep found negligible sensitivity
%                 (0.16-0.28 BPM swing over {1,2,4,8}) -- not re-swept
%                 here for that reason either.
%
% Outputs:
%   pulseNormalized - 1 x N vector, s_clean(t), the phase-normalized
%                     cardiac signal.
%   envelope        - 1 x N vector, A(t), the instantaneous envelope
%                     (before slow-lowpass), returned for
%                     provenance/debugging.
%   envelopeSlow    - 1 x N vector, A_slow(t), the lowpass-filtered
%                     envelope.
%   instPhase       - 1 x N vector, phi(t), the instantaneous phase
%                     (radians), returned for provenance/debugging (e.g.
%                     downstream phase-based metrics).

if nargin < 3 || isempty(fenv)
    fenv = 0.30;
end
if nargin < 4 || isempty(kappa)
    kappa = 2;
end

pulseSignal = pulseSignal(:)';
N = numel(pulseSignal);
if N < 10
    error('cpaceHomodyneNormalize:tooShort', 'Need at least 10 samples, got %d.', N);
end

nyquistHz = frameRate / 2;

% --- Step 1: re-bandpass to the cardiac band (same band/order as
% cpaceEigenExtract.m's Stage-1-style cardiac-band filter). ---
cardiacLowHz = 0.7;
cardiacHighHz = 3.0;
cardiacOrder = 4;
[bCard, aCard] = butter(cardiacOrder, [cardiacLowHz, cardiacHighHz] / nyquistHz, 'bandpass');
sigBp = filtfilt(bCard, aCard, pulseSignal);

% --- Step 2: analytic signal -> envelope + phase. ---
analyticSig = hilbert(sigBp);
envelope = abs(analyticSig);
instPhase = angle(analyticSig);

% --- Step 3: lowpass the envelope at fenv Hz. ---
lowpassOrder = 2;
[bEnv, aEnv] = butter(lowpassOrder, fenv / nyquistHz, 'low');
envelopeSlow = filtfilt(bEnv, aEnv, envelope);

% Guard against near-zero slow envelope (silent/clipped segments) blowing
% up the ratio -- floor at a small fraction of the recording's own RMS
% envelope rather than a fixed epsilon, so the guard scales with signal
% amplitude across subjects/conditions.
envelopeFloor = 1e-6 * sqrt(mean(envelope .^ 2)) + eps;
envelopeSlowSafe = max(envelopeSlow, envelopeFloor);

% --- Step 4: demodulate with the gate exponent kappa. ---
gate = (envelope ./ envelopeSlowSafe) .^ kappa;
pulseNormalized = gate .* cos(instPhase);

end
