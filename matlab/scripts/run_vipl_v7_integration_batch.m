% RUN_VIPL_V7_INTEGRATION_BATCH Batch driver that runs the full,
% unmodified Segment 2-5 pipeline (extractROISignals -> detrendSignal ->
% bandpassClean -> chromCombine/posCombine -> fftHeartRate ->
% ratioOfRatios) against VIPL-HR's v7 (after-exercise) scenario, using the
% SAME io/loadVIPLVideo.m and io/loadVIPLGroundTruth.m as
% run_vipl_integration_batch.m -- both already take scenarioNum as an
% explicit argument, so no changes were needed there. This is Segment 6
% Task K, see docs/Segment6_Task_K_v7_Integration.md.
%
% Why v7 and not another scenario: docs/VIPL_Scenario_Coverage.md found
% v7 (after-exercise) is the only VIPL scenario whose ground-truth HR
% distribution meaningfully differs from v1 -- cleaned mean 75.4 -> 98.6
% bpm, std 10.1 -> 16.7, range extends to 157 bpm. SpO2 barely moves
% across scenarios and is not chased further here.
%
% Subject list below follows the SAME source1-primary/source2-fallback
% rule already used for v1 (see VIPL_Scenario_Coverage.md Section 1's
% coverage matrix): source1 whenever p*'s v7 folder has it, source2
% otherwise. p56 has no v6-v9 at all and is excluded, giving n=106.
%
% For each (subjectNum, scenarioNum, sourceNum) triple this script:
%   1. Calls io/loadVIPLVideo.m to open the video and get its real fs.
%   2. Calls roi/extractROISignals.m to get R(t), G(t), B(t) -- completely
%      unmodified from the UBFC/VIPL-v1 pipeline.
%   3. Saves data/processed/VIPL_pX_v7_sourceZ_rgb_traces.mat and a
%      face+ROI sanity PNG, same as run_vipl_integration_batch.m does.
%   4. Calls filtering/detrendSignal.m and filtering/bandpassClean.m on
%      each channel, saves data/processed/..._filtered_traces.mat and a
%      raw/detrended/filtered sanity PNG.
%   5. Calls pulseextraction/chromCombine.m and posCombine.m, re-filters,
%      and calls heartrate/fftHeartRate.m for HR_chrom/HR_pos/HR_green,
%      saves data/processed/..._hr_estimates.mat and an FFT-spectrum
%      sanity PNG.
%   6. Calls io/loadVIPLGroundTruth.m for HR_groundtruth (mean of
%      gt_HR.csv, AFTER fault-code stripping -- see below) and SpO2_true
%      (mean of gt_SpO2.csv, also after fault-code stripping), and
%      spo2/ratioOfRatios.m for this subject's R value.
%   7. Appends one row to results/metrics/segment4_hr_summary_v7.csv --
%      a NEW file, same schema as segment4_hr_summary.csv/
%      segment4_hr_summary_vipl.csv plus one extra trailing "scenario"
%      column, kept separate from the existing v1 CSVs on disk (Task K's
%      pooling happens at analysis time in run_segment6_task_k_pooled.m,
%      not by writing into the shared v1 files).
%
% Fault-code stripping (Task K Action 3, same discipline already applied
% to UBFC's p25): VIPL's gt_HR.csv/gt_SpO2.csv use HR==255 and
% SpO2 in {44} or SpO2>=127 as sensor-fault codes, not real readings --
% confirmed against the actual v1 file already handled elsewhere and
% against docs/VIPL_Scenario_Coverage.md Section 2's raw-vs-cleaned pass.
% Fault samples are dropped from gt.hr/gt.spo2 BEFORE the mean() used for
% HR_groundtruth/SpO2_true is taken, per-subject, so a partially-faulted
% sensor trace does not pull that subject's ground truth toward 255% or
% 44/127%. Every subject where this actually strips at least one sample
% is logged to the console and collected into a summary at the end.
%
% If a subject fails (missing file, corrupt video, detector error), this
% script logs the error and moves on to the next subject rather than
% halting the whole batch. A summary of any failures is printed at the
% end, same discipline as run_vipl_integration_batch.m.

subjectTriples = [
    1, 7, 2
    2, 7, 1
    3, 7, 1
    4, 7, 1
    5, 7, 1
    6, 7, 1
    7, 7, 1
    8, 7, 1
    9, 7, 1
    10, 7, 1
    11, 7, 2
    12, 7, 1
    13, 7, 2
    14, 7, 1
    15, 7, 1
    16, 7, 1
    17, 7, 1
    18, 7, 1
    19, 7, 1
    20, 7, 1
    21, 7, 1
    22, 7, 1
    23, 7, 1
    24, 7, 1
    25, 7, 1
    26, 7, 1
    27, 7, 1
    28, 7, 1
    29, 7, 1
    30, 7, 1
    31, 7, 1
    32, 7, 1
    33, 7, 1
    34, 7, 1
    35, 7, 1
    36, 7, 1
    37, 7, 1
    38, 7, 1
    39, 7, 1
    40, 7, 1
    41, 7, 1
    42, 7, 1
    43, 7, 1
    44, 7, 2
    45, 7, 1
    46, 7, 1
    47, 7, 1
    48, 7, 1
    49, 7, 1
    50, 7, 1
    51, 7, 1
    52, 7, 1
    53, 7, 1
    54, 7, 1
    55, 7, 1
    57, 7, 1
    58, 7, 1
    59, 7, 1
    60, 7, 1
    61, 7, 1
    62, 7, 1
    63, 7, 1
    64, 7, 1
    65, 7, 1
    66, 7, 1
    67, 7, 1
    68, 7, 1
    69, 7, 1
    70, 7, 1
    71, 7, 1
    72, 7, 1
    73, 7, 1
    74, 7, 1
    75, 7, 1
    76, 7, 1
    77, 7, 1
    78, 7, 1
    79, 7, 1
    80, 7, 1
    81, 7, 1
    82, 7, 1
    83, 7, 1
    84, 7, 1
    85, 7, 1
    86, 7, 1
    87, 7, 1
    88, 7, 1
    89, 7, 1
    90, 7, 1
    91, 7, 1
    92, 7, 1
    93, 7, 1
    94, 7, 1
    95, 7, 1
    96, 7, 1
    97, 7, 2
    98, 7, 2
    99, 7, 2
    100, 7, 2
    101, 7, 2
    102, 7, 2
    103, 7, 2
    104, 7, 2
    105, 7, 2
    106, 7, 2
    107, 7, 2
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

hrCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_v7.csv');

if ~isfile(hrCsvPath)
    hrHeaderLine = "subjectID,dataset,HR_chrom,HR_pos,HR_green,HR_groundtruth,abs_error_chrom,abs_error_pos,abs_error_green,scenario";
    writelines(hrHeaderLine, hrCsvPath);
end

numSubjects = size(subjectTriples, 1);
failedSubjects = {};
failedReasons = {};

usableSubjectID = {};
usableR = [];
usableSpO2True = [];

faultSubjects = {};
faultCounts = [];

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

        hrFaultMask = gt.hr == 255;
        spo2FaultMask = gt.spo2 == 44 | gt.spo2 >= 127;

        numHRFaultSamples = sum(hrFaultMask);
        numSpO2FaultSamples = sum(spo2FaultMask);
        numTotalFaultSamples = numHRFaultSamples + numSpO2FaultSamples;

        if numTotalFaultSamples > 0
            disp([subjectID ': FAULT CODES -- ' num2str(numHRFaultSamples) ' HR sample(s) == 255, ' num2str(numSpO2FaultSamples) ' SpO2 sample(s) == 44 or >= 127. Stripping before mean().']);
            faultSubjects{end + 1} = subjectID;
            faultCounts(end + 1) = numTotalFaultSamples;
        end

        hrClean = gt.hr(~hrFaultMask);
        spo2Clean = gt.spo2(~spo2FaultMask);

        HR_groundtruth = mean(hrClean);
        SpO2_true = mean(spo2Clean);

        disp([subjectID ': HR_groundtruth = ' num2str(HR_groundtruth) ' bpm, SpO2_true = ' num2str(SpO2_true) ' % (fault-stripped)']);

        hrEstimatesPath = fullfile(processedDataRoot, [subjectID '_hr_estimates.mat']);
        save(hrEstimatesPath, 'HR_chrom', 'HR_pos', 'HR_green', 'HR_groundtruth', 'SpO2_true', 'subjectID', 'fs');

        disp([subjectID ': saved ' hrEstimatesPath]);

        absErrorChrom = abs(HR_chrom - HR_groundtruth);
        absErrorPos = abs(HR_pos - HR_groundtruth);
        absErrorGreen = abs(HR_green - HR_groundtruth);

        hrRowParts = {subjectID, 'VIPL', num2str(HR_chrom), num2str(HR_pos), num2str(HR_green), num2str(HR_groundtruth), num2str(absErrorChrom), num2str(absErrorPos), num2str(absErrorGreen), ['v' num2str(scenarioNum)]};
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

disp('--- v7 HR/ROI/filtering batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

disp(' ');
disp(['--- Fault-code summary: ' num2str(numel(faultSubjects)) ' subjects had at least one HR==255 or SpO2 in {44,127+} sample stripped ---']);

for faultPos = 1:numel(faultSubjects)
    disp(['  ' faultSubjects{faultPos} ': ' num2str(faultCounts(faultPos)) ' fault sample(s) stripped']);
end

numUsable = numel(usableSubjectID);

disp(' ');
disp(['--- SpO2 calibration: ' num2str(numUsable) ' usable subjects ---']);

if numUsable < 3
    disp('Fewer than 3 usable subjects -- leave-one-out SpO2 calibration needs at least 3 to be even minimally meaningful. Stopping here.');
else
    spo2CsvPath = fullfile(metricsRoot, 'segment5_v7_calibration.csv');
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
    title('VIPL-HR v7 Integration -- Leave-One-Out SpO2 Calibration');
    grid on;
    hold off;

    spo2PngOutPath = fullfile(figuresRoot, 'segment5_v7_calibration_scatter.png');
    exportgraphics(spo2FigureHandle, spo2PngOutPath);
    close(spo2FigureHandle);

    disp(['Saved ' spo2PngOutPath]);
end

disp('--- VIPL v7 integration batch complete ---');
