function [meanDiff, limitsOfAgreement] = blandAltman(predicted, groundTruth, plotTitle, outputPath, datasetLabels)
% BLANDALTMAN Generate a Bland-Altman plot comparing predicted vs.
% ground-truth vital sign measurements, and return its summary stats.
%
% Pipeline stage: Stage 6 (validation) — the standard tool for comparing
% two vital-sign measurement methods (here: camera-based estimate vs.
% pulse-oximeter/contact-PPG ground truth), used alongside
% validation/computeMetrics.m.
%
% Signature grew from the original 3-argument stub the same way
% pulseextraction/chromCombine.m's and spo2/ratioOfRatios.m's signatures
% grew in earlier segments: the stub had nowhere to put the plot (no
% output path) and no way to color points by dataset (mandatory per this
% segment's brief, since every pooled plot must show UBFC vs. VIPL
% points distinguishably). Both additions are optional-in-spirit but
% required by this segment's own deliverables, so they were added as
% explicit trailing arguments rather than hidden behind global state.
%
% Inputs:
%   predicted    - vector, estimated values (HR bpm or SpO2%).
%   groundTruth  - vector, same length, ground-truth reference values.
%   plotTitle    - string/char, title for the generated figure.
%   outputPath   - string/char, full file path the figure PNG is saved to.
%   datasetLabels - optional, cell array of strings, same length as
%                   predicted/groundTruth, one dataset name per point
%                   (e.g. 'UBFC' or 'VIPL'). When omitted, every point is
%                   drawn the same way with no legend.
%
% Outputs:
%   meanDiff          - scalar, mean of (predicted - groundTruth), the
%                        bias between methods.
%   limitsOfAgreement - 1x2 vector, [lower, upper] 95% limits of
%                        agreement (mean difference +/- 1.96*SD).

if nargin < 5
    datasetLabels = {};
end

predicted = predicted(:);
groundTruth = groundTruth(:);

if numel(predicted) ~= numel(groundTruth)
    error('blandAltman:sizeMismatch', 'predicted and groundTruth must have the same number of elements.');
end

N = numel(predicted);

meanOfPair = zeros(N, 1);
diffOfPair = zeros(N, 1);

for i = 1:N
    meanOfPair(i) = (predicted(i) + groundTruth(i)) / 2;
    diffOfPair(i) = predicted(i) - groundTruth(i);
end

sumDiff = 0;

for i = 1:N
    sumDiff = sumDiff + diffOfPair(i);
end

meanDiff = sumDiff / N;

sumSquaredDev = 0;

for i = 1:N
    sumSquaredDev = sumSquaredDev + (diffOfPair(i) - meanDiff)^2;
end

if N > 1
    stdDiff = sqrt(sumSquaredDev / (N - 1));
else
    stdDiff = 0;
end

upperLimit = meanDiff + 1.96 * stdDiff;
lowerLimit = meanDiff - 1.96 * stdDiff;

limitsOfAgreement = [lowerLimit, upperLimit];

figureHandle = figure('Visible', 'off');
hold on;

markerList = {'o', 's', '^', 'd', 'v'};

showLegend = false;

if isempty(datasetLabels)
    scatter(meanOfPair, diffOfPair, 60, 'filled');
else
    uniqueDatasets = unique(datasetLabels);
    numDatasets = numel(uniqueDatasets);

    for datasetPos = 1:numDatasets
        thisDataset = uniqueDatasets{datasetPos};
        pointMask = false(N, 1);

        for i = 1:N
            if strcmp(datasetLabels{i}, thisDataset)
                pointMask(i) = true;
            end
        end

        markerStyle = markerList{mod(datasetPos - 1, numel(markerList)) + 1};
        scatter(meanOfPair(pointMask), diffOfPair(pointMask), 60, 'filled', markerStyle, 'DisplayName', thisDataset);
    end

    showLegend = true;
end

xLimitsCurrent = xlim;

plot(xLimitsCurrent, [meanDiff meanDiff], 'k-', 'LineWidth', 1.5, 'DisplayName', 'Bias (mean diff)');
plot(xLimitsCurrent, [upperLimit upperLimit], 'r--', 'LineWidth', 1.2, 'DisplayName', 'Upper limit of agreement');
plot(xLimitsCurrent, [lowerLimit lowerLimit], 'r--', 'LineWidth', 1.2, 'DisplayName', 'Lower limit of agreement');
xlim(xLimitsCurrent);

if showLegend
    legend('show', 'Location', 'best');
end

xlabel('Mean of predicted and ground truth');
ylabel('Predicted - ground truth');
title(plotTitle);
grid on;
hold off;

exportgraphics(figureHandle, outputPath);
close(figureHandle);

end
