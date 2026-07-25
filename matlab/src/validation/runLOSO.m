function results = runLOSO(subjectData, pipelineFn)
% RUNLOSO Leave-one-subject-out cross-validation driver.
%
% Pipeline stage: Stage 6 (validation) — repeatedly holds out one
% subject's data as the test set, fits any calibration (e.g.
% spo2/calibrateSpO2.m) on the remaining subjects, runs the full pipeline
% (pipeline/estimateVitals.m) on the held-out subject, and collects
% predictions vs. ground truth for computeMetrics.m / blandAltman.m.
% Never let the same subject appear in both calibration and test data.
%
% Inputs:
%   subjectData - struct array or cell array, one entry per subject,
%                 containing whatever pipeline/estimateVitals.m needs
%                 (video path/frames, ground truth, etc.).
%   pipelineFn  - function handle, e.g. @estimateVitals, applied to each
%                 held-out subject.
%
% Outputs:
%   results - struct array, one entry per fold, holding predicted vs.
%             ground-truth HR/SpO2 for that held-out subject.

error('Not implemented yet — see docs/');

end
