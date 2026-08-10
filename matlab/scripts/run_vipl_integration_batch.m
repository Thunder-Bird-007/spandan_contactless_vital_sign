% RUN_VIPL_INTEGRATION_BATCH Batch driver that runs the full, unmodified
% Segment 2-5 pipeline (extractROISignals -> detrendSignal -> bandpassClean
% -> chromCombine/posCombine -> fftHeartRate -> ratioOfRatios) against
% VIPL-HR subjects, using io/loadVIPLVideo.m and io/loadVIPLGroundTruth.m
% in place of the UBFC-specific loaders.
%
% Each team member edits the SUBJECT LIST section below to their own
% assigned (subjectNum, scenarioNum, sourceNum) triples -- see
% vipl_integration/VIPL_Team_README.md for how VIPL-HR's real subjects are
% split up and how to extract just your own share of the archive. Every
% subject's output filename is tagged with a "VIPL_pX_vY_sourceZ" subject
% ID (never just "pX", so nothing collides with UBFC's "5-gt"/"subject5"
% style IDs when Segment 6 later pools both datasets together -- see
% docs/VIPL_DATA_FORMAT.md Section 1 for why a (subject, scenario, source)
% triple, not a single subject ID, is VIPL-HR's real addressable unit).
%
% For each (subjectNum, scenarioNum, sourceNum) triple this script:
%   1. Calls io/loadVIPLVideo.m to open the video and get its real fs (see
%      loadVIPLVideo.m's own header for why this is NOT simply
%      VideoReader.FrameRate for VIPL-HR).
%   2. Calls roi/extractROISignals.m to get R(t), G(t), B(t) -- completely
%      unmodified from the UBFC pipeline.
%   3. Saves data/processed/VIPL_pX_vY_sourceZ_rgb_traces.mat and a
%      face+ROI sanity PNG, same as run_segment2_roi_batch.m does for UBFC.
%   4. Calls filtering/detrendSignal.m and filtering/bandpassClean.m on
%      each channel, saves data/processed/..._filtered_traces.mat and a
%      raw/detrended/filtered sanity PNG, same as
%      run_segment3_filtering_batch.m does for UBFC.
%   5. Calls pulseextraction/chromCombine.m and posCombine.m, re-filters,
%      and calls heartrate/fftHeartRate.m for HR_chrom/HR_pos/HR_green,
%      saves data/processed/..._hr_estimates.mat and an FFT-spectrum
%      sanity PNG, same as run_segment4_heartrate_batch.m does for UBFC.
%   6. Calls io/loadVIPLGroundTruth.m for HR_groundtruth (mean of
%      gt_HR.csv) and SpO2_true (mean of gt_SpO2.csv), and
%      spo2/ratioOfRatios.m for this subject's R value.
%   7. Appends one row to results/metrics/segment4_hr_summary_vipl.csv.
%
% Design decision on the shared CSV files (see
% vipl_integration/VIPL_Integration_LineByLine_Explanation.md Part 3 for
% the full reasoning): results/metrics/segment4_hr_summary.csv and
% segment5_dataset1_calibration.csv already exist with real UBFC rows
% written by teammates under a fixed column header that has no "dataset"
% column. Rather than rewrite those live shared files' headers (which
% run_segment4_heartrate_batch.m/run_segment5_dataset1_calibration_batch.m
% own, not this script), this script writes to its own
% segment4_hr_summary_vipl.csv / segment5_vipl_calibration.csv files, using
% the SAME column layout as their UBFC counterparts plus one explicit
% trailing "dataset" column. Segment 6 can pool both datasets either by
% concatenating the two same-shaped HR files (inferring dataset from the
% VIPL_ subjectID prefix on rows that lack the column) or by reading the
% explicit "dataset" column on VIPL rows directly.
%
% After all subjects are processed, if at least 3 subjects succeeded, this
% script also runs a leave-one-out spo2/calibrateSpO2.m loop across them
% (same leakage-avoidance logic as run_segment5_dataset1_calibration_batch.m)
% and saves results/metrics/segment5_vipl_calibration.csv plus a scatter
% PNG -- with the same "thin data" caveat that script already documents,
% since a first VIPL validation batch is likely to be just as small as
% DATASET_1's 5 subjects.
%
% If a subject fails (missing file, corrupt video, detector error), this
% script logs the error and moves on to the next subject rather than
% halting the whole batch. A summary of any failures is printed at the end.

subjectTriples = [
    1, 1, 1
    2, 1, 1
    3, 1, 1
    4, 1, 1
    5, 1, 1
    6, 1, 1
    7, 1, 1
    8, 1, 1
    9, 1, 1
    10, 1, 1
    11, 1, 1
    12, 1, 1
    13, 1, 1
    14, 1, 1
    15, 1, 1
    16, 1, 1
    17, 1, 1
    18, 1, 1
    19, 1, 1
    20, 1, 1
    21, 1, 1
    22, 1, 1
    23, 1, 1
    24, 1, 1
    25, 1, 1
    26, 1, 1
    27, 1, 1
    28, 1, 1
    29, 1, 1
    30, 1, 1
    31, 1, 1
    32, 1, 1
    33, 1, 1
    34, 1, 1
    35, 1, 1
    36, 1, 1
    37, 1, 1
    38, 1, 1
    39, 1, 1
    40, 1, 1
    41, 1, 1
    42, 1, 1
    43, 1, 1
    44, 1, 1
    45, 1, 1
    46, 1, 1
    47, 1, 1
    48, 1, 1
    49, 1, 1
    50, 1, 1
    51, 1, 1
    52, 1, 1
    53, 1, 1
    54, 1, 1
    55, 1, 1
    56, 1, 1
    57, 1, 1
    58, 1, 1
    59, 1, 1
    60, 1, 1
    61, 1, 1
    62, 1, 1
    63, 1, 1
    64, 1, 1
    65, 1, 1
    66, 1, 1
    67, 1, 1
    68, 1, 1
    69, 1, 1
    70, 1, 1
    71, 1, 1
    72, 1, 1
    73, 1, 1
    74, 1, 1
    75, 1, 1
    76, 1, 1
    77, 1, 1
    78, 1, 1
    79, 1, 1
    80, 1, 1
    81, 1, 1
    82, 1, 1
    83, 1, 1
    84, 1, 2
    85, 1, 1
    86, 1, 1
    87, 1, 1
    88, 1, 1
    89, 1, 1
    90, 1, 1
    91, 1, 1
    92, 1, 1
    93, 1, 1
    94, 1, 1
    95, 1, 1
    96, 1, 1
    97, 1, 2
    98, 1, 2
    99, 1, 2
    100, 1, 2
    101, 1, 2
    102, 1, 2
    103, 1, 2
    104, 1, 2
    105, 1, 2
    106, 1, 2
    107, 1, 2
];

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(processedDataRoot)
    mkdir(processedDataRoot);
end

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

hrCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');

if ~isfile(hrCsvPath)
    hrHeaderLine = "subjectID,dataset,HR_chrom,HR_pos,HR_green,HR_groundtruth,abs_error_chrom,abs_error_pos,abs_error_green";
    writelines(hrHeaderLine, hrCsvPath);
end

numSubjects = size(subjectTriples, 1);
failedSubjects = {};
failedReasons = {};

usableSubjectID = {};
usableR = [];
usableSpO2True = [];

for subjectPos = 1:numSubjects
    subjectNum = subjectTriples(subjectPos, 1);
    scenarioNum = subjectTriples(subjectPos, 2);
    sourceNum = subjectTriples(subjectPos, 3);

    subjectID = ['VIPL_p' num2str(subjectNum) '_v' num2str(scenarioNum) '_source' num2str(sourceNum)];

    disp(['--- Processing ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        [videoReaderObj, fs, numFrames, videoPath] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum);

        disp([subjectID ': loaded ' videoPath ', fs = ' num2str(fs) ' fps, numFrames = ' num2str(numFrames)]);

        [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(videoReaderObj, fs);

        numDroppedFrames = numel(droppedFrameIdx);

        disp([subjectID ': dropped/reused-bbox frames = ' num2str(numDroppedFrames)]);

        rgbMatOutPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
        save(rgbMatOutPath, 'R', 'G', 'B', 'fs', 'subjectID', 'numDroppedFrames');

        disp([subjectID ': saved ' rgbMatOutPath]);

        annotatedImg = insertObjectAnnotation(debugFrame.image, 'rectangle', debugFrame.faceBBox, 'Detected Face', 'Color', 'yellow', 'LineWidth', 3);
        annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrame.roiBBox, 'ROI (forehead)', 'Color', 'green', 'LineWidth', 3);

        roiPngOutPath = fullfile(figuresRoot, [subjectID '_roi_sanity.png']);
        imwrite(annotatedImg, roiPngOutPath);

        disp([subjectID ': saved ' roiPngOutPath]);

        [R_detrended, detrendOrder] = detrendSignal(R);
        [G_detrended, detrendOrder] = detrendSignal(G);
        [B_detrended, detrendOrder] = detrendSignal(B);

        [R_filtered, filterOrder] = bandpassClean(R_detrended, fs);
        [G_filtered, filterOrder] = bandpassClean(G_detrended, fs);
        [B_filtered, filterOrder] = bandpassClean(B_detrended, fs);

        disp([subjectID ': detrend order = ' num2str(detrendOrder) ', filter order = ' num2str(filterOrder)]);

        filteredMatOutPath = fullfile(processedDataRoot, [subjectID '_filtered_traces.mat']);
        save(filteredMatOutPath, 'R_filtered', 'G_filtered', 'B_filtered', 'fs', 'subjectID', 'detrendOrder', 'filterOrder');

        disp([subjectID ': saved ' filteredMatOutPath]);

        numSamples = numel(G);
        timeAxis = (0:numSamples - 1) / fs;

        filterFigureHandle = figure('Visible', 'off');

        subplot(3, 1, 1);
        plot(timeAxis, G);
        title('Raw G(t)');
        xlabel('Time (s)');
        ylabel('Pixel intensity');

        subplot(3, 1, 2);
        plot(timeAxis, G_detrended);
        title('Detrended G(t)');
        xlabel('Time (s)');
        ylabel('Pixel intensity (detrended)');

        subplot(3, 1, 3);
        plot(timeAxis, G_filtered);
        title('Detrended + Bandpass-Filtered G(t)');
        xlabel('Time (s)');
        ylabel('Pixel intensity (filtered)');

        sgtitle([subjectID ' -- Segment 3 Filtering Sanity Check'], 'Interpreter', 'none');

        filterPngOutPath = fullfile(figuresRoot, [subjectID '_filtering_sanity.png']);
        exportgraphics(filterFigureHandle, filterPngOutPath);
        close(filterFigureHandle);

        disp([subjectID ': saved ' filterPngOutPath]);

        pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
        pulseChromFiltered = bandpassClean(pulseChrom, fs);
        [HR_chrom, freqSpectrumChrom, powerSpectrumChrom] = fftHeartRate(pulseChromFiltered, fs);

        pulsePos = posCombine(R_filtered, G_filtered, B_filtered, fs, R, G, B);
        pulsePosFiltered = bandpassClean(pulsePos, fs);
        [HR_pos, freqSpectrumPos, powerSpectrumPos] = fftHeartRate(pulsePosFiltered, fs);

        [HR_green, freqSpectrumGreen, powerSpectrumGreen] = fftHeartRate(G_filtered, fs);

        disp([subjectID ': HR_chrom = ' num2str(HR_chrom) ' bpm, HR_pos = ' num2str(HR_pos) ' bpm, HR_green = ' num2str(HR_green) ' bpm']);

        gt = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, sourceNum);

        HR_groundtruth = mean(gt.hr);
        SpO2_true = mean(gt.spo2);

        disp([subjectID ': HR_groundtruth = ' num2str(HR_groundtruth) ' bpm, SpO2_true = ' num2str(SpO2_true) ' %']);

        hrEstimatesPath = fullfile(processedDataRoot, [subjectID '_hr_estimates.mat']);
        save(hrEstimatesPath, 'HR_chrom', 'HR_pos', 'HR_green', 'HR_groundtruth', 'SpO2_true', 'subjectID', 'fs');

        disp([subjectID ': saved ' hrEstimatesPath]);

        absErrorChrom = abs(HR_chrom - HR_groundtruth);
        absErrorPos = abs(HR_pos - HR_groundtruth);
        absErrorGreen = abs(HR_green - HR_groundtruth);

        hrRowParts = {subjectID, 'VIPL', num2str(HR_chrom), num2str(HR_pos), num2str(HR_green), num2str(HR_groundtruth), num2str(absErrorChrom), num2str(absErrorPos), num2str(absErrorGreen)};
        hrRowLine = strjoin(hrRowParts, ',');
        writelines(hrRowLine, hrCsvPath, 'WriteMode', 'append');

        disp([subjectID ': appended row to ' hrCsvPath]);

        plotMaskChrom = freqSpectrumChrom <= 5;
        plotMaskPos = freqSpectrumPos <= 5;
        plotMaskGreen = freqSpectrumGreen <= 5;

        hrFigureHandle = figure('Visible', 'off');

        subplot(3, 1, 1);
        plot(freqSpectrumChrom(plotMaskChrom), powerSpectrumChrom(plotMaskChrom));
        xregion(0.7, 4.0);
        xline(HR_chrom / 60, 'r', 'LineWidth', 1.5);
        titleChrom = ['CHROM: ' num2str(HR_chrom) ' bpm (GT: ' num2str(HR_groundtruth) ' bpm)'];
        title(titleChrom);
        xlabel('Frequency (Hz)');
        ylabel('|FFT| magnitude');
        xlim([0 5]);

        subplot(3, 1, 2);
        plot(freqSpectrumPos(plotMaskPos), powerSpectrumPos(plotMaskPos));
        xregion(0.7, 4.0);
        xline(HR_pos / 60, 'r', 'LineWidth', 1.5);
        titlePos = ['POS: ' num2str(HR_pos) ' bpm (GT: ' num2str(HR_groundtruth) ' bpm)'];
        title(titlePos);
        xlabel('Frequency (Hz)');
        ylabel('|FFT| magnitude');
        xlim([0 5]);

        subplot(3, 1, 3);
        plot(freqSpectrumGreen(plotMaskGreen), powerSpectrumGreen(plotMaskGreen));
        xregion(0.7, 4.0);
        xline(HR_green / 60, 'r', 'LineWidth', 1.5);
        titleGreen = ['Green-only: ' num2str(HR_green) ' bpm (GT: ' num2str(HR_groundtruth) ' bpm)'];
        title(titleGreen);
        xlabel('Frequency (Hz)');
        ylabel('|FFT| magnitude');
        xlim([0 5]);

        sgtitle([subjectID ' -- Segment 4 Heart Rate Sanity Check'], 'Interpreter', 'none');

        hrPngOutPath = fullfile(figuresRoot, [subjectID '_heartrate_sanity.png']);
        exportgraphics(hrFigureHandle, hrPngOutPath);
        close(hrFigureHandle);

        disp([subjectID ': saved ' hrPngOutPath]);

        R_value = ratioOfRatios(R_filtered, G_filtered, B_filtered, R, G, B, fs);

        disp([subjectID ': R (ratio-of-ratios) = ' num2str(R_value)]);

        usableSubjectID{end + 1} = subjectID;
        usableR(end + 1) = R_value;
        usableSpO2True(end + 1) = SpO2_true;
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID;
        failedReasons{end + 1} = causeErr.message;
    end
end

disp('--- HR/ROI/filtering batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numUsable = numel(usableSubjectID);

disp(['--- SpO2 calibration: ' num2str(numUsable) ' usable subjects ---']);

if numUsable < 3
    disp('Fewer than 3 usable subjects -- leave-one-out SpO2 calibration needs at least 3 to be even minimally meaningful. Stopping here.');
else
    spo2CsvPath = fullfile(metricsRoot, 'segment5_vipl_calibration.csv');
    spo2HeaderLine = "subjectID,dataset,R_value,SpO2_true,SpO2_predicted,abs_error";
    writelines(spo2HeaderLine, spo2CsvPath);

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

        spo2RowParts = {usableSubjectID{holdoutPos}, 'VIPL', num2str(usableR(holdoutPos)), num2str(usableSpO2True(holdoutPos)), num2str(spo2Pred), num2str(abs_error(holdoutPos))};
        spo2RowLine = strjoin(spo2RowParts, ',');
        writelines(spo2RowLine, spo2CsvPath, 'WriteMode', 'append');
    end

    disp(['Saved ' spo2CsvPath]);
    disp(['Mean absolute error across ' num2str(numUsable) ' leave-one-out folds: ' num2str(mean(abs_error)) ' percentage points']);

    spo2FigureHandle = figure('Visible', 'off');
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
    title('VIPL-HR Integration -- Leave-One-Out SpO2 Calibration');
    grid on;
    hold off;

    spo2PngOutPath = fullfile(figuresRoot, 'segment5_vipl_calibration_scatter.png');
    exportgraphics(spo2FigureHandle, spo2PngOutPath);
    close(spo2FigureHandle);

    disp(['Saved ' spo2PngOutPath]);
end

disp('--- VIPL integration batch complete ---');
