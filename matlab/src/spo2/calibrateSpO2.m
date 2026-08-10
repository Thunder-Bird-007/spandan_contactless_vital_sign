function [spo2Est, calibParams] = calibrateSpO2(R, groundTruthSpO2, calibParams)
% CALIBRATESPO2 Fit/apply a linear R -> SpO2% calibration.
%
% Pipeline stage: Stage 5 (SpO2 estimation) — fits a linear mapping
% SpO2 = A - B*R (the standard empirical form used for pulse-oximetry
% ratio-of-ratios calibration, since SpO2 falls as R rises) between
% ratio-of-ratios values (spo2/ratioOfRatios.m) and ground-truth SpO2
% labels (io/loadGroundTruth.m), or applies an already-fitted mapping.
% This function is a plain black box: it does not know or care whether
% its caller is DATASET_1's leave-one-out calibration or the Hoffman
% finger-camera sanity check — nothing dataset-specific is hardcoded
% here. Calibration must be fit only on subjects/trials NOT being
% predicted in the same call — see the caller scripts for how each one
% enforces this.
%
% Inputs:
%   R               - scalar or vector, ratio-of-ratios value(s) from
%                     spo2/ratioOfRatios.m.
%   groundTruthSpO2 - vector or [], ground-truth SpO2% labels to fit
%                     against. Pass [] when only applying an existing
%                     calibration (calibParams already given).
%   calibParams     - struct or [], existing calibration {A, B}. Pass []
%                     to fit a new calibration from R/groundTruthSpO2.
%
% Outputs:
%   spo2Est     - scalar or vector, estimated SpO2% for the given R. When
%                 fitting (calibParams passed in as []), these are the
%                 fitted model's own predictions on the training data
%                 itself, returned so the caller can compute residuals
%                 (spo2Est - groundTruthSpO2) as a training-set fit-
%                 quality sanity check — NOT a held-out prediction.
%   calibParams - struct {A, B}, the (possibly newly fit) linear
%                 calibration coefficients, SpO2 = A - B*R.

if isempty(calibParams)
    fitCoeffs = polyfit(R, groundTruthSpO2, 1);
    slopeCoeff = fitCoeffs(1);
    interceptCoeff = fitCoeffs(2);

    A = interceptCoeff;
    B = -slopeCoeff;

    calibParams = struct();
    calibParams.A = A;
    calibParams.B = B;
else
    A = calibParams.A;
    B = calibParams.B;
end

spo2Est = A - B * R;

end
