% RUN_SEGMENT6_TASK5_RAKF_BATCH Segment 6 Action 5. Head-to-head:
% validation/residualAdaptiveKalmanHR.m (RAKF, Debnath & Kim 2026) vs.
% Task P/Q's existing windowed-consistency methods, on the SAME 107-
% subject v1 VIPL pool and the SAME cached per-window candidates/quality
% scores those tasks used (heartrate/windowedHeartRate.m's output) --
% then RAKF alone (no Task P/Q comparison exists for these) on the full
% pooled 112 (5 UBFC + 107 VIPL) for generalization.
%
% Does NOT reprocess any video -- loads the same cached
% data/processed/<subjectID>_rgb_traces.mat / _filtered_traces.mat Task P
% used. Does NOT modify heartrate/windowedHeartRate.m,
% validation/selectHarmonicConsistentHR.m,
% validation/selectHarmonicConsistentHR_anchored.m,
% validation/computeWindowQualityThreshold.m,
% validation/aggregateGatedWindowHR.m, or
% validation/residualAdaptiveKalmanHR.m.
%
% Part 1 (head-to-head, 107 VIPL): whole-clip/naiveWindowed/gatingOnly/
% gatingPlusContinuity/gatingPlusAnchoredContinuity are read DIRECTLY from
% results/metrics/segment6_task_q_anchored_windowed_hr_summary.csv (Task
% Q's own output already has all five) -- not recomputed, so this is an
% exact apples-to-apples comparison against already-published numbers.
% RAKF is computed fresh here from each subject's own cached
% windowResults (same windows, same candidates, same quality scores Task
% P/Q used).
%
% Part 2 (pooled 112, generalization): whole-clip (already-validated
% results/metrics/segment6_hr_pooled_metrics.csv's CHROM row, read not
% recomputed) vs. RAKF (computed fresh on the same 112 subjects' cached
% traces).
%
% Outputs:
%   results/metrics/segment6_task5_rakf_vipl107_hr_summary.csv
%   results/metrics/segment6_task5_rakf_vipl107_metrics.csv (6-row
%     head-to-head)
%   results/metrics/segment6_task5_rakf_pooled112_metrics.csv (2-row:
%     whole-clip vs RAKF)

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

disp('=== Segment 6 Task 5 (RAKF), Part 1: 107 VIPL pool head-to-head vs Task P/Q ===');

taskQCsvPath = fullfile(metricsRoot, 'segment6_task_q_anchored_windowed_hr_summary.csv');
taskQTable = readtable(taskQCsvPath, 'TextType', 'string');
numViplSubjects = height(taskQTable);

hrRakfVipl = nan(numViplSubjects, 1);
viplUsable = false(numViplSubjects, 1);
failedVipl = {};

for rowPos = 1:numViplSubjects
    subjID = char(taskQTable.subjectID(rowPos));

    try
        rgbMatPath = fullfile(processedDataRoot, [subjID '_rgb_traces.mat']);
        filteredMatPath = fullfile(processedDataRoot, [subjID '_filtered_traces.mat']);
        rgbData = load(rgbMatPath);
        filteredData = load(filteredMatPath);
        fs = filteredData.fs;

        pulseChrom = chromCombine(filteredData.R_filtered, filteredData.G_filtered, filteredData.B_filtered, rgbData.R, rgbData.G, rgbData.B);
        pulseChromFiltered = bandpassClean(pulseChrom, fs);

        [~, windowResultsThis] = windowedHeartRate(pulseChromFiltered, fs);

        hrRakfVipl(rowPos) = residualAdaptiveKalmanHR(windowResultsThis.candidateBpm(:, 1), windowResultsThis.qualityScore);
        viplUsable(rowPos) = true;
    catch causeErr
        disp([subjID ': FAILED -- ' causeErr.message]);
        failedVipl{end + 1} = subjID; %#ok<AGROW>
    end
end

disp([num2str(sum(viplUsable)) ' of ' num2str(numViplSubjects) ' VIPL subjects usable for RAKF, ' num2str(numel(failedVipl)) ' failed.']);

hrSummaryCsvPath = fullfile(metricsRoot, 'segment6_task5_rakf_vipl107_hr_summary.csv');
hrHeaderLine = "subjectID,HR_wholeClip,HR_naiveWindowed,HR_gatingOnly,HR_gatingPlusContinuity_TaskP,HR_gatingPlusAnchoredContinuity_TaskQ,HR_RAKF,HR_groundtruth";
writelines(hrHeaderLine, hrSummaryCsvPath);

for rowPos = 1:numViplSubjects
    if ~viplUsable(rowPos)
        continue
    end
    row = {char(taskQTable.subjectID(rowPos)), num2str(taskQTable.HR_wholeClip(rowPos)), num2str(taskQTable.HR_naiveWindowed(rowPos)), ...
        num2str(taskQTable.HR_gatingOnly(rowPos)), num2str(taskQTable.HR_gatingPlusWindow1Continuity(rowPos)), ...
        num2str(taskQTable.HR_gatingPlusAnchoredContinuity(rowPos)), num2str(hrRakfVipl(rowPos)), num2str(taskQTable.HR_groundtruth(rowPos))};
    writelines(strjoin(row, ','), hrSummaryCsvPath, 'WriteMode', 'append');
end
disp(['Saved ' hrSummaryCsvPath]);

usableIdx = find(viplUsable);
gt = taskQTable.HR_groundtruth(usableIdx);

metricsWholeClip = computeMetrics(taskQTable.HR_wholeClip(usableIdx), gt);
metricsNaiveWindowed = computeMetrics(taskQTable.HR_naiveWindowed(usableIdx), gt);
metricsGatingOnly = computeMetrics(taskQTable.HR_gatingOnly(usableIdx), gt);
metricsGatingContinuityP = computeMetrics(taskQTable.HR_gatingPlusWindow1Continuity(usableIdx), gt);
metricsGatingAnchoredQ = computeMetrics(taskQTable.HR_gatingPlusAnchoredContinuity(usableIdx), gt);
metricsRakf = computeMetrics(hrRakfVipl(usableIdx), gt);

disp(' ');
disp('Method                              | N   | MAE     | RMSE    | Pearson r');
disp(['whole-clip (baseline)               | ' num2str(metricsWholeClip.n) ' | ' num2str(metricsWholeClip.mae) ' | ' num2str(metricsWholeClip.rmse) ' | ' num2str(metricsWholeClip.pearsonR)]);
disp(['naive windowed                      | ' num2str(metricsNaiveWindowed.n) ' | ' num2str(metricsNaiveWindowed.mae) ' | ' num2str(metricsNaiveWindowed.rmse) ' | ' num2str(metricsNaiveWindowed.pearsonR)]);
disp(['gating only                         | ' num2str(metricsGatingOnly.n) ' | ' num2str(metricsGatingOnly.mae) ' | ' num2str(metricsGatingOnly.rmse) ' | ' num2str(metricsGatingOnly.pearsonR)]);
disp(['gating + continuity (Task P)        | ' num2str(metricsGatingContinuityP.n) ' | ' num2str(metricsGatingContinuityP.mae) ' | ' num2str(metricsGatingContinuityP.rmse) ' | ' num2str(metricsGatingContinuityP.pearsonR)]);
disp(['gating + anchored continuity (Task Q)| ' num2str(metricsGatingAnchoredQ.n) ' | ' num2str(metricsGatingAnchoredQ.mae) ' | ' num2str(metricsGatingAnchoredQ.rmse) ' | ' num2str(metricsGatingAnchoredQ.pearsonR)]);
disp(['RAKF (Task 5, NEW)                  | ' num2str(metricsRakf.n) ' | ' num2str(metricsRakf.mae) ' | ' num2str(metricsRakf.rmse) ' | ' num2str(metricsRakf.pearsonR)]);

metricsCsvPath = fullfile(metricsRoot, 'segment6_task5_rakf_vipl107_metrics.csv');
metricsHeaderLine = "method,n,mae,rmse,pearson_r";
writelines(metricsHeaderLine, metricsCsvPath);
methodRows = {
    {'whole_clip_baseline', metricsWholeClip}
    {'naive_windowed', metricsNaiveWindowed}
    {'gating_only', metricsGatingOnly}
    {'gating_plus_continuity_taskP', metricsGatingContinuityP}
    {'gating_plus_anchored_continuity_taskQ', metricsGatingAnchoredQ}
    {'rakf_task5', metricsRakf}
};
for i = 1:numel(methodRows)
    name = methodRows{i}{1};
    m = methodRows{i}{2};
    writelines(strjoin({name, num2str(m.n), num2str(m.mae), num2str(m.rmse), num2str(m.pearsonR)}, ','), metricsCsvPath, 'WriteMode', 'append');
end
disp(['Saved ' metricsCsvPath]);

disp(' ');
disp('=== Segment 6 Task 5 (RAKF), Part 2: pooled 112 (5 UBFC + 107 VIPL) generalization ===');

ubfcCsvPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');
viplHrCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');
ubfcTable = readtable(ubfcCsvPath, 'TextType', 'string');
viplHrTable = readtable(viplHrCsvPath, 'TextType', 'string');

pooledSubjectID = [ubfcTable.subjectID; viplHrTable.subjectID];
pooledGT = [ubfcTable.HR_groundtruth; viplHrTable.HR_groundtruth];
pooledWholeClipChrom = [ubfcTable.HR_chrom; viplHrTable.HR_chrom];

numPooled = numel(pooledSubjectID);
hrRakfPooled = nan(numPooled, 1);
pooledUsable = false(numPooled, 1);
failedPooled = {};

for rowPos = 1:numPooled
    subjID = char(pooledSubjectID(rowPos));
    try
        rgbMatPath = fullfile(processedDataRoot, [subjID '_rgb_traces.mat']);
        filteredMatPath = fullfile(processedDataRoot, [subjID '_filtered_traces.mat']);
        rgbData = load(rgbMatPath);
        filteredData = load(filteredMatPath);
        fs = filteredData.fs;

        pulseChrom = chromCombine(filteredData.R_filtered, filteredData.G_filtered, filteredData.B_filtered, rgbData.R, rgbData.G, rgbData.B);
        pulseChromFiltered = bandpassClean(pulseChrom, fs);

        [~, windowResultsThis] = windowedHeartRate(pulseChromFiltered, fs);
        hrRakfPooled(rowPos) = residualAdaptiveKalmanHR(windowResultsThis.candidateBpm(:, 1), windowResultsThis.qualityScore);
        pooledUsable(rowPos) = true;
    catch causeErr
        disp([subjID ': FAILED (pooled) -- ' causeErr.message]);
        failedPooled{end + 1} = subjID; %#ok<AGROW>
    end
end

pooledUsableIdx = find(pooledUsable);
disp([num2str(numel(pooledUsableIdx)) ' of ' num2str(numPooled) ' pooled subjects usable for RAKF, ' num2str(numel(failedPooled)) ' failed.']);

metricsWholeClipPooled = computeMetrics(pooledWholeClipChrom(pooledUsableIdx), pooledGT(pooledUsableIdx));
metricsRakfPooled = computeMetrics(hrRakfPooled(pooledUsableIdx), pooledGT(pooledUsableIdx));

disp(' ');
disp('Method                    | N   | MAE     | RMSE    | Pearson r');
disp(['whole-clip CHROM baseline | ' num2str(metricsWholeClipPooled.n) ' | ' num2str(metricsWholeClipPooled.mae) ' | ' num2str(metricsWholeClipPooled.rmse) ' | ' num2str(metricsWholeClipPooled.pearsonR)]);
disp(['RAKF (Task 5, NEW)        | ' num2str(metricsRakfPooled.n) ' | ' num2str(metricsRakfPooled.mae) ' | ' num2str(metricsRakfPooled.rmse) ' | ' num2str(metricsRakfPooled.pearsonR)]);

pooledMetricsCsvPath = fullfile(metricsRoot, 'segment6_task5_rakf_pooled112_metrics.csv');
pooledMetricsHeaderLine = "method,n,mae,rmse,pearson_r";
writelines(pooledMetricsHeaderLine, pooledMetricsCsvPath);
writelines(strjoin({'whole_clip_chrom_baseline', num2str(metricsWholeClipPooled.n), num2str(metricsWholeClipPooled.mae), num2str(metricsWholeClipPooled.rmse), num2str(metricsWholeClipPooled.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'rakf_task5', num2str(metricsRakfPooled.n), num2str(metricsRakfPooled.mae), num2str(metricsRakfPooled.rmse), num2str(metricsRakfPooled.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');
disp(['Saved ' pooledMetricsCsvPath]);

disp(' ');
disp('--- Segment 6 Task 5 (RAKF) batch complete ---');
