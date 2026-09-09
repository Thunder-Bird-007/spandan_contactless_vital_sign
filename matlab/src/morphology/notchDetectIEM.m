function [notchDetected, notchPositionNormalized, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype, fs)
% NOTCHDETECTIEM Dicrotic notch detection on an ensemble-averaged beat
% prototype via the Iterative Envelope Mean (IEM) method.
%
% Pipeline stage: Segment 7 Task B, Action 2 (NEW, additive) — operates
% on morphology/ensembleAverageBeats.m's `prototype.trimmedMean` output
% (or any other 1 x N single-cycle waveform), NOT on a raw multi-beat
% signal. Does not modify morphology/bandpassMorphology.m or
% morphology/ensembleAverageBeats.m.
%
% Reference: Pal R, Rudas A, Kim S, Chiang JN, Barney A, Cannesson M.
% "An algorithm to detect dicrotic notch in arterial blood pressure and
% photoplethysmography waveforms using the iterative envelope mean
% method." Computers in Biology and Medicine, June 2024, 254:108283
% (PMC11323035). The paper reports IEM's mean PPG notch-timing error at
% 4.6 ms (SD 2.9 ms) vs. a plain 2nd-derivative method's 96.8 ms (SD 90.9
% ms) -- roughly a 21x improvement -- which is why this task implements
% IEM rather than a 2nd-derivative peak-pick. THIS IS THE PUBLISHED
% METHOD'S OWN REPORTED NUMBER, cited only to explain the method choice
% -- it describes the paper's own reference implementation evaluated on
% the paper's own dataset, NOT this implementation's accuracy, which has
% not been independently measured or validated anywhere in this project.
% Do not cite 4.6 ms / 21x elsewhere as if it were a result of this code.
%
% IMPLEMENTATION FIDELITY CAVEAT (stated plainly, per this project's
% convention of not overclaiming): this implementation was built from a
% detailed algorithmic description of the paper obtained via a web
% fetch/summarization of PMC11323035, NOT by reading the original
% manuscript's equations directly. The steps below follow that
% description as literally as possible (preprocessing, Savitzky-Golay
% smoothing, envelope-mean sifting with the paper's own stated
% parameters, and the paper's own stopping criterion and notch-location
% rule). One point that read as genuinely ambiguous in the fetched
% description (see Step 2 below) was resolved with an explicit,
% documented choice rather than silently guessed at, and has since been
% checked against the primary source and confirmed correct (2026-08-26).
% Treat the rest of this implementation as a faithful best-effort
% reproduction, not a byte-for-byte verified reimplementation -- readers
% who need the authoritative version should check the primary source.
%
% ALGORITHM (adapted from the paper's Section 2 as fetched):
%   Step 1 (preprocessing): min-max normalize the input to [0, 1] (the
%     paper's Eq. 1), so the beta stopping threshold below is meaningful
%     on a consistent scale regardless of the caller's own signal units.
%   Step 2 (extrema location): the fetched description states "locate
%     local extrema of [the smoothed signal's] first derivative by
%     examining sign changes in [its] second derivative" -- read
%     literally, this locates INFLECTION points of the signal (where
%     curvature changes sign), not the signal's own peaks/troughs. This
%     implementation honors the literal reading -- inflection points,
%     classified as an "upper" envelope anchor where curvature goes
%     concave-up -> concave-down, or a "lower" anchor where it goes
%     concave-down -> concave-up -- since that is what the fetched text
%     actually says, even though it is the less standard construction
%     (the more common "sign changes in the first derivative" would
%     instead find the signal's own local maxima/minima). VERIFIED
%     against the primary source, 2026-08-26 (Segment 7 Task D, Action 0
%     doc fix): this inflection-point reading matches the primary
%     manuscript (medRxiv 2024.03.05.24303735), so what was previously
%     flagged here as an ambiguous point "resolved by documented guess"
%     is confirmed correct, not merely a defensible interpretation of a
%     secondhand fetched summary.
%   Step 3 (envelope): cubic-spline the SIGNAL'S OWN VALUES at the
%     "upper" anchor indices into an upper envelope, and at the "lower"
%     anchor indices into a lower envelope (both splines forced through
%     the first and last sample so they span the whole prototype without
%     extrapolation); mean envelope = (upper + lower) / 2 (Eq. 2).
%   Step 4 (residual): subtract the mean envelope from the CURRENT
%     iteration's input signal (Eq. 3).
%   Step 5 (stopping criterion): stop when the residual's variance
%     changes by less than beta = 0.1 between iterations (Eq. 4, the
%     paper's own value), or after a hard cap of 20 iterations (this
%     cap is NOT from the paper -- added here only as a safety guard
%     against non-convergence, since the paper does not state one).
%   Notch location: in the final residual (the paper's "non-stationary
%     component"), the first local minimum that is (a) at least 0.1 s
%     (converted to samples via the caller-supplied fs) after the
%     prototype's systolic peak, and (b) below zero, is reported as the
%     dicrotic notch -- exactly the paper's own stated rule.
%
% Inputs:
%   prototype - 1 x N vector, a single-cycle ensemble-averaged pulse
%               waveform (e.g. morphology/ensembleAverageBeats.m's
%               prototype.trimmedMean, N = beatSamples, typically 256).
%   fs        - scalar, Hz, the EFFECTIVE sample rate of prototype when
%               mapped back to real time, i.e. beatSamples / (one real
%               cardiac cycle's duration in seconds) -- NOT
%               morphology/resampleUniform.m's 250 Hz grid rate,
%               since a single prototype cycle does not span a full
%               second at that rate. Callers typically derive this from
%               an independent HR estimate (e.g.
%               heartrate/fftHeartRate.m on the same uniform signal
%               ensembleAverageBeats.m consumed): fs = beatSamples *
%               (hrBpm / 60).
%
% Outputs:
%   notchDetected           - logical scalar, true if a valid notch
%                              candidate was found.
%   notchPositionNormalized - scalar in (0, 1), the notch's location as
%                              a fraction of the full cycle (same
%                              cycle-fraction convention as
%                              morphology/ensembleAverageBeats.m's
%                              beatSamples grid). NaN if not detected.
%   notchDepth              - scalar, the amplitude drop from the
%                              nearest preceding local shoulder (the
%                              highest point of the ORIGINAL prototype
%                              between the systolic peak and the notch;
%                              the peak itself if no intermediate
%                              shoulder exists) down to the notch,
%                              normalized by the prototype's own
%                              peak-to-trough range. NaN if not
%                              detected.
%   confidence              - scalar in [0, 1]. NOT part of the paper
%                              (the fetched description does not report
%                              one) -- this project's own addition,
%                              documented rather than silently invented:
%                              min(1, |finalResidual(notchIdx)| /
%                              (std(finalResidual) + eps)), i.e. how many
%                              residual-noise standard deviations deep
%                              the detected valley is below the
%                              residual's own zero baseline. 0 if not
%                              detected. CAVEAT (Segment 7 Task C,
%                              finding 1): the min(1, ...) clip means any
%                              subject whose true ratio exceeds 1 reads
%                              as an identical 1.0000 to every other
%                              subject past that ceiling -- this looks
%                              like uniform confidence across subjects
%                              but is actually a resolution floor/ceiling
%                              artifact, not a real tie. Use
%                              confidenceRaw (below) to rank or compare
%                              subjects that clip here; keep using
%                              confidence only for the fixed >= 1.0 /
%                              >= 0.3 threshold comparisons already
%                              established in
%                              docs/Segment7_Task_B_Notch_Quantification.md,
%                              where the clip does not change which side
%                              of either threshold a value falls on.
%   confidenceRaw           - scalar >= 0, UNCLIPPED. Same formula as
%                              confidence (|finalResidual(notchIdx)| /
%                              (std(finalResidual) + eps)) but without
%                              the min(1, ...) ceiling, so values above 1
%                              remain distinguishable from each other.
%                              Added in Segment 7 Task C purely to
%                              restore ranking resolution above the
%                              clip; does not change notchDetected,
%                              notchPositionNormalized, notchDepth, or
%                              confidence's own value or behaviour in any
%                              way. 0 if not detected.

betaStopThreshold = 0.1;
maxIterations = 20;
sgPolyOrder = 4;
sgFrameLen = 25;
minGapSec = 0.1;

protoRow = prototype(:)';
N = numel(protoRow);

protoRange = max(protoRow) - min(protoRow);
if protoRange <= 0
    error('notchDetectIEM:flatSignal', 'prototype is constant -- cannot normalize or detect a notch.');
end
protoNorm = (protoRow - min(protoRow)) / protoRange;

frameLen = min(sgFrameLen, N);
if mod(frameLen, 2) == 0
    frameLen = frameLen - 1;
end
frameLen = max(frameLen, sgPolyOrder + 1 + mod(sgPolyOrder + 1, 2));
frameLen = min(frameLen, N - (1 - mod(N, 2)));

currentSignal = protoNorm;
previousResidualVar = var(currentSignal);
finalResidual = currentSignal;

for iterIdx = 1:maxIterations
    smoothed = sgolayfilt(currentSignal, sgPolyOrder, frameLen);

    firstDeriv = gradient(smoothed);
    secondDeriv = gradient(firstDeriv);

    upperAnchors = [1, N];
    lowerAnchors = [1, N];

    for i = 1:(N - 1)
        if secondDeriv(i) >= 0 && secondDeriv(i + 1) < 0
            upperAnchors(end + 1) = i; %#ok<AGROW>
        elseif secondDeriv(i) < 0 && secondDeriv(i + 1) >= 0
            lowerAnchors(end + 1) = i; %#ok<AGROW>
        end
    end

    upperAnchors = unique(upperAnchors);
    lowerAnchors = unique(lowerAnchors);

    upperEnvelope = interp1(upperAnchors, currentSignal(upperAnchors), 1:N, 'pchip');
    lowerEnvelope = interp1(lowerAnchors, currentSignal(lowerAnchors), 1:N, 'pchip');

    meanEnvelope = (upperEnvelope + lowerEnvelope) / 2;
    residual = currentSignal - meanEnvelope;

    residualVar = var(residual);

    finalResidual = residual;

    if abs(previousResidualVar - residualVar) < betaStopThreshold
        break
    end

    previousResidualVar = residualVar;
    currentSignal = residual;
end

[~, peakIdx] = max(protoNorm);
minGapSamples = max(round(minGapSec * fs), 1);
searchStart = peakIdx + minGapSamples;

notchDetected = false;
notchIdx = NaN;

for i = max(searchStart, 2):(N - 1)
    isLocalMin = finalResidual(i - 1) > finalResidual(i) && finalResidual(i) < finalResidual(i + 1);
    if isLocalMin && finalResidual(i) < 0
        notchDetected = true;
        notchIdx = i;
        break
    end
end

if notchDetected
    notchPositionNormalized = (notchIdx - 1) / (N - 1);

    shoulderValue = max(protoNorm(peakIdx:notchIdx));
    notchDepth = (shoulderValue - protoNorm(notchIdx)) / (max(protoNorm) - min(protoNorm));

    residualStd = std(finalResidual);
    confidenceRaw = abs(finalResidual(notchIdx)) / (residualStd + eps);
    confidence = min(1, confidenceRaw);
else
    notchPositionNormalized = NaN;
    notchDepth = NaN;
    confidence = 0;
    confidenceRaw = 0;
end

end
