% RUN_SEGMENT6_REGION_SWITCH_WEIGHTED_PILOT Exploratory pilot (Spandan
% Field Guide "still open" list), Action 3. Feasibility/direction-finding
% only -- SMALL slice on purpose. Tests
% validation/computeRegionSwitchingEstimateWeighted.m (NEW, additive --
% does not replace or modify computeRegionSwitchingEstimate.m or
% computeRegionSwitchingEstimate2Way.m) against the two Task N scenarios
% where the existing unweighted switcher already showed promise: v2
% (motion) and v5 (dark) -- NOT v1/v4 (where the existing switcher already
% loses to a single region) and not a fresh subject pool.
%
% Does NOT reprocess any video or recompute any per-region HR estimate --
% reads the already-cached per-region HR values directly from
% results/metrics/segment6_task_n_region_hr_summary.csv (the exact same
% source docs/Segment6_Task_N_Multi_Region_ROI.md Section 5's 7.72/4.79
% numbers came from), for the v2_motion and v5_dark scenario rows only (20
% subjects each, same N as the reference numbers -- no subject subsetting
% needed since this is already-cached, zero-marginal-cost data, not a new
% video-processing batch).
%
% Reference points (from docs/Segment6_Task_N_Multi_Region_ROI.md Section
% 5, NOT recomputed, quoted for comparison only):
%   v2 (motion): best single region = forehead, MAE 8.18. Existing
%     (unweighted) switcher: MAE 7.72.
%   v5 (dark):   best single region = cheek, MAE 4.98. Existing
%     (unweighted) switcher: MAE 4.79.
%
% Output: results/metrics/segment6_region_switch_weighted_pilot.csv

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

taskNCsvPath = fullfile(metricsRoot, 'segment6_task_n_region_hr_summary.csv');
taskNTable = readtable(taskNCsvPath, 'TextType', 'string');

scenarios = {'v2_motion', 'v5_dark'};

% Reference numbers, quoted from docs/Segment6_Task_N_Multi_Region_ROI.md
% Section 5 -- NOT recomputed here, kept as literal reference constants so
% this script's own output can be compared against them without re-deriving.
referenceBestSingleRegionName = struct('v2_motion', 'forehead', 'v5_dark', 'cheek');
referenceBestSingleRegionMae = struct('v2_motion', 8.18, 'v5_dark', 4.98);
referenceExistingSwitcherMae = struct('v2_motion', 7.72, 'v5_dark', 4.79);

outCsvPath = fullfile(metricsRoot, 'segment6_region_switch_weighted_pilot.csv');
headerLine = "scenario,method,N,MAE,RMSE,Pearson_r";
writelines(headerLine, outCsvPath);

disp('=== Segment 6 region-switching pilot: weighted standout-first rule, v2/v5 only ===');

for scenarioPos = 1:numel(scenarios)
    scenarioName = scenarios{scenarioPos};
    scenarioMask = taskNTable.scenario == scenarioName;
    scenarioTable = taskNTable(scenarioMask, :);
    n = height(scenarioTable);

    hrForehead = scenarioTable.HR_forehead;
    hrGlabella = scenarioTable.HR_glabella;
    hrMalar = scenarioTable.HR_malar;
    hrCheek = scenarioTable.HR_cheek;
    hrGroundtruth = scenarioTable.HR_groundtruth;

    disp(' ');
    disp(['--- Scenario: ' scenarioName ' (N=' num2str(n) ') ---']);

    % --- New weighted switcher (this pilot). ---
    [hrSwitchedWeighted, selectedRegionWeighted, usedStandout] = computeRegionSwitchingEstimateWeighted(hrForehead, hrGlabella, hrMalar, hrCheek);
    metricsWeighted = computeMetrics(hrSwitchedWeighted, hrGroundtruth);

    numStandout = sum(usedStandout);
    disp(['Standout branch fired for ' num2str(numStandout) '/' num2str(n) ' subjects; weighted-vote fallback fired for the other ' num2str(n - numStandout) '.']);

    regionCounts = struct('forehead', 0, 'glabella', 0, 'malar', 0, 'cheek', 0);
    for i = 1:n
        regionCounts.(selectedRegionWeighted{i}) = regionCounts.(selectedRegionWeighted{i}) + 1;
    end
    disp(['Region selection counts (weighted rule): forehead=' num2str(regionCounts.forehead) ...
        ', glabella=' num2str(regionCounts.glabella) ', malar=' num2str(regionCounts.malar) ...
        ', cheek=' num2str(regionCounts.cheek)]);

    disp(['NEW weighted switcher: MAE=' num2str(metricsWeighted.mae) ' RMSE=' num2str(metricsWeighted.rmse) ' r=' num2str(metricsWeighted.pearsonR)]);

    % --- Existing (unweighted) switcher, recomputed here on this same
    % slice for a same-N, same-data direct comparison (its own numbers in
    % the doc were computed over the same 20 subjects, but recomputing
    % directly here removes any doubt). ---
    [hrSwitchedExisting, ~] = computeRegionSwitchingEstimate(hrForehead, hrGlabella, hrMalar, hrCheek);
    metricsExisting = computeMetrics(hrSwitchedExisting, hrGroundtruth);
    disp(['Existing (unweighted) switcher, recomputed on this slice: MAE=' num2str(metricsExisting.mae) ' RMSE=' num2str(metricsExisting.rmse) ' r=' num2str(metricsExisting.pearsonR) ' (doc reference: MAE=' num2str(referenceExistingSwitcherMae.(scenarioName)) ')']);

    % --- Best single region, for reference. ---
    metricsForehead = computeMetrics(hrForehead, hrGroundtruth);
    metricsCheek = computeMetrics(hrCheek, hrGroundtruth);
    disp(['forehead alone: MAE=' num2str(metricsForehead.mae) '; cheek alone: MAE=' num2str(metricsCheek.mae) ...
        ' (doc reference best single region ''' referenceBestSingleRegionName.(scenarioName) ''': MAE=' num2str(referenceBestSingleRegionMae.(scenarioName)) ')']);

    rows = {
        {scenarioName, 'weighted_standout_switcher_NEW', metricsWeighted}
        {scenarioName, 'existing_unweighted_switcher', metricsExisting}
        {scenarioName, 'forehead_alone', metricsForehead}
        {scenarioName, 'cheek_alone', metricsCheek}
    };
    for r = 1:numel(rows)
        row = rows{r};
        m = row{3};
        writelines(strjoin({row{1}, row{2}, num2str(m.n), num2str(m.mae), num2str(m.rmse), num2str(m.pearsonR)}, ','), outCsvPath, 'WriteMode', 'append');
    end
end

disp(' ');
disp(['Saved ' outCsvPath]);
