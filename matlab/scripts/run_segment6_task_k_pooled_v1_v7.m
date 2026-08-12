% RUN_SEGMENT6_TASK_K_POOLED_V1_V7 Segment 6 "Task K" driver: recomputes
% Tasks G/H/I/J's HR analysis on the pooled v1+v7 dataset, now that
% scripts/run_vipl_v7_integration_batch.m has produced v7 (after-exercise)
% HR rows alongside the existing v1 pool.
%
% This script does NOT reprocess any video or raw trace, and does NOT
% modify pulseextraction/chromCombine.m, pulseextraction/posCombine.m,
% heartrate/fftHeartRate.m, validation/computeMetrics.m,
% validation/computeAgreementConfidence.m, or
% validation/computeSwitchingEstimate.m. It only reads the already-
% computed results/metrics/segment4_hr_summary.csv (UBFC v1),
% segment4_hr_summary_vipl.csv (VIPL v1), and the new
% segment4_hr_summary_v7.csv (VIPL v7), calls the existing unmodified
% validation functions, and writes new, separate output CSVs. This is an
% ADDITION (Task K), not a rewrite of Tasks A-J in
% docs/Segment6_Refinement_Notes.md -- those numbers are left as-is.
%
% Per the project decision for Task K: the CHROM/POS agreement threshold
% is REFIT on the combined v1+v7 pool rather than frozen at Task I's
% v1-only 29.27% value, since v7 brings in higher-HR, higher-disagreement
% subjects that the v1-only threshold never saw. Both the old frozen
% threshold's pooled score and the new refit threshold's pooled score are
% reported side by side (Part 3) so neither number is thrown away.
%
% Note: SpO2 is deliberately NOT touched here. VIPL_Scenario_Coverage.md
% found v7's SpO2 ground-truth spread barely differs from v1's once fault
% codes are stripped, so runLOSO.m/runLOSOStratified.m's SpO2 pooling is
% left exactly as Tasks A-J already left it.
%
% Outputs:
%   results/metrics/segment6_hr_pooled_metrics_v1_v7.csv - CHROM/POS/green
%     MAE/RMSE/Pearson r, scope = v1_only vs v1_plus_v7, side by side.
%   results/metrics/segment6_hr_agreement_flags_v1_v7.csv - per-subject
%     relative disagreement + low-confidence flag on the v1+v7 pool, same
%     shape as Task I's segment6_hr_agreement_flags.csv.
%   results/metrics/segment6_hr_switching_metrics_v1_v7.csv - one row per
%     (method, threshold_source) pair: chrom_alone/pos_alone (threshold-
%     independent) plus switched_old_threshold (29.27%, frozen) and
%     switched_refit_threshold (this task's pooled refit), all scored on
%     the SAME v1+v7 pooled set.
%
% See docs/Segment6_Task_K_v7_Integration.md for the full writeup.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

disp('=== Segment 6 Task K: loading v1 pool (UBFC + VIPL v1) and v7 pool (VIPL v7) ===');

v1SubjectID = {};
v1Dataset = {};
v1Chrom = [];
v1Pos = [];
v1Green = [];
v1Groundtruth = [];

ubfcPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');

if isfile(ubfcPath)
    ubfcTable = readtable(ubfcPath);
    numRows = height(ubfcTable);

    for rowPos = 1:numRows
        v1SubjectID{end + 1} = extractTextTaskK(ubfcTable.subjectID, rowPos);
        v1Dataset{end + 1} = 'UBFC';
        v1Chrom(end + 1) = ubfcTable.HR_chrom(rowPos);
        v1Pos(end + 1) = ubfcTable.HR_pos(rowPos);
        v1Green(end + 1) = ubfcTable.HR_green(rowPos);
        v1Groundtruth(end + 1) = ubfcTable.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' UBFC (v1-equivalent) HR rows from ' ubfcPath]);
end

viplV1Path = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');

if isfile(viplV1Path)
    viplV1Table = readtable(viplV1Path);
    numRows = height(viplV1Table);

    for rowPos = 1:numRows
        v1SubjectID{end + 1} = extractTextTaskK(viplV1Table.subjectID, rowPos);
        v1Dataset{end + 1} = extractTextTaskK(viplV1Table.dataset, rowPos);
        v1Chrom(end + 1) = viplV1Table.HR_chrom(rowPos);
        v1Pos(end + 1) = viplV1Table.HR_pos(rowPos);
        v1Green(end + 1) = viplV1Table.HR_green(rowPos);
        v1Groundtruth(end + 1) = viplV1Table.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL v1 HR rows from ' viplV1Path]);
end

numV1 = numel(v1SubjectID);

disp(['v1-only pool: ' num2str(numV1) ' subjects.']);

v7SubjectID = {};
v7Dataset = {};
v7Chrom = [];
v7Pos = [];
v7Green = [];
v7Groundtruth = [];

viplV7Path = fullfile(metricsRoot, 'segment4_hr_summary_v7.csv');

if isfile(viplV7Path)
    viplV7Table = readtable(viplV7Path);
    numRows = height(viplV7Table);

    for rowPos = 1:numRows
        v7SubjectID{end + 1} = extractTextTaskK(viplV7Table.subjectID, rowPos);
        v7Dataset{end + 1} = extractTextTaskK(viplV7Table.dataset, rowPos);
        v7Chrom(end + 1) = viplV7Table.HR_chrom(rowPos);
        v7Pos(end + 1) = viplV7Table.HR_pos(rowPos);
        v7Green(end + 1) = viplV7Table.HR_green(rowPos);
        v7Groundtruth(end + 1) = viplV7Table.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL v7 HR rows from ' viplV7Path]);
else
    error('runSegment6TaskKPooledV1V7:noV7Data', 'segment4_hr_summary_v7.csv not found -- run scripts/run_vipl_v7_integration_batch.m first.');
end

numV7 = numel(v7SubjectID);

pooledSubjectID = [v1SubjectID, v7SubjectID];
pooledDataset = [v1Dataset, v7Dataset];
pooledChrom = [v1Chrom, v7Chrom];
pooledPos = [v1Pos, v7Pos];
pooledGreen = [v1Green, v7Green];
pooledGroundtruth = [v1Groundtruth, v7Groundtruth];

numPooled = numel(pooledSubjectID);

disp(['v1+v7 pooled: ' num2str(numPooled) ' subjects (' num2str(numV1) ' v1 + ' num2str(numV7) ' v7).']);

disp(' ');
disp('=== Part 1: pooled HR metrics, v1-only vs v1+v7-pooled, CHROM/POS/green ===');

v1ChromMetrics = computeMetrics(v1Chrom, v1Groundtruth);
v1PosMetrics = computeMetrics(v1Pos, v1Groundtruth);
v1GreenMetrics = computeMetrics(v1Green, v1Groundtruth);

pooledChromMetrics = computeMetrics(pooledChrom, pooledGroundtruth);
pooledPosMetrics = computeMetrics(pooledPos, pooledGroundtruth);
pooledGreenMetrics = computeMetrics(pooledGreen, pooledGroundtruth);

disp(' ');
disp('Method  | Scope       | N   | MAE     | RMSE    | Pearson r');
disp(['CHROM   | v1-only     | ' num2str(v1ChromMetrics.n) ' | ' num2str(v1ChromMetrics.mae) ' | ' num2str(v1ChromMetrics.rmse) ' | ' num2str(v1ChromMetrics.pearsonR)]);
disp(['CHROM   | v1+v7 pooled| ' num2str(pooledChromMetrics.n) ' | ' num2str(pooledChromMetrics.mae) ' | ' num2str(pooledChromMetrics.rmse) ' | ' num2str(pooledChromMetrics.pearsonR)]);
disp(['POS     | v1-only     | ' num2str(v1PosMetrics.n) ' | ' num2str(v1PosMetrics.mae) ' | ' num2str(v1PosMetrics.rmse) ' | ' num2str(v1PosMetrics.pearsonR)]);
disp(['POS     | v1+v7 pooled| ' num2str(pooledPosMetrics.n) ' | ' num2str(pooledPosMetrics.mae) ' | ' num2str(pooledPosMetrics.rmse) ' | ' num2str(pooledPosMetrics.pearsonR)]);
disp(['Green   | v1-only     | ' num2str(v1GreenMetrics.n) ' | ' num2str(v1GreenMetrics.mae) ' | ' num2str(v1GreenMetrics.rmse) ' | ' num2str(v1GreenMetrics.pearsonR)]);
disp(['Green   | v1+v7 pooled| ' num2str(pooledGreenMetrics.n) ' | ' num2str(pooledGreenMetrics.mae) ' | ' num2str(pooledGreenMetrics.rmse) ' | ' num2str(pooledGreenMetrics.pearsonR)]);

pooledMetricsCsvPath = fullfile(metricsRoot, 'segment6_hr_pooled_metrics_v1_v7.csv');
pooledMetricsHeaderLine = "method,scope,n,mae,rmse,pearson_r";
writelines(pooledMetricsHeaderLine, pooledMetricsCsvPath);

writelines(strjoin({'chrom', 'v1_only', num2str(v1ChromMetrics.n), num2str(v1ChromMetrics.mae), num2str(v1ChromMetrics.rmse), num2str(v1ChromMetrics.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'chrom', 'v1_plus_v7', num2str(pooledChromMetrics.n), num2str(pooledChromMetrics.mae), num2str(pooledChromMetrics.rmse), num2str(pooledChromMetrics.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'pos', 'v1_only', num2str(v1PosMetrics.n), num2str(v1PosMetrics.mae), num2str(v1PosMetrics.rmse), num2str(v1PosMetrics.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'pos', 'v1_plus_v7', num2str(pooledPosMetrics.n), num2str(pooledPosMetrics.mae), num2str(pooledPosMetrics.rmse), num2str(pooledPosMetrics.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'green', 'v1_only', num2str(v1GreenMetrics.n), num2str(v1GreenMetrics.mae), num2str(v1GreenMetrics.rmse), num2str(v1GreenMetrics.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'green', 'v1_plus_v7', num2str(pooledGreenMetrics.n), num2str(pooledGreenMetrics.mae), num2str(pooledGreenMetrics.rmse), num2str(pooledGreenMetrics.pearsonR)}, ','), pooledMetricsCsvPath, 'WriteMode', 'append');

disp(['Saved ' pooledMetricsCsvPath]);

disp(' ');
disp('=== Part 2: refit CHROM/POS agreement threshold on the v1+v7 pool (Task I method, new pool) ===');

relativeDisagreement = computeAgreementConfidence(pooledChrom, pooledPos);

relativeDisagreementPercent = zeros(1, numPooled);

for i = 1:numPooled
    relativeDisagreementPercent(i) = relativeDisagreement(i) * 100;
end

minPercent = min(relativeDisagreementPercent);
medianPercent = median(relativeDisagreementPercent);
maxPercent = max(relativeDisagreementPercent);

disp(['min = ' num2str(minPercent) '%, median = ' num2str(medianPercent) '%, max = ' num2str(maxPercent) '%']);

sortedPercent = sort(relativeDisagreementPercent);
nonZeroSortedPercent = sortedPercent(sortedPercent > 0);
numNonZero = numel(nonZeroSortedPercent);

largestGapValue = 0;
largestGapLowerBound = 0;
secondLargestGapValue = 0;
secondLargestGapLowerBound = 0;

for i = 2:numNonZero
    gapValue = nonZeroSortedPercent(i) - nonZeroSortedPercent(i - 1);

    if gapValue > largestGapValue
        secondLargestGapValue = largestGapValue;
        secondLargestGapLowerBound = largestGapLowerBound;
        largestGapValue = gapValue;
        largestGapLowerBound = nonZeroSortedPercent(i - 1);
    elseif gapValue > secondLargestGapValue
        secondLargestGapValue = gapValue;
        secondLargestGapLowerBound = nonZeroSortedPercent(i - 1);
    end
end

disp(['Largest gap in the sorted non-zero disagreement values: ' num2str(largestGapValue) ' percentage points, sitting right above ' num2str(largestGapLowerBound) '%.']);
disp(['Second-largest gap: ' num2str(secondLargestGapValue) ' percentage points, sitting right above ' num2str(secondLargestGapLowerBound) '%.']);

refitThresholdPercent = secondLargestGapLowerBound;
refitThresholdFraction = refitThresholdPercent / 100;

disp(['Refit low-confidence threshold on v1+v7 pool (second-largest-gap lower bound): ' num2str(refitThresholdPercent) '% relative disagreement.']);
disp(['For comparison, Task I''s old v1-only threshold was 29.27% -- this task does NOT discard that number, see Part 3 below.']);

lowConfidenceFlag = false(1, numPooled);
numFlagged = 0;

for i = 1:numPooled
    if relativeDisagreementPercent(i) > refitThresholdPercent
        lowConfidenceFlag(i) = true;
        numFlagged = numFlagged + 1;
    end
end

disp(['Subjects flagged low-confidence under the refit threshold: ' num2str(numFlagged) ' of ' num2str(numPooled) ' (' num2str(numFlagged / numPooled * 100) '%).']);

agreementCsvPath = fullfile(metricsRoot, 'segment6_hr_agreement_flags_v1_v7.csv');
agreementHeaderLine = "subjectID,dataset,HR_chrom,HR_pos,HR_groundtruth,relative_disagreement,low_confidence_flag_refit";
writelines(agreementHeaderLine, agreementCsvPath);

for i = 1:numPooled
    flagValue = 0;

    if lowConfidenceFlag(i)
        flagValue = 1;
    end

    rowParts = {pooledSubjectID{i}, pooledDataset{i}, num2str(pooledChrom(i)), num2str(pooledPos(i)), num2str(pooledGroundtruth(i)), num2str(relativeDisagreement(i)), num2str(flagValue)};
    rowLine = strjoin(rowParts, ',');
    writelines(rowLine, agreementCsvPath, 'WriteMode', 'append');
end

disp(['Saved ' agreementCsvPath]);

disp(' ');
disp('=== Part 3: switching estimator on the v1+v7 pool -- refit threshold vs. old frozen 29.27% threshold ===');
disp('CAVEAT: the refit threshold is derived from and scored on the SAME v1+v7 pool -- not a clean out-of-sample validation of the refit rule, same caveat Task J already carried for the v1-only threshold.');

oldThresholdPercent = 29.27;
oldThresholdFraction = oldThresholdPercent / 100;

[HR_switched_refit, usedPosRefit] = computeSwitchingEstimate(pooledChrom, pooledPos, refitThresholdFraction);
[HR_switched_old, usedPosOld] = computeSwitchingEstimate(pooledChrom, pooledPos, oldThresholdFraction);

numSwitchedRefit = sum(usedPosRefit);
numSwitchedOld = sum(usedPosOld);

disp(['Refit threshold (' num2str(refitThresholdPercent) '%): switch fired for ' num2str(numSwitchedRefit) ' of ' num2str(numPooled) ' subjects (' num2str(numSwitchedRefit / numPooled * 100) '%).']);
disp(['Old frozen threshold (' num2str(oldThresholdPercent) '%): switch fired for ' num2str(numSwitchedOld) ' of ' num2str(numPooled) ' subjects (' num2str(numSwitchedOld / numPooled * 100) '%).']);

chromPooledMetrics = computeMetrics(pooledChrom, pooledGroundtruth);
posPooledMetrics = computeMetrics(pooledPos, pooledGroundtruth);
switchedRefitMetrics = computeMetrics(HR_switched_refit, pooledGroundtruth);
switchedOldMetrics = computeMetrics(HR_switched_old, pooledGroundtruth);

disp(' ');
disp('Method                    | N   | MAE     | RMSE    | Pearson r');
disp(['CHROM alone               | ' num2str(chromPooledMetrics.n) ' | ' num2str(chromPooledMetrics.mae) ' | ' num2str(chromPooledMetrics.rmse) ' | ' num2str(chromPooledMetrics.pearsonR)]);
disp(['POS alone                 | ' num2str(posPooledMetrics.n) ' | ' num2str(posPooledMetrics.mae) ' | ' num2str(posPooledMetrics.rmse) ' | ' num2str(posPooledMetrics.pearsonR)]);
disp(['Switched (old 29.27%)     | ' num2str(switchedOldMetrics.n) ' | ' num2str(switchedOldMetrics.mae) ' | ' num2str(switchedOldMetrics.rmse) ' | ' num2str(switchedOldMetrics.pearsonR)]);
disp(['Switched (refit ' num2str(refitThresholdPercent) '%) | ' num2str(switchedRefitMetrics.n) ' | ' num2str(switchedRefitMetrics.mae) ' | ' num2str(switchedRefitMetrics.rmse) ' | ' num2str(switchedRefitMetrics.pearsonR)]);

switchingCsvPath = fullfile(metricsRoot, 'segment6_hr_switching_metrics_v1_v7.csv');
switchingHeaderLine = "method,threshold_source,threshold_percent,scope,n,mae,rmse,pearson_r";
writelines(switchingHeaderLine, switchingCsvPath);

writelines(strjoin({'chrom_alone', 'n/a', 'n/a', 'v1_plus_v7_pooled', num2str(chromPooledMetrics.n), num2str(chromPooledMetrics.mae), num2str(chromPooledMetrics.rmse), num2str(chromPooledMetrics.pearsonR)}, ','), switchingCsvPath, 'WriteMode', 'append');
writelines(strjoin({'pos_alone', 'n/a', 'n/a', 'v1_plus_v7_pooled', num2str(posPooledMetrics.n), num2str(posPooledMetrics.mae), num2str(posPooledMetrics.rmse), num2str(posPooledMetrics.pearsonR)}, ','), switchingCsvPath, 'WriteMode', 'append');
writelines(strjoin({'switched', 'old_frozen_task_i', num2str(oldThresholdPercent), 'v1_plus_v7_pooled', num2str(switchedOldMetrics.n), num2str(switchedOldMetrics.mae), num2str(switchedOldMetrics.rmse), num2str(switchedOldMetrics.pearsonR)}, ','), switchingCsvPath, 'WriteMode', 'append');
writelines(strjoin({'switched', 'refit_task_k', num2str(refitThresholdPercent), 'v1_plus_v7_pooled', num2str(switchedRefitMetrics.n), num2str(switchedRefitMetrics.mae), num2str(switchedRefitMetrics.rmse), num2str(switchedRefitMetrics.pearsonR)}, ','), switchingCsvPath, 'WriteMode', 'append');

disp(['Saved ' switchingCsvPath]);

disp(' ');
disp('=== Part 4: failure-mode check for the refit-threshold switch ===');

numSwitchHelped = 0;
numSwitchHurt = 0;
numSwitchTied = 0;

for i = 1:numPooled
    if ~usedPosRefit(i)
        continue;
    end

    absErrorChromThis = abs(pooledChrom(i) - pooledGroundtruth(i));
    absErrorPosThis = abs(pooledPos(i) - pooledGroundtruth(i));

    if absErrorPosThis < absErrorChromThis
        numSwitchHelped = numSwitchHelped + 1;
    elseif absErrorPosThis > absErrorChromThis
        numSwitchHurt = numSwitchHurt + 1;
    else
        numSwitchTied = numSwitchTied + 1;
    end
end

disp(['Of the ' num2str(numSwitchedRefit) ' subjects where the refit-threshold switch fired:']);
disp(['  Switch HELPED (POS error < CHROM error): ' num2str(numSwitchHelped) ' subjects.']);
disp(['  Switch HURT (POS error > CHROM error):   ' num2str(numSwitchHurt) ' subjects.']);
disp(['  Tied (POS error == CHROM error):         ' num2str(numSwitchTied) ' subjects.']);

disp(' ');
disp('--- Segment 6 Task K batch complete ---');

function textVal = extractTextTaskK(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
