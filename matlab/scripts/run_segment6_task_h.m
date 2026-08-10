% RUN_SEGMENT6_TASK_H Segment 6 "Task H" driver: p25 with/without SpO2
% comparison and the stratified (within-dataset-only) SpO2 LOSO check.
%
% This script does NOT reprocess any video or raw trace, and does NOT
% modify validation/runLOSO.m, validation/centerRPerDataset.m,
% validation/computeMetrics.m, validation/blandAltman.m, or
% scripts/run_segment6_validation.m. It only reads the same already-
% computed Segment 5 SpO2 CSVs those files read
% (results/metrics/segment5_dataset1_calibration.csv and
% results/metrics/segment5_vipl_calibration.csv), calls the existing
% unmodified runLOSO.m/computeMetrics.m and the new
% validation/runLOSOStratified.m, and writes new, separate output CSVs.
%
% Outputs:
%   results/metrics/segment6_spo2_with_p25.csv    - raw/baseline/centered
%     pooled+UBFC+VIPL metrics, p25 INCLUDED (current/unchanged pool).
%   results/metrics/segment6_spo2_excluding_p25.csv - same shape, p25
%     EXCLUDED from the pool before re-running LOSO.
%   results/metrics/segment6_spo2_stratified_metrics.csv - per-dataset
%     metrics from runLOSOStratified.m (within-dataset-only training).
%
% See Segment6_Refinement_Notes.md Task H for the p25 exclusion
% justification and the stratified-vs-pooled reading.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

disp('=== Segment 6 Task H: loading pooled SpO2 subjects (same source CSVs as run_segment6_validation.m) ===');

spo2SubjectID = {};
spo2Dataset = {};
spo2R = [];
spo2True = [];

spo2UbfcPath = fullfile(metricsRoot, 'segment5_dataset1_calibration.csv');

if isfile(spo2UbfcPath)
    ubfcSpo2Table = readtable(spo2UbfcPath);
    numRows = height(ubfcSpo2Table);

    for rowPos = 1:numRows
        spo2SubjectID{end + 1} = extractTextTaskH(ubfcSpo2Table.subjectID, rowPos);
        spo2Dataset{end + 1} = 'UBFC';
        spo2R(end + 1) = ubfcSpo2Table.R_value(rowPos);
        spo2True(end + 1) = ubfcSpo2Table.SpO2_true(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' UBFC SpO2 rows from ' spo2UbfcPath]);
end

spo2ViplPath = fullfile(metricsRoot, 'segment5_vipl_calibration.csv');

if isfile(spo2ViplPath)
    viplSpo2Table = readtable(spo2ViplPath);
    numRows = height(viplSpo2Table);

    for rowPos = 1:numRows
        spo2SubjectID{end + 1} = extractTextTaskH(viplSpo2Table.subjectID, rowPos);
        spo2Dataset{end + 1} = extractTextTaskH(viplSpo2Table.dataset, rowPos);
        spo2R(end + 1) = viplSpo2Table.R_value(rowPos);
        spo2True(end + 1) = viplSpo2Table.SpO2_true(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL SpO2 rows from ' spo2ViplPath]);
end

numSpo2Total = numel(spo2SubjectID);

disp(['Pooled SpO2 subjects available: ' num2str(numSpo2Total)]);

disp(' ');
disp('=== Part 1: pooled metrics WITH p25 included (current pool, unchanged) ===');

withP25ResultsLoso = runLOSO(spo2SubjectID, spo2Dataset, spo2R, spo2True);
writeThreeWayMetricsCsvTaskH(fullfile(metricsRoot, 'segment6_spo2_with_p25.csv'), withP25ResultsLoso);

disp(' ');
disp('=== Part 2: pooled metrics WITH p25 EXCLUDED ===');

excludeMask = true(1, numSpo2Total);

for i = 1:numSpo2Total
    if strcmp(spo2SubjectID{i}, 'VIPL_p25_v1_source1')
        excludeMask(i) = false;
    end
end

numExcluded = numSpo2Total - sum(excludeMask);

disp(['Subjects excluded: ' num2str(numExcluded) ' (expected 1, VIPL_p25_v1_source1).']);

spo2SubjectIDExcl = spo2SubjectID(excludeMask);
spo2DatasetExcl = spo2Dataset(excludeMask);
spo2RExcl = spo2R(excludeMask);
spo2TrueExcl = spo2True(excludeMask);

excludingP25ResultsLoso = runLOSO(spo2SubjectIDExcl, spo2DatasetExcl, spo2RExcl, spo2TrueExcl);
writeThreeWayMetricsCsvTaskH(fullfile(metricsRoot, 'segment6_spo2_excluding_p25.csv'), excludingP25ResultsLoso);

disp(' ');
disp('=== Part 3: stratified (within-dataset-only) SpO2 LOSO, full pool including p25 ===');

stratifiedResults = runLOSOStratified(spo2SubjectID, spo2Dataset, spo2R, spo2True);

stratifiedPredicted = zeros(1, numSpo2Total);
stratifiedTrue = zeros(1, numSpo2Total);
stratifiedDatasetAll = cell(1, numSpo2Total);

for i = 1:numSpo2Total
    stratifiedPredicted(i) = stratifiedResults(i).SpO2_predicted;
    stratifiedTrue(i) = stratifiedResults(i).SpO2_true;
    stratifiedDatasetAll{i} = stratifiedResults(i).dataset;
end

stratifiedCsvPath = fullfile(metricsRoot, 'segment6_spo2_stratified_metrics.csv');
stratifiedHeaderLine = "scope,N,MAE,RMSE,Pearson_r,reliability_note";
writelines(stratifiedHeaderLine, stratifiedCsvPath);

stratifiedDatasetScopes = {'UBFC', 'VIPL'};
stratifiedReliabilityNotes = {'THIN: N=5, trains on only 4 subjects per fold -- directional signal only, not a reliable number', 'thin-data-safe: N=107, trains on ~106 subjects per fold'};

for scopePos = 1:numel(stratifiedDatasetScopes)
    scopeName = stratifiedDatasetScopes{scopePos};
    scopeMask = false(1, numSpo2Total);

    for i = 1:numSpo2Total
        if strcmp(stratifiedDatasetAll{i}, scopeName)
            scopeMask(i) = true;
        end
    end

    scopePredicted = stratifiedPredicted(scopeMask);
    scopeTrue = stratifiedTrue(scopeMask);
    scopeMetrics = computeMetrics(scopePredicted, scopeTrue);

    rowParts = {scopeName, num2str(scopeMetrics.n), num2str(scopeMetrics.mae), num2str(scopeMetrics.rmse), num2str(scopeMetrics.pearsonR), stratifiedReliabilityNotes{scopePos}};
    rowLine = strjoin(rowParts, ',');
    writelines(rowLine, stratifiedCsvPath, 'WriteMode', 'append');

    disp([scopeName ' stratified: N=' num2str(scopeMetrics.n) ', MAE=' num2str(scopeMetrics.mae) ', RMSE=' num2str(scopeMetrics.rmse) ', Pearson r=' num2str(scopeMetrics.pearsonR)]);
end

disp(['Saved ' stratifiedCsvPath]);

disp(' ');
disp('--- Segment 6 Task H batch complete ---');

function textVal = extractTextTaskH(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end

function writeThreeWayMetricsCsvTaskH(csvPath, losoResults)

numResults = numel(losoResults);

predictedRaw = zeros(1, numResults);
predictedBaseline = zeros(1, numResults);
predictedCentered = zeros(1, numResults);
trueVals = zeros(1, numResults);
datasetVals = cell(1, numResults);

for i = 1:numResults
    predictedRaw(i) = losoResults(i).SpO2_predicted;
    predictedBaseline(i) = losoResults(i).SpO2_predicted_baseline;
    predictedCentered(i) = losoResults(i).SpO2_predicted_centered;
    trueVals(i) = losoResults(i).SpO2_true;
    datasetVals{i} = losoResults(i).dataset;
end

headerLine = "metric_type,scope,N,MAE,RMSE,Pearson_r";
writelines(headerLine, csvPath);

metricTypeNames = {'raw', 'baseline', 'centered'};
metricTypeValues = {predictedRaw, predictedBaseline, predictedCentered};

datasetScopes = {'UBFC', 'VIPL'};

for typePos = 1:numel(metricTypeNames)
    typeName = metricTypeNames{typePos};
    typeValues = metricTypeValues{typePos};

    pooledMetrics = computeMetrics(typeValues, trueVals);
    rowLine = strjoin({typeName, 'pooled', num2str(pooledMetrics.n), num2str(pooledMetrics.mae), num2str(pooledMetrics.rmse), num2str(pooledMetrics.pearsonR)}, ',');
    writelines(rowLine, csvPath, 'WriteMode', 'append');

    for scopePos = 1:numel(datasetScopes)
        scopeName = datasetScopes{scopePos};
        scopeMask = false(1, numResults);

        for i = 1:numResults
            if strcmp(datasetVals{i}, scopeName)
                scopeMask(i) = true;
            end
        end

        scopePredicted = typeValues(scopeMask);
        scopeTrue = trueVals(scopeMask);
        scopeMetrics = computeMetrics(scopePredicted, scopeTrue);

        rowLine = strjoin({typeName, scopeName, num2str(scopeMetrics.n), num2str(scopeMetrics.mae), num2str(scopeMetrics.rmse), num2str(scopeMetrics.pearsonR)}, ',');
        writelines(rowLine, csvPath, 'WriteMode', 'append');
    end
end

disp(['Saved ' csvPath]);

end
