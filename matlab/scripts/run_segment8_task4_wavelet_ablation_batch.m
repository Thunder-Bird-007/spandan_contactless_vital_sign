% RUN_SEGMENT8_TASK4_WAVELET_ABLATION_BATCH Segment 8 (post-review
% follow-up), Action 4. Ablation: filtering/waveletDenoise.m (DWT
% wavelet-shrinkage, Debnath & Kim, PLOS ONE 2026, 21(1):e0340097) as an
% ADDITIVE optional pre-step ahead of filtering/detrendSignal.m +
% filtering/bandpassClean.m in Branch 1, on the FULL 112-subject pool (5
% UBFC-D1 + 107 VIPL) already validated in
% results/metrics/segment6_hr_pooled_metrics.csv.
%
% "WITHOUT wavelet" values are NOT recomputed -- they are read directly
% from the already-validated results/metrics/segment4_hr_summary.csv and
% segment4_hr_summary_vipl.csv (the exact same numbers
% segment6_hr_pooled_metrics.csv was built from), matched by subjectID.
% "WITH wavelet" values ARE freshly computed here: same ROI decode (fresh
% VideoReader, extractROISignals), with waveletDenoise.m inserted on each
% raw R/G/B channel BEFORE detrendSignal.m + bandpassClean.m -- everything
% else in the chain (detrendSignal, bandpassClean, chromCombine, posCombine,
% fftHeartRate) is called completely unmodified, at the exact same
% parameters as run_segment4_heartrate_batch.m / run_vipl_integration_batch.m.
%
% Does NOT modify filtering/detrendSignal.m, filtering/bandpassClean.m,
% pulseextraction/chromCombine.m, pulseextraction/posCombine.m,
% heartrate/fftHeartRate.m, or filtering/waveletDenoise.m -- new,
% additive script only.
%
% Output: results/metrics/segment8_task4_wavelet_ablation.csv

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
ubfcD1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

ubfcBaselinePath = fullfile(metricsRoot, 'segment4_hr_summary.csv');
viplBaselinePath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');
ubfcBaselineTable = readtable(ubfcBaselinePath, 'TextType', 'string');
viplBaselineTable = readtable(viplBaselinePath, 'TextType', 'string');

outCsvPath = fullfile(metricsRoot, 'segment8_task4_wavelet_ablation.csv');
headerLine = "subjectID,dataset,HR_groundtruth,HR_chrom_nowavelet,HR_chrom_wavelet,HR_pos_nowavelet,HR_pos_wavelet,abs_err_chrom_nowavelet,abs_err_chrom_wavelet,abs_err_pos_nowavelet,abs_err_pos_wavelet";

% RESUME SUPPORT: if a prior run was interrupted (e.g. killed under
% memory pressure), don't reprocess subjects already saved -- read
% whichever subjectIDs already have a row and skip them below.
alreadyDoneIds = {};
if isfile(outCsvPath)
    existingTable = readtable(outCsvPath, 'TextType', 'string');
    if height(existingTable) > 0
        alreadyDoneIds = cellstr(existingTable.subjectID);
    end
    fprintf('Resuming: %d subjects already in %s, will be skipped.\n', numel(alreadyDoneIds), outCsvPath);
else
    writelines(headerLine, outCsvPath);
end

% --- Subject list: same 5 UBFC-D1 + same 107 VIPL (subjectNum, scenarioNum,
% sourceNum) triples as run_vipl_integration_batch.m, for a subject-for-
% subject match against the baseline CSVs. ---
ubfcSubjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

viplSubjectTriples = [1,1,1;2,1,1;3,1,1;4,1,1;5,1,1;6,1,1;7,1,1;8,1,1;9,1,1;10,1,1;
    11,1,1;12,1,1;13,1,1;14,1,1;15,1,1;16,1,1;17,1,1;18,1,1;19,1,1;20,1,1;
    21,1,1;22,1,1;23,1,1;24,1,1;25,1,1;26,1,1;27,1,1;28,1,1;29,1,1;30,1,1;
    31,1,1;32,1,1;33,1,1;34,1,1;35,1,1;36,1,1;37,1,1;38,1,1;39,1,1;40,1,1;
    41,1,1;42,1,1;43,1,1;44,1,1;45,1,1;46,1,1;47,1,1;48,1,1;49,1,1;50,1,1;
    51,1,1;52,1,1;53,1,1;54,1,1;55,1,1;56,1,1;57,1,1;58,1,1;59,1,1;60,1,1;
    61,1,1;62,1,1;63,1,1;64,1,1;65,1,1;66,1,1;67,1,1;68,1,1;69,1,1;70,1,1;
    71,1,1;72,1,1;73,1,1;74,1,1;75,1,1;76,1,1;77,1,1;78,1,1;79,1,1;80,1,1;
    81,1,1;82,1,1;83,1,1;84,1,2;85,1,1;86,1,1;87,1,1;88,1,1;89,1,1;90,1,1;
    91,1,1;92,1,1;93,1,1;94,1,1;95,1,1;96,1,1;97,1,2;98,1,2;99,1,2;100,1,2;
    101,1,2;102,1,2;103,1,2;104,1,2;105,1,2;106,1,2;107,1,2];

failedSubjects = {};

function baselineRow = findBaselineRow(subjectID, ubfcTable, viplTable)
row = ubfcTable(ubfcTable.subjectID == subjectID, :);
if height(row) == 1
    baselineRow = row;
    return
end
row = viplTable(viplTable.subjectID == subjectID, :);
if height(row) == 1
    baselineRow = row;
    return
end
baselineRow = [];
end

processedCount = 0;

% --- UBFC-D1 subjects ---
for k = 1:numel(ubfcSubjectList)
    subjectID = ubfcSubjectList{k};

    if any(strcmp(alreadyDoneIds, subjectID))
        continue
    end

    subjDir = fullfile(ubfcD1Root, subjectID);
    aviFiles = dir(fullfile(subjDir, '*.avi'));

    fprintf('--- Task 4 wavelet ablation: %s (UBFC) ---\n', subjectID);
    tSubj = tic;

    try
        videoPath = fullfile(subjDir, aviFiles(1).name);
        [frames, fs, ~] = loadUBFCVideo(videoPath);
        [R, G, B, ~, ~, ~] = extractROISignals(frames, fs);

        R_wd = waveletDenoise(R);
        G_wd = waveletDenoise(G);
        B_wd = waveletDenoise(B);

        [Rd, ~] = detrendSignal(R_wd); [Gd, ~] = detrendSignal(G_wd); [Bd, ~] = detrendSignal(B_wd);
        [Rf, ~] = bandpassClean(Rd, fs); [Gf, ~] = bandpassClean(Gd, fs); [Bf, ~] = bandpassClean(Bd, fs);

        pulseChrom = chromCombine(Rf, Gf, Bf, R_wd, G_wd, B_wd);
        pulseChromF = bandpassClean(pulseChrom, fs);
        HR_chrom_wavelet = fftHeartRate(pulseChromF, fs);

        pulsePos = posCombine(Rf, Gf, Bf, fs, R_wd, G_wd, B_wd);
        pulsePosF = bandpassClean(pulsePos, fs);
        HR_pos_wavelet = fftHeartRate(pulsePosF, fs);

        baselineRow = findBaselineRow(subjectID, ubfcBaselineTable, viplBaselineTable);
        if isempty(baselineRow)
            error('run_segment8_task4_wavelet_ablation_batch:noBaseline', 'No baseline row for %s', subjectID);
        end
        HR_chrom_nowavelet = baselineRow.HR_chrom(1);
        HR_pos_nowavelet = baselineRow.HR_pos(1);
        HR_groundtruth = baselineRow.HR_groundtruth(1);

        absErrChromNo = abs(HR_chrom_nowavelet - HR_groundtruth);
        absErrChromW = abs(HR_chrom_wavelet - HR_groundtruth);
        absErrPosNo = abs(HR_pos_nowavelet - HR_groundtruth);
        absErrPosW = abs(HR_pos_wavelet - HR_groundtruth);

        fprintf('%s: GT=%.2f chrom_no=%.2f chrom_w=%.2f pos_no=%.2f pos_w=%.2f (%.0fs)\n', subjectID, HR_groundtruth, HR_chrom_nowavelet, HR_chrom_wavelet, HR_pos_nowavelet, HR_pos_wavelet, toc(tSubj));

        row = {subjectID, 'UBFC', num2str(HR_groundtruth, '%.4f'), num2str(HR_chrom_nowavelet, '%.4f'), num2str(HR_chrom_wavelet, '%.4f'), ...
            num2str(HR_pos_nowavelet, '%.4f'), num2str(HR_pos_wavelet, '%.4f'), num2str(absErrChromNo, '%.4f'), num2str(absErrChromW, '%.4f'), ...
            num2str(absErrPosNo, '%.4f'), num2str(absErrPosW, '%.4f')};
        writelines(strjoin(row, ','), outCsvPath, 'WriteMode', 'append');
        processedCount = processedCount + 1;
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
    end
end

% --- VIPL subjects ---
for k = 1:size(viplSubjectTriples, 1)
    subjectNum = viplSubjectTriples(k, 1);
    scenarioNum = viplSubjectTriples(k, 2);
    sourceNum = viplSubjectTriples(k, 3);
    subjectID = ['VIPL_p' num2str(subjectNum) '_v' num2str(scenarioNum) '_source' num2str(sourceNum)];

    if any(strcmp(alreadyDoneIds, subjectID))
        continue
    end

    fprintf('--- Task 4 wavelet ablation: %s (%d/%d, VIPL) ---\n', subjectID, k, size(viplSubjectTriples, 1));
    tSubj = tic;

    try
        [frames, fs, ~, ~] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum);
        [R, G, B, ~, ~, ~] = extractROISignals(frames, fs);

        R_wd = waveletDenoise(R);
        G_wd = waveletDenoise(G);
        B_wd = waveletDenoise(B);

        [Rd, ~] = detrendSignal(R_wd); [Gd, ~] = detrendSignal(G_wd); [Bd, ~] = detrendSignal(B_wd);
        [Rf, ~] = bandpassClean(Rd, fs); [Gf, ~] = bandpassClean(Gd, fs); [Bf, ~] = bandpassClean(Bd, fs);

        pulseChrom = chromCombine(Rf, Gf, Bf, R_wd, G_wd, B_wd);
        pulseChromF = bandpassClean(pulseChrom, fs);
        HR_chrom_wavelet = fftHeartRate(pulseChromF, fs);

        pulsePos = posCombine(Rf, Gf, Bf, fs, R_wd, G_wd, B_wd);
        pulsePosF = bandpassClean(pulsePos, fs);
        HR_pos_wavelet = fftHeartRate(pulsePosF, fs);

        baselineRow = findBaselineRow(subjectID, ubfcBaselineTable, viplBaselineTable);
        if isempty(baselineRow)
            error('run_segment8_task4_wavelet_ablation_batch:noBaseline', 'No baseline row for %s', subjectID);
        end
        HR_chrom_nowavelet = baselineRow.HR_chrom(1);
        HR_pos_nowavelet = baselineRow.HR_pos(1);
        HR_groundtruth = baselineRow.HR_groundtruth(1);

        absErrChromNo = abs(HR_chrom_nowavelet - HR_groundtruth);
        absErrChromW = abs(HR_chrom_wavelet - HR_groundtruth);
        absErrPosNo = abs(HR_pos_nowavelet - HR_groundtruth);
        absErrPosW = abs(HR_pos_wavelet - HR_groundtruth);

        fprintf('%s: GT=%.2f chrom_no=%.2f chrom_w=%.2f pos_no=%.2f pos_w=%.2f (%.0fs)\n', subjectID, HR_groundtruth, HR_chrom_nowavelet, HR_chrom_wavelet, HR_pos_nowavelet, HR_pos_wavelet, toc(tSubj));

        row = {subjectID, 'VIPL', num2str(HR_groundtruth, '%.4f'), num2str(HR_chrom_nowavelet, '%.4f'), num2str(HR_chrom_wavelet, '%.4f'), ...
            num2str(HR_pos_nowavelet, '%.4f'), num2str(HR_pos_wavelet, '%.4f'), num2str(absErrChromNo, '%.4f'), num2str(absErrChromW, '%.4f'), ...
            num2str(absErrPosNo, '%.4f'), num2str(absErrPosW, '%.4f')};
        writelines(strjoin(row, ','), outCsvPath, 'WriteMode', 'append');
        processedCount = processedCount + 1;
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
    end
end

disp(' ');
disp(['--- Segment 8 Task 4 wavelet ablation complete: ' num2str(processedCount) ' subjects processed, ' num2str(numel(failedSubjects)) ' failed ---']);
for k = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{k}]);
end
disp(['Saved ' outCsvPath]);
