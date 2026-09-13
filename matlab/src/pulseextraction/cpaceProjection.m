function [Rc, Gc, Bc, qHat, skinColorAngleDeg] = cpaceProjection(R, G, B)
% CPACEPROJECTION Project out the isochromatic ("skin mean reflectance")
% direction from a raw ROI-averaged RGB trace, per cPACE Stage 1.
%
% Pipeline stage: Segment 11 Task 1 (NEW, additive) -- an OPTIONAL pre-step
% callers may insert ahead of pulseextraction/chromCombine.m or
% pulseextraction/posCombine.m. Does NOT modify either of those files, or
% filtering/detrendSignal.m, or roi/extractROISignals.m -- this function
% only transforms the raw trace those functions already consume; it does
% not replace any pipeline stage.
%
% Reference: Kaur, G., Lakshminarayanan, V. & Saini, S.S. (2026). "Missed
% isochromatic cardiac pulsation in remote photoplethysmography: detection,
% impact, and removal." Biomedical Optics Express 17(7):3832,
% doi:10.1364/BOE.599752. Their claim: the standard rPPG signal model
% (chromatic-only, i.e. what CHROM/POS/every other classical combiner
% assumes) is incomplete -- a second cardiac-frequency "isochromatic"
% component (ballistocardiographic skin-geometry + scattering modulation)
% lies along the skin's mean reflectance direction q_hat and carries the
% MAJORITY of cardiac-band energy in their data (median 69-83% across three
% cohorts). Because both components sit at the same cardiac frequency,
% "temporal filtering cannot separate them" -- only a spatial (per-channel)
% projection can. Their cPACE method's Stage 1 is exactly this projection;
% Stages 2-3 (phase-optimal eigenvector selection, in-band noise
% suppression) are NOT implemented here -- this is Stage 1 only, per the
% Segment 11 Task 1 brief.
%
% METHOD:
%   q_hat = [Rbar, Gbar, Bbar] / norm([Rbar, Gbar, Bbar])   (temporal means)
%   P     = I - q_hat * q_hat'                              (3x3 projector)
%   x_corrected(t) = P * x(t)                                (per-sample)
%
% q_hat is built from the SAME raw per-channel temporal means
% (mean(R), mean(G), mean(B)) that pulseextraction/chromCombine.m and
% pulseextraction/posCombine.m already compute for their own normalization
% step (their meanRRaw/meanGRaw/meanBRaw), and spo2/ratioOfRatios.m already
% computes for its DC term -- this function recomputes the same three
% scalars the same way (raw, whole-clip, pre-detrend, pre-filter), not a
% different convention.
%
% IMPORTANT CALLER NOTE (read before wiring this in): because q_hat is BY
% CONSTRUCTION the normalized direction of [mean(R),mean(G),mean(B)], the
% projection removes that mean EXACTLY -- mean(Rc) = mean(Gc) = mean(Bc) =
% 0 to numerical precision, not just approximately. This means chromCombine.m/
% posCombine.m's own normalization step (Rn = R./meanRRaw etc.) MUST still
% be called with the ORIGINAL, uncorrected raw traces as their RRaw/GRaw/BRaw
% argument -- using the corrected trace's own (zero) mean there would divide
% by zero. Callers should pass Rc/Gc/Bc (this function's output, after
% detrendSignal.m + bandpassClean.m as usual) as chromCombine.m's/
% posCombine.m's FILTERED R/G/B argument, while still passing the ORIGINAL
% R/G/B as the RRaw/GRaw/BRaw normalization argument. See
% scripts/run_segment11_task1_cpace_and_plv.m for a worked example of this
% exact wiring.
%
% Inputs:
%   R, G, B - 1 x N vectors, RAW (pre-detrend, pre-filter) ROI-averaged
%             color channel traces -- the same raw trace CHROM/POS already
%             take as their RRaw/GRaw/BRaw argument (i.e.
%             data/processed/<subjectID>_rgb_traces.mat's R, G, B).
%
% Outputs:
%   Rc, Gc, Bc        - 1 x N vectors, the projected trace (same length,
%                        zero-mean by construction).
%   qHat              - 3 x 1 vector, the unit skin-reflectance direction
%                        used for this subject/window, returned for
%                        provenance/debugging (e.g. to confirm the
%                        zero-mean claim above, or to reuse the same q_hat
%                        on a related signal).
%   skinColorAngleDeg - scalar, the angle in degrees between qHat and the
%                        skin-tone axis [1,1,1]/sqrt(3) -- the paper's own
%                        "skin-colour angle theta" (their reported medians:
%                        ~5-10 degrees lightly pigmented, ~30-50 degrees
%                        darkly pigmented). Returned here because it falls
%                        out of the same q_hat computation for free and
%                        this task's brief asks for it per subject.

R = R(:)';
G = G(:)';
B = B(:)';

if numel(R) ~= numel(G) || numel(R) ~= numel(B)
    error('cpaceProjection:sizeMismatch', 'R, G, B must be the same length.');
end

meanVec = [mean(R); mean(G); mean(B)];
meanNorm = norm(meanVec);
if meanNorm == 0
    error('cpaceProjection:zeroMean', 'R/G/B temporal means are all zero -- cannot form a skin-reflectance direction.');
end
qHat = meanVec / meanNorm;

P = eye(3) - qHat * qHat';

X = [R; G; B];
Xc = P * X;

Rc = Xc(1, :);
Gc = Xc(2, :);
Bc = Xc(3, :);

skinToneAxis = [1; 1; 1] / sqrt(3);
cosAngle = max(-1, min(1, dot(qHat, skinToneAxis)));
skinColorAngleDeg = acosd(cosAngle);

end
