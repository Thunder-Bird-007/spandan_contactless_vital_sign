function [spo2Est, calibParams] = calibrateSpO2(R, groundTruthSpO2, calibParams)
% CALIBRATESPO2 Fit/apply a linear R -> SpO2% calibration.
%
% Pipeline stage: Stage 5 (SpO2 estimation) — fits a linear mapping
% (SpO2 = a*R + b) between ratio-of-ratios values (spo2/ratioOfRatios.m)
% and ground-truth SpO2 labels (io/loadGroundTruth.m, DATASET_1 subjects
% only — see docs/DATA_FORMAT.md), or applies an already-fitted mapping.
% Calibration must be fit per validation/runLOSO.m fold, never on the
% subject being tested.
%
% Inputs:
%   R               - scalar or vector, ratio-of-ratios value(s) from
%                     spo2/ratioOfRatios.m.
%   groundTruthSpO2 - vector or [], ground-truth SpO2% labels to fit
%                     against. Pass [] when only applying an existing
%                     calibration (calibParams already given).
%   calibParams     - struct or [], existing calibration {a, b}. Pass []
%                     to fit a new calibration from R/groundTruthSpO2.
%
% Outputs:
%   spo2Est     - scalar or vector, estimated SpO2% for the given R.
%   calibParams - struct {a, b}, the (possibly newly fit) linear
%                 calibration coefficients.

error('Not implemented yet — see docs/');

end
