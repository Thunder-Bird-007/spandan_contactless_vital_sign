function metrics = computeMetrics(predicted, groundTruth)
% COMPUTEMETRICS Compute standard agreement metrics between predicted and
% ground-truth vital sign values.
%
% Pipeline stage: Stage 6 (validation) — summarizes validation/runLOSO.m
% output (SpO2) or a pooled HR CSV (HR). Reports MAE, RMSE, and Pearson
% correlation, the standard metrics for comparing an estimation method
% against ground truth. Deliberately generic: works identically for HR
% (bpm) or SpO2 (%) since neither unit changes the arithmetic.
%
% Inputs:
%   predicted   - vector, estimated values (HR bpm or SpO2%).
%   groundTruth - vector, same length, ground-truth reference values.
%
% Outputs:
%   metrics - struct with fields: mae, rmse, pearsonR, n. n is the number
%             of (predicted, groundTruth) pairs actually used — kept
%             alongside every other number since, with this project's
%             current pool sizes, a metric without its N next to it is
%             not trustworthy on its own.

predicted = predicted(:);
groundTruth = groundTruth(:);

if numel(predicted) ~= numel(groundTruth)
    error('computeMetrics:sizeMismatch', 'predicted and groundTruth must have the same number of elements.');
end

N = numel(predicted);

sumAbsError = 0;
sumSquaredError = 0;

for i = 1:N
    errorVal = predicted(i) - groundTruth(i);
    sumAbsError = sumAbsError + abs(errorVal);
    sumSquaredError = sumSquaredError + errorVal^2;
end

mae = sumAbsError / N;
rmse = sqrt(sumSquaredError / N);

sumPredicted = 0;
sumGroundTruth = 0;

for i = 1:N
    sumPredicted = sumPredicted + predicted(i);
    sumGroundTruth = sumGroundTruth + groundTruth(i);
end

meanPredicted = sumPredicted / N;
meanGroundTruth = sumGroundTruth / N;

numerator = 0;
denomPredicted = 0;
denomGroundTruth = 0;

for i = 1:N
    devPredicted = predicted(i) - meanPredicted;
    devGroundTruth = groundTruth(i) - meanGroundTruth;
    numerator = numerator + devPredicted * devGroundTruth;
    denomPredicted = denomPredicted + devPredicted^2;
    denomGroundTruth = denomGroundTruth + devGroundTruth^2;
end

pearsonR = numerator / sqrt(denomPredicted * denomGroundTruth);

metrics = struct();
metrics.mae = mae;
metrics.rmse = rmse;
metrics.pearsonR = pearsonR;
metrics.n = N;

end
