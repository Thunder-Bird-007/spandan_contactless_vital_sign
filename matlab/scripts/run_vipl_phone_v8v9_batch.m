% RUN_VIPL_PHONE_V8V9_BATCH Task L, Action 3 (v8/v9 half). Runs the
% full, unmodified Segment 2-5 pipeline (extractROISignals ->
% detrendSignal -> bandpassClean -> chromCombine/posCombine ->
% fftHeartRate -> ratioOfRatios) against every VIPL-HR subject's v8
% (hand-held phone, stable) and v9 (hand-held phone, large motion)
% source2 (HUAWEI P9 phone) videos.
%
% v8/v9 are the HIGHEST PRIORITY data for this project's Android demo --
% see docs/VIPL_Scenario_Coverage.md Section 5 and the Task L brief: v1-v7
% source2 recordings have the phone FIXED on a stand, but v8/v9 are the
% only VIPL-HR scenarios where the subject actually HOLDS the phone
% ("video chat scenario" per the dataset authors), which is the real
% physical framing of the Android app at defense. source1/source3 do not
% exist at all for v8/v9 (phone-only scenarios, confirmed in
% docs/VIPL_Scenario_Coverage.md Section 1), so sourceNum is hardcoded to
% 2 here -- there is no fallback logic to write.
%
% Subjects are discovered dynamically per scenario by checking which
% data/raw/VIPL-HR/pX/v{8,9}/source2/video.avi files actually exist on
% disk, same discipline as run_vipl_phone_v1_batch.m. Expected coverage
% per docs/VIPL_Scenario_Coverage.md Section 1 is v8: 106/107, v9:
% 105/107 -- this script does not hardcode those counts, it just
% processes whatever Action 1's extraction pass reached and logs
% "not extracted" for the rest.
%
% Hand-held footage (motion blur, framing drift as the subject holds the
% phone) is expected to be genuinely harder for viola.jones face
% detection than any fixed-camera scenario already in this pipeline --
% per the Task L brief this is an ANTICIPATED FINDING to document via
% the mandatory per-subject ROI sanity PNG, not a bug to chase or a
% detector change to make. extractROISignals.m is used completely
% unmodified.
%
% Output naming mirrors run_vipl_integration_batch.m / and
% run_vipl_phone_v1_batch.m's pattern but writes to its own
% segment4_hr_summary_vipl_phone_v8v9.csv /
% segment5_vipl_calibration_phone_v8v9.csv, with an extra "scenario"
% column (v8/v9 pooled together in one CSV, distinguished by this column)
% so run_vipl_device_stratified_eval.m can break v8 and v9 out
% separately without needing two more files.
%
% If a subject fails (corrupt video, detector error, etc) this script
% logs the error and moves on to the next subject rather than halting
% the whole batch, same discipline as the other VIPL batch scripts.

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

hrCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl_phone_v8v9.csv');

if ~isfile(hrCsvPath)
    hrHeaderLine = "subjectID,dataset,scenario,HR_chrom,HR_pos,HR_green,HR_groundtruth,abs_error_chrom,abs_error_pos,abs_error_green";
    writelines(hrHeaderLine, hrCsvPath);
end

sourceNum = 2;
maxSubjectNum = 107;
scenarioList = [8 9];

failedSubjects = {};
failedReasons = {};
notExtractedSubjects = {};

usableSubjectID = {};
usableR = [];
usableSpO2True = [];

numAttempted = 0;

for scenarioPos = 1:numel(scenarioList)
    scenarioNum = scenarioList(scenarioPos);

    for subjectNum = 1:maxSubjectNum
        subjectFolder = ['p' num2str(subjectNum)];
        sourceFolder = ['source' num2str(sourceNum)];
        scenarioFolder = ['v' num2str(scenarioNum)];
        videoPath = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder, 'video.avi');

        if ~isfile(videoPath)
            notExtractedSubjects{end + 1} = [subjectFolder '/' scenarioFolder];
            continue;
        end

        numAttempted = numAttempted + 1;

        subjectID = ['VIPL_p' num2str(subjectNum) '_v' num2str(scenarioNum) '_source' num2str(sourceNum)];

        disp(['--- Processing ' subjectID ' (subject ' num2str(subjectNum) ' of ' num2str(maxSubjectNum) ', scenario v' num2str(scenarioNum) ') ---']);

        try
            [videoReaderObj, fs, numFrames, videoPathLoaded] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum);

            disp([subjectID ': loaded ' videoPathLoaded ', fs = ' num2str(fs) ' fps, numFrames = ' num2str(numFrames)]);

            [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(videoReaderObj, fs);

            numDroppedFrames = numel(droppedFrameIdx);

            disp([subjectID ': dropped/reused-bbox frames = ' num2str(numDroppedFrames) ' of ' num2str(numFrames) ' total']);

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

            sgtitle([subjectID ' -- Task L Phone v8/v9 Filtering Sanity Check'], 'Interpreter', 'none');

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

            hrRowParts = {subjectID, 'VIPL', ['v' num2str(scenarioNum)], num2str(HR_chrom), num2str(HR_pos), num2str(HR_green), num2str(HR_groundtruth), num2str(absErrorChrom), num2str(absErrorPos), num2str(absErrorGreen)};
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

            sgtitle([subjectID ' -- Task L Phone v8/v9 Heart Rate Sanity Check'], 'Interpreter', 'none');

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
end

disp('--- Task L Phone v8/v9 batch complete ---');
disp(['Subjects with v8/v9 source2 extracted and attempted: ' num2str(numAttempted)]);
disp(['Subject/scenario combos not extracted (skipped, not a failure): ' num2str(numel(notExtractedSubjects))]);
disp(['Subjects failed during processing: ' num2str(numel(failedSubjects))]);

for notExtractedPos = 1:numel(notExtractedSubjects)
    disp(['  not extracted: ' notExtractedSubjects{notExtractedPos}]);
end

for failPos = 1:numel(failedSubjects)
    disp(['  FAILED: ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numUsable = numel(usableSubjectID);

disp(['--- SpO2 calibration: ' num2str(numUsable) ' usable subjects ---']);

if numUsable < 3
    disp('Fewer than 3 usable subjects -- leave-one-out SpO2 calibration needs at least 3 to be even minimally meaningful. Stopping here.');
else
    spo2CsvPath = fullfile(metricsRoot, 'segment5_vipl_calibration_phone_v8v9.csv');
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
end

disp('--- Task L Phone v8v9 batch script complete ---');
