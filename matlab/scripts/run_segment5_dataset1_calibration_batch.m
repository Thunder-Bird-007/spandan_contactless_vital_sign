% RUN_SEGMENT5_DATASET1_CALIBRATION_BATCH Batch driver for Segment 5's
% real (thin-data) SpO2 calibration attempt on DATASET_1's 5 subjects with
% facial-video SpO2 ground truth.
%
% This is NOT Segment 6's formal LOSO validation pipeline (runLOSO.m,
% computeMetrics.m, blandAltman.m remain untouched stubs). DATASET_1 only
% has 5 subjects, so this script does a simple leave-one-out loop purely
% to avoid a subject ever calibrating and predicting itself — see
% segment5_spo2/Segment5_LineByLine_Explanation.md for why 5 subjects is
% thin data and this loop is a leakage-avoidance measure, not a claim of
% trustworthy calibration.
%
% For each of the 5 subjects this script:
%   1. Loads data/processed/<subjectID>_rgb_traces.mat (Segment 2 output)
%      and data/processed/<subjectID>_filtered_traces.mat (Segment 3
%      output). If either is missing for a subject, it prints which
%      subject/segment is missing and skips that subject.
%   2. Calls spo2/ratioOfRatios.m to get that subject's whole-clip R.
%   3. Loads gtdump.xmp via io/loadGroundTruth.m, keeps only the GT rows
%      whose timestamp falls inside the video's own duration (timestamp-
%      based alignment, not a naive 1:1 index match — DATASET_1's
%      oximeter runs at ~62 Hz, independent of the ~28.67 fps video), and
%      averages SpO2 over that window as the subject's single ground-truth
%      value.
% Then, across the subjects that succeeded:
%   4. Runs a 5-fold leave-one-out loop: fit spo2/calibrateSpO2.m on the
%      other subjects, predict the held-out subject's SpO2, record
%      predicted vs actual. No subject ever predicts itself.
%   5. Saves results/metrics/segment5_dataset1_calibration.csv.
%   6. Saves results/figures/segment5_dataset1_calibration_scatter.png
%      (predicted vs actual, y=x reference line, points labeled by
%      subjectID).

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

numSubjects = numel(subjectList);
usableSubjectID = {};
usableR = [];
usableSpO2True = [];
failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};

    disp(['--- Processing subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);

        if ~isfile(rgbMatPath)
            error('run_segment5_dataset1_calibration_batch:missingInput', 'Segment 2 output not found for %s: %s -- run run_segment2_roi_batch.m on this subject first.', subjectID, rgbMatPath);
        end

        filteredMatPath = fullfile(processedDataRoot, [subjectID '_filtered_traces.mat']);

        if ~isfile(filteredMatPath)
            error('run_segment5_dataset1_calibration_batch:missingInput', 'Segment 3 output not found for %s: %s -- run run_segment3_filtering_batch.m on this subject first.', subjectID, filteredMatPath);
        end

        rgbData = load(rgbMatPath);
        R_raw = rgbData.R;
        G_raw = rgbData.G;
        B_raw = rgbData.B;
        fs = rgbData.fs;

        filteredData = load(filteredMatPath);
        R_filtered = filteredData.R_filtered;
        G_filtered = filteredData.G_filtered;
        B_filtered = filteredData.B_filtered;

        R_value = ratioOfRatios(R_filtered, G_filtered, B_filtered, R_raw, G_raw, B_raw, fs);

        disp(['Subject ' subjectID ': R (ratio-of-ratios) = ' num2str(R_value)]);

        gtPath = fullfile(dataset1Root, subjectID, 'gtdump.xmp');

        if ~isfile(gtPath)
            error('run_segment5_dataset1_calibration_batch:missingGT', 'gtdump.xmp not found for %s: %s', subjectID, gtPath);
        end

        gt = loadGroundTruth(gtPath, 'dataset1');

        videoDurationSec = numel(R_raw) / fs;
        inClipMask = gt.timestamp <= videoDurationSec;
        spo2InClip = gt.spo2(inClipMask);

        if isempty(spo2InClip)
            error('run_segment5_dataset1_calibration_batch:emptyGTWindow', 'No gtdump.xmp rows fell inside the video duration (%.2f s) for %s.', videoDurationSec, subjectID);
        end

        SpO2_true = mean(spo2InClip);

        disp(['Subject ' subjectID ': video duration = ' num2str(videoDurationSec) ' s, GT rows in window = ' num2str(numel(spo2InClip)) ', SpO2_true = ' num2str(SpO2_true)]);

        usableSubjectID{end + 1} = subjectID;
        usableR(end + 1) = R_value;
        usableSpO2True(end + 1) = SpO2_true;
    catch causeErr
        disp(['Subject ' subjectID ': FAILED — ' causeErr.message]);
        failedSubjects{end + 1} = subjectID;
        failedReasons{end + 1} = causeErr.message;
    end
end

disp('--- Loading complete ---');
disp(['Subjects usable: ' num2str(numel(usableSubjectID)) ' of ' num2str(numSubjects)]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numUsable = numel(usableSubjectID);

if numUsable < 3
    disp('Fewer than 3 usable subjects -- leave-one-out calibration needs at least 3 to be even minimally meaningful. Stopping here.');
else
    csvPath = fullfile(metricsRoot, 'segment5_dataset1_calibration.csv');
    headerLine = "subjectID,R_value,SpO2_true,SpO2_predicted,abs_error";
    writelines(headerLine, csvPath);

    SpO2_predicted = zeros(1, numUsable);
    abs_error = zeros(1, numUsable);

    for holdoutPos = 1:numUsable
        trainMask = true(1, numUsable);
        trainMask(holdoutPos) = false;

        R_train = usableR(trainMask);
        SpO2_train = usableSpO2True(trainMask);

        [~, calibParams] = calibrateSpO2(R_train, SpO2_train, []);

        R_test = usableR(holdoutPos);
        [spo2Pred, ~] = calibrateSpO2(R_test, [], calibParams);

        SpO2_predicted(holdoutPos) = spo2Pred;
        abs_error(holdoutPos) = abs(spo2Pred - usableSpO2True(holdoutPos));

        disp(['Held out ' usableSubjectID{holdoutPos} ': A = ' num2str(calibParams.A) ', B = ' num2str(calibParams.B) ', SpO2_predicted = ' num2str(spo2Pred) ', SpO2_true = ' num2str(usableSpO2True(holdoutPos)) ', abs_error = ' num2str(abs_error(holdoutPos))]);

        rowParts = {usableSubjectID{holdoutPos}, num2str(usableR(holdoutPos)), num2str(usableSpO2True(holdoutPos)), num2str(spo2Pred), num2str(abs_error(holdoutPos))};
        rowLine = strjoin(rowParts, ',');
        writelines(rowLine, csvPath, 'WriteMode', 'append');
    end

    disp(['Saved ' csvPath]);
    disp(['Mean absolute error across ' num2str(numUsable) ' leave-one-out folds: ' num2str(mean(abs_error)) ' percentage points']);

    figureHandle = figure('Visible', 'off');
    hold on;

    minAxisVal = min([usableSpO2True, SpO2_predicted]) - 2;
    maxAxisVal = max([usableSpO2True, SpO2_predicted]) + 2;

    plot([minAxisVal maxAxisVal], [minAxisVal maxAxisVal], 'k--', 'LineWidth', 1);
    scatter(usableSpO2True, SpO2_predicted, 60, 'filled');

    for labelPos = 1:numUsable
        text(usableSpO2True(labelPos) + 0.1, SpO2_predicted(labelPos), usableSubjectID{labelPos}, 'FontSize', 9);
    end

    xlim([minAxisVal maxAxisVal]);
    ylim([minAxisVal maxAxisVal]);
    xlabel('SpO2 true (%)');
    ylabel('SpO2 predicted (%)');
    title('Segment 5 -- DATASET1 Leave-One-Out SpO2 Calibration');
    grid on;
    hold off;

    pngOutPath = fullfile(figuresRoot, 'segment5_dataset1_calibration_scatter.png');
    exportgraphics(figureHandle, pngOutPath);
    close(figureHandle);

    disp(['Saved ' pngOutPath]);
end

disp('--- Batch complete ---');
