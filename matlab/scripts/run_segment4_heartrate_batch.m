% RUN_SEGMENT4_HEARTRATE_BATCH Batch driver for Segment 4 (CHROM/POS
% combination + FFT heart rate) across a configurable list of subjects
% that already have Segment 3 output.
%
% Each team member edits the SUBJECT LIST section below to their own
% already-filtered subset from Segment 3, then runs this script. Every
% subject's output filename is tagged with that subject's own ID, so
% everyone's .mat/.png outputs can be copied into one shared folder
% afterwards without collisions.
%
% For each subject this script:
%   1. Loads data/processed/<subjectID>_filtered_traces.mat (Segment 3
%      output) and data/processed/<subjectID>_rgb_traces.mat (Segment 2
%      output, needed only for the CHROM/POS normalization mean — see
%      pulseextraction/chromCombine.m).
%   2. Calls pulseextraction/chromCombine.m, re-filters the result with
%      filtering/bandpassClean.m, then calls heartrate/fftHeartRate.m to
%      get HR_chrom.
%   3. Same as (2) with pulseextraction/posCombine.m to get HR_pos.
%   4. Calls heartrate/fftHeartRate.m directly on G_filtered (no
%      combination) to get HR_green.
%   5. Tries io/loadGroundTruth.m for this subject's ground-truth HR, if
%      the subject's dataset folder is found; records NaN if not found or
%      if it errors (that function is still a stub as of Segment 4).
%   6. Saves data/processed/<subjectID>_hr_estimates.mat.
%   7. Appends one row to the shared results/metrics/segment4_hr_summary.csv.
%   8. Saves a three-subplot sanity PNG (CHROM, POS, green spectra) to
%      results/figures/<subjectID>_heartrate_sanity.png.
%   9. Prints progress and the HR estimates to the console.
%
% If a subject's filtered_traces.mat or rgb_traces.mat is missing, this
% script logs the reason and moves on to the next subject rather than
% halting the whole batch. A summary of any failures is printed at the
% end.
%
% IMPORTANT for a 4-person team writing to the SAME CSV path: this script
% checks whether results/metrics/segment4_hr_summary.csv already has a
% header before writing one, and appends each subject's row as it is
% processed rather than holding everything in memory and overwriting the
% file at the end. If you and a teammate are both running this against a
% shared synced folder, run one at a time if possible to avoid the small
% window where two processes could check-and-write at the same moment.

subjectList = {'5-gt', '6-gt', '7-gt'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
dataset2Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_2');
csvPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');

if ~isfolder(processedDataRoot)
    mkdir(processedDataRoot);
end

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

if ~isfile(csvPath)
    headerLine = "subjectID,HR_chrom,HR_pos,HR_green,HR_groundtruth,abs_error_chrom,abs_error_pos,abs_error_green";
    writelines(headerLine, csvPath);
end

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};

    disp(['--- Processing subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        filteredMatPath = fullfile(processedDataRoot, [subjectID '_filtered_traces.mat']);

        if ~isfile(filteredMatPath)
            error('run_segment4_heartrate_batch:missingInput', 'Segment 3 output not found: %s', filteredMatPath);
        end

        filteredData = load(filteredMatPath);

        R_filtered = filteredData.R_filtered;
        G_filtered = filteredData.G_filtered;
        B_filtered = filteredData.B_filtered;
        fs = filteredData.fs;

        disp(['Subject ' subjectID ': loaded filtered_traces.mat, fs = ' num2str(fs) ' fps, numFrames = ' num2str(numel(G_filtered))]);

        rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);

        if ~isfile(rgbMatPath)
            error('run_segment4_heartrate_batch:missingInput', 'Segment 2 raw traces not found (needed for CHROM/POS normalization mean): %s', rgbMatPath);
        end

        rgbData = load(rgbMatPath);

        R_raw = rgbData.R;
        G_raw = rgbData.G;
        B_raw = rgbData.B;

        pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R_raw, G_raw, B_raw);
        pulseChromFiltered = bandpassClean(pulseChrom, fs);
        [HR_chrom, freqSpectrumChrom, powerSpectrumChrom] = fftHeartRate(pulseChromFiltered, fs);

        pulsePos = posCombine(R_filtered, G_filtered, B_filtered, fs, R_raw, G_raw, B_raw);
        pulsePosFiltered = bandpassClean(pulsePos, fs);
        [HR_pos, freqSpectrumPos, powerSpectrumPos] = fftHeartRate(pulsePosFiltered, fs);

        [HR_green, freqSpectrumGreen, powerSpectrumGreen] = fftHeartRate(G_filtered, fs);

        disp(['Subject ' subjectID ': HR_chrom = ' num2str(HR_chrom) ' bpm, HR_pos = ' num2str(HR_pos) ' bpm, HR_green = ' num2str(HR_green) ' bpm']);

        gtPathDataset1 = fullfile(dataset1Root, subjectID, 'gtdump.xmp');
        gtPathDataset2 = fullfile(dataset2Root, subjectID, 'ground_truth.txt');

        if isfile(gtPathDataset1)
            gtPath = gtPathDataset1;
            datasetFormat = 'dataset1';
        elseif isfile(gtPathDataset2)
            gtPath = gtPathDataset2;
            datasetFormat = 'dataset2';
        else
            gtPath = '';
            datasetFormat = '';
        end

        if isempty(gtPath)
            HR_groundtruth = NaN;
            disp(['Subject ' subjectID ': no ground truth file found under data/raw/UBFC-rPPG, recording NaN.']);
        else
            try
                gt = loadGroundTruth(gtPath, datasetFormat);
                HR_groundtruth = mean(gt.hr);
            catch gtErr
                HR_groundtruth = NaN;
                disp(['Subject ' subjectID ': loadGroundTruth failed (' gtErr.message '), recording NaN.']);
            end
        end

        disp(['Subject ' subjectID ': HR_groundtruth = ' num2str(HR_groundtruth) ' bpm']);

        hrEstimatesPath = fullfile(processedDataRoot, [subjectID '_hr_estimates.mat']);
        save(hrEstimatesPath, 'HR_chrom', 'HR_pos', 'HR_green', 'HR_groundtruth', 'subjectID', 'fs');

        disp(['Subject ' subjectID ': saved ' hrEstimatesPath]);

        absErrorChrom = abs(HR_chrom - HR_groundtruth);
        absErrorPos = abs(HR_pos - HR_groundtruth);
        absErrorGreen = abs(HR_green - HR_groundtruth);

        rowParts = {subjectID, num2str(HR_chrom), num2str(HR_pos), num2str(HR_green), num2str(HR_groundtruth), num2str(absErrorChrom), num2str(absErrorPos), num2str(absErrorGreen)};
        rowLine = strjoin(rowParts, ',');
        writelines(rowLine, csvPath, 'WriteMode', 'append');

        disp(['Subject ' subjectID ': appended row to ' csvPath]);

        plotMaskChrom = freqSpectrumChrom <= 5;
        plotMaskPos = freqSpectrumPos <= 5;
        plotMaskGreen = freqSpectrumGreen <= 5;

        figureHandle = figure('Visible', 'off');

        subplot(3, 1, 1);
        plot(freqSpectrumChrom(plotMaskChrom), powerSpectrumChrom(plotMaskChrom));
        xregion(0.7, 4.0);
        xline(HR_chrom / 60, 'r', 'LineWidth', 1.5);
        titleChrom = ['CHROM: ' num2str(HR_chrom) ' bpm'];
        if ~isnan(HR_groundtruth)
            titleChrom = [titleChrom ' (GT: ' num2str(HR_groundtruth) ' bpm)'];
        end
        title(titleChrom);
        xlabel('Frequency (Hz)');
        ylabel('|FFT| magnitude');
        xlim([0 5]);

        subplot(3, 1, 2);
        plot(freqSpectrumPos(plotMaskPos), powerSpectrumPos(plotMaskPos));
        xregion(0.7, 4.0);
        xline(HR_pos / 60, 'r', 'LineWidth', 1.5);
        titlePos = ['POS: ' num2str(HR_pos) ' bpm'];
        if ~isnan(HR_groundtruth)
            titlePos = [titlePos ' (GT: ' num2str(HR_groundtruth) ' bpm)'];
        end
        title(titlePos);
        xlabel('Frequency (Hz)');
        ylabel('|FFT| magnitude');
        xlim([0 5]);

        subplot(3, 1, 3);
        plot(freqSpectrumGreen(plotMaskGreen), powerSpectrumGreen(plotMaskGreen));
        xregion(0.7, 4.0);
        xline(HR_green / 60, 'r', 'LineWidth', 1.5);
        titleGreen = ['Green-only: ' num2str(HR_green) ' bpm'];
        if ~isnan(HR_groundtruth)
            titleGreen = [titleGreen ' (GT: ' num2str(HR_groundtruth) ' bpm)'];
        end
        title(titleGreen);
        xlabel('Frequency (Hz)');
        ylabel('|FFT| magnitude');
        xlim([0 5]);

        sgtitle(['Subject ' subjectID ' — Segment 4 Heart Rate Sanity Check']);

        pngOutPath = fullfile(figuresRoot, [subjectID '_heartrate_sanity.png']);
        exportgraphics(figureHandle, pngOutPath);
        close(figureHandle);

        disp(['Subject ' subjectID ': saved ' pngOutPath]);
    catch causeErr
        disp(['Subject ' subjectID ': FAILED — ' causeErr.message]);
        failedSubjects{end + 1} = subjectID;
        failedReasons{end + 1} = causeErr.message;
    end
end

disp('--- Batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end
