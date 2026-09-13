function [selectedSignal, selectedMethodLabel, selectedNotchConfidence, wasSubstituted] = ...
    harmonicFilterConfidenceGate(primarySignal, primaryNotchConfidence, primaryMethodLabel, ...
    fallbackSignals, fallbackNotchConfidences, fallbackMethodLabels, confidenceThreshold)
% HARMONICFILTERCONFIDENCEGATE Keep a primary harmonic-filtered signal
% wherever its OWN notch-confidence score already clears this project's
% house bar; substitute a fallback candidate (or the best of several)
% only where the primary already fails.
%
% Pipeline stage: Segment 13 Task 2 (NEW, additive) -- a GATED,
% OFF-BY-DEFAULT selection wrapper, motivated by Segment 13 Task 1's own
% root-cause finding (see docs/Segment13_Task1_Gaussian_Regression_Root_
% Cause_and_Gate.md): every one of the 17 subjects that regressed severely
% when Segment 12 Task 2's harmonicSelectiveGaussianFilter.m (alpha=0.15)
% was applied POOL-WIDE was a subject where morphology/
% adaptiveHarmonicFilter.m's ABPF comb ALREADY passed this project's 0.3
% notch-confidence bar -- zero of the 76 subjects where ABPF already
% failed showed a severe regression. This function encodes the resulting
% design principle directly: never override an already-successful
% primary result, so a severe regression on an already-good subject
% becomes structurally impossible, by construction, not just empirically
% rare.
%
% NOT wired into pipeline/estimateVitalsAndMorphology.m or any other
% production call site -- morphology/adaptiveHarmonicFilter.m stays the
% sole production harmonic filter. This function is a standalone,
% reusable selection utility a future session can call explicitly.
%
% TWO USE MODES, same function:
%   (a) SAFE single-fallback gate (the recommended mode, per Segment 13
%       Task 2's own evaluation): fallbackSignals/fallbackNotchConfidences/
%       fallbackMethodLabels each hold exactly ONE candidate. Verified
%       (Segment 13 Task 2): pass rate 24%->47%, median notch confidence
%       0.058->0.235, median waveform correlation 0.519->0.522, harmonic
%       confusion 5%->3%, and ZERO severe notch-confidence regressions
%       (by construction) on the same 100-subject pool -- though a real,
%       smaller cost is still honestly on record: among the 76 subjects
%       actually substituted, waveform correlation improves for 45 and
%       regresses for 31 (6 by more than 0.1), stated so a caller does not
%       assume the fallback is a free, unconditional win for every
%       substituted subject even though the notch-confidence pass/fail
%       status itself can only ever go from fail to (possibly) pass, never
%       pass to fail.
%   (b) MULTI-candidate "highest self-reported confidence wins" mode:
%       pass more than one fallback candidate (e.g. several
%       harmonicSelectiveGaussianFilter.m alpha values). VERIFIED AND
%       ACTIVELY DISCOURAGED (Segment 13 Task 2's own supplementary
%       check): picking the best of many candidates by their own
%       self-reported notch confidence inflates the reported pass rate
%       dramatically (72% in that check, vs. this function's own safe
%       mode's 47%) but its median waveform correlation was simultaneously
%       the WORST of every method compared (0.497, worse than plain ABPF's
%       0.519) -- clear evidence of a selection-bias artifact (repeatedly
%       picking whichever noisy candidate happens to score highest
%       inflates that very score without a corresponding real fidelity
%       gain), not a genuine improvement. Mode (b) is implemented here
%       ONLY so a future session does not have to reimplement it to
%       rediscover this warning; it is NOT the recommended configuration.
%
% Inputs:
%   primarySignal            - 1 x N vector, the primary (production)
%                               harmonic-filtered pulse signal, e.g.
%                               morphology/adaptiveHarmonicFilter.m's
%                               output combined via
%                               pulseextraction/chromCombine.m.
%   primaryNotchConfidence    - scalar in [0,1], e.g.
%                               morphology/notchDetectIEM.m's own
%                               `confidence` output for primarySignal's
%                               own ensemble-averaged beat prototype.
%   primaryMethodLabel        - string/char, echoed back for provenance
%                               (e.g. 'abpf').
%   fallbackSignals           - cell array of 1 x N vectors, one or more
%                               candidate alternative signals (e.g.
%                               morphology/harmonicSelectiveGaussianFilter.m
%                               at one or more alpha values).
%   fallbackNotchConfidences  - vector, same length as fallbackSignals,
%                               each candidate's own notch confidence.
%   fallbackMethodLabels      - cell array of strings/chars, same length,
%                               echoed back for provenance.
%   confidenceThreshold       - (optional) scalar, default 0.3, this
%                               project's own standing notch-confidence
%                               bar (see docs/Segment7_Task_B_Notch_
%                               Quantification.md).
%
% Outputs:
%   selectedSignal            - 1 x N vector, whichever candidate was kept.
%   selectedMethodLabel        - string, the label of the kept candidate.
%   selectedNotchConfidence    - scalar, the kept candidate's own notch
%                               confidence.
%   wasSubstituted             - logical, true if a fallback candidate was
%                               used instead of the primary.

if nargin < 7 || isempty(confidenceThreshold)
    confidenceThreshold = 0.3;
end

if ~iscell(fallbackSignals)
    fallbackSignals = {fallbackSignals};
end
if ~iscell(fallbackMethodLabels)
    fallbackMethodLabels = {fallbackMethodLabels};
end
fallbackNotchConfidences = fallbackNotchConfidences(:)';

if numel(fallbackSignals) ~= numel(fallbackNotchConfidences) || numel(fallbackSignals) ~= numel(fallbackMethodLabels)
    error('harmonicFilterConfidenceGate:sizeMismatch', ...
        'fallbackSignals, fallbackNotchConfidences, and fallbackMethodLabels must all have the same number of candidates.');
end

if ~isnan(primaryNotchConfidence) && primaryNotchConfidence > confidenceThreshold
    selectedSignal = primarySignal;
    selectedMethodLabel = primaryMethodLabel;
    selectedNotchConfidence = primaryNotchConfidence;
    wasSubstituted = false;
    return
end

[bestConf, bestIdx] = max(fallbackNotchConfidences);
selectedSignal = fallbackSignals{bestIdx};
selectedMethodLabel = fallbackMethodLabels{bestIdx};
selectedNotchConfidence = bestConf;
wasSubstituted = true;

end
