% RUN_SEGMENT6_TASK_O_DETREND_SWEEP Segment 6 Task O, Action 1. Sweeps
% filtering/detrendSignal.m's new optional polyOrder argument across
% 2, 3, 4, 5 on the existing 107-subject VIPL-HR v1 pool, reusing already-
% extracted data/processed/VIPL_p*_v1_source*_rgb_traces.mat cached R/G/B
% traces and results/metrics/segment4_hr_summary_vipl.csv's HR_groundtruth
% column -- no video is re-decoded and no ROI re-extraction happens here.
%
% Part 1 (regression check): confirms detrendSignal(signal) with no
% second argument reproduces byte-identical output to the pre-Task-O
% hardcoded order-3 behavior, on 3 already-processed subjects, before the
% sweep runs at all.
%
% Part 2 (sweep): for polyOrder in [2 3 4 5], reruns
% detrendSignal -> bandpassClean -> chromCombine/posCombine -> fftHeartRate
% (bandpassClean.m and everything downstream of detrendSignal.m are
% completely unmodified) on all 107 subjects and scores HR_chrom/HR_pos/
% HR_green against HR_groundtruth with validation/computeMetrics.m.
%
% Outputs:
%   results/metrics/segment6_task_o_detrend_sweep_metrics.csv - one row
%     per (polyOrder, method) pair: MAE, RMSE, Pearson r, N.
%   results/metrics/segment6_task_o_detrend_sweep_details.csv - one row
%     per (polyOrder, subjectID): HR_chrom/HR_pos/HR_green and their
%     abs errors, for audit.
%
% See docs/Segment6_Task_O_Detrend_And_Adaptive_Bandpass.md for the
% regression check result and the 4-order comparison table.

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

disp(['=== Segment 6 Task O, Action 1: loaded ' num2str(numSubjects) ' subjects from ' viplSummaryPath ' ===']);

disp('--- Part 1: regression check on 3 subjects ---');

regressionSubjectIdx = [1, 2, 3];
allRegressionMatch = true;

for regressionPos = 1:numel(regressionSubjectIdx)
    subjectRowIdx = regressionSubjectIdx(regressionPos);
    subjectID = char(viplSummaryTable.subjectID(subjectRowIdx));

    rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
    loadedRgb = load(rgbMatPath, 'R', 'G', 'B');

    [R_detrended_default, orderDefault] = detrendSignal(loadedRgb.R);
    [R_detrended_explicit, orderExplicit] = detrendSignal(loadedRgb.R, 3);
    R_detrended_builtin = detrend(loadedRgb.R, 3);

    matchExplicit = isequal(R_detrended_default, R_detrended_explicit);
    matchBuiltin = isequal(R_detrended_default, R_detrended_builtin);
    matchOrder = isequal(orderDefault, orderExplicit) && orderDefault == 3;

    subjectMatch = matchExplicit && matchBuiltin && matchOrder;
    allRegressionMatch = allRegressionMatch && subjectMatch;

    disp([subjectID ': default vs explicit-order-3 byte-identical = ' num2str(matchExplicit) ', default vs builtin detrend(R,3) byte-identical = ' num2str(matchBuiltin) ', detrendOrder reported = ' num2str(orderDefault)]);
end

disp(['Regression check across 3 subjects: all byte-identical = ' num2str(allRegressionMatch)]);

if ~allRegressionMatch
    error('Segment6TaskO:regressionFailed', 'detrendSignal default-argument call did not reproduce byte-identical output -- stopping before the sweep runs.');
end

disp('--- Part 2: detrend-order sweep (polyOrder = 2, 3, 4, 5) ---');

polyOrderList = [2, 3, 4, 5];

sweepMetricsPath = fullfile(metricsRoot, 'segment6_task_o_detrend_sweep_metrics.csv');
sweepMetricsHeaderLine = "polyOrder,method,MAE,RMSE,pearsonR,N";
writelines(sweepMetricsHeaderLine, sweepMetricsPath);

sweepDetailsPath = fullfile(metricsRoot, 'segment6_task_o_detrend_sweep_details.csv');
sweepDetailsHeaderLine = "polyOrder,subjectID,HR_chrom,HR_pos,HR_green,HR_groundtruth,abs_error_chrom,abs_error_pos,abs_error_green";
writelines(sweepDetailsHeaderLine, sweepDetailsPath);

for polyOrderPos = 1:numel(polyOrderList)
    polyOrder = polyOrderList(polyOrderPos);

    disp(['--- polyOrder = ' num2str(polyOrder) ' ---']);

    hrChromAll = [];
    hrPosAll = [];
    hrGreenAll = [];
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

            [R_detrended, ~] = detrendSignal(R, polyOrder);
            [G_detrended, ~] = detrendSignal(G, polyOrder);
            [B_detrended, ~] = detrendSignal(B, polyOrder);

            [R_filtered, ~] = bandpassClean(R_detrended, fs);
            [G_filtered, ~] = bandpassClean(G_detrended, fs);
            [B_filtered, ~] = bandpassClean(B_detrended, fs);

            pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
            pulseChromFiltered = bandpassClean(pulseChrom, fs);
            [HR_chrom, ~, ~] = fftHeartRate(pulseChromFiltered, fs);

            pulsePos = posCombine(R_filtered, G_filtered, B_filtered, fs, R, G, B);
            pulsePosFiltered = bandpassClean(pulsePos, fs);
            [HR_pos, ~, ~] = fftHeartRate(pulsePosFiltered, fs);

            [HR_green, ~, ~] = fftHeartRate(G_filtered, fs);

            absErrorChrom = abs(HR_chrom - HR_groundtruth);
            absErrorPos = abs(HR_pos - HR_groundtruth);
            absErrorGreen = abs(HR_green - HR_groundtruth);

            detailsRowParts = {num2str(polyOrder), subjectID, num2str(HR_chrom), num2str(HR_pos), num2str(HR_green), num2str(HR_groundtruth), num2str(absErrorChrom), num2str(absErrorPos), num2str(absErrorGreen)};
            detailsRowLine = strjoin(detailsRowParts, ',');
            writelines(detailsRowLine, sweepDetailsPath, 'WriteMode', 'append');

            hrChromAll(end + 1) = HR_chrom;
            hrPosAll(end + 1) = HR_pos;
            hrGreenAll(end + 1) = HR_green;
            groundtruthAll(end + 1) = HR_groundtruth;
        catch causeErr
            disp([subjectID ': FAILED at polyOrder ' num2str(polyOrder) ' -- ' causeErr.message]);
            failedSubjects{end + 1} = subjectID;
            failedReasons{end + 1} = causeErr.message;
        end
    end

    disp(['polyOrder ' num2str(polyOrder) ': subjects succeeded = ' num2str(numel(groundtruthAll)) ', failed = ' num2str(numel(failedSubjects))]);

    for failPos = 1:numel(failedSubjects)
        disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
    end

    chromMetrics = computeMetrics(hrChromAll, groundtruthAll);
    posMetrics = computeMetrics(hrPosAll, groundtruthAll);
    greenMetrics = computeMetrics(hrGreenAll, groundtruthAll);

    disp(['polyOrder ' num2str(polyOrder) ' CHROM: MAE = ' num2str(chromMetrics.mae) ', RMSE = ' num2str(chromMetrics.rmse) ', r = ' num2str(chromMetrics.pearsonR) ', N = ' num2str(chromMetrics.n)]);
    disp(['polyOrder ' num2str(polyOrder) ' POS: MAE = ' num2str(posMetrics.mae) ', RMSE = ' num2str(posMetrics.rmse) ', r = ' num2str(posMetrics.pearsonR) ', N = ' num2str(posMetrics.n)]);
    disp(['polyOrder ' num2str(polyOrder) ' Green: MAE = ' num2str(greenMetrics.mae) ', RMSE = ' num2str(greenMetrics.rmse) ', r = ' num2str(greenMetrics.pearsonR) ', N = ' num2str(greenMetrics.n)]);

    chromRowParts = {num2str(polyOrder), 'chrom', num2str(chromMetrics.mae), num2str(chromMetrics.rmse), num2str(chromMetrics.pearsonR), num2str(chromMetrics.n)};
    writelines(strjoin(chromRowParts, ','), sweepMetricsPath, 'WriteMode', 'append');

    posRowParts = {num2str(polyOrder), 'pos', num2str(posMetrics.mae), num2str(posMetrics.rmse), num2str(posMetrics.pearsonR), num2str(posMetrics.n)};
    writelines(strjoin(posRowParts, ','), sweepMetricsPath, 'WriteMode', 'append');

    greenRowParts = {num2str(polyOrder), 'green', num2str(greenMetrics.mae), num2str(greenMetrics.rmse), num2str(greenMetrics.pearsonR), num2str(greenMetrics.n)};
    writelines(strjoin(greenRowParts, ','), sweepMetricsPath, 'WriteMode', 'append');
end

disp('--- Segment 6 Task O, Action 1 sweep complete ---');
disp(['Saved ' sweepMetricsPath]);
disp(['Saved ' sweepDetailsPath]);
