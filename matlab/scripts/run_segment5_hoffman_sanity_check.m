% RUN_SEGMENT5_HOFFMAN_SANITY_CHECK Code-correctness sanity check for
% spo2/ratioOfRatios.m and spo2/calibrateSpO2.m using the Hoffman et al.
% finger-camera oximetry dataset (github.com/ubicomplab/oximetry-phone-
% cam-data), NOT DATASET_1's facial video.
%
% This is a DIFFERENT MODALITY (finger pressed on a phone camera+flash,
% contact-based) from this project's facial rPPG pipeline. It exists ONLY
% to confirm ratioOfRatios.m/calibrateSpO2.m behave sensibly when there is
% real, wide SpO2 variance to fit against (this dataset spans roughly
% 65-100% via a controlled FiO2 desaturation protocol), something
% DATASET_1's narrow 95-99% resting range cannot test. A good fit here
% demonstrates the CODE is correct. It says NOTHING about facial-video
% SpO2 accuracy -- see segment5_spo2/Segment5_LineByLine_Explanation.md
% and the Guideline PDF for why that distinction matters, and
% docs/HOFFMAN_DATA_FORMAT.md for exactly how this dataset's files were
% inspected and what every column here means.
%
% This script is self-contained: it does not call roi/extractROISignals.m
% (there is no face/ROI here, it is a completely different signal path),
% but it does reuse filtering/detrendSignal.m, filtering/bandpassClean.m,
% spo2/ratioOfRatios.m, and spo2/calibrateSpO2.m directly, so this really
% is exercising this segment's own production code, not a reimplementation
% of it.
%
% Steps:
%   1. For each of the 6 Hoffman subjects, loads data/raw/Hoffman/data/
%      ppg-csv/Left/<subjectID>.csv (per-frame camera R,G,B means, 30 Hz)
%      and data/raw/Hoffman/data/gt/<subjectID>.csv (per-second SpO2 from
%      5 pulse oximeters; this script uses the "SpO2 2" column, the first
%      column confirmed to be a real, always-populated device reading --
%      see docs/HOFFMAN_DATA_FORMAT.md Section 3).
%   2. Splits each subject's recording into consecutive 5-second windows
%      (150 camera frames each, aligned to 5 GT seconds each, using the
%      same frame-index-to-GT-second grouping the dataset's own authors
%      use -- see docs/HOFFMAN_DATA_FORMAT.md Section 4). A whole-clip
%      single R value (as ratioOfRatios.m computes for DATASET_1) would
%      average away the very desaturation trend this dataset exists to
%      provide -- windowing is what makes the "wide range" visible in R
%      itself, not just in the ground truth. See the explanation doc for
%      the full reasoning.
%   3. Within each window: detrends and bandpass-filters R, G, B (same
%      filtering/detrendSignal.m + filtering/bandpassClean.m used
%      elsewhere in this project), then calls spo2/ratioOfRatios.m on the
%      raw + filtered window to get that window's R value, paired with
%      the mean SpO2 over the same 5 GT seconds.
%   4. Splits subjects into a 4-subject training set and a 2-subject test
%      set (not a per-window split, so no window from a test subject's
%      own recording leaks into training).
%   5. Fits spo2/calibrateSpO2.m once on all pooled training windows,
%      applies it to all test windows, records predicted vs actual.
%   6. Saves results/metrics/segment5_hoffman_sanity_check.csv (same
%      column style as segment5_dataset1_calibration.csv).
%   7. Saves results/figures/segment5_hoffman_sanity_scatter.png -- R vs
%      SpO2_true for every window (train + test pooled), with the fitted
%      calibration line overlaid.

trainSubjectList = {'100001', '100002', '100003', '100004'};
testSubjectList = {'100005', '100006'};
allSubjectList = [trainSubjectList, testSubjectList];

cameraFps = 30;
windowSeconds = 5;
windowFrames = windowSeconds * cameraFps;

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
hoffmanRoot = fullfile(projectRoot, 'data', 'raw', 'Hoffman', 'data');
ppgRoot = fullfile(hoffmanRoot, 'ppg-csv', 'Left');
gtRoot = fullfile(hoffmanRoot, 'gt');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

windowSubjectID = {};
windowR = [];
windowSpO2True = [];
windowIsTrain = [];

numSubjects = numel(allSubjectList);

for subjectPos = 1:numSubjects
    subjectID = allSubjectList{subjectPos};
    isTrainSubject = subjectPos <= numel(trainSubjectList);

    disp(['--- Processing Hoffman subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    ppgPath = fullfile(ppgRoot, [subjectID '.csv']);
    gtPath = fullfile(gtRoot, [subjectID '.csv']);

    if ~isfile(ppgPath) || ~isfile(gtPath)
        disp(['Subject ' subjectID ': FAILED -- missing ' ppgPath ' or ' gtPath]);
        continue
    end

    ppgData = readmatrix(ppgPath);
    R_raw_full = ppgData(:, 1);
    G_raw_full = ppgData(:, 2);
    B_raw_full = ppgData(:, 3);

    gtData = readmatrix(gtPath);
    spo2Column = gtData(:, 3);
    validGTMask = ~isnan(spo2Column) & spo2Column > 0;
    spo2Valid = spo2Column(validGTMask);

    numGTSeconds = numel(spo2Valid);
    numCameraFrames = numel(R_raw_full);

    numWindowsByGT = floor(numGTSeconds / windowSeconds);
    numWindowsByCamera = floor(numCameraFrames / windowFrames);
    numWindows = min(numWindowsByGT, numWindowsByCamera);

    disp(['Subject ' subjectID ': ' num2str(numCameraFrames) ' camera frames, ' num2str(numGTSeconds) ' valid GT seconds, ' num2str(numWindows) ' windows of ' num2str(windowSeconds) ' s each']);

    for windowPos = 1:numWindows
        frameStart = (windowPos - 1) * windowFrames + 1;
        frameEnd = windowPos * windowFrames;

        R_rawWindow = R_raw_full(frameStart:frameEnd);
        G_rawWindow = G_raw_full(frameStart:frameEnd);
        B_rawWindow = B_raw_full(frameStart:frameEnd);

        [R_detrendedWindow, detrendOrder] = detrendSignal(R_rawWindow);
        [G_detrendedWindow, detrendOrder] = detrendSignal(G_rawWindow);
        [B_detrendedWindow, detrendOrder] = detrendSignal(B_rawWindow);

        [R_filteredWindow, filterOrder] = bandpassClean(R_detrendedWindow, cameraFps);
        [G_filteredWindow, filterOrder] = bandpassClean(G_detrendedWindow, cameraFps);
        [B_filteredWindow, filterOrder] = bandpassClean(B_detrendedWindow, cameraFps);

        R_value = ratioOfRatios(R_filteredWindow, G_filteredWindow, B_filteredWindow, R_rawWindow, G_rawWindow, B_rawWindow, cameraFps);

        gtSecStart = (windowPos - 1) * windowSeconds + 1;
        gtSecEnd = windowPos * windowSeconds;
        SpO2_windowTrue = mean(spo2Valid(gtSecStart:gtSecEnd));

        windowSubjectID{end + 1} = subjectID;
        windowR(end + 1) = R_value;
        windowSpO2True(end + 1) = SpO2_windowTrue;
        windowIsTrain(end + 1) = isTrainSubject;
    end
end

disp('--- Window extraction complete ---');
disp(['Total windows: ' num2str(numel(windowR)) ' (train: ' num2str(sum(windowIsTrain == 1)) ', test: ' num2str(sum(windowIsTrain == 0)) ')']);

disp('--- Per-subject R-vs-SpO2 correlation (diagnostic, see Line-by-Line doc Part 4) ---');

for subjectPos = 1:numSubjects
    subjectID = allSubjectList{subjectPos};
    subjectWindowMask = strcmp(windowSubjectID, subjectID);

    if sum(subjectWindowMask) < 2
        continue
    end

    subjectCorrMatrix = corrcoef(windowR(subjectWindowMask), windowSpO2True(subjectWindowMask));
    disp(['Subject ' subjectID ': n = ' num2str(sum(subjectWindowMask)) ', corr(R, SpO2) = ' num2str(subjectCorrMatrix(1, 2))]);
end

pooledCorrMatrix = corrcoef(windowR, windowSpO2True);
disp(['Pooled across all subjects (ignoring subject identity): corr(R, SpO2) = ' num2str(pooledCorrMatrix(1, 2))]);
disp('A pooled correlation much weaker than the per-subject correlations above is expected here, not a bug -- it means each subject has its own R baseline offset (skin tone, perfusion, finger pressure), and a single pooled line partly averages that real per-subject signal away. See Part 4 of the Line-by-Line explanation.');

trainMask = windowIsTrain == 1;
testMask = windowIsTrain == 0;

R_train = windowR(trainMask);
SpO2_train = windowSpO2True(trainMask);

[~, calibParams] = calibrateSpO2(R_train, SpO2_train, []);

disp(['Fitted on training windows: A = ' num2str(calibParams.A) ', B = ' num2str(calibParams.B)]);

testSubjectIDs = windowSubjectID(testMask);
R_test = windowR(testMask);
SpO2_testTrue = windowSpO2True(testMask);

[SpO2_testPredicted, ~] = calibrateSpO2(R_test, [], calibParams);

abs_error = abs(SpO2_testPredicted - SpO2_testTrue);

disp(['Mean absolute error on ' num2str(numel(R_test)) ' held-out test windows: ' num2str(mean(abs_error)) ' percentage points']);

csvPath = fullfile(metricsRoot, 'segment5_hoffman_sanity_check.csv');
headerLine = "subjectID,R_value,SpO2_true,SpO2_predicted,abs_error";
writelines(headerLine, csvPath);

numTestWindows = numel(R_test);

for rowPos = 1:numTestWindows
    rowParts = {testSubjectIDs{rowPos}, num2str(R_test(rowPos)), num2str(SpO2_testTrue(rowPos)), num2str(SpO2_testPredicted(rowPos)), num2str(abs_error(rowPos))};
    rowLine = strjoin(rowParts, ',');
    writelines(rowLine, csvPath, 'WriteMode', 'append');
end

disp(['Saved ' csvPath]);

figureHandle = figure('Visible', 'off', 'Position', [100 100 1200 500]);

subplot(1, 2, 1);
hold on;

scatter(windowR(trainMask), windowSpO2True(trainMask), 12, [0.4 0.4 0.4], 'filled');
scatter(windowR(testMask), windowSpO2True(testMask), 12, [0.85 0.33 0.10], 'filled');

RLineAxis = linspace(min(windowR), max(windowR), 100);
SpO2Line = calibParams.A - calibParams.B * RLineAxis;
plot(RLineAxis, SpO2Line, 'b-', 'LineWidth', 2);

xlabel('R (ratio-of-ratios)');
ylabel('SpO2 true (%)');
title('Pooled: R vs SpO2, All Subjects Together');
legend({'Training windows', 'Test windows', 'Fitted calibration line'}, 'Location', 'best');
grid on;
hold off;

subplot(1, 2, 2);
hold on;

subjectColors = lines(numel(allSubjectList));

for subjectPos = 1:numel(allSubjectList)
    subjectID = allSubjectList{subjectPos};
    subjectWindowMask = strcmp(windowSubjectID, subjectID);
    scatter(windowR(subjectWindowMask), windowSpO2True(subjectWindowMask), 12, subjectColors(subjectPos, :), 'filled');
end

xlabel('R (ratio-of-ratios)');
ylabel('SpO2 true (%)');
title('Same Data, Colored Per Subject');
legend(allSubjectList, 'Location', 'best');
grid on;
hold off;

sgtitle('Segment 5 -- Hoffman Sanity Check: R vs SpO2 Across a Wide Range');

pngOutPath = fullfile(figuresRoot, 'segment5_hoffman_sanity_scatter.png');
exportgraphics(figureHandle, pngOutPath);
close(figureHandle);

disp(['Saved ' pngOutPath]);
disp('--- Hoffman sanity check complete ---');
