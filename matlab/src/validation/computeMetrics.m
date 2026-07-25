function metrics = computeMetrics(predicted, groundTruth)
% COMPUTEMETRICS Compute standard agreement metrics between predicted and
% ground-truth vital sign values.
%
% Pipeline stage: Stage 6 (validation) — summarizes validation/runLOSO.m
% output. Reports MAE, RMSE, and Pearson correlation, the standard metrics
% for comparing an estimation method against ground truth.
%
% Inputs:
%   predicted   - vector, estimated values (HR bpm or SpO2%).
%   groundTruth - vector, same length, ground-truth reference values.
%
% Outputs:
%   metrics - struct with fields: mae, rmse, pearsonR.

error('Not implemented yet — see docs/');

end
