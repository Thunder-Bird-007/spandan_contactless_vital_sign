% RUN_TASK_Q_2WAY_REGION_SWITCHING Segment 6 Task Q, Part 2 Action 5:
% runs the forehead/cheek-only 2-way region switch (validation/
% computeRegionAgreement2Way.m, validation/
% computeRegionSwitchingEstimate2Way.m) on Task N's existing 4-scenario,
% 20-subject pool, reusing the already-cached per-region HR estimates in
% results/metrics/segment6_task_n_region_hr_summary.csv -- no video
% reprocessing, no re-extraction, no changes to roi/extractROISignals.m's
% region-mode geometry or any other validated core file.
%
% Scenario label note: the CSV's scenario column still says "v4_dark" for
% what docs/Task_N_v4_v5_Brightness_Verification.md proved by direct
% pixel measurement is actually the BRIGHT scenario (v4) -- the CSV
% column itself was never renamed, only the report prose was corrected
% (see docs/Segment6_Task_N_Multi_Region_ROI.md's label-correction note).
% This script keeps reading the literal "v4_dark" CSV key but displays it
% as "v4 (bright)" throughout, same as Task N's own report does.
%
% Outputs:
%   results/metrics/segment6_task_q_2way_switching_summary.csv - per
%     scenario: MAE/RMSE/Pearson r/N for the 2-way switch, alongside Task
%     N's existing best-single-region numbers for that scenario.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

disp('=== Segment 6 Task Q Part 2 Action 5: loading Task N region HR summary (segment6_task_n_region_hr_summary.csv) ===');

regionCsvPath = fullfile(metricsRoot, 'segment6_task_n_region_hr_summary.csv');
regionTable = readtable(regionCsvPath);
numRows = height(regionTable);

disp(['Loaded ' num2str(numRows) ' (subject, scenario) rows from ' regionCsvPath]);

scenarioKeys = {'v1_baseline', 'v2_motion', 'v4_dark', 'v5_dark'};
scenarioLabels = {'v1 (baseline)', 'v2 (motion)', 'v4 (bright)', 'v5 (dark)'};
bestSingleRegionName = {'cheek', 'forehead', 'forehead', 'cheek'};

numScenarios = numel(scenarioKeys);

metricsCsvPath = fullfile(metricsRoot, 'segment6_task_q_2way_switching_summary.csv');
metricsHeaderLine = "scenario,method,n,mae,rmse,pearson_r";
writelines(metricsHeaderLine, metricsCsvPath);

disp(' ');
disp('=== Per-scenario 2-way (forehead/cheek) switching vs Task N''s best single region ===');
disp(' ');
disp('Scenario       | Method              | N  | MAE     | RMSE    | Pearson r');

for scenarioIdx = 1:numScenarios
    thisScenarioKey = scenarioKeys{scenarioIdx};
    thisScenarioLabel = scenarioLabels{scenarioIdx};
    thisBestSingleRegion = bestSingleRegionName{scenarioIdx};

    scenarioRowMask = strcmp(regionTable.scenario, thisScenarioKey);

    HR_forehead = regionTable.HR_forehead(scenarioRowMask);
    HR_cheek = regionTable.HR_cheek(scenarioRowMask);
    HR_groundtruth = regionTable.HR_groundtruth(scenarioRowMask);

    numSubjectsThisScenario = sum(scenarioRowMask);

    disp(['--- ' thisScenarioLabel ': ' num2str(numSubjectsThisScenario) ' subjects loaded ---']);

    relativeSpread2Way = computeRegionAgreement2Way(HR_forehead, HR_cheek);
    [HR_switched2Way, selectedRegion2Way] = computeRegionSwitchingEstimate2Way(HR_forehead, HR_cheek);

    numSelectedForehead = sum(strcmp(selectedRegion2Way, 'forehead'));
    numSelectedCheek = sum(strcmp(selectedRegion2Way, 'cheek'));

    disp(['  2-way selection counts: forehead = ' num2str(numSelectedForehead) ', cheek = ' num2str(numSelectedCheek) ' (mean relative spread = ' num2str(mean(relativeSpread2Way)) ')']);

    if numSelectedCheek == 0
        disp('  CONFIRMS the documented degeneracy: computeRegionSwitchingEstimate2Way.m selected forehead for every subject in this scenario (proven mathematically, not scenario-specific).');
    end

    if strcmp(thisBestSingleRegion, 'forehead')
        HR_bestSingle = HR_forehead;
    else
        HR_bestSingle = HR_cheek;
    end

    metrics2Way = computeMetrics(HR_switched2Way, HR_groundtruth);
    metricsBestSingle = computeMetrics(HR_bestSingle, HR_groundtruth);
    metricsForehead = computeMetrics(HR_forehead, HR_groundtruth);
    metricsCheek = computeMetrics(HR_cheek, HR_groundtruth);

    disp([thisScenarioLabel ' | 2-way switch        | ' num2str(metrics2Way.n) ' | ' num2str(metrics2Way.mae) ' | ' num2str(metrics2Way.rmse) ' | ' num2str(metrics2Way.pearsonR)]);
    disp([thisScenarioLabel ' | best single (' thisBestSingleRegion ') | ' num2str(metricsBestSingle.n) ' | ' num2str(metricsBestSingle.mae) ' | ' num2str(metricsBestSingle.rmse) ' | ' num2str(metricsBestSingle.pearsonR)]);
    disp([thisScenarioLabel ' | forehead alone      | ' num2str(metricsForehead.n) ' | ' num2str(metricsForehead.mae) ' | ' num2str(metricsForehead.rmse) ' | ' num2str(metricsForehead.pearsonR)]);
    disp([thisScenarioLabel ' | cheek alone         | ' num2str(metricsCheek.n) ' | ' num2str(metricsCheek.mae) ' | ' num2str(metricsCheek.rmse) ' | ' num2str(metricsCheek.pearsonR)]);
    disp(' ');

    row2Way = strjoin({thisScenarioKey, 'switch_2way', num2str(metrics2Way.n), num2str(metrics2Way.mae), num2str(metrics2Way.rmse), num2str(metrics2Way.pearsonR)}, ',');
    rowBestSingle = strjoin({thisScenarioKey, ['best_single_' thisBestSingleRegion], num2str(metricsBestSingle.n), num2str(metricsBestSingle.mae), num2str(metricsBestSingle.rmse), num2str(metricsBestSingle.pearsonR)}, ',');
    rowForehead = strjoin({thisScenarioKey, 'forehead', num2str(metricsForehead.n), num2str(metricsForehead.mae), num2str(metricsForehead.rmse), num2str(metricsForehead.pearsonR)}, ',');
    rowCheek = strjoin({thisScenarioKey, 'cheek', num2str(metricsCheek.n), num2str(metricsCheek.mae), num2str(metricsCheek.rmse), num2str(metricsCheek.pearsonR)}, ',');

    writelines(row2Way, metricsCsvPath, 'WriteMode', 'append');
    writelines(rowBestSingle, metricsCsvPath, 'WriteMode', 'append');
    writelines(rowForehead, metricsCsvPath, 'WriteMode', 'append');
    writelines(rowCheek, metricsCsvPath, 'WriteMode', 'append');
end

disp(['Saved ' metricsCsvPath]);

disp(' ');
disp('--- Segment 6 Task Q Part 2 Action 5 2-way region switching complete ---');
