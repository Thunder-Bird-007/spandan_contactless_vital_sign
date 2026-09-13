% RUN_SEGMENT6_TASK5B_RAKF_PARAM_SWEEP_PILOT Exploratory pilot (Field Guide
% "still open" list), Action 2. Feasibility/direction-finding only -- SMALL
% sample on purpose, not a full validation pass. Does NOT modify
% validation/residualAdaptiveKalmanHR.m (its internals are unchanged; this
% script only varies the `opts` struct it already accepts).
%
% Background: Task 5's own doc (docs/Segment6_Task5_RAKF_Kalman_Smoothing.md)
% stated up front that its R0/beta/Q defaults are this implementation's own
% data-derived choices, NOT values taken from Debnath & Kim's paper (not
% independently available to that session). This pilot fetched the actual
% paper (PMC12818640, "Advanced signal-processing framework for remote
% photoplethysmography-based heart rate measurement...") and found real
% numeric values:
%   - Eq. 12: R_k^adaptive = R0 * (1 + |innovation|^beta)  -- an EXPONENT,
%     not this implementation's own R_k = R0 * (1 + |innovation|/beta)
%     (a DIVISION). This is a genuine mechanism mismatch, stated honestly
%     here -- NOT fixed in this pilot (that would be more than "check the
%     sweep ranges", it would be re-deriving the filter itself, out of this
%     pilot's scope; flagged as a finding for a future task instead).
%   - The paper fixes R0 = 25 (bpm^2) and Q_k = 2e-4 (bpm^2) ACROSS ALL
%     DATASETS, both applied PER VIDEO FRAME (30fps, i.e. per ~33ms) --
%     structurally different from this implementation's per-5-SECOND-HOP
%     window state update (residualAdaptiveKalmanHR.m's own header). A
%     random-walk process noise variance scales roughly linearly with
%     elapsed time/step count, so the paper's per-frame Q_k does not carry
%     over numerically to a per-window Q without conversion -- approximated
%     here as Q_scaled = Q_paper * framesPerWindow (150 frames per 5s hop at
%     a nominal 30fps) = 2e-4 * 150 = 0.03. Stated as an approximation, not
%     an exact unit conversion (the paper does not give enough detail on its
%     own per-frame smoothing/decimation to do better than this).
%   - Beta is given no explicit numeric default in the paper (sensitivity
%     analysis says the method is "robust" to it, <0.3bpm effect) -- swept
%     around this implementation's own data-derived default instead, since
%     the paper gives nothing more specific to anchor to.
%
% Sweep grid (still using this implementation's own division-based formula,
% per the note above): R0 in {5, 10, 25 (paper), 50}, Q in {2e-4 (paper,
% literal/unconverted), 0.03 (paper, per-window-scaled), 0.1, 1 (current
% default order of magnitude)}, beta as a MULTIPLIER on each subject's own
% std(measurementBpm) (this implementation's own default) in {0.5, 1, 2} --
% 4 x 4 x 3 = 48 combinations, cheap (no video reprocessing, scalar Kalman
% filter over a handful of windows per subject).
%
% Subjects: first 10 VIPL subjects (p1-p10, v1/source1) from
% results/metrics/segment6_task_q_anchored_windowed_hr_summary.csv, reusing
% the SAME cached data/processed/<subjectID>_rgb_traces.mat /
% _filtered_traces.mat Task P/Q/5 already used -- no new video decode.
%
% Output: results/metrics/segment6_task5b_rakf_sweep_pilot.csv (one row per
% grid combo, pooled MAE/RMSE/r across the 10-subject sample).

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

taskQCsvPath = fullfile(metricsRoot, 'segment6_task_q_anchored_windowed_hr_summary.csv');
taskQTable = readtable(taskQCsvPath, 'TextType', 'string');

pilotSubjectIDs = taskQTable.subjectID(1:10);
pilotGroundTruth = taskQTable.HR_groundtruth(1:10);

disp(['Segment 6 Task 5b (RAKF param sweep pilot): ' num2str(numel(pilotSubjectIDs)) ' subjects: ' strjoin(cellstr(pilotSubjectIDs), ', ')]);

% --- Load each pilot subject's cached windowResults ONCE (expensive-ish
% part, but still no video decode -- just chromCombine/bandpassClean/
% windowedHeartRate on already-cached traces), reused across every grid
% combo below. ---
numSubjects = numel(pilotSubjectIDs);
candidateBpmBySubject = cell(numSubjects, 1);
qualityScoreBySubject = cell(numSubjects, 1);
usable = false(numSubjects, 1);

for i = 1:numSubjects
    subjID = char(pilotSubjectIDs(i));
    try
        rgbData = load(fullfile(processedDataRoot, [subjID '_rgb_traces.mat']));
        filteredData = load(fullfile(processedDataRoot, [subjID '_filtered_traces.mat']));
        fs = filteredData.fs;

        pulseChrom = chromCombine(filteredData.R_filtered, filteredData.G_filtered, filteredData.B_filtered, rgbData.R, rgbData.G, rgbData.B);
        pulseChromFiltered = bandpassClean(pulseChrom, fs);

        [~, windowResultsThis] = windowedHeartRate(pulseChromFiltered, fs);
        candidateBpmBySubject{i} = windowResultsThis.candidateBpm(:, 1);
        qualityScoreBySubject{i} = windowResultsThis.qualityScore;
        usable(i) = true;
    catch causeErr
        disp([subjID ': FAILED to load/prep -- ' causeErr.message]);
    end
end

usableIdx = find(usable);
disp([num2str(numel(usableIdx)) ' of ' num2str(numSubjects) ' pilot subjects usable.']);

% --- Current-default baseline, on THIS 10-subject sample (for a fair
% same-sample comparison, since the full-107 flat number was on a much
% larger pool). ---
hrDefault = nan(numSubjects, 1);
for k = 1:numel(usableIdx)
    i = usableIdx(k);
    hrDefault(i) = residualAdaptiveKalmanHR(candidateBpmBySubject{i}, qualityScoreBySubject{i});
end
metricsDefault = computeMetrics(hrDefault(usableIdx), pilotGroundTruth(usableIdx));
disp(['Current-default RAKF on this 10-subject sample: N=' num2str(metricsDefault.n) ' MAE=' num2str(metricsDefault.mae) ' RMSE=' num2str(metricsDefault.rmse) ' r=' num2str(metricsDefault.pearsonR)]);

% --- Sweep grid. ---
r0Grid = [5, 10, 25, 50];
qGrid = [2e-4, 0.03, 0.1, 1];
betaMultGrid = [0.5, 1, 2];

outCsvPath = fullfile(metricsRoot, 'segment6_task5b_rakf_sweep_pilot.csv');
headerLine = "R0,Q,betaMultiplier,N,MAE,RMSE,Pearson_r";
writelines(headerLine, outCsvPath);

bestMae = Inf;
bestRow = struct();

for r0 = r0Grid
    for qVal = qGrid
        for betaMult = betaMultGrid
            hrThisCombo = nan(numSubjects, 1);
            for k = 1:numel(usableIdx)
                i = usableIdx(k);
                opts = struct();
                opts.R0 = r0;
                opts.Q = qVal;
                opts.beta = betaMult * max(std(candidateBpmBySubject{i}), 1);
                hrThisCombo(i) = residualAdaptiveKalmanHR(candidateBpmBySubject{i}, qualityScoreBySubject{i}, opts);
            end
            m = computeMetrics(hrThisCombo(usableIdx), pilotGroundTruth(usableIdx));
            rowLine = strjoin({num2str(r0), num2str(qVal), num2str(betaMult), num2str(m.n), num2str(m.mae), num2str(m.rmse), num2str(m.pearsonR)}, ',');
            writelines(rowLine, outCsvPath, 'WriteMode', 'append');

            if m.mae < bestMae
                bestMae = m.mae;
                bestRow.R0 = r0;
                bestRow.Q = qVal;
                bestRow.betaMult = betaMult;
                bestRow.metrics = m;
            end
        end
    end
end

disp(' ');
disp('=== Best sweep combo by MAE (this 10-subject sample) ===');
disp(['R0=' num2str(bestRow.R0) ', Q=' num2str(bestRow.Q) ', betaMultiplier=' num2str(bestRow.betaMult) ...
    ': N=' num2str(bestRow.metrics.n) ' MAE=' num2str(bestRow.metrics.mae) ' RMSE=' num2str(bestRow.metrics.rmse) ' r=' num2str(bestRow.metrics.pearsonR)]);

disp(' ');
disp('=== Reference points (NOT to be beaten on N=10 -- directional comparison only) ===');
disp(['Current-default RAKF, same 10-subject sample: MAE=' num2str(metricsDefault.mae) ' RMSE=' num2str(metricsDefault.rmse) ' r=' num2str(metricsDefault.pearsonR)]);
disp('Full-107-subject flat numbers (docs/Segment6_Task5_RAKF_Kalman_Smoothing.md): RAKF default MAE=12.148 RMSE=22.040 r=0.204; naive-windowed MAE=10.338 RMSE=15.643 r=0.316 (best simple method); whole-clip baseline MAE=9.346 RMSE=18.372 r=0.278.');

disp(' ');
disp(['Saved ' outCsvPath]);
