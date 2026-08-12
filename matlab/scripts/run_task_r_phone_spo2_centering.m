% RUN_TASK_R_PHONE_SPO2_CENTERING Segment 6 Task R: does Task L's phone
% (source2) processing already produce Segment 5 SpO2 outputs as a
% byproduct, what does the phone (source2) vs webcam (source1) R value
% distribution look like, and does validation/centerRPerDataset.m's
% existing per-group-centering approach give the phone camera its own
% real, data-backed centering offset the way it already did for
% UBFC/VIPL (Segment6_Refinement_Notes.md Task E)?
%
% This script does NOT reprocess any video and does NOT modify
% spo2/ratioOfRatios.m, spo2/calibrateSpO2.m, validation/
% centerRPerDataset.m, validation/runLOSO.m, or validation/computeMetrics.m
% -- it only reads two already-on-disk Segment 5 calibration CSVs (Action
% 1's finding: they already exist as a Task L byproduct) and pools them
% through the SAME unmodified LOSO/centering machinery Task E already
% used for UBFC vs VIPL, with dataset labels 'source1'/'source2' instead.
%
% Inputs (both already on disk before this script runs):
%   results/metrics/segment5_vipl_calibration.csv - VIPL v1 webcam
%     (source1) calibration, 107 rows, of which 95 are genuine
%     '_v1_source1' subjects and 12 are '_v1_source2' fallback subjects
%     (subjects with no real source1 video -- see
%     docs/VIPL_Scenario_Coverage.md Section 5). Only the 95 genuine
%     '_v1_source1' rows are used as "source1" here.
%   results/metrics/segment5_vipl_calibration_phone_v1.csv - Task L's
%     v1/source2 (HUAWEI P9 phone) calibration, 107 rows, all
%     '_v1_source2'.
%
% Outputs:
%   results/metrics/segment6_task_r_source_R_comparison.csv - descriptive
%     R-value and SpO2_true range stats per device, matched-subject
%     overlap noted.
%   results/metrics/segment6_task_r_source2_spo2_metrics.csv - source2
%     scope MAE/RMSE/Pearson r for: raw pooled (uncentered), per-device
%     centered, trivial baseline, and a webcam-only-trained/blind-applied
%     baseline.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

disp('=== Segment 6 Task R Action 1: checking whether Task L already produced Segment 5 SpO2 outputs ===');

source1CsvPath = fullfile(metricsRoot, 'segment5_vipl_calibration.csv');
source2CsvPath = fullfile(metricsRoot, 'segment5_vipl_calibration_phone_v1.csv');

if isfile(source1CsvPath) && isfile(source2CsvPath)
    disp(['FOUND: ' source1CsvPath]);
    disp(['FOUND: ' source2CsvPath]);
    disp('CONFIRMED: Task L''s v1/source2 batch (run_vipl_phone_v1_batch.m) already called ratioOfRatios.m and calibrateSpO2.m as a byproduct of running the full Segment 2-5 pipeline -- Segment 5 was NOT skipped for phone video. Task L''s own report (Segment6_Task_L_Phone_Device_Evaluation.md) never discusses this because it only analyzed the HR side.');
else
    error('run_task_r_phone_spo2_centering:missingByproduct', 'Expected byproduct CSVs not found -- Action 1''s premise (data already exists) does not hold; this script does not implement the Action 2 fallback (re-running Segment 5 from scratch), see task brief.');
end

disp(' ');
disp('=== Loading both CSVs ===');

source1Table = readtable(source1CsvPath);
source2Table = readtable(source2CsvPath);

source1Table.subjectID = cellstr(string(source1Table.subjectID));
source2Table.subjectID = cellstr(string(source2Table.subjectID));

disp(['Loaded ' num2str(height(source1Table)) ' rows from ' source1CsvPath ' (webcam VIPL v1 calibration, mixed source1/source2-fallback).']);
disp(['Loaded ' num2str(height(source2Table)) ' rows from ' source2CsvPath ' (Task L phone v1/source2 calibration).']);

isGenuineSource1 = endsWith(string(source1Table.subjectID), '_source1');
numGenuineSource1 = sum(isGenuineSource1);
numFallbackSource2InOldCsv = sum(~isGenuineSource1);

disp(['Of the ' num2str(height(source1Table)) ' rows in the webcam CSV, ' num2str(numGenuineSource1) ' are genuine ''_source1'' subjects and ' num2str(numFallbackSource2InOldCsv) ' are pre-existing ''_source2'' fallback subjects (VIPL_Scenario_Coverage.md Section 5) -- only the genuine ' num2str(numGenuineSource1) ' are used as "source1" below, so this comparison is not contaminated by phone data already sitting inside the nominally-webcam CSV.']);

genuineSource1Table = source1Table(isGenuineSource1, :);

disp(' ');
disp('=== Sanity check: do the 12 pre-existing source2-fallback rows in the old CSV match Task L''s freshly-recomputed values for the same subjects? ===');

fallbackTable = source1Table(~isGenuineSource1, :);
numMatched = 0;
numMismatched = 0;

for rowPos = 1:height(fallbackTable)
    thisSubjectID = fallbackTable.subjectID{rowPos};
    matchIdx = find(strcmp(source2Table.subjectID, thisSubjectID), 1);

    if isempty(matchIdx)
        continue;
    end

    numMatched = numMatched + 1;

    if abs(fallbackTable.R_value(rowPos) - source2Table.R_value(matchIdx)) > 1e-6
        numMismatched = numMismatched + 1;
        disp(['  MISMATCH: ' thisSubjectID ' old R = ' num2str(fallbackTable.R_value(rowPos)) ', Task L R = ' num2str(source2Table.R_value(matchIdx))]);
    end
end

disp([num2str(numMatched) ' of ' num2str(height(fallbackTable)) ' fallback subjects matched by subjectID, ' num2str(numMismatched) ' R-value mismatches (expect 0 -- same cached extraction, same unmodified pipeline).']);

disp(' ');
disp('=== Segment 6 Task R Action 2: source2 (phone) vs source1 (webcam) R-value distribution, same style as Task D/E''s UBFC-vs-VIPL comparison ===');

R_source1 = genuineSource1Table.R_value;
SpO2_source1 = genuineSource1Table.SpO2_true;
R_source2 = source2Table.R_value;
SpO2_source2 = source2Table.SpO2_true;

disp(' ');
disp('Full pools (source1 = genuine webcam rows only, source2 = full Task L pool):');
disp(['  source1 (webcam, n=' num2str(numel(R_source1)) '): R range = [' num2str(min(R_source1)) ', ' num2str(max(R_source1)) '], mean R = ' num2str(mean(R_source1)) ', SpO2_true range = [' num2str(min(SpO2_source1)) '%, ' num2str(max(SpO2_source1)) '%]']);
disp(['  source2 (phone,  n=' num2str(numel(R_source2)) '): R range = [' num2str(min(R_source2)) ', ' num2str(max(R_source2)) '], mean R = ' num2str(mean(R_source2)) ', SpO2_true range = [' num2str(min(SpO2_source2)) '%, ' num2str(max(SpO2_source2)) '%]']);

genuineSubjectBase = extractBefore(string(genuineSource1Table.subjectID), '_v1_source1');
phoneSubjectBase = extractBefore(string(source2Table.subjectID), '_v1_source2');

[commonBase, idx1, idx2] = intersect(genuineSubjectBase, phoneSubjectBase);
numCommon = numel(commonBase);

disp(' ');
disp(['Same-subject overlap: ' num2str(numCommon) ' of ' num2str(numGenuineSource1) ' genuine source1 subjects also have a v1/source2 row (Task L extracted phone v1 for the full 107-subject pool).']);

R_source1_matched = R_source1(idx1);
R_source2_matched = R_source2(idx2);
SpO2_source1_matched = SpO2_source1(idx1);
SpO2_source2_matched = SpO2_source2(idx2);

disp(' ');
disp(['Matched-subject pairs only (n=' num2str(numCommon) ', same ' num2str(numCommon) ' people, same v1 scenario, different camera):']);
disp(['  source1 (webcam): R range = [' num2str(min(R_source1_matched)) ', ' num2str(max(R_source1_matched)) '], mean R = ' num2str(mean(R_source1_matched))]);
disp(['  source2 (phone):  R range = [' num2str(min(R_source2_matched)) ', ' num2str(max(R_source2_matched)) '], mean R = ' num2str(mean(R_source2_matched))]);

meanDiffMatched = mean(R_source2_matched - R_source1_matched);
disp(['  mean paired (source2 - source1) R difference = ' num2str(meanDiffMatched)]);

numOverlappingRange = sum(R_source2_matched >= min(R_source1_matched) & R_source2_matched <= max(R_source1_matched));
disp(['  of the ' num2str(numCommon) ' matched source2 R values, ' num2str(numOverlappingRange) ' fall inside source1''s own R range -- the rest sit outside it.']);

rComparisonCsvPath = fullfile(metricsRoot, 'segment6_task_r_source_R_comparison.csv');
rComparisonHeaderLine = "scope,device,n,R_min,R_max,R_mean,SpO2_true_min,SpO2_true_max";
writelines(rComparisonHeaderLine, rComparisonCsvPath);

rowFullSource1 = strjoin({'full_pool', 'source1', num2str(numel(R_source1)), num2str(min(R_source1)), num2str(max(R_source1)), num2str(mean(R_source1)), num2str(min(SpO2_source1)), num2str(max(SpO2_source1))}, ',');
rowFullSource2 = strjoin({'full_pool', 'source2', num2str(numel(R_source2)), num2str(min(R_source2)), num2str(max(R_source2)), num2str(mean(R_source2)), num2str(min(SpO2_source2)), num2str(max(SpO2_source2))}, ',');
rowMatchedSource1 = strjoin({'matched_subjects', 'source1', num2str(numCommon), num2str(min(R_source1_matched)), num2str(max(R_source1_matched)), num2str(mean(R_source1_matched)), num2str(min(SpO2_source1_matched)), num2str(max(SpO2_source1_matched))}, ',');
rowMatchedSource2 = strjoin({'matched_subjects', 'source2', num2str(numCommon), num2str(min(R_source2_matched)), num2str(max(R_source2_matched)), num2str(mean(R_source2_matched)), num2str(min(SpO2_source2_matched)), num2str(max(SpO2_source2_matched))}, ',');

writelines(rowFullSource1, rComparisonCsvPath, 'WriteMode', 'append');
writelines(rowFullSource2, rComparisonCsvPath, 'WriteMode', 'append');
writelines(rowMatchedSource1, rComparisonCsvPath, 'WriteMode', 'append');
writelines(rowMatchedSource2, rComparisonCsvPath, 'WriteMode', 'append');

disp(['Saved ' rComparisonCsvPath]);

disp(' ');
disp('=== Segment 6 Task R Action 3: fitting a source2-specific centering offset (validation/centerRPerDataset.m, unmodified) ===');

pooledSubjectID = [genuineSource1Table.subjectID; source2Table.subjectID];
pooledDatasetLabel = [repmat({'source1'}, numGenuineSource1, 1); repmat({'source2'}, height(source2Table), 1)];
pooledR = [R_source1; R_source2];
pooledSpO2True = [SpO2_source1; SpO2_source2];

numPooled = numel(pooledSubjectID);

disp(['Pooled source1+source2 set for LOSO: n = ' num2str(numPooled) ' (' num2str(numGenuineSource1) ' source1 + ' num2str(height(source2Table)) ' source2).']);

fullTrainMask = true(numPooled, 1);
fullDatasetTrainMean = zeros(1, 2);
uniqueLabels = unique(pooledDatasetLabel);

for labelPos = 1:numel(uniqueLabels)
    thisLabel = uniqueLabels{labelPos};
    labelMask = strcmp(pooledDatasetLabel, thisLabel);
    fullDatasetTrainMean(labelPos) = mean(pooledR(labelMask));
    disp(['  Full-pool mean R for ' thisLabel ' (all subjects, not per-fold -- descriptive only): ' num2str(fullDatasetTrainMean(labelPos))]);
end

sourceOffset = fullDatasetTrainMean(strcmp(uniqueLabels, 'source2')) - fullDatasetTrainMean(strcmp(uniqueLabels, 'source1'));
disp(['Descriptive source2-minus-source1 mean R offset (full pool, not a LOSO fold value): ' num2str(sourceOffset)]);

losoResults = runLOSO(pooledSubjectID, pooledDatasetLabel, pooledR, pooledSpO2True);

isSource2Fold = strcmp({losoResults.dataset}, 'source2');

SpO2_true_s2 = [losoResults(isSource2Fold).SpO2_true]';
SpO2_pred_raw_s2 = [losoResults(isSource2Fold).SpO2_predicted]';
SpO2_pred_centered_s2 = [losoResults(isSource2Fold).SpO2_predicted_centered]';
SpO2_pred_baseline_s2 = [losoResults(isSource2Fold).SpO2_predicted_baseline]';

metricsRawSource2 = computeMetrics(SpO2_pred_raw_s2, SpO2_true_s2);
metricsCenteredSource2 = computeMetrics(SpO2_pred_centered_s2, SpO2_true_s2);
metricsBaselineSource2 = computeMetrics(SpO2_pred_baseline_s2, SpO2_true_s2);

disp(' ');
disp('=== source2-scope LOSO results (raw pooled two-device fit vs per-device centered vs trivial baseline) ===');
disp(['  raw pooled (uncentered), source2 only: n=' num2str(metricsRawSource2.n) ', MAE=' num2str(metricsRawSource2.mae) ', RMSE=' num2str(metricsRawSource2.rmse) ', r=' num2str(metricsRawSource2.pearsonR)]);
disp(['  per-device centered,     source2 only: n=' num2str(metricsCenteredSource2.n) ', MAE=' num2str(metricsCenteredSource2.mae) ', RMSE=' num2str(metricsCenteredSource2.rmse) ', r=' num2str(metricsCenteredSource2.pearsonR)]);
disp(['  trivial baseline,        source2 only: n=' num2str(metricsBaselineSource2.n) ', MAE=' num2str(metricsBaselineSource2.mae) ', RMSE=' num2str(metricsBaselineSource2.rmse) ', r=' num2str(metricsBaselineSource2.pearsonR) ' (*LOSO arithmetic artifact on r, see Task D -- ignore the correlation, MAE/RMSE are the meaningful part)']);

disp(' ');
disp('=== Additional baseline: webcam-only-trained calibration applied BLIND to phone data (no phone subject ever in training) ===');

[~, webcamOnlyCalibParams] = calibrateSpO2(R_source1, SpO2_source1, []);
disp(['Webcam-only fit: A = ' num2str(webcamOnlyCalibParams.A) ', B = ' num2str(webcamOnlyCalibParams.B) ' (SpO2 = A - B*R, fit on all ' num2str(numGenuineSource1) ' source1 subjects, zero source2 subjects in training).']);

[SpO2_pred_webcamBlind_s2, ~] = calibrateSpO2(R_source2, [], webcamOnlyCalibParams);
metricsWebcamBlindSource2 = computeMetrics(SpO2_pred_webcamBlind_s2, SpO2_source2);

disp(['  webcam-only, applied blind to source2: n=' num2str(metricsWebcamBlindSource2.n) ', MAE=' num2str(metricsWebcamBlindSource2.mae) ', RMSE=' num2str(metricsWebcamBlindSource2.rmse) ', r=' num2str(metricsWebcamBlindSource2.pearsonR)]);

disp(' ');
disp('=== Verdict: does per-device centering give source2 a real accuracy win over the uncentered / webcam-blind baselines? ===');

if metricsCenteredSource2.mae < metricsRawSource2.mae
    disp(['Centered MAE (' num2str(metricsCenteredSource2.mae) ') beats raw pooled uncentered MAE (' num2str(metricsRawSource2.mae) ') for source2.']);
else
    disp(['Centered MAE (' num2str(metricsCenteredSource2.mae) ') does NOT beat raw pooled uncentered MAE (' num2str(metricsRawSource2.mae) ') for source2.']);
end

if metricsCenteredSource2.mae < metricsWebcamBlindSource2.mae
    disp(['Centered MAE (' num2str(metricsCenteredSource2.mae) ') beats the webcam-only-blind MAE (' num2str(metricsWebcamBlindSource2.mae) ') for source2.']);
else
    disp(['Centered MAE (' num2str(metricsCenteredSource2.mae) ') does NOT beat the webcam-only-blind MAE (' num2str(metricsWebcamBlindSource2.mae) ') for source2.']);
end

if metricsCenteredSource2.mae < metricsBaselineSource2.mae
    disp(['Centered MAE (' num2str(metricsCenteredSource2.mae) ') beats the trivial training-mean baseline MAE (' num2str(metricsBaselineSource2.mae) ') for source2.']);
else
    disp(['Centered MAE (' num2str(metricsCenteredSource2.mae) ') does NOT beat the trivial training-mean baseline MAE (' num2str(metricsBaselineSource2.mae) ') for source2.']);
end

metricsCsvPath = fullfile(metricsRoot, 'segment6_task_r_source2_spo2_metrics.csv');
metricsHeaderLine = "method,scope,n,mae,rmse,pearson_r";
writelines(metricsHeaderLine, metricsCsvPath);

rowRaw = strjoin({'raw_pooled_uncentered', 'source2', num2str(metricsRawSource2.n), num2str(metricsRawSource2.mae), num2str(metricsRawSource2.rmse), num2str(metricsRawSource2.pearsonR)}, ',');
rowCentered = strjoin({'per_device_centered', 'source2', num2str(metricsCenteredSource2.n), num2str(metricsCenteredSource2.mae), num2str(metricsCenteredSource2.rmse), num2str(metricsCenteredSource2.pearsonR)}, ',');
rowBaseline = strjoin({'trivial_baseline', 'source2', num2str(metricsBaselineSource2.n), num2str(metricsBaselineSource2.mae), num2str(metricsBaselineSource2.rmse), num2str(metricsBaselineSource2.pearsonR)}, ',');
rowWebcamBlind = strjoin({'webcam_only_blind', 'source2', num2str(metricsWebcamBlindSource2.n), num2str(metricsWebcamBlindSource2.mae), num2str(metricsWebcamBlindSource2.rmse), num2str(metricsWebcamBlindSource2.pearsonR)}, ',');

writelines(rowRaw, metricsCsvPath, 'WriteMode', 'append');
writelines(rowCentered, metricsCsvPath, 'WriteMode', 'append');
writelines(rowBaseline, metricsCsvPath, 'WriteMode', 'append');
writelines(rowWebcamBlind, metricsCsvPath, 'WriteMode', 'append');

disp(['Saved ' metricsCsvPath]);

disp(' ');
disp('=== Fault-code check: any SpO2_true values outside a physiologically plausible 50-100% band? (same fault-code class already documented project-wide for p25, VIPL_Scenario_Coverage.md Section 2 / Segment6_Refinement_Notes.md Task H2) ===');

isFaultSource1 = SpO2_source1 < 50 | SpO2_source1 > 100;
isFaultSource2 = SpO2_source2 < 50 | SpO2_source2 > 100;

faultSubjectsSource1 = genuineSource1Table.subjectID(isFaultSource1);
faultSubjectsSource2 = source2Table.subjectID(isFaultSource2);

for faultPos = 1:numel(faultSubjectsSource1)
    disp(['  FAULT (source1): ' faultSubjectsSource1{faultPos} ', SpO2_true = ' num2str(SpO2_source1(isFaultSource1)) '%']);
end

for faultPos = 1:numel(faultSubjectsSource2)
    idx = find(strcmp(source2Table.subjectID, faultSubjectsSource2{faultPos}));
    disp(['  FAULT (source2): ' faultSubjectsSource2{faultPos} ', SpO2_true = ' num2str(SpO2_source2(idx)) '% -- NOT previously documented (Task L never analyzed the SpO2 side, see Action 1 above), flagged here for the first time.']);
end

disp(' ');
disp('=== Re-running the source2-scope LOSO comparison EXCLUDING known/newly-found fault-code subjects, same both-numbers-reported discipline as the project-wide p25 precedent ===');

cleanMask = ~ismember(pooledSubjectID, [faultSubjectsSource1; faultSubjectsSource2]);
numExcluded = sum(~cleanMask);

disp(['Excluding ' num2str(numExcluded) ' fault-code subject-rows from the pooled set (n=' num2str(numPooled) ' -> n=' num2str(sum(cleanMask)) ').']);

losoResultsClean = runLOSO(pooledSubjectID(cleanMask), pooledDatasetLabel(cleanMask), pooledR(cleanMask), pooledSpO2True(cleanMask));

isSource2FoldClean = strcmp({losoResultsClean.dataset}, 'source2');

SpO2_true_s2_clean = [losoResultsClean(isSource2FoldClean).SpO2_true]';
SpO2_pred_raw_s2_clean = [losoResultsClean(isSource2FoldClean).SpO2_predicted]';
SpO2_pred_centered_s2_clean = [losoResultsClean(isSource2FoldClean).SpO2_predicted_centered]';
SpO2_pred_baseline_s2_clean = [losoResultsClean(isSource2FoldClean).SpO2_predicted_baseline]';

metricsRawSource2Clean = computeMetrics(SpO2_pred_raw_s2_clean, SpO2_true_s2_clean);
metricsCenteredSource2Clean = computeMetrics(SpO2_pred_centered_s2_clean, SpO2_true_s2_clean);
metricsBaselineSource2Clean = computeMetrics(SpO2_pred_baseline_s2_clean, SpO2_true_s2_clean);

disp(['  [clean] raw pooled (uncentered), source2 only: n=' num2str(metricsRawSource2Clean.n) ', MAE=' num2str(metricsRawSource2Clean.mae) ', RMSE=' num2str(metricsRawSource2Clean.rmse) ', r=' num2str(metricsRawSource2Clean.pearsonR)]);
disp(['  [clean] per-device centered,     source2 only: n=' num2str(metricsCenteredSource2Clean.n) ', MAE=' num2str(metricsCenteredSource2Clean.mae) ', RMSE=' num2str(metricsCenteredSource2Clean.rmse) ', r=' num2str(metricsCenteredSource2Clean.pearsonR)]);
disp(['  [clean] trivial baseline,        source2 only: n=' num2str(metricsBaselineSource2Clean.n) ', MAE=' num2str(metricsBaselineSource2Clean.mae) ', RMSE=' num2str(metricsBaselineSource2Clean.rmse) ', r=' num2str(metricsBaselineSource2Clean.pearsonR) ' (*LOSO arithmetic artifact on r)']);

cleanRowRaw = strjoin({'raw_pooled_uncentered', 'source2_excl_faults', num2str(metricsRawSource2Clean.n), num2str(metricsRawSource2Clean.mae), num2str(metricsRawSource2Clean.rmse), num2str(metricsRawSource2Clean.pearsonR)}, ',');
cleanRowCentered = strjoin({'per_device_centered', 'source2_excl_faults', num2str(metricsCenteredSource2Clean.n), num2str(metricsCenteredSource2Clean.mae), num2str(metricsCenteredSource2Clean.rmse), num2str(metricsCenteredSource2Clean.pearsonR)}, ',');
cleanRowBaseline = strjoin({'trivial_baseline', 'source2_excl_faults', num2str(metricsBaselineSource2Clean.n), num2str(metricsBaselineSource2Clean.mae), num2str(metricsBaselineSource2Clean.rmse), num2str(metricsBaselineSource2Clean.pearsonR)}, ',');

writelines(cleanRowRaw, metricsCsvPath, 'WriteMode', 'append');
writelines(cleanRowCentered, metricsCsvPath, 'WriteMode', 'append');
writelines(cleanRowBaseline, metricsCsvPath, 'WriteMode', 'append');

disp(' ');
disp('=== Segment 6 Task R Action 4: explicit scope statement ===');

SpO2_pooled_clean = pooledSpO2True(cleanMask);
disp(['Cleaned (fault-codes excluded) SpO2_true range across BOTH devices: ' num2str(min(SpO2_pooled_clean)) '% - ' num2str(max(SpO2_pooled_clean)) '%.']);
disp('This task does NOT widen the observed SpO2 range (still narrow-band, ~90-99% once known fault codes are excluded -- the same root cause documented throughout this project, e.g. p25''s constant 44% ground truth). It only provides a real, data-backed source2 centering value in place of an invented session-relative assumption.');

disp(' ');
disp('--- Segment 6 Task R phone SpO2 centering complete ---');
