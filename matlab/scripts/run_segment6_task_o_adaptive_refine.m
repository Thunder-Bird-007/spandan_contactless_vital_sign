% RUN_SEGMENT6_TASK_O_ADAPTIVE_REFINE Segment 6 Task O, Action 2. Runs the
% new two-stage adaptive bandpass (filtering/adaptiveNarrowRefine.m) on
% the existing 107-subject VIPL-HR v1 pool, reusing already-extracted
% data/processed/VIPL_p*_v1_source*_rgb_traces.mat cached R/G/B traces and
% results/metrics/segment4_hr_summary_vipl.csv's HR_groundtruth column --
% no video is re-decoded and no ROI re-extraction happens here.
%
% Pass 1 (original, unmodified): detrendSignal.m -> bandpassClean.m ->
% chromCombine.m/posCombine.m -> fftHeartRate.m, exactly what
% scripts/run_vipl_integration_batch.m already does and exactly what
% segment4_hr_summary_vipl.csv already records -- recomputed here (not
% just re-read from the CSV) because Pass 2 needs the intermediate
% ALREADY-detrended signal each Pass-1 estimate was built from:
%   - green:  G_detrended (filtering/detrendSignal.m's output on G),
%             Pass-1 estimate = fftHeartRate(bandpassClean(G_detrended)).
%   - chrom:  pulseChrom (pulseextraction/chromCombine.m's output, itself
%             built from the detrended+bandpassed R/G/B channels), Pass-1
%             estimate = fftHeartRate(bandpassClean(pulseChrom)).
%   - pos:    pulsePos (pulseextraction/posCombine.m's output), same
%             pattern as chrom.
% None of detrendSignal.m, bandpassClean.m, chromCombine.m, posCombine.m,
% or fftHeartRate.m are modified by this script.
%
% Pass 2 (new, additive): filtering/adaptiveNarrowRefine.m takes each of
% the three ALREADY-detrended signals above plus its own Pass-1 rough
% estimate, builds a narrow +/-15 bpm Butterworth bandpass centered on
% that estimate, and calls fftHeartRate.m again for a refined estimate --
% one refined estimate per method (green, chrom, pos), each refined
% against its OWN Pass-1 estimate, not a single shared "best" method.
%
% Outputs:
%   results/metrics/segment6_task_o_adaptive_refine_metrics.csv - one row
%     per (method, stage) pair where stage is original/refined: MAE, RMSE,
%     Pearson r, N.
%   results/metrics/segment6_task_o_adaptive_refine_details.csv - one row
%     per subjectID: original and refined HR for all 3 methods plus their
%     abs errors, for audit.
%
% See docs/Segment6_Task_O_Detrend_And_Adaptive_Bandpass.md for the
% original-vs-refined comparison table.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

viplSummaryPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');
viplSummaryTable = readtable(viplSummaryPath, 'TextType', 'string');

numSubjects = height(viplSummaryTable);

disp(['=== Segment 6 Task O, Action 2: loaded ' num2str(numSubjects) ' subjects from ' viplSummaryPath ' ===']);

detailsPath = fullfile(metricsRoot, 'segment6_task_o_adaptive_refine_details.csv');
detailsHeaderLine = "subjectID,HR_groundtruth,HR_green_orig,HR_green_refined,HR_chrom_orig,HR_chrom_refined,HR_pos_orig,HR_pos_refined,abs_error_green_orig,abs_error_green_refined,abs_error_chrom_orig,abs_error_chrom_refined,abs_error_pos_orig,abs_error_pos_refined";
writelines(detailsHeaderLine, detailsPath);

greenOrigAll = [];
greenRefinedAll = [];
chromOrigAll = [];
chromRefinedAll = [];
posOrigAll = [];
posRefinedAll = [];
groundtruthAll = [];
failedSubjects = {};
failedReasons = {};

for subjectRowIdx = 1:numSubjects
    subjectID = char(viplSummaryTable.subjectID(subjectRowIdx));
    HR_groundtruth = viplSummaryTable.HR_groundtruth(subjectRowIdx);

    try
        rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
        loadedRgb = load(rgbMatPath, 'R', 'G', 'B', 'fs');

        R = loadedRgb.R;
        G = loadedRgb.G;
        B = loadedRgb.B;
        fs = loadedRgb.fs;

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        [R_filtered, ~] = bandpassClean(R_detrended, fs);
        [G_filtered, ~] = bandpassClean(G_detrended, fs);
        [B_filtered, ~] = bandpassClean(B_detrended, fs);

        [HR_green_orig, ~, ~] = fftHeartRate(G_filtered, fs);
        [HR_green_refined, ~, ~] = adaptiveNarrowRefine(G_detrended, fs, HR_green_orig);

        pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
        pulseChromFiltered = bandpassClean(pulseChrom, fs);
        [HR_chrom_orig, ~, ~] = fftHeartRate(pulseChromFiltered, fs);
        [HR_chrom_refined, ~, ~] = adaptiveNarrowRefine(pulseChrom, fs, HR_chrom_orig);

        pulsePos = posCombine(R_filtered, G_filtered, B_filtered, fs, R, G, B);
        pulsePosFiltered = bandpassClean(pulsePos, fs);
        [HR_pos_orig, ~, ~] = fftHeartRate(pulsePosFiltered, fs);
        [HR_pos_refined, ~, ~] = adaptiveNarrowRefine(pulsePos, fs, HR_pos_orig);

        absErrorGreenOrig = abs(HR_green_orig - HR_groundtruth);
        absErrorGreenRefined = abs(HR_green_refined - HR_groundtruth);
        absErrorChromOrig = abs(HR_chrom_orig - HR_groundtruth);
        absErrorChromRefined = abs(HR_chrom_refined - HR_groundtruth);
        absErrorPosOrig = abs(HR_pos_orig - HR_groundtruth);
        absErrorPosRefined = abs(HR_pos_refined - HR_groundtruth);

        disp([subjectID ': green ' num2str(HR_green_orig) ' -> ' num2str(HR_green_refined) ' bpm, chrom ' num2str(HR_chrom_orig) ' -> ' num2str(HR_chrom_refined) ' bpm, pos ' num2str(HR_pos_orig) ' -> ' num2str(HR_pos_refined) ' bpm (GT ' num2str(HR_groundtruth) ' bpm)']);

        detailsRowParts = {subjectID, num2str(HR_groundtruth), num2str(HR_green_orig), num2str(HR_green_refined), num2str(HR_chrom_orig), num2str(HR_chrom_refined), num2str(HR_pos_orig), num2str(HR_pos_refined), num2str(absErrorGreenOrig), num2str(absErrorGreenRefined), num2str(absErrorChromOrig), num2str(absErrorChromRefined), num2str(absErrorPosOrig), num2str(absErrorPosRefined)};
        detailsRowLine = strjoin(detailsRowParts, ',');
        writelines(detailsRowLine, detailsPath, 'WriteMode', 'append');

        greenOrigAll(end + 1) = HR_green_orig;
        greenRefinedAll(end + 1) = HR_green_refined;
        chromOrigAll(end + 1) = HR_chrom_orig;
        chromRefinedAll(end + 1) = HR_chrom_refined;
        posOrigAll(end + 1) = HR_pos_orig;
        posRefinedAll(end + 1) = HR_pos_refined;
        groundtruthAll(end + 1) = HR_groundtruth;
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID;
        failedReasons{end + 1} = causeErr.message;
    end
end

disp(['Subjects succeeded: ' num2str(numel(groundtruthAll)) ', failed: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

greenOrigMetrics = computeMetrics(greenOrigAll, groundtruthAll);
greenRefinedMetrics = computeMetrics(greenRefinedAll, groundtruthAll);
chromOrigMetrics = computeMetrics(chromOrigAll, groundtruthAll);
chromRefinedMetrics = computeMetrics(chromRefinedAll, groundtruthAll);
posOrigMetrics = computeMetrics(posOrigAll, groundtruthAll);
posRefinedMetrics = computeMetrics(posRefinedAll, groundtruthAll);

disp(['Green original: MAE = ' num2str(greenOrigMetrics.mae) ', RMSE = ' num2str(greenOrigMetrics.rmse) ', r = ' num2str(greenOrigMetrics.pearsonR) ', N = ' num2str(greenOrigMetrics.n)]);
disp(['Green refined:  MAE = ' num2str(greenRefinedMetrics.mae) ', RMSE = ' num2str(greenRefinedMetrics.rmse) ', r = ' num2str(greenRefinedMetrics.pearsonR) ', N = ' num2str(greenRefinedMetrics.n)]);
disp(['CHROM original: MAE = ' num2str(chromOrigMetrics.mae) ', RMSE = ' num2str(chromOrigMetrics.rmse) ', r = ' num2str(chromOrigMetrics.pearsonR) ', N = ' num2str(chromOrigMetrics.n)]);
disp(['CHROM refined:  MAE = ' num2str(chromRefinedMetrics.mae) ', RMSE = ' num2str(chromRefinedMetrics.rmse) ', r = ' num2str(chromRefinedMetrics.pearsonR) ', N = ' num2str(chromRefinedMetrics.n)]);
disp(['POS original:   MAE = ' num2str(posOrigMetrics.mae) ', RMSE = ' num2str(posOrigMetrics.rmse) ', r = ' num2str(posOrigMetrics.pearsonR) ', N = ' num2str(posOrigMetrics.n)]);
disp(['POS refined:    MAE = ' num2str(posRefinedMetrics.mae) ', RMSE = ' num2str(posRefinedMetrics.rmse) ', r = ' num2str(posRefinedMetrics.pearsonR) ', N = ' num2str(posRefinedMetrics.n)]);

metricsPath = fullfile(metricsRoot, 'segment6_task_o_adaptive_refine_metrics.csv');
metricsHeaderLine = "method,stage,MAE,RMSE,pearsonR,N";
writelines(metricsHeaderLine, metricsPath);

rowsToWrite = {
    'green', 'original', greenOrigMetrics
    'green', 'refined', greenRefinedMetrics
    'chrom', 'original', chromOrigMetrics
    'chrom', 'refined', chromRefinedMetrics
    'pos', 'original', posOrigMetrics
    'pos', 'refined', posRefinedMetrics
};

numRowsToWrite = size(rowsToWrite, 1);

for rowPos = 1:numRowsToWrite
    methodName = rowsToWrite{rowPos, 1};
    stageName = rowsToWrite{rowPos, 2};
    rowMetrics = rowsToWrite{rowPos, 3};

    rowParts = {methodName, stageName, num2str(rowMetrics.mae), num2str(rowMetrics.rmse), num2str(rowMetrics.pearsonR), num2str(rowMetrics.n)};
    writelines(strjoin(rowParts, ','), metricsPath, 'WriteMode', 'append');
end

disp('--- Segment 6 Task O, Action 2 adaptive refine batch complete ---');
disp(['Saved ' metricsPath]);
disp(['Saved ' detailsPath]);
