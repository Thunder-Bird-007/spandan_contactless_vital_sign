function results = runLOSOStratified(subjectIDs, datasetLabels, R_values, spo2True)
% RUNLOSOSTRATIFIED Leave-one-subject-out cross-validation driver for
% SpO2 calibration, stratified WITHIN each dataset only (no cross-dataset
% training contamination).
%
% Pipeline stage: Stage 6 (validation) — a new, additional evaluation
% path alongside the existing validation/runLOSO.m, not a replacement for
% it. runLOSO.m fits calibrateSpO2.m on every OTHER subject in the ENTIRE
% pooled set, regardless of dataset, for every fold. At the current pool
% composition (107 VIPL vs 5 UBFC), that means every UBFC held-out
% subject's training fold is ~96% VIPL data, so runLOSO.m's "UBFC only"
% scoring rows no longer isolate a UBFC-specific result — they mostly
% measure how a VIPL-dominated fit performs on UBFC subjects (see
% Segment6_Refinement_Notes.md Task G, Section 4c). This function fixes
% that specific pool-imbalance artifact by restricting each fold's
% training set to subjects from the SAME dataset as the held-out subject
% only, giving a true within-dataset leave-one-out result: UBFC held-out
% subjects train only on the other UBFC subjects, VIPL held-out subjects
% train only on the other VIPL subjects. This isolates real within-
% dataset generalization from cross-dataset transfer effects.
%
% Only SpO2 gets this treatment, not HR — same reasoning as runLOSO.m's
% own header comment: calibrateSpO2.m has a fitted parameter (A, B) that
% must never be fit on the same subject it then predicts, so a train/test
% split matters for SpO2. HR's heartrate/fftHeartRate.m has no fitted
% parameter at all — it is a direct FFT peak read with nothing that could
% leak between subjects or between datasets — so the existing per-dataset
% HR breakdown in segment6_hr_pooled_metrics.csv is already a fair,
% uncontaminated comparison and needs no stratified equivalent.
%
% Inputs:
%   subjectIDs    - cell array of strings, one subject ID per pooled
%                   entry.
%   datasetLabels - cell array of strings, same length, which dataset
%                   ('UBFC' or 'VIPL') each entry came from.
%   R_values      - vector, same length, each subject's whole-clip
%                   ratio-of-ratios value from spo2/ratioOfRatios.m.
%   spo2True      - vector, same length, each subject's ground-truth
%                   SpO2%.
%
% Outputs:
%   results - struct array, one entry per held-out subject, with fields
%             subjectID, dataset, R_value, SpO2_true, SpO2_predicted,
%             abs_error. Same field names as runLOSO.m's first six
%             fields, deliberately, so the same computeMetrics.m call
%             that consumes runLOSO.m's output can consume this
%             function's output unmodified. runLOSO.m itself is not
%             called or modified by this function.

numSubjects = numel(subjectIDs);

if numel(datasetLabels) ~= numSubjects || numel(R_values) ~= numSubjects || numel(spo2True) ~= numSubjects
    error('runLOSOStratified:sizeMismatch', 'subjectIDs, datasetLabels, R_values, and spo2True must all have the same length.');
end

results = struct('subjectID', {}, 'dataset', {}, 'R_value', {}, 'SpO2_true', {}, 'SpO2_predicted', {}, 'abs_error', {});

for holdoutPos = 1:numSubjects
    holdoutDataset = datasetLabels{holdoutPos};

    trainMask = false(1, numSubjects);

    for i = 1:numSubjects
        if i ~= holdoutPos && strcmp(datasetLabels{i}, holdoutDataset)
            trainMask(i) = true;
        end
    end

    if sum(trainMask) == 0
        error('runLOSOStratified:noTrainingData', ['No same-dataset training subjects remain for held-out subject ' subjectIDs{holdoutPos} ' (dataset ' holdoutDataset ').']);
    end

    R_train = R_values(trainMask);
    SpO2_train = spo2True(trainMask);

    [~, calibParams] = calibrateSpO2(R_train, SpO2_train, []);

    R_test = R_values(holdoutPos);
    [SpO2_predicted, ~] = calibrateSpO2(R_test, [], calibParams);

    absError = abs(SpO2_predicted - spo2True(holdoutPos));

    results(holdoutPos).subjectID = subjectIDs{holdoutPos};
    results(holdoutPos).dataset = holdoutDataset;
    results(holdoutPos).R_value = R_values(holdoutPos);
    results(holdoutPos).SpO2_true = spo2True(holdoutPos);
    results(holdoutPos).SpO2_predicted = SpO2_predicted;
    results(holdoutPos).abs_error = absError;
end

end
