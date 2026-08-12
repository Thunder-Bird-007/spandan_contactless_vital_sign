% RUN_SEGMENT5_FINAL_SPO2_REPORT Segment 5/6 finalization: produces the
% final SpO2 reporting artifacts for the report (Actions 1-3 of the SpO2
% finalization task). Does NOT modify calibrateSpO2.m, centerRPerDataset.m,
% runLOSO.m, or runLOSOStratified.m -- this script only calls those
% existing, unmodified functions and writes new output files.
%
% Standing decision, unchanged: SpO2 is NOT approved for Android display.
% This script is MATLAB-side reporting/documentation only.
%
% Outputs:
%   results/metrics/segment5_final_spo2_predictions.csv - per-subject
%     stratified (within-dataset-only) LOSO SpO2 predictions, the Task H3
%     result, for the full v1-only pool (UBFC N=5 + VIPL N=107 = 112).
%   Console output: the observed R/SpO2 range (overall and per dataset)
%     used to write the Action 3 caveat paragraph, and the production
%     calibration coefficients (A, B, per-dataset R offsets) used to
%     write the Action 2 spec doc.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

disp('=== Segment 5 Final SpO2 Report: loading pooled SpO2 subjects (same source CSVs as run_segment6_task_h.m) ===');

spo2SubjectID = {};
spo2Dataset = {};
spo2R = [];
spo2True = [];

spo2UbfcPath = fullfile(metricsRoot, 'segment5_dataset1_calibration.csv');

if isfile(spo2UbfcPath)
    ubfcSpo2Table = readtable(spo2UbfcPath);
    numRows = height(ubfcSpo2Table);

    for rowPos = 1:numRows
        spo2SubjectID{end + 1} = extractTextFinalSpo2(ubfcSpo2Table.subjectID, rowPos);
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
        spo2SubjectID{end + 1} = extractTextFinalSpo2(viplSpo2Table.subjectID, rowPos);
        spo2Dataset{end + 1} = extractTextFinalSpo2(viplSpo2Table.dataset, rowPos);
        spo2R(end + 1) = viplSpo2Table.R_value(rowPos);
        spo2True(end + 1) = viplSpo2Table.SpO2_true(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL SpO2 rows from ' spo2ViplPath]);
end

numSpo2Total = numel(spo2SubjectID);

disp(['Pooled SpO2 subjects available: ' num2str(numSpo2Total)]);

disp(' ');
disp('=== Action 3: observed R / SpO2 range in the 112-subject training pool ===');

overallRMin = min(spo2R);
overallRMax = max(spo2R);
overallSpo2Min = min(spo2True);
overallSpo2Max = max(spo2True);

disp(['Overall R range: [' num2str(overallRMin, 10) ', ' num2str(overallRMax, 10) ']']);
disp(['Overall SpO2 range: [' num2str(overallSpo2Min, 10) ', ' num2str(overallSpo2Max, 10) ']']);

datasetScopesRange = {'UBFC', 'VIPL'};

for scopePos = 1:numel(datasetScopesRange)
    scopeName = datasetScopesRange{scopePos};
    scopeMask = false(1, numSpo2Total);

    for i = 1:numSpo2Total
        if strcmp(spo2Dataset{i}, scopeName)
            scopeMask(i) = true;
        end
    end

    scopeR = spo2R(scopeMask);
    scopeSpo2 = spo2True(scopeMask);

    disp([scopeName ' R range: [' num2str(min(scopeR), 10) ', ' num2str(max(scopeR), 10) '], SpO2 range: [' num2str(min(scopeSpo2), 10) ', ' num2str(max(scopeSpo2), 10) ']']);
end

disp(' ');
disp('=== Action 1: stratified (within-dataset-only) LOSO SpO2 predictions, per subject (Task H3 method) ===');

stratifiedResults = runLOSOStratified(spo2SubjectID, spo2Dataset, spo2R, spo2True);

predictionsCsvPath = fullfile(metricsRoot, 'segment5_final_spo2_predictions.csv');
headerLine = "subjectID,dataset,SpO2_true,SpO2_predicted,R_value,abs_error,out_of_range_flag";
writelines(headerLine, predictionsCsvPath);

numOutOfRange = 0;

for i = 1:numSpo2Total
    subjID = stratifiedResults(i).subjectID;
    datasetName = stratifiedResults(i).dataset;
    trueVal = stratifiedResults(i).SpO2_true;
    predVal = stratifiedResults(i).SpO2_predicted;
    rVal = stratifiedResults(i).R_value;
    absErr = stratifiedResults(i).abs_error;

    outOfRange = 0;

    if rVal < overallRMin || rVal > overallRMax
        outOfRange = 1;
    end

    if outOfRange == 1
        numOutOfRange = numOutOfRange + 1;
    end

    predValStr = num2str(predVal, '%.1f');
    trueValStr = num2str(trueVal, '%.4f');
    rValStr = num2str(rVal, '%.5f');
    absErrStr = num2str(absErr, '%.4f');

    rowLine = strjoin({subjID, datasetName, trueValStr, predValStr, rValStr, absErrStr, num2str(outOfRange)}, ',');
    writelines(rowLine, predictionsCsvPath, 'WriteMode', 'append');
end

disp(['Saved ' predictionsCsvPath ' with ' num2str(numSpo2Total) ' subject rows.']);
disp(['Out-of-range subjects flagged (should be 0, same pool as the range itself): ' num2str(numOutOfRange)]);

disp(' ');
disp('=== Action 2: production calibration, fit on ALL 112 subjects at once (documentation only, NOT deployed) ===');

uniqueDatasetsProd = unique(spo2Dataset);
numDatasetsProd = numel(uniqueDatasetsProd);
datasetFullMean = zeros(1, numDatasetsProd);

for datasetPos = 1:numDatasetsProd
    thisDataset = uniqueDatasetsProd{datasetPos};
    sumR = 0;
    countR = 0;

    for i = 1:numSpo2Total
        if strcmp(spo2Dataset{i}, thisDataset)
            sumR = sumR + spo2R(i);
            countR = countR + 1;
        end
    end

    datasetFullMean(datasetPos) = sumR / countR;
    disp(['Dataset ' thisDataset ' full-pool mean R (N=' num2str(countR) '): ' num2str(datasetFullMean(datasetPos), 10)]);
end

spo2RCenteredProd = zeros(1, numSpo2Total);

for i = 1:numSpo2Total
    for datasetPos = 1:numDatasetsProd
        if strcmp(spo2Dataset{i}, uniqueDatasetsProd{datasetPos})
            spo2RCenteredProd(i) = spo2R(i) - datasetFullMean(datasetPos);
        end
    end
end

[~, prodCalibParams] = calibrateSpO2(spo2RCenteredProd, spo2True, []);

disp(['Production calibration (fit on all ' num2str(numSpo2Total) ' subjects, per-dataset-centered R): A = ' num2str(prodCalibParams.A, 10) ', B = ' num2str(prodCalibParams.B, 10)]);
disp('Formula: SpO2 = A - B * (R - datasetMeanR[dataset])');

disp(' ');
disp('--- Segment 5 Final SpO2 Report batch complete ---');

function textVal = extractTextFinalSpo2(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
