% RUN_TASK_P_WINDOWED_BATCH Segment 6 Task P, Action 4: runs the full
% windowed pipeline (Action 1 windowing -> Action 3 harmonic continuity +
% Action 2 quality gating, together) on the same 107-subject v1 VIPL pool
% used in every prior HR comparison (results/metrics/
% segment4_hr_summary_vipl.csv), and reports MAE/RMSE/r against the
% current whole-clip single-FFT baseline (heartrate/fftHeartRate.m,
% unmodified).
%
% This script does NOT reprocess any video -- it loads the already-cached
% data/processed/<subjectID>_rgb_traces.mat and _filtered_traces.mat for
% each of the 107 pool subjects (the same files
% run_vipl_integration_batch.m / run_vipl_phone_v1_batch.m already
% produced), and does NOT modify heartrate/fftHeartRate.m,
% heartrate/windowedHeartRate.m, filtering/bandpassClean.m, or
% pulseextraction/chromCombine.m.
%
% To isolate which of the two Action 2/3 mechanisms is doing the work,
% this script builds FOUR per-subject HR estimates from the same
% per-window candidates:
%   1. wholeClip        - heartrate/fftHeartRate.m on the whole-clip
%                          signal (the existing baseline).
%   2. naiveWindowed     - heartrate/windowedHeartRate.m's own hrBpmNaive
%                          output: mean of each window's tallest peak, no
%                          continuity, no gating.
%   3. gatingOnly        - naiveWindowed's per-window tallest-peak choices,
%                          quality-gated (validation/
%                          aggregateGatedWindowHR.m) -- continuity is NOT
%                          applied here, so any change from naiveWindowed
%                          is attributable to gating alone.
%   4. gatingPlusContinuity - validation/selectHarmonicConsistentHR.m's
%                          per-window choices, quality-gated with the
%                          SAME threshold and SAME windows as (3) -- since
%                          gating is identical between (3) and (4), any
%                          change from (3) to (4) is attributable to
%                          harmonic continuity alone, isolating it from
%                          gating's effect.
% The quality threshold used by (3) and (4) is derived ONCE from the
% pooled quality scores of every window of every subject in this batch
% (validation/computeWindowQualityThreshold.m), not per-subject and not
% hardcoded.
%
% Run scripts/run_task_p_p21_isolated_check.m first -- that script
% verifies Action 3 in isolation on the known VIPL_p21/v1/forehead
% harmonic-confusion case before this script runs it across the full pool.
%
% Outputs:
%   results/metrics/segment6_task_p_windowed_hr_summary.csv - one row per
%     subject: HR_wholeClip, HR_naiveWindowed, HR_gatingOnly,
%     HR_gatingPlusContinuity, HR_groundtruth, numWindows, numWindowsUsed
%     (post-gating), numContinuityOverrides (window-level count),
%     changedByContinuity (subject-level flag, gatingPlusContinuity vs
%     gatingOnly).
%   results/metrics/segment6_task_p_windowed_metrics.csv - one row per
%     method, pooled MAE/RMSE/Pearson r/N against ground truth.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

disp('=== Segment 6 Task P Action 4: loading the 107-subject v1 VIPL pool (segment4_hr_summary_vipl.csv) ===');

poolCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');
poolTable = readtable(poolCsvPath);
numSubjects = height(poolTable);

disp(['Loaded ' num2str(numSubjects) ' pool subjects from ' poolCsvPath]);

subjectID = cell(numSubjects, 1);
HR_groundtruth = zeros(numSubjects, 1);

for rowPos = 1:numSubjects
    subjectID{rowPos} = extractTextTaskP(poolTable.subjectID, rowPos);
    HR_groundtruth(rowPos) = poolTable.HR_groundtruth(rowPos);
end

disp(' ');
disp('=== Pass 1: per-subject windowing (Action 1), collecting per-window candidates + quality scores for every subject ===');

HR_wholeClip = nan(numSubjects, 1);
HR_naiveWindowed = nan(numSubjects, 1);
numWindowsPerSubject = zeros(numSubjects, 1);

windowResultsBySubject = cell(numSubjects, 1);
subjectUsable = false(numSubjects, 1);

pooledQualityScores = [];

failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    thisSubjectID = subjectID{subjectPos};

    disp(['--- Processing ' thisSubjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        rgbMatPath = fullfile(processedDataRoot, [thisSubjectID '_rgb_traces.mat']);
        filteredMatPath = fullfile(processedDataRoot, [thisSubjectID '_filtered_traces.mat']);

        rgbData = load(rgbMatPath);
        filteredData = load(filteredMatPath);

        fs = filteredData.fs;

        pulseChrom = chromCombine(filteredData.R_filtered, filteredData.G_filtered, filteredData.B_filtered, rgbData.R, rgbData.G, rgbData.B);
        pulseChromFiltered = bandpassClean(pulseChrom, fs);

        [HR_wholeClipThis, freqSpectrumThis, powerSpectrumThis] = fftHeartRate(pulseChromFiltered, fs);

        [hrBpmNaiveThis, windowResultsThis] = windowedHeartRate(pulseChromFiltered, fs);

        HR_wholeClip(subjectPos) = HR_wholeClipThis;
        HR_naiveWindowed(subjectPos) = hrBpmNaiveThis;
        numWindowsPerSubject(subjectPos) = windowResultsThis.numWindows;
        windowResultsBySubject{subjectPos} = windowResultsThis;
        subjectUsable(subjectPos) = true;

        pooledQualityScores = [pooledQualityScores; windowResultsThis.qualityScore]; %#ok<AGROW>

        disp([thisSubjectID ': HR_wholeClip = ' num2str(HR_wholeClipThis) ' bpm, HR_naiveWindowed = ' num2str(hrBpmNaiveThis) ' bpm, numWindows = ' num2str(windowResultsThis.numWindows)]);
    catch causeErr
        disp([thisSubjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = thisSubjectID;
        failedReasons{end + 1} = causeErr.message;
    end
end

numUsableSubjects = sum(subjectUsable);

disp(' ');
disp([num2str(numUsableSubjects) ' of ' num2str(numSubjects) ' subjects usable, ' num2str(numel(failedSubjects)) ' failed.']);

disp(' ');
disp('=== Pass 2: deriving the pooled quality threshold (Action 2, validation/computeWindowQualityThreshold.m) ===');

[qualityThreshold, thresholdDiagnostics] = computeWindowQualityThreshold(pooledQualityScores);

disp(['Pooled window quality scores: n = ' num2str(thresholdDiagnostics.n) ', min = ' num2str(thresholdDiagnostics.minScore) ', median = ' num2str(thresholdDiagnostics.medianScore) ', max = ' num2str(thresholdDiagnostics.maxScore)]);
disp(['Largest gap = ' num2str(thresholdDiagnostics.largestGapValue) ', lower bound = ' num2str(thresholdDiagnostics.largestGapLowerBound) '. Used second-largest gap instead (lone-outlier fallback) = ' num2str(thresholdDiagnostics.usedSecondLargestGap)]);
disp(['Chosen quality threshold: ' num2str(qualityThreshold) ' (windows with qualityScore >= this are kept).']);

disp(' ');
disp('=== Pass 3: per-subject gating-only vs gating+continuity (Action 2 + Action 3), isolating which mechanism moves the final HR ===');

HR_gatingOnly = nan(numSubjects, 1);
HR_gatingPlusContinuity = nan(numSubjects, 1);
numWindowsUsedPerSubject = nan(numSubjects, 1);
numContinuityOverridesPerSubject = nan(numSubjects, 1);
changedByContinuity = false(numSubjects, 1);
allExcludedFallbackPerSubject = false(numSubjects, 1);

for subjectPos = 1:numSubjects
    if ~subjectUsable(subjectPos)
        continue;
    end

    windowResultsThis = windowResultsBySubject{subjectPos};

    naiveChosenBpm = windowResultsThis.candidateBpm(:, 1);
    [continuityChosenBpm, overrideFired] = selectHarmonicConsistentHR(windowResultsThis.candidateBpm, windowResultsThis.candidateMagnitude);

    [HR_gatingOnlyThis, numUsedGatingOnly, numExcludedGatingOnly, fallbackGatingOnly] = aggregateGatedWindowHR(naiveChosenBpm, windowResultsThis.qualityScore, qualityThreshold);
    [HR_gatingPlusContinuityThis, numUsedGatingContinuity, numExcludedGatingContinuity, fallbackGatingContinuity] = aggregateGatedWindowHR(continuityChosenBpm, windowResultsThis.qualityScore, qualityThreshold);

    HR_gatingOnly(subjectPos) = HR_gatingOnlyThis;
    HR_gatingPlusContinuity(subjectPos) = HR_gatingPlusContinuityThis;
    numWindowsUsedPerSubject(subjectPos) = numUsedGatingContinuity;
    numContinuityOverridesPerSubject(subjectPos) = sum(overrideFired);
    allExcludedFallbackPerSubject(subjectPos) = fallbackGatingOnly || fallbackGatingContinuity;

    if abs(HR_gatingPlusContinuityThis - HR_gatingOnlyThis) > 1e-9
        changedByContinuity(subjectPos) = true;
    end
end

numSubjectsChangedByContinuity = sum(changedByContinuity(subjectUsable));

disp(['Subjects whose final HR changed specifically because harmonic continuity fired (gatingPlusContinuity vs gatingOnly, same gating both sides): ' num2str(numSubjectsChangedByContinuity) ' of ' num2str(numUsableSubjects) '.']);

numSubjectsChangedByGating = sum(subjectUsable & (abs(HR_naiveWindowed - HR_gatingOnly) > 1e-9));

disp(['Subjects whose final HR changed because of quality gating alone (naiveWindowed vs gatingOnly, no continuity either side): ' num2str(numSubjectsChangedByGating) ' of ' num2str(numUsableSubjects) '.']);

disp(' ');
disp('=== Saving per-subject summary CSV ===');

hrCsvPath = fullfile(metricsRoot, 'segment6_task_p_windowed_hr_summary.csv');
hrHeaderLine = "subjectID,HR_wholeClip,HR_naiveWindowed,HR_gatingOnly,HR_gatingPlusContinuity,HR_groundtruth,numWindows,numWindowsUsed,numContinuityOverrides,changedByContinuity,allWindowsExcludedFallback";
writelines(hrHeaderLine, hrCsvPath);

for subjectPos = 1:numSubjects
    if ~subjectUsable(subjectPos)
        continue;
    end

    changedByContinuityValue = 0;

    if changedByContinuity(subjectPos)
        changedByContinuityValue = 1;
    end

    fallbackValue = 0;

    if allExcludedFallbackPerSubject(subjectPos)
        fallbackValue = 1;
    end

    rowParts = {subjectID{subjectPos}, num2str(HR_wholeClip(subjectPos)), num2str(HR_naiveWindowed(subjectPos)), num2str(HR_gatingOnly(subjectPos)), num2str(HR_gatingPlusContinuity(subjectPos)), num2str(HR_groundtruth(subjectPos)), num2str(numWindowsPerSubject(subjectPos)), num2str(numWindowsUsedPerSubject(subjectPos)), num2str(numContinuityOverridesPerSubject(subjectPos)), num2str(changedByContinuityValue), num2str(fallbackValue)};
    rowLine = strjoin(rowParts, ',');
    writelines(rowLine, hrCsvPath, 'WriteMode', 'append');
end

disp(['Saved ' hrCsvPath]);

disp(' ');
disp('=== Pooled metrics: whole-clip baseline vs naive windowed vs gating-only vs gating+continuity ===');

usableIdx = find(subjectUsable);

metricsWholeClip = computeMetrics(HR_wholeClip(usableIdx), HR_groundtruth(usableIdx));
metricsNaiveWindowed = computeMetrics(HR_naiveWindowed(usableIdx), HR_groundtruth(usableIdx));
metricsGatingOnly = computeMetrics(HR_gatingOnly(usableIdx), HR_groundtruth(usableIdx));
metricsGatingPlusContinuity = computeMetrics(HR_gatingPlusContinuity(usableIdx), HR_groundtruth(usableIdx));

disp(' ');
disp('Method                    | N   | MAE     | RMSE    | Pearson r');
disp(['whole-clip (baseline)     | ' num2str(metricsWholeClip.n) ' | ' num2str(metricsWholeClip.mae) ' | ' num2str(metricsWholeClip.rmse) ' | ' num2str(metricsWholeClip.pearsonR)]);
disp(['naive windowed            | ' num2str(metricsNaiveWindowed.n) ' | ' num2str(metricsNaiveWindowed.mae) ' | ' num2str(metricsNaiveWindowed.rmse) ' | ' num2str(metricsNaiveWindowed.pearsonR)]);
disp(['gating only               | ' num2str(metricsGatingOnly.n) ' | ' num2str(metricsGatingOnly.mae) ' | ' num2str(metricsGatingOnly.rmse) ' | ' num2str(metricsGatingOnly.pearsonR)]);
disp(['gating + continuity       | ' num2str(metricsGatingPlusContinuity.n) ' | ' num2str(metricsGatingPlusContinuity.mae) ' | ' num2str(metricsGatingPlusContinuity.rmse) ' | ' num2str(metricsGatingPlusContinuity.pearsonR)]);

metricsCsvPath = fullfile(metricsRoot, 'segment6_task_p_windowed_metrics.csv');
metricsHeaderLine = "method,n,mae,rmse,pearson_r";
writelines(metricsHeaderLine, metricsCsvPath);

wholeClipRow = strjoin({'whole_clip_baseline', num2str(metricsWholeClip.n), num2str(metricsWholeClip.mae), num2str(metricsWholeClip.rmse), num2str(metricsWholeClip.pearsonR)}, ',');
naiveWindowedRow = strjoin({'naive_windowed', num2str(metricsNaiveWindowed.n), num2str(metricsNaiveWindowed.mae), num2str(metricsNaiveWindowed.rmse), num2str(metricsNaiveWindowed.pearsonR)}, ',');
gatingOnlyRow = strjoin({'gating_only', num2str(metricsGatingOnly.n), num2str(metricsGatingOnly.mae), num2str(metricsGatingOnly.rmse), num2str(metricsGatingOnly.pearsonR)}, ',');
gatingContinuityRow = strjoin({'gating_plus_continuity', num2str(metricsGatingPlusContinuity.n), num2str(metricsGatingPlusContinuity.mae), num2str(metricsGatingPlusContinuity.rmse), num2str(metricsGatingPlusContinuity.pearsonR)}, ',');

writelines(wholeClipRow, metricsCsvPath, 'WriteMode', 'append');
writelines(naiveWindowedRow, metricsCsvPath, 'WriteMode', 'append');
writelines(gatingOnlyRow, metricsCsvPath, 'WriteMode', 'append');
writelines(gatingContinuityRow, metricsCsvPath, 'WriteMode', 'append');

disp(['Saved ' metricsCsvPath]);

disp(' ');
disp('--- Segment 6 Task P Action 4 windowed batch complete ---');
disp(['Failed subjects: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

function textVal = extractTextTaskP(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
