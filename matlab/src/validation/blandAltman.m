function [meanDiff, limitsOfAgreement] = blandAltman(predicted, groundTruth, plotTitle)
% BLANDALTMAN Generate a Bland-Altman plot comparing predicted vs.
% ground-truth vital sign measurements, and return its summary stats.
%
% Pipeline stage: Stage 6 (validation) — the standard tool for comparing
% two vital-sign measurement methods (here: camera-based estimate vs.
% pulse-oximeter ground truth), used alongside computeMetrics.m.
%
% Inputs:
%   predicted   - vector, estimated values (HR bpm or SpO2%).
%   groundTruth - vector, same length, ground-truth reference values.
%   plotTitle   - string/char, title for the generated figure.
%
% Outputs:
%   meanDiff          - scalar, mean of (predicted - groundTruth), the
%                        bias between methods.
%   limitsOfAgreement - 1x2 vector, [lower, upper] 95% limits of
%                        agreement (mean difference +/- 1.96*SD).

error('Not implemented yet — see docs/');

end
