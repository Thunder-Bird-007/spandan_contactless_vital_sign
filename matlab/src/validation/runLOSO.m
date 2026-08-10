function results = runLOSO(subjectIDs, datasetLabels, R_values, spo2True)
% RUNLOSO Leave-one-subject-out cross-validation driver for SpO2
% calibration, genuinely pooled across UBFC and VIPL subjects.
%
% Pipeline stage: Stage 6 (validation) — for each subject in the pooled
% set, fits spo2/calibrateSpO2.m on every OTHER subject in the ENTIRE
% pooled set (not per-dataset), predicts the held-out subject's SpO2, and
% records predicted vs. ground truth for validation/computeMetrics.m /
% validation/blandAltman.m. Never lets the same subject appear in both
% calibration and test data for its own fold.
%
% Signature grew away from the original generic (subjectData, pipelineFn)
% stub because this segment's own scope is explicitly NOT to reprocess
% video or re-run the Segment 2-5 pipeline (see the task brief's SCOPE
% section) — it only pools already-computed R/SpO2 values sitting in
% Segment 5's CSVs. A pipeline function handle has nothing to call here;
% what this fold loop actually needs is the four parallel vectors below,
% the same shape run_segment5_dataset1_calibration_batch.m and
% run_vipl_integration_batch.m already produce per dataset. This mirrors
% those two scripts' own leave-one-out loop, just pooled across BOTH
% datasets at once instead of run separately per dataset.
%
% Only SpO2 gets this treatment, not HR — see
% Segment6_LineByLine_Explanation.md for why: calibrateSpO2.m has a
% fitted parameter (A, B) that must never be fit on the same subject it
% then predicts, while HR has no fitted parameter at all, so HR is simply
% evaluated pooled and direct (see scripts/run_segment6_validation.m).
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
%             abs_error, SpO2_predicted_baseline, abs_error_baseline,
%             SpO2_predicted_centered, abs_error_centered.
%             The baseline fields are a TRIVIAL comparison point added
%             alongside the real calibrated prediction, not a separate
%             pipeline: for each fold, SpO2_predicted_baseline is just
%             the mean SpO2_true of that fold's training subjects, with R
%             ignored entirely. If the real calibration cannot beat this
%             on MAE/RMSE, R is not adding predictive value yet for the
%             current pooled subject set -- see
%             Segment6_Refinement_Notes.md for the investigation this
%             was added for. The centered fields are a SEPARATE, NEW code
%             path that runs the exact same leave-one-out loop but feeds
%             validation/centerRPerDataset.m's per-fold, per-dataset-
%             mean-subtracted R into the same unmodified calibrateSpO2.m,
%             instead of raw pooled R -- see
%             Segment6_Refinement_Notes.md for why (a per-dataset R
%             offset visible in segment6_R_vs_SpO2_by_dataset.png).
%             Existing fields are unchanged, so any caller reading only
%             subjectID/dataset/R_value/SpO2_true/SpO2_predicted/
%             abs_error keeps working exactly as before.

numSubjects = numel(subjectIDs);

if numel(datasetLabels) ~= numSubjects || numel(R_values) ~= numSubjects || numel(spo2True) ~= numSubjects
    error('runLOSO:sizeMismatch', 'subjectIDs, datasetLabels, R_values, and spo2True must all have the same length.');
end

results = struct('subjectID', {}, 'dataset', {}, 'R_value', {}, 'SpO2_true', {}, 'SpO2_predicted', {}, 'abs_error', {}, 'SpO2_predicted_baseline', {}, 'abs_error_baseline', {}, 'SpO2_predicted_centered', {}, 'abs_error_centered', {});

for holdoutPos = 1:numSubjects
    trainMask = true(1, numSubjects);
    trainMask(holdoutPos) = false;

    R_train = R_values(trainMask);
    SpO2_train = spo2True(trainMask);

    [~, calibParams] = calibrateSpO2(R_train, SpO2_train, []);

    R_test = R_values(holdoutPos);
    [SpO2_predicted, ~] = calibrateSpO2(R_test, [], calibParams);

    absError = abs(SpO2_predicted - spo2True(holdoutPos));

    SpO2_predicted_baseline = mean(SpO2_train);
    absErrorBaseline = abs(SpO2_predicted_baseline - spo2True(holdoutPos));

    R_values_centered = centerRPerDataset(R_values, datasetLabels, holdoutPos);
    R_train_centered = R_values_centered(trainMask);
    R_test_centered = R_values_centered(holdoutPos);

    [~, calibParamsCentered] = calibrateSpO2(R_train_centered, SpO2_train, []);
    [SpO2_predicted_centered, ~] = calibrateSpO2(R_test_centered, [], calibParamsCentered);

    absErrorCentered = abs(SpO2_predicted_centered - spo2True(holdoutPos));

    results(holdoutPos).subjectID = subjectIDs{holdoutPos};
    results(holdoutPos).dataset = datasetLabels{holdoutPos};
    results(holdoutPos).R_value = R_values(holdoutPos);
    results(holdoutPos).SpO2_true = spo2True(holdoutPos);
    results(holdoutPos).SpO2_predicted = SpO2_predicted;
    results(holdoutPos).abs_error = absError;
    results(holdoutPos).SpO2_predicted_baseline = SpO2_predicted_baseline;
    results(holdoutPos).abs_error_baseline = absErrorBaseline;
    results(holdoutPos).SpO2_predicted_centered = SpO2_predicted_centered;
    results(holdoutPos).abs_error_centered = absErrorCentered;
end

end
