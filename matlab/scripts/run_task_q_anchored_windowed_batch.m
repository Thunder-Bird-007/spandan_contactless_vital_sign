% RUN_TASK_Q_ANCHORED_WINDOWED_BATCH Segment 6 Task Q, Part 1 Action 3:
% runs quality-anchored harmonic continuity (validation/
% selectHarmonicConsistentHR_anchored.m) plus quality gating on the same
% 107-subject v1 VIPL pool Task P used (results/metrics/
% segment4_hr_summary_vipl.csv), and reports it as a FIFTH row against
% Task P's existing four (whole-clip, naive windowed, gating-only,
% gating+continuity-from-window-1).
%
% This script does NOT reprocess any video -- it loads the already-cached
% data/processed/<subjectID>_rgb_traces.mat and _filtered_traces.mat for
% each of the 107 pool subjects (the same files run_task_p_windowed_batch.m
% already loaded) and recomputes heartrate/windowedHeartRate.m's
% per-window outputs from those cached traces -- this is the "reuse
% windowedHeartRate.m's already-cached window-level outputs" referred to
% in the task brief: the expensive step (video decode + ROI + CHROM +
% bandpass) is skipped entirely, only the cheap deterministic per-window
% FFT step is repeated from cached traces, same as Task P's own script
% did for its four rows. Does NOT modify heartrate/fftHeartRate.m,
% heartrate/windowedHeartRate.m, filtering/bandpassClean.m,
% pulseextraction/chromCombine.m, validation/selectHarmonicConsistentHR.m,
% validation/computeWindowQualityThreshold.m, or
% validation/aggregateGatedWindowHR.m.
%
% The SAME pooled quality threshold derivation (validation/
% computeWindowQualityThreshold.m, largest-gap-vs-second-largest-gap) is
% used here as Task P used, so the gating half of "gating +
% anchored-continuity" is directly comparable to Task P's "gating +
% continuity-from-window-1" row -- any difference between the two rows is
% attributable to the anchor choice alone.
%
% Outputs:
%   results/metrics/segment6_task_q_anchored_windowed_hr_summary.csv -
%     one row per subject: HR_wholeClip, HR_naiveWindowed, HR_gatingOnly,
%     HR_gatingPlusWindow1Continuity, HR_gatingPlusAnchoredContinuity,
%     HR_groundtruth, numWindows, anchorWindowIdx, changedByAnchoring.
%   results/metrics/segment6_task_q_anchored_windowed_metrics.csv - one
%     row per method (all five), pooled MAE/RMSE/Pearson r/N.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

disp('=== Segment 6 Task Q Part 1 Action 3: loading the 107-subject v1 VIPL pool (segment4_hr_summary_vipl.csv) ===');

poolCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');
poolTable = readtable(poolCsvPath);
numSubjects = height(poolTable);

disp(['Loaded ' num2str(numSubjects) ' pool subjects from ' poolCsvPath]);

subjectID = cell(numSubjects, 1);
HR_groundtruth = zeros(numSubjects, 1);

for rowPos = 1:numSubjects
    subjectID{rowPos} = extractTextTaskQ(poolTable.subjectID, rowPos);
    HR_groundtruth(rowPos) = poolTable.HR_groundtruth(rowPos);
end

disp(' ');
disp('=== Pass 1: per-subject windowing, recomputed from cached rgb/filtered traces (no video reprocessing) ===');

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
disp('=== Pass 2: deriving the pooled quality threshold (same method as Task P, validation/computeWindowQualityThreshold.m) ===');

[qualityThreshold, thresholdDiagnostics] = computeWindowQualityThreshold(pooledQualityScores);

disp(['Pooled window quality scores: n = ' num2str(thresholdDiagnostics.n) ', min = ' num2str(thresholdDiagnostics.minScore) ', median = ' num2str(thresholdDiagnostics.medianScore) ', max = ' num2str(thresholdDiagnostics.maxScore)]);
disp(['Chosen quality threshold: ' num2str(qualityThreshold) ' (windows with qualityScore >= this are kept).']);

disp(' ');
disp('=== Pass 3: per-subject gating-only vs gating+window1-continuity (Task P) vs gating+anchored-continuity (Task Q) ===');

HR_gatingOnly = nan(numSubjects, 1);
HR_gatingPlusWindow1Continuity = nan(numSubjects, 1);
HR_gatingPlusAnchoredContinuity = nan(numSubjects, 1);
anchorWindowIdxPerSubject = nan(numSubjects, 1);
changedByAnchoring = false(numSubjects, 1);

for subjectPos = 1:numSubjects
    if ~subjectUsable(subjectPos)
        continue;
    end

    windowResultsThis = windowResultsBySubject{subjectPos};

    naiveChosenBpm = windowResultsThis.candidateBpm(:, 1);
    [window1ContinuityChosenBpm, overrideFiredWindow1] = selectHarmonicConsistentHR(windowResultsThis.candidateBpm, windowResultsThis.candidateMagnitude);
    [anchoredContinuityChosenBpm, overrideFiredAnchored, anchorWindowIdxThis] = selectHarmonicConsistentHR_anchored(windowResultsThis.candidateBpm, windowResultsThis.candidateMagnitude, windowResultsThis.qualityScore);

    [HR_gatingOnlyThis, numUsedGatingOnly, numExcludedGatingOnly, fallbackGatingOnly] = aggregateGatedWindowHR(naiveChosenBpm, windowResultsThis.qualityScore, qualityThreshold);
    [HR_gatingWindow1Continuity, numUsedWindow1, numExcludedWindow1, fallbackWindow1] = aggregateGatedWindowHR(window1ContinuityChosenBpm, windowResultsThis.qualityScore, qualityThreshold);
    [HR_gatingAnchoredContinuity, numUsedAnchored, numExcludedAnchored, fallbackAnchored] = aggregateGatedWindowHR(anchoredContinuityChosenBpm, windowResultsThis.qualityScore, qualityThreshold);

    HR_gatingOnly(subjectPos) = HR_gatingOnlyThis;
    HR_gatingPlusWindow1Continuity(subjectPos) = HR_gatingWindow1Continuity;
    HR_gatingPlusAnchoredContinuity(subjectPos) = HR_gatingAnchoredContinuity;
    anchorWindowIdxPerSubject(subjectPos) = anchorWindowIdxThis;

    if abs(HR_gatingAnchoredContinuity - HR_gatingWindow1Continuity) > 1e-9
        changedByAnchoring(subjectPos) = true;
    end
end

numSubjectsChangedByAnchoring = sum(changedByAnchoring(subjectUsable));

disp(['Subjects whose final HR changed specifically because the anchor moved off window 1 (gatingPlusAnchoredContinuity vs gatingPlusWindow1Continuity, same gating both sides): ' num2str(numSubjectsChangedByAnchoring) ' of ' num2str(numUsableSubjects) '.']);

numSubjectsAnchorNotWindow1 = sum(subjectUsable & (anchorWindowIdxPerSubject ~= 1));

disp(['Subjects whose highest-quality window is NOT window 1: ' num2str(numSubjectsAnchorNotWindow1) ' of ' num2str(numUsableSubjects) '.']);

disp(' ');
disp('=== Saving per-subject summary CSV ===');

hrCsvPath = fullfile(metricsRoot, 'segment6_task_q_anchored_windowed_hr_summary.csv');
hrHeaderLine = "subjectID,HR_wholeClip,HR_naiveWindowed,HR_gatingOnly,HR_gatingPlusWindow1Continuity,HR_gatingPlusAnchoredContinuity,HR_groundtruth,numWindows,anchorWindowIdx,changedByAnchoring";
writelines(hrHeaderLine, hrCsvPath);

for subjectPos = 1:numSubjects
    if ~subjectUsable(subjectPos)
        continue;
    end

    changedByAnchoringValue = 0;

    if changedByAnchoring(subjectPos)
        changedByAnchoringValue = 1;
    end

    rowParts = {subjectID{subjectPos}, num2str(HR_wholeClip(subjectPos)), num2str(HR_naiveWindowed(subjectPos)), num2str(HR_gatingOnly(subjectPos)), num2str(HR_gatingPlusWindow1Continuity(subjectPos)), num2str(HR_gatingPlusAnchoredContinuity(subjectPos)), num2str(HR_groundtruth(subjectPos)), num2str(numWindowsPerSubject(subjectPos)), num2str(anchorWindowIdxPerSubject(subjectPos)), num2str(changedByAnchoringValue)};
    rowLine = strjoin(rowParts, ',');
    writelines(rowLine, hrCsvPath, 'WriteMode', 'append');
end

disp(['Saved ' hrCsvPath]);

disp(' ');
disp('=== Pooled metrics: five-row comparison ===');

usableIdx = find(subjectUsable);

metricsWholeClip = computeMetrics(HR_wholeClip(usableIdx), HR_groundtruth(usableIdx));
metricsNaiveWindowed = computeMetrics(HR_naiveWindowed(usableIdx), HR_groundtruth(usableIdx));
metricsGatingOnly = computeMetrics(HR_gatingOnly(usableIdx), HR_groundtruth(usableIdx));
metricsGatingWindow1Continuity = computeMetrics(HR_gatingPlusWindow1Continuity(usableIdx), HR_groundtruth(usableIdx));
metricsGatingAnchoredContinuity = computeMetrics(HR_gatingPlusAnchoredContinuity(usableIdx), HR_groundtruth(usableIdx));

disp(' ');
disp('Method                              | N   | MAE     | RMSE    | Pearson r');
disp(['whole-clip (baseline)               | ' num2str(metricsWholeClip.n) ' | ' num2str(metricsWholeClip.mae) ' | ' num2str(metricsWholeClip.rmse) ' | ' num2str(metricsWholeClip.pearsonR)]);
disp(['naive windowed                      | ' num2str(metricsNaiveWindowed.n) ' | ' num2str(metricsNaiveWindowed.mae) ' | ' num2str(metricsNaiveWindowed.rmse) ' | ' num2str(metricsNaiveWindowed.pearsonR)]);
disp(['gating only                         | ' num2str(metricsGatingOnly.n) ' | ' num2str(metricsGatingOnly.mae) ' | ' num2str(metricsGatingOnly.rmse) ' | ' num2str(metricsGatingOnly.pearsonR)]);
disp(['gating + continuity (window 1)      | ' num2str(metricsGatingWindow1Continuity.n) ' | ' num2str(metricsGatingWindow1Continuity.mae) ' | ' num2str(metricsGatingWindow1Continuity.rmse) ' | ' num2str(metricsGatingWindow1Continuity.pearsonR)]);
disp(['gating + continuity (quality-anchor)| ' num2str(metricsGatingAnchoredContinuity.n) ' | ' num2str(metricsGatingAnchoredContinuity.mae) ' | ' num2str(metricsGatingAnchoredContinuity.rmse) ' | ' num2str(metricsGatingAnchoredContinuity.pearsonR)]);

metricsCsvPath = fullfile(metricsRoot, 'segment6_task_q_anchored_windowed_metrics.csv');
metricsHeaderLine = "method,n,mae,rmse,pearson_r";
writelines(metricsHeaderLine, metricsCsvPath);

wholeClipRow = strjoin({'whole_clip_baseline', num2str(metricsWholeClip.n), num2str(metricsWholeClip.mae), num2str(metricsWholeClip.rmse), num2str(metricsWholeClip.pearsonR)}, ',');
naiveWindowedRow = strjoin({'naive_windowed', num2str(metricsNaiveWindowed.n), num2str(metricsNaiveWindowed.mae), num2str(metricsNaiveWindowed.rmse), num2str(metricsNaiveWindowed.pearsonR)}, ',');
gatingOnlyRow = strjoin({'gating_only', num2str(metricsGatingOnly.n), num2str(metricsGatingOnly.mae), num2str(metricsGatingOnly.rmse), num2str(metricsGatingOnly.pearsonR)}, ',');
gatingWindow1ContinuityRow = strjoin({'gating_plus_continuity_window1', num2str(metricsGatingWindow1Continuity.n), num2str(metricsGatingWindow1Continuity.mae), num2str(metricsGatingWindow1Continuity.rmse), num2str(metricsGatingWindow1Continuity.pearsonR)}, ',');
gatingAnchoredContinuityRow = strjoin({'gating_plus_continuity_quality_anchor', num2str(metricsGatingAnchoredContinuity.n), num2str(metricsGatingAnchoredContinuity.mae), num2str(metricsGatingAnchoredContinuity.rmse), num2str(metricsGatingAnchoredContinuity.pearsonR)}, ',');

writelines(wholeClipRow, metricsCsvPath, 'WriteMode', 'append');
writelines(naiveWindowedRow, metricsCsvPath, 'WriteMode', 'append');
writelines(gatingOnlyRow, metricsCsvPath, 'WriteMode', 'append');
writelines(gatingWindow1ContinuityRow, metricsCsvPath, 'WriteMode', 'append');
writelines(gatingAnchoredContinuityRow, metricsCsvPath, 'WriteMode', 'append');

disp(['Saved ' metricsCsvPath]);

disp(' ');
disp('--- Segment 6 Task Q Part 1 Action 3 anchored windowed batch complete ---');
disp(['Failed subjects: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

function textVal = extractTextTaskQ(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
