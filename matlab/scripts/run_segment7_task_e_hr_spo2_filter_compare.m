% RUN_SEGMENT7_TASK_E_HR_SPO2_FILTER_COMPARE Segment 7 Task E: classical-DSP
% A/B comparison of the filtering stage for BOTH HR and SpO2, on the SAME
% validated methodology and SAME pools already used for the currently
% reported numbers -- purely additive, no modification to any pipeline
% function.
%
% Does NOT modify (verified by SHA-256 before/after in the accompanying
% report): filtering/bandpassClean.m, filtering/detrendSignal.m,
% morphology/bandpassMorphology.m, morphology/adaptiveHarmonicFilter.m,
% pulseextraction/chromCombine.m, pulseextraction/posCombine.m,
% heartrate/fftHeartRate.m, spo2/ratioOfRatios.m, spo2/calibrateSpO2.m,
% validation/runLOSO.m, validation/runLOSOStratified.m,
% validation/computeMetrics.m, roi/extractROISignals.m. This script only
% calls those existing functions and writes new, separately-named output
% files.
%
% Does NOT re-decode any video and does NOT re-run roi/extractROISignals.m.
% It reuses the already-cached data/processed/<subjectID>_rgb_traces.mat
% files (that function's own unmodified output: raw R(t)/G(t)/B(t) + fs)
% for the exact same subject pool already used to produce the currently
% reported numbers, and reads ground truth from the already-computed
% results/metrics/segment4_hr_summary*.csv / segment5_vipl_calibration.csv
% files rather than re-invoking any ground-truth loader.
%
% Two filtering conditions, both computed from the SAME cached raw traces:
%   (a) baseline -- detrendSignal -> bandpassClean, EXACTLY the pipeline
%       already used by run_segment4_heartrate_batch.m /
%       run_vipl_integration_batch.m (including that pipeline's second
%       bandpassClean pass on the CHROM/POS-combined pulse, for HR).
%   (b) candidate -- detrendSignal -> adaptiveHarmonicFilter (6 harmonics),
%       per channel, pre-CHROM/POS, with f0 estimated once per subject from
%       a bandpassMorphology('wide') + chromCombine + fftHeartRate pulse and
%       shared across R/G/B. This is EXACTLY the "adaptiveHarmonic"
%       operating point already established and validated in
%       scripts/run_segment7_task_b_branch2_batch.m and
%       scripts/run_segment7_task_c2_true_combined_batch.m (Task C2's
%       corrected operating point) -- not a new invention for this script.
%
% HR scope: UBFC (N=5, the same 5 subjects in segment4_hr_summary.csv) +
% VIPL v1 (N=107, the same subjectTriples as run_vipl_integration_batch.m)
% = 112, pooled DIRECTLY via validation/computeMetrics.m -- NO
% validation/runLOSO.m anywhere in this HR path, matching
% run_segment6_validation.m's own header comment that HR (heartrate/
% fftHeartRate.m) has no fitted parameter and so needs no leave-one-out
% loop. Both CHROM and POS are evaluated for both conditions (condition
% (a)'s reported baseline, segment6_hr_pooled_metrics.csv, already reports
% both methods).
%
% SpO2 scope: VIPL v1 ONLY (N=107) -- NOT pooled with UBFC. This
% deliberately matches the actual scope of the currently reported SpO2 MAE
% 1.908 figure (matlab/docs/SpO2_Final_Report_Section.md's own "VIPL's
% N=107 stratified number... is the one worth citing" statement), via
% validation/runLOSOStratified.m, unmodified.
%
% Outputs:
%   results/metrics/segment7_task_e_hr_filter_comparison.csv
%   results/metrics/segment7_task_e_spo2_filter_comparison.csv
%   Console: explicit regression-check PASS/FAIL against the currently
%     reported baseline numbers for condition (a), for both HR and SpO2,
%     before condition (b) is trusted.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

disp('=== Segment 7 Task E: HR + SpO2 filtering A/B comparison ===');

%% === Load ground-truth lookups from already-computed CSVs (unmodified sources) ===

hrGtMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
spo2TrueMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

ubfcHrTable = readtable(fullfile(metricsRoot, 'segment4_hr_summary.csv'));
for i = 1:height(ubfcHrTable)
    sid = extractTextTaskE(ubfcHrTable.subjectID, i);
    hrGtMap(sid) = ubfcHrTable.HR_groundtruth(i);
end
disp(['Loaded ' num2str(height(ubfcHrTable)) ' UBFC HR ground-truth rows.']);

viplHrTable = readtable(fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv'));
for i = 1:height(viplHrTable)
    sid = extractTextTaskE(viplHrTable.subjectID, i);
    hrGtMap(sid) = viplHrTable.HR_groundtruth(i);
end
disp(['Loaded ' num2str(height(viplHrTable)) ' VIPL HR ground-truth rows.']);

viplSpo2Table = readtable(fullfile(metricsRoot, 'segment5_vipl_calibration.csv'));
for i = 1:height(viplSpo2Table)
    sid = extractTextTaskE(viplSpo2Table.subjectID, i);
    spo2TrueMap(sid) = viplSpo2Table.SpO2_true(i);
end
disp(['Loaded ' num2str(height(viplSpo2Table)) ' VIPL SpO2 ground-truth rows.']);

%% === Subject pool: UBFC (5) + VIPL v1 (107), identical to the existing pipeline ===

ubfcSubjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

% Identical subjectTriples to scripts/run_vipl_integration_batch.m, so the
% VIPL v1 subject pool here is exactly the one that produced
% segment4_hr_summary_vipl.csv / segment5_vipl_calibration.csv.
viplTriples = [
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

subjectID_all = {};
datasetLabel_all = {};

for i = 1:numel(ubfcSubjectList)
    subjectID_all{end + 1} = ubfcSubjectList{i}; %#ok<AGROW>
    datasetLabel_all{end + 1} = 'UBFC'; %#ok<AGROW>
end

for i = 1:size(viplTriples, 1)
    pNum = viplTriples(i, 1);
    vNum = viplTriples(i, 2);
    sNum = viplTriples(i, 3);
    subjectID_all{end + 1} = ['VIPL_p' num2str(pNum) '_v' num2str(vNum) '_source' num2str(sNum)]; %#ok<AGROW>
    datasetLabel_all{end + 1} = 'VIPL'; %#ok<AGROW>
end

numSubjects = numel(subjectID_all);
disp(['Subject pool: ' num2str(numSubjects) ' total (' num2str(numel(ubfcSubjectList)) ' UBFC + ' num2str(size(viplTriples, 1)) ' VIPL v1).']);

%% === Per-subject processing: both filtering conditions, CHROM+POS HR, R-value ===

HR_chrom_a = nan(1, numSubjects);
HR_pos_a = nan(1, numSubjects);
HR_chrom_b = nan(1, numSubjects);
HR_pos_b = nan(1, numSubjects);
Rval_a = nan(1, numSubjects);
Rval_b = nan(1, numSubjects);
HR_groundtruth_all = nan(1, numSubjects);
SpO2_true_all = nan(1, numSubjects);

failedSubjects = {};
failedReasons = {};

for k = 1:numSubjects
    sid = subjectID_all{k};

    disp(['--- Task E: subject ' sid ' (' num2str(k) ' of ' num2str(numSubjects) ') ---']);

    try
        rgbPath = fullfile(processedDataRoot, [sid '_rgb_traces.mat']);

        if ~isfile(rgbPath)
            error('run_segment7_task_e:missingInput', 'Cached raw traces not found: %s', rgbPath);
        end

        rgbData = load(rgbPath);
        R = rgbData.R;
        G = rgbData.G;
        B = rgbData.B;
        fs = rgbData.fs;

        % --- Shared detrend: identical input feeds both conditions ---
        [Rd, ~] = detrendSignal(R);
        [Gd, ~] = detrendSignal(G);
        [Bd, ~] = detrendSignal(B);

        % --- Condition (a): baseline, EXACTLY the existing HR/SpO2 pipeline ---
        [Ra, ~] = bandpassClean(Rd, fs);
        [Ga, ~] = bandpassClean(Gd, fs);
        [Ba, ~] = bandpassClean(Bd, fs);

        pulseChromA = chromCombine(Ra, Ga, Ba, R, G, B);
        pulseChromAFilt = bandpassClean(pulseChromA, fs);
        HR_chrom_a(k) = fftHeartRate(pulseChromAFilt, fs);

        pulsePosA = posCombine(Ra, Ga, Ba, fs, R, G, B);
        pulsePosAFilt = bandpassClean(pulsePosA, fs);
        HR_pos_a(k) = fftHeartRate(pulsePosAFilt, fs);

        Rval_a(k) = ratioOfRatios(Ra, Ga, Ba, R, G, B, fs);

        % --- Condition (b): candidate, Task C2's corrected operating point ---
        [Rw, ~, ~] = bandpassMorphology(Rd, fs, 'wide');
        [Gw, ~, ~] = bandpassMorphology(Gd, fs, 'wide');
        [Bw, ~, ~] = bandpassMorphology(Bd, fs, 'wide');
        pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
        sharedF0Hz = fftHeartRate(pulseWide, fs) / 60;

        [Rb, ~, ~] = adaptiveHarmonicFilter(Rd, fs, 6, sharedF0Hz);
        [Gb, ~, ~] = adaptiveHarmonicFilter(Gd, fs, 6, sharedF0Hz);
        [Bb, ~, ~] = adaptiveHarmonicFilter(Bd, fs, 6, sharedF0Hz);

        pulseChromB = chromCombine(Rb, Gb, Bb, R, G, B);
        HR_chrom_b(k) = fftHeartRate(pulseChromB, fs);

        pulsePosB = posCombine(Rb, Gb, Bb, fs, R, G, B);
        HR_pos_b(k) = fftHeartRate(pulsePosB, fs);

        Rval_b(k) = ratioOfRatios(Rb, Gb, Bb, R, G, B, fs);

        if isKey(hrGtMap, sid)
            HR_groundtruth_all(k) = hrGtMap(sid);
        end

        if isKey(spo2TrueMap, sid)
            SpO2_true_all(k) = spo2TrueMap(sid);
        end

        disp(['  HR_chrom: a=' num2str(HR_chrom_a(k)) ' b=' num2str(HR_chrom_b(k)) ' bpm | HR_pos: a=' num2str(HR_pos_a(k)) ' b=' num2str(HR_pos_b(k)) ' bpm | R: a=' num2str(Rval_a(k)) ' b=' num2str(Rval_b(k))]);
    catch causeErr
        disp(['Subject ' sid ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = sid; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp(' ');
disp(['Subjects attempted: ' num2str(numSubjects) ', failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

%% === HR metrics: pooled direct evaluation, NO LOSO, both conditions/methods/scopes ===

disp(' ');
disp('=== HR: pooled direct evaluation (computeMetrics.m, no LOSO) ===');

hrValidMask = ~isnan(HR_groundtruth_all) & ~isnan(HR_chrom_a) & ~isnan(HR_chrom_b);
disp(['HR usable rows (non-NaN ground truth and both conditions succeeded): ' num2str(sum(hrValidMask)) ' of ' num2str(numSubjects)]);

hrMethodNames = {'chrom', 'pos'};
hrConditionNames = {'a_bandpassClean', 'b_adaptiveHarmonicFilter'};
hrValuesByMethodCondition = {HR_chrom_a, HR_chrom_b; HR_pos_a, HR_pos_b};
hrDatasetScopes = {'UBFC', 'VIPL'};

hrCsvPath = fullfile(metricsRoot, 'segment7_task_e_hr_filter_comparison.csv');
hrHeaderLine = "method,filterCondition,scope,N,MAE,RMSE,Pearson_r";
writelines(hrHeaderLine, hrCsvPath);

hrMetricsStore = struct();

for methodPos = 1:numel(hrMethodNames)
    methodName = hrMethodNames{methodPos};

    for condPos = 1:numel(hrConditionNames)
        condName = hrConditionNames{condPos};
        methodValues = hrValuesByMethodCondition{methodPos, condPos};

        pooledPredicted = methodValues(hrValidMask);
        pooledGroundTruth = HR_groundtruth_all(hrValidMask);
        pooledMetrics = computeMetrics(pooledPredicted, pooledGroundTruth);

        rowLine = strjoin({methodName, condName, 'pooled', num2str(pooledMetrics.n), num2str(pooledMetrics.mae, 10), num2str(pooledMetrics.rmse, 10), num2str(pooledMetrics.pearsonR, 10)}, ',');
        writelines(rowLine, hrCsvPath, 'WriteMode', 'append');

        hrMetricsStore.(methodName).(condName).pooled = pooledMetrics;

        disp([methodName ' [' condName '] pooled: N=' num2str(pooledMetrics.n) ', MAE=' num2str(pooledMetrics.mae) ', RMSE=' num2str(pooledMetrics.rmse) ', r=' num2str(pooledMetrics.pearsonR)]);

        for scopePos = 1:numel(hrDatasetScopes)
            scopeName = hrDatasetScopes{scopePos};
            scopeMask = hrValidMask & strcmp(datasetLabel_all, scopeName);

            scopePredicted = methodValues(scopeMask);
            scopeGroundTruth = HR_groundtruth_all(scopeMask);
            scopeMetrics = computeMetrics(scopePredicted, scopeGroundTruth);

            rowLine = strjoin({methodName, condName, scopeName, num2str(scopeMetrics.n), num2str(scopeMetrics.mae, 10), num2str(scopeMetrics.rmse, 10), num2str(scopeMetrics.pearsonR, 10)}, ',');
            writelines(rowLine, hrCsvPath, 'WriteMode', 'append');

            hrMetricsStore.(methodName).(condName).(scopeName) = scopeMetrics;

            disp(['  ' methodName ' [' condName '] ' scopeName ': N=' num2str(scopeMetrics.n) ', MAE=' num2str(scopeMetrics.mae) ', RMSE=' num2str(scopeMetrics.rmse) ', r=' num2str(scopeMetrics.pearsonR)]);
        end
    end
end

disp(['Saved ' hrCsvPath]);

%% === HR regression check: condition (a) must match segment6_hr_pooled_metrics.csv ===

disp(' ');
disp('=== HR regression check: condition (a) vs currently reported full-pool (N=112) numbers ===');

expectedChromMAE = 9.0969; expectedChromRMSE = 18.0047; expectedChromR = 0.31448;
expectedPosMAE = 8.6795; expectedPosRMSE = 16.4537; expectedPosR = 0.28091;
tol = 0.01;

chromA = hrMetricsStore.chrom.a_bandpassClean.pooled;
posA = hrMetricsStore.pos.a_bandpassClean.pooled;

chromPass = abs(chromA.mae - expectedChromMAE) < tol && abs(chromA.rmse - expectedChromRMSE) < tol && abs(chromA.pearsonR - expectedChromR) < tol;
posPass = abs(posA.mae - expectedPosMAE) < tol && abs(posA.rmse - expectedPosRMSE) < tol && abs(posA.pearsonR - expectedPosR) < tol;

disp(['CHROM condition (a) pooled: computed MAE=' num2str(chromA.mae) '/RMSE=' num2str(chromA.rmse) '/r=' num2str(chromA.pearsonR) ' vs expected MAE=' num2str(expectedChromMAE) '/RMSE=' num2str(expectedChromRMSE) '/r=' num2str(expectedChromR)]);
if chromPass
    disp('CHROM condition (a): REGRESSION CHECK PASSED.');
else
    disp('CHROM condition (a): REGRESSION CHECK FAILED -- STOP, do not trust condition (b) comparison below.');
end

disp(['POS condition (a) pooled: computed MAE=' num2str(posA.mae) '/RMSE=' num2str(posA.rmse) '/r=' num2str(posA.pearsonR) ' vs expected MAE=' num2str(expectedPosMAE) '/RMSE=' num2str(expectedPosRMSE) '/r=' num2str(expectedPosR)]);
if posPass
    disp('POS condition (a): REGRESSION CHECK PASSED.');
else
    disp('POS condition (a): REGRESSION CHECK FAILED -- STOP, do not trust condition (b) comparison below.');
end

%% === SpO2: VIPL-only (N=107), stratified LOSO, both conditions ===

disp(' ');
disp('=== SpO2: VIPL v1 only (N=107), runLOSOStratified.m, both conditions ===');

spo2ValidMask = strcmp(datasetLabel_all, 'VIPL') & ~isnan(SpO2_true_all) & ~isnan(Rval_a) & ~isnan(Rval_b);
disp(['SpO2 usable VIPL rows (both conditions succeeded): ' num2str(sum(spo2ValidMask)) ' of ' num2str(sum(strcmp(datasetLabel_all, 'VIPL')))]);

spo2SubjectIDsVipl = subjectID_all(spo2ValidMask);
spo2DatasetVipl = datasetLabel_all(spo2ValidMask);
spo2TrueVipl = SpO2_true_all(spo2ValidMask);
Rval_a_vipl = Rval_a(spo2ValidMask);
Rval_b_vipl = Rval_b(spo2ValidMask);

spo2CsvPath = fullfile(metricsRoot, 'segment7_task_e_spo2_filter_comparison.csv');
spo2HeaderLine = "filterCondition,scope,N,MAE,RMSE,Pearson_r";
writelines(spo2HeaderLine, spo2CsvPath);

spo2ResultsA = runLOSOStratified(spo2SubjectIDsVipl, spo2DatasetVipl, Rval_a_vipl, spo2TrueVipl);
spo2PredictedA = [spo2ResultsA.SpO2_predicted];
spo2MetricsA = computeMetrics(spo2PredictedA, spo2TrueVipl);
rowLine = strjoin({'a_bandpassClean', 'VIPL', num2str(spo2MetricsA.n), num2str(spo2MetricsA.mae, 10), num2str(spo2MetricsA.rmse, 10), num2str(spo2MetricsA.pearsonR, 10)}, ',');
writelines(rowLine, spo2CsvPath, 'WriteMode', 'append');
disp(['SpO2 condition (a) VIPL: N=' num2str(spo2MetricsA.n) ', MAE=' num2str(spo2MetricsA.mae) ', RMSE=' num2str(spo2MetricsA.rmse) ', r=' num2str(spo2MetricsA.pearsonR)]);

spo2ResultsB = runLOSOStratified(spo2SubjectIDsVipl, spo2DatasetVipl, Rval_b_vipl, spo2TrueVipl);
spo2PredictedB = [spo2ResultsB.SpO2_predicted];
spo2MetricsB = computeMetrics(spo2PredictedB, spo2TrueVipl);
rowLine = strjoin({'b_adaptiveHarmonicFilter', 'VIPL', num2str(spo2MetricsB.n), num2str(spo2MetricsB.mae, 10), num2str(spo2MetricsB.rmse, 10), num2str(spo2MetricsB.pearsonR, 10)}, ',');
writelines(rowLine, spo2CsvPath, 'WriteMode', 'append');
disp(['SpO2 condition (b) VIPL: N=' num2str(spo2MetricsB.n) ', MAE=' num2str(spo2MetricsB.mae) ', RMSE=' num2str(spo2MetricsB.rmse) ', r=' num2str(spo2MetricsB.pearsonR)]);

disp(['Saved ' spo2CsvPath]);

%% === SpO2 regression check: condition (a) must match SpO2_Final_Report_Section.md's VIPL N=107 number ===

disp(' ');
disp('=== SpO2 regression check: condition (a) vs currently reported VIPL N=107 number ===');

expectedSpo2MAE = 1.9078; expectedSpo2RMSE = 5.4303; expectedSpo2R = -0.3333;
spo2Tol = 0.01;

spo2Pass = abs(spo2MetricsA.mae - expectedSpo2MAE) < spo2Tol && abs(spo2MetricsA.rmse - expectedSpo2RMSE) < spo2Tol && abs(spo2MetricsA.pearsonR - expectedSpo2R) < spo2Tol;

disp(['SpO2 condition (a) VIPL: computed MAE=' num2str(spo2MetricsA.mae) '/RMSE=' num2str(spo2MetricsA.rmse) '/r=' num2str(spo2MetricsA.pearsonR) ' vs expected MAE=' num2str(expectedSpo2MAE) '/RMSE=' num2str(expectedSpo2RMSE) '/r=' num2str(expectedSpo2R)]);
if spo2Pass
    disp('SpO2 condition (a): REGRESSION CHECK PASSED.');
else
    disp('SpO2 condition (a): REGRESSION CHECK FAILED -- STOP, do not trust condition (b) comparison above.');
end

disp(' ');
disp('--- Segment 7 Task E batch complete ---');

function textVal = extractTextTaskE(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
