% RUN_SEGMENT6_VALIDATION Segment 6 batch driver: pools the ALREADY-
% COMPUTED per-subject results sitting in Segment 4's HR CSVs and
% Segment 5's SpO2 CSVs (UBFC + VIPL siblings), and produces this
% project's first formal validation numbers -- MAE, RMSE, Pearson
% correlation, and Bland-Altman plots -- across every subject currently
% available.
%
% This script does NOT reprocess any video or raw trace. It only reads
% results/metrics/segment4_hr_summary.csv, segment4_hr_summary_vipl.csv,
% segment5_dataset1_calibration.csv, and segment5_vipl_calibration.csv,
% whichever of the four currently exist -- so re-running this later, once
% more VIPL subjects have been extracted and processed, picks up the
% larger pool automatically with no code changes needed.
%
% SpO2 and HR are deliberately evaluated differently, for a real reason
% (see Segment6_LineByLine_Explanation.md for the full argument):
%   - SpO2's spo2/calibrateSpO2.m has a FITTED parameter (A, B). Pooling
%     UBFC + VIPL and evaluating directly, without holding subjects out,
%     would let a subject's own (R, SpO2) pair participate in fitting the
%     very line used to predict it -- textbook leakage. So SpO2 gets a
%     genuine leave-one-subject-out refit via validation/runLOSO.m, with
%     every fold's training set pooled across BOTH datasets.
%   - HR's heartrate/fftHeartRate.m has no fitted parameter at all -- it
%     is a direct FFT peak read, with nothing that could leak from one
%     subject to another. So HR is pooled and evaluated directly with
%     validation/computeMetrics.m, no leave-one-out loop needed or
%     appropriate.
%
% Outputs:
%   results/metrics/segment6_hr_pooled_metrics.csv
%   results/metrics/segment6_spo2_loso_pooled.csv (now also carries
%     SpO2_predicted_baseline / abs_error_baseline columns -- see below)
%   results/metrics/segment6_spo2_loso_metrics.csv
%   results/metrics/segment6_spo2_loso_baseline_metrics.csv (trivial
%     training-mean-only baseline, same MAE/RMSE/Pearson_r shape as the
%     real metrics CSV above, for direct side-by-side comparison)
%   results/metrics/segment6_spo2_loso_centered_metrics.csv (new --
%     per-dataset R-centered calibration, via validation/
%     centerRPerDataset.m, same MAE/RMSE/Pearson_r shape, for direct
%     three-way comparison against the raw pooled calibration and the
%     trivial baseline above)
%   results/figures/segment6_hr_bland_altman_chrom.png
%   results/figures/segment6_hr_bland_altman_pos.png
%   results/figures/segment6_hr_bland_altman_green.png
%   results/figures/segment6_spo2_bland_altman_pooled.png
%   results/figures/segment6_spo2_predicted_vs_true.png
%   results/figures/segment6_R_vs_SpO2_by_dataset.png (new -- raw R vs
%     true SpO2, colored by dataset, BEFORE calibration is applied; a
%     diagnostic for whether UBFC and VIPL show a cross-device R offset)
%
% Also added: a trivial per-fold SpO2 baseline (mean SpO2 of that fold's
% training subjects, R ignored entirely) computed alongside the real
% calibrated LOSO prediction via validation/runLOSO.m's new
% SpO2_predicted_baseline / abs_error_baseline fields, so the real
% calibration's benefit over "just guess the training mean" can be judged
% directly rather than assumed. See Segment6_Refinement_Notes.md.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

disp('=== Segment 6 Validation: HR (pooled, direct evaluation) ===');

hrSubjectID = {};
hrDataset = {};
hrChrom = [];
hrPos = [];
hrGreen = [];
hrGroundtruth = [];

hrUbfcPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');

if isfile(hrUbfcPath)
    ubfcHrTable = readtable(hrUbfcPath);
    numRows = height(ubfcHrTable);

    for rowPos = 1:numRows
        hrSubjectID{end + 1} = extractText(ubfcHrTable.subjectID, rowPos);
        hrDataset{end + 1} = 'UBFC';
        hrChrom(end + 1) = ubfcHrTable.HR_chrom(rowPos);
        hrPos(end + 1) = ubfcHrTable.HR_pos(rowPos);
        hrGreen(end + 1) = ubfcHrTable.HR_green(rowPos);
        hrGroundtruth(end + 1) = ubfcHrTable.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' UBFC HR rows from ' hrUbfcPath]);
else
    disp(['UBFC HR summary not found, skipping: ' hrUbfcPath]);
end

hrViplPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');

if isfile(hrViplPath)
    viplHrTable = readtable(hrViplPath);
    numRows = height(viplHrTable);

    for rowPos = 1:numRows
        hrSubjectID{end + 1} = extractText(viplHrTable.subjectID, rowPos);
        hrDataset{end + 1} = extractText(viplHrTable.dataset, rowPos);
        hrChrom(end + 1) = viplHrTable.HR_chrom(rowPos);
        hrPos(end + 1) = viplHrTable.HR_pos(rowPos);
        hrGreen(end + 1) = viplHrTable.HR_green(rowPos);
        hrGroundtruth(end + 1) = viplHrTable.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL HR rows from ' hrViplPath]);
else
    disp(['VIPL HR summary not found, skipping: ' hrViplPath]);
end

numHrTotal = numel(hrSubjectID);
hrValidMask = false(1, numHrTotal);

for i = 1:numHrTotal
    if ~isnan(hrGroundtruth(i))
        hrValidMask(i) = true;
    end
end

numHrSkipped = numHrTotal - sum(hrValidMask);

disp(['HR pooled: ' num2str(numHrTotal) ' total rows, ' num2str(numHrSkipped) ' skipped for NaN ground truth, ' num2str(sum(hrValidMask)) ' usable.']);

hrMethodNames = {'chrom', 'pos', 'green'};
hrMethodValues = {hrChrom, hrPos, hrGreen};
hrDatasetScopes = {'UBFC', 'VIPL'};

hrMetricsCsvPath = fullfile(metricsRoot, 'segment6_hr_pooled_metrics.csv');
hrMetricsHeaderLine = "method,scope,N,MAE,RMSE,Pearson_r";
writelines(hrMetricsHeaderLine, hrMetricsCsvPath);

hrMetricsStore = struct();

for methodPos = 1:numel(hrMethodNames)
    methodName = hrMethodNames{methodPos};
    methodValues = hrMethodValues{methodPos};

    pooledPredicted = methodValues(hrValidMask);
    pooledGroundTruth = hrGroundtruth(hrValidMask);
    pooledMetrics = computeMetrics(pooledPredicted, pooledGroundTruth);

    rowLine = formatMetricsRow({methodName, 'pooled'}, pooledMetrics);
    writelines(rowLine, hrMetricsCsvPath, 'WriteMode', 'append');

    hrMetricsStore.(methodName).pooled = pooledMetrics;

    for scopePos = 1:numel(hrDatasetScopes)
        scopeName = hrDatasetScopes{scopePos};
        scopeMask = false(1, numHrTotal);

        for i = 1:numHrTotal
            if hrValidMask(i) && strcmp(hrDataset{i}, scopeName)
                scopeMask(i) = true;
            end
        end

        scopePredicted = methodValues(scopeMask);
        scopeGroundTruth = hrGroundtruth(scopeMask);
        scopeMetrics = computeMetrics(scopePredicted, scopeGroundTruth);

        rowLine = formatMetricsRow({methodName, scopeName}, scopeMetrics);
        writelines(rowLine, hrMetricsCsvPath, 'WriteMode', 'append');

        hrMetricsStore.(methodName).(scopeName) = scopeMetrics;
    end

    disp([methodName ' pooled: N=' num2str(pooledMetrics.n) ', MAE=' num2str(pooledMetrics.mae) ', RMSE=' num2str(pooledMetrics.rmse) ', Pearson r=' num2str(pooledMetrics.pearsonR)]);
end

disp(['Saved ' hrMetricsCsvPath]);

hrDatasetValid = hrDataset(hrValidMask);
hrGroundtruthValid = hrGroundtruth(hrValidMask);

[hrChromBias, hrChromLoA] = blandAltman(hrChrom(hrValidMask), hrGroundtruthValid, 'Segment 6 -- Pooled HR Bland-Altman (CHROM)', fullfile(figuresRoot, 'segment6_hr_bland_altman_chrom.png'), hrDatasetValid);
disp(['HR CHROM Bland-Altman: bias = ' num2str(hrChromBias) ', limits of agreement = [' num2str(hrChromLoA(1)) ', ' num2str(hrChromLoA(2)) ']']);

[hrPosBias, hrPosLoA] = blandAltman(hrPos(hrValidMask), hrGroundtruthValid, 'Segment 6 -- Pooled HR Bland-Altman (POS)', fullfile(figuresRoot, 'segment6_hr_bland_altman_pos.png'), hrDatasetValid);
disp(['HR POS Bland-Altman: bias = ' num2str(hrPosBias) ', limits of agreement = [' num2str(hrPosLoA(1)) ', ' num2str(hrPosLoA(2)) ']']);

[hrGreenBias, hrGreenLoA] = blandAltman(hrGreen(hrValidMask), hrGroundtruthValid, 'Segment 6 -- Pooled HR Bland-Altman (Green-only)', fullfile(figuresRoot, 'segment6_hr_bland_altman_green.png'), hrDatasetValid);
disp(['HR Green-only Bland-Altman: bias = ' num2str(hrGreenBias) ', limits of agreement = [' num2str(hrGreenLoA(1)) ', ' num2str(hrGreenLoA(2)) ']']);

disp(' ');
disp('=== Segment 6 Validation: SpO2 (genuine pooled leave-one-subject-out refit) ===');

spo2SubjectID = {};
spo2Dataset = {};
spo2R = [];
spo2True = [];

spo2UbfcPath = fullfile(metricsRoot, 'segment5_dataset1_calibration.csv');

if isfile(spo2UbfcPath)
    ubfcSpo2Table = readtable(spo2UbfcPath);
    numRows = height(ubfcSpo2Table);

    for rowPos = 1:numRows
        spo2SubjectID{end + 1} = extractText(ubfcSpo2Table.subjectID, rowPos);
        spo2Dataset{end + 1} = 'UBFC';
        spo2R(end + 1) = ubfcSpo2Table.R_value(rowPos);
        spo2True(end + 1) = ubfcSpo2Table.SpO2_true(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' UBFC SpO2 rows from ' spo2UbfcPath]);
else
    disp(['UBFC SpO2 calibration CSV not found, skipping: ' spo2UbfcPath]);
end

spo2ViplPath = fullfile(metricsRoot, 'segment5_vipl_calibration.csv');

if isfile(spo2ViplPath)
    viplSpo2Table = readtable(spo2ViplPath);
    numRows = height(viplSpo2Table);

    for rowPos = 1:numRows
        spo2SubjectID{end + 1} = extractText(viplSpo2Table.subjectID, rowPos);
        spo2Dataset{end + 1} = extractText(viplSpo2Table.dataset, rowPos);
        spo2R(end + 1) = viplSpo2Table.R_value(rowPos);
        spo2True(end + 1) = viplSpo2Table.SpO2_true(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL SpO2 rows from ' spo2ViplPath]);
else
    disp(['VIPL SpO2 calibration CSV not found, skipping: ' spo2ViplPath]);
end

numSpo2Total = numel(spo2SubjectID);

disp(['SpO2 pooled: ' num2str(numSpo2Total) ' total subjects with SpO2 ground truth (UBFC + VIPL combined).']);

if numSpo2Total < 15
    disp('NOTE: this pooled SpO2 N is still thin. Treat these numbers as an early snapshot, not a final validated result -- see Segment6_Team_README.md.');
end

if numSpo2Total > 0
    disp(' ');
    disp('=== Segment 6 Diagnostic: raw R vs true SpO2, by dataset (before calibration) ===');
    disp('This is the RAW relationship the calibration line is fit on -- it is NOT the predicted-vs-true scatter below. If UBFC and VIPL occupy visibly different R ranges for similar SpO2, that is a cross-dataset R offset, not a physiological SpO2 signal.');

    rVsSpo2FigureHandle = figure('Visible', 'off');
    hold on;

    uniqueRSpo2Datasets = unique(spo2Dataset);
    markerListRSpo2 = {'o', 's', '^', 'd', 'v'};

    for datasetPos = 1:numel(uniqueRSpo2Datasets)
        thisDataset = uniqueRSpo2Datasets{datasetPos};
        pointMask = false(1, numSpo2Total);

        for i = 1:numSpo2Total
            if strcmp(spo2Dataset{i}, thisDataset)
                pointMask(i) = true;
            end
        end

        markerStyle = markerListRSpo2{mod(datasetPos - 1, numel(markerListRSpo2)) + 1};
        scatter(spo2R(pointMask), spo2True(pointMask), 70, 'filled', markerStyle, 'DisplayName', thisDataset);

        disp([thisDataset ': R range = [' num2str(min(spo2R(pointMask))) ', ' num2str(max(spo2R(pointMask))) '], SpO2_true range = [' num2str(min(spo2True(pointMask))) ', ' num2str(max(spo2True(pointMask))) ']']);
    end

    legend('show', 'Location', 'best');
    xlabel('R (ratio-of-ratios, raw, pre-calibration)');
    ylabel('SpO2 true (%)');
    title('Segment 6 -- Raw R vs True SpO2, by Dataset');
    grid on;
    hold off;

    rVsSpo2PngPath = fullfile(figuresRoot, 'segment6_R_vs_SpO2_by_dataset.png');
    exportgraphics(rVsSpo2FigureHandle, rVsSpo2PngPath);
    close(rVsSpo2FigureHandle);

    disp(['Saved ' rVsSpo2PngPath]);
end

spo2LosoRan = false;

if numSpo2Total < 3
    disp('Fewer than 3 pooled SpO2 subjects -- leave-one-subject-out refitting needs at least 3 to be even minimally meaningful. Stopping SpO2 validation here.');
else
    spo2LosoResults = runLOSO(spo2SubjectID, spo2Dataset, spo2R, spo2True);

    spo2LosoCsvPath = fullfile(metricsRoot, 'segment6_spo2_loso_pooled.csv');
    spo2LosoHeaderLine = "subjectID,dataset,R_value,SpO2_true,SpO2_predicted,abs_error,SpO2_predicted_baseline,abs_error_baseline,SpO2_predicted_centered,abs_error_centered";
    writelines(spo2LosoHeaderLine, spo2LosoCsvPath);

    for foldPos = 1:numel(spo2LosoResults)
        foldResult = spo2LosoResults(foldPos);
        rowParts = {foldResult.subjectID, foldResult.dataset, num2str(foldResult.R_value), num2str(foldResult.SpO2_true), num2str(foldResult.SpO2_predicted), num2str(foldResult.abs_error), num2str(foldResult.SpO2_predicted_baseline), num2str(foldResult.abs_error_baseline), num2str(foldResult.SpO2_predicted_centered), num2str(foldResult.abs_error_centered)};
        rowLine = strjoin(rowParts, ',');
        writelines(rowLine, spo2LosoCsvPath, 'WriteMode', 'append');
    end

    disp(['Saved ' spo2LosoCsvPath ' (now includes SpO2_predicted_baseline / abs_error_baseline -- the trivial training-mean-only prediction -- and SpO2_predicted_centered / abs_error_centered -- the per-dataset-R-centered calibration -- alongside the original real R-based calibration, all three side by side).']);

    spo2PredictedAll = zeros(1, numSpo2Total);
    spo2TrueAll = zeros(1, numSpo2Total);
    spo2DatasetAll = cell(1, numSpo2Total);
    spo2PredictedBaselineAll = zeros(1, numSpo2Total);
    spo2PredictedCenteredAll = zeros(1, numSpo2Total);

    for foldPos = 1:numSpo2Total
        spo2PredictedAll(foldPos) = spo2LosoResults(foldPos).SpO2_predicted;
        spo2TrueAll(foldPos) = spo2LosoResults(foldPos).SpO2_true;
        spo2DatasetAll{foldPos} = spo2LosoResults(foldPos).dataset;
        spo2PredictedBaselineAll(foldPos) = spo2LosoResults(foldPos).SpO2_predicted_baseline;
        spo2PredictedCenteredAll(foldPos) = spo2LosoResults(foldPos).SpO2_predicted_centered;
    end

    spo2MetricsCsvPath = fullfile(metricsRoot, 'segment6_spo2_loso_metrics.csv');
    spo2MetricsHeaderLine = "scope,N,MAE,RMSE,Pearson_r";
    writelines(spo2MetricsHeaderLine, spo2MetricsCsvPath);

    spo2PooledMetrics = computeMetrics(spo2PredictedAll, spo2TrueAll);
    spo2RowLine = formatMetricsRow({'pooled'}, spo2PooledMetrics);
    writelines(spo2RowLine, spo2MetricsCsvPath, 'WriteMode', 'append');

    spo2ScopeMetricsStore = struct();
    spo2ScopeMetricsStore.pooled = spo2PooledMetrics;

    spo2DatasetScopes = {'UBFC', 'VIPL'};

    for scopePos = 1:numel(spo2DatasetScopes)
        scopeName = spo2DatasetScopes{scopePos};
        scopeMask = false(1, numSpo2Total);

        for i = 1:numSpo2Total
            if strcmp(spo2DatasetAll{i}, scopeName)
                scopeMask(i) = true;
            end
        end

        scopePredicted = spo2PredictedAll(scopeMask);
        scopeTrue = spo2TrueAll(scopeMask);
        scopeMetrics = computeMetrics(scopePredicted, scopeTrue);

        scopeRowLine = formatMetricsRow({scopeName}, scopeMetrics);
        writelines(scopeRowLine, spo2MetricsCsvPath, 'WriteMode', 'append');

        spo2ScopeMetricsStore.(scopeName) = scopeMetrics;
    end

    disp(['Saved ' spo2MetricsCsvPath]);
    disp(['SpO2 LOSO pooled: N=' num2str(spo2PooledMetrics.n) ', MAE=' num2str(spo2PooledMetrics.mae) ', RMSE=' num2str(spo2PooledMetrics.rmse) ', Pearson r=' num2str(spo2PooledMetrics.pearsonR)]);

    disp(' ');
    disp('=== Segment 6 Diagnostic: trivial baseline comparison (training-set mean, R ignored) ===');

    spo2BaselineMetricsCsvPath = fullfile(metricsRoot, 'segment6_spo2_loso_baseline_metrics.csv');
    spo2BaselineMetricsHeaderLine = "scope,N,MAE,RMSE,Pearson_r";
    writelines(spo2BaselineMetricsHeaderLine, spo2BaselineMetricsCsvPath);

    spo2PooledBaselineMetrics = computeMetrics(spo2PredictedBaselineAll, spo2TrueAll);
    spo2BaselineRowLine = formatMetricsRow({'pooled'}, spo2PooledBaselineMetrics);
    writelines(spo2BaselineRowLine, spo2BaselineMetricsCsvPath, 'WriteMode', 'append');

    spo2BaselineScopeMetricsStore = struct();
    spo2BaselineScopeMetricsStore.pooled = spo2PooledBaselineMetrics;

    for scopePos = 1:numel(spo2DatasetScopes)
        scopeName = spo2DatasetScopes{scopePos};
        scopeMask = false(1, numSpo2Total);

        for i = 1:numSpo2Total
            if strcmp(spo2DatasetAll{i}, scopeName)
                scopeMask(i) = true;
            end
        end

        scopePredictedBaseline = spo2PredictedBaselineAll(scopeMask);
        scopeTrue = spo2TrueAll(scopeMask);
        scopeBaselineMetrics = computeMetrics(scopePredictedBaseline, scopeTrue);

        scopeBaselineRowLine = formatMetricsRow({scopeName}, scopeBaselineMetrics);
        writelines(scopeBaselineRowLine, spo2BaselineMetricsCsvPath, 'WriteMode', 'append');

        spo2BaselineScopeMetricsStore.(scopeName) = scopeBaselineMetrics;
    end

    disp(['Saved ' spo2BaselineMetricsCsvPath]);
    disp(['SpO2 baseline (training-mean-only) pooled: N=' num2str(spo2PooledBaselineMetrics.n) ', MAE=' num2str(spo2PooledBaselineMetrics.mae) ', RMSE=' num2str(spo2PooledBaselineMetrics.rmse) ', Pearson r=' num2str(spo2PooledBaselineMetrics.pearsonR)]);
    disp(['Real calibration pooled MAE = ' num2str(spo2PooledMetrics.mae) ' vs baseline pooled MAE = ' num2str(spo2PooledBaselineMetrics.mae) '.']);

    if spo2PooledMetrics.mae >= spo2PooledBaselineMetrics.mae
        disp('FINDING: the real R-based calibration does NOT beat the trivial training-mean baseline on pooled MAE. R is not yet demonstrating predictive value over just guessing the training mean, at the current pooled N.');
    else
        disp('FINDING: the real R-based calibration beats the trivial training-mean baseline on pooled MAE.');
    end

    disp(' ');
    disp('=== Segment 6 Diagnostic: per-dataset R-centered calibration (validation/centerRPerDataset.m) ===');
    disp('Each fold subtracts that dataset''s OWN training-only mean R (recomputed per fold, held-out subject excluded) from every R value before calling the unmodified calibrateSpO2.m. See Segment6_Refinement_Notes.md for the per-dataset slope diagnostic that justified trying this.');

    spo2CenteredMetricsCsvPath = fullfile(metricsRoot, 'segment6_spo2_loso_centered_metrics.csv');
    spo2CenteredMetricsHeaderLine = "scope,N,MAE,RMSE,Pearson_r";
    writelines(spo2CenteredMetricsHeaderLine, spo2CenteredMetricsCsvPath);

    spo2PooledCenteredMetrics = computeMetrics(spo2PredictedCenteredAll, spo2TrueAll);
    spo2CenteredRowLine = formatMetricsRow({'pooled'}, spo2PooledCenteredMetrics);
    writelines(spo2CenteredRowLine, spo2CenteredMetricsCsvPath, 'WriteMode', 'append');

    spo2CenteredScopeMetricsStore = struct();
    spo2CenteredScopeMetricsStore.pooled = spo2PooledCenteredMetrics;

    for scopePos = 1:numel(spo2DatasetScopes)
        scopeName = spo2DatasetScopes{scopePos};
        scopeMask = false(1, numSpo2Total);

        for i = 1:numSpo2Total
            if strcmp(spo2DatasetAll{i}, scopeName)
                scopeMask(i) = true;
            end
        end

        scopePredictedCentered = spo2PredictedCenteredAll(scopeMask);
        scopeTrue = spo2TrueAll(scopeMask);
        scopeCenteredMetrics = computeMetrics(scopePredictedCentered, scopeTrue);

        scopeCenteredRowLine = formatMetricsRow({scopeName}, scopeCenteredMetrics);
        writelines(scopeCenteredRowLine, spo2CenteredMetricsCsvPath, 'WriteMode', 'append');

        spo2CenteredScopeMetricsStore.(scopeName) = scopeCenteredMetrics;
    end

    disp(['Saved ' spo2CenteredMetricsCsvPath]);
    disp(['SpO2 centered-calibration pooled: N=' num2str(spo2PooledCenteredMetrics.n) ', MAE=' num2str(spo2PooledCenteredMetrics.mae) ', RMSE=' num2str(spo2PooledCenteredMetrics.rmse) ', Pearson r=' num2str(spo2PooledCenteredMetrics.pearsonR)]);
    disp(['Centered calibration pooled MAE = ' num2str(spo2PooledCenteredMetrics.mae) ' vs raw calibration pooled MAE = ' num2str(spo2PooledMetrics.mae) ' vs baseline pooled MAE = ' num2str(spo2PooledBaselineMetrics.mae) '.']);

    if spo2PooledCenteredMetrics.mae >= spo2PooledBaselineMetrics.mae
        disp('FINDING: per-dataset R centering does NOT get the real calibration to beat the trivial training-mean baseline on pooled MAE either.');
    else
        disp('FINDING: per-dataset R centering DOES get the real calibration to beat the trivial training-mean baseline on pooled MAE.');
    end

    [spo2Bias, spo2LoA] = blandAltman(spo2PredictedAll, spo2TrueAll, 'Segment 6 -- Pooled SpO2 LOSO Bland-Altman', fullfile(figuresRoot, 'segment6_spo2_bland_altman_pooled.png'), spo2DatasetAll);
    disp(['SpO2 Bland-Altman: bias = ' num2str(spo2Bias) ', limits of agreement = [' num2str(spo2LoA(1)) ', ' num2str(spo2LoA(2)) ']']);

    spo2ScatterFigureHandle = figure('Visible', 'off');
    hold on;

    minAxisVal = min([spo2TrueAll, spo2PredictedAll]) - 2;
    maxAxisVal = max([spo2TrueAll, spo2PredictedAll]) + 2;

    plot([minAxisVal maxAxisVal], [minAxisVal maxAxisVal], 'k--', 'LineWidth', 1, 'DisplayName', 'y = x (perfect agreement)');

    uniqueSpo2Datasets = unique(spo2DatasetAll);
    markerListScatter = {'o', 's', '^', 'd', 'v'};

    for datasetPos = 1:numel(uniqueSpo2Datasets)
        thisDataset = uniqueSpo2Datasets{datasetPos};
        pointMask = false(1, numSpo2Total);

        for i = 1:numSpo2Total
            if strcmp(spo2DatasetAll{i}, thisDataset)
                pointMask(i) = true;
            end
        end

        markerStyle = markerListScatter{mod(datasetPos - 1, numel(markerListScatter)) + 1};
        scatter(spo2TrueAll(pointMask), spo2PredictedAll(pointMask), 60, 'filled', markerStyle, 'DisplayName', thisDataset);
    end

    legend('show', 'Location', 'best');
    xlim([minAxisVal maxAxisVal]);
    ylim([minAxisVal maxAxisVal]);
    xlabel('SpO2 true (%)');
    ylabel('SpO2 predicted (%)');
    title('Segment 6 -- Pooled SpO2 LOSO: Predicted vs True');
    grid on;
    hold off;

    spo2ScatterPngPath = fullfile(figuresRoot, 'segment6_spo2_predicted_vs_true.png');
    exportgraphics(spo2ScatterFigureHandle, spo2ScatterPngPath);
    close(spo2ScatterFigureHandle);

    disp(['Saved ' spo2ScatterPngPath]);

    spo2LosoRan = true;
end

disp(' ');
disp('=== Segment 6 Validation Summary ===');
disp(' ');
disp('--- SpO2 (genuine leave-one-subject-out refit, pooled UBFC+VIPL) ---');

if ~spo2LosoRan
    disp('Not run: fewer than 3 pooled SpO2 subjects currently available.');
else
    disp(['Pooled:    N=' num2str(spo2PooledMetrics.n) ', MAE=' num2str(spo2PooledMetrics.mae) ', RMSE=' num2str(spo2PooledMetrics.rmse) ', Pearson r=' num2str(spo2PooledMetrics.pearsonR)]);
    disp(['UBFC only: N=' num2str(spo2ScopeMetricsStore.UBFC.n) ', MAE=' num2str(spo2ScopeMetricsStore.UBFC.mae) ', RMSE=' num2str(spo2ScopeMetricsStore.UBFC.rmse) ', Pearson r=' num2str(spo2ScopeMetricsStore.UBFC.pearsonR)]);
    disp(['VIPL only: N=' num2str(spo2ScopeMetricsStore.VIPL.n) ', MAE=' num2str(spo2ScopeMetricsStore.VIPL.mae) ', RMSE=' num2str(spo2ScopeMetricsStore.VIPL.rmse) ', Pearson r=' num2str(spo2ScopeMetricsStore.VIPL.pearsonR)]);
    disp(' ');
    disp('--- SpO2 trivial baseline (training-mean-only, R ignored) for comparison ---');
    disp(['Pooled:    N=' num2str(spo2PooledBaselineMetrics.n) ', MAE=' num2str(spo2PooledBaselineMetrics.mae) ', RMSE=' num2str(spo2PooledBaselineMetrics.rmse) ', Pearson r=' num2str(spo2PooledBaselineMetrics.pearsonR)]);
    disp(['UBFC only: N=' num2str(spo2BaselineScopeMetricsStore.UBFC.n) ', MAE=' num2str(spo2BaselineScopeMetricsStore.UBFC.mae) ', RMSE=' num2str(spo2BaselineScopeMetricsStore.UBFC.rmse) ', Pearson r=' num2str(spo2BaselineScopeMetricsStore.UBFC.pearsonR)]);
    disp(['VIPL only: N=' num2str(spo2BaselineScopeMetricsStore.VIPL.n) ', MAE=' num2str(spo2BaselineScopeMetricsStore.VIPL.mae) ', RMSE=' num2str(spo2BaselineScopeMetricsStore.VIPL.rmse) ', Pearson r=' num2str(spo2BaselineScopeMetricsStore.VIPL.pearsonR)]);
    disp(' ');
    disp('--- SpO2 per-dataset R-centered calibration (validation/centerRPerDataset.m) for comparison ---');
    disp(['Pooled:    N=' num2str(spo2PooledCenteredMetrics.n) ', MAE=' num2str(spo2PooledCenteredMetrics.mae) ', RMSE=' num2str(spo2PooledCenteredMetrics.rmse) ', Pearson r=' num2str(spo2PooledCenteredMetrics.pearsonR)]);
    disp(['UBFC only: N=' num2str(spo2CenteredScopeMetricsStore.UBFC.n) ', MAE=' num2str(spo2CenteredScopeMetricsStore.UBFC.mae) ', RMSE=' num2str(spo2CenteredScopeMetricsStore.UBFC.rmse) ', Pearson r=' num2str(spo2CenteredScopeMetricsStore.UBFC.pearsonR)]);
    disp(['VIPL only: N=' num2str(spo2CenteredScopeMetricsStore.VIPL.n) ', MAE=' num2str(spo2CenteredScopeMetricsStore.VIPL.mae) ', RMSE=' num2str(spo2CenteredScopeMetricsStore.VIPL.rmse) ', Pearson r=' num2str(spo2CenteredScopeMetricsStore.VIPL.pearsonR)]);
end

disp(' ');
disp('--- HR (pooled direct evaluation, no fitted parameter) ---');

for methodPos = 1:numel(hrMethodNames)
    methodName = hrMethodNames{methodPos};
    disp(['Method: ' methodName]);
    disp(['  Pooled:    N=' num2str(hrMetricsStore.(methodName).pooled.n) ', MAE=' num2str(hrMetricsStore.(methodName).pooled.mae) ', RMSE=' num2str(hrMetricsStore.(methodName).pooled.rmse) ', Pearson r=' num2str(hrMetricsStore.(methodName).pooled.pearsonR)]);
    disp(['  UBFC only: N=' num2str(hrMetricsStore.(methodName).UBFC.n) ', MAE=' num2str(hrMetricsStore.(methodName).UBFC.mae) ', RMSE=' num2str(hrMetricsStore.(methodName).UBFC.rmse) ', Pearson r=' num2str(hrMetricsStore.(methodName).UBFC.pearsonR)]);
    disp(['  VIPL only: N=' num2str(hrMetricsStore.(methodName).VIPL.n) ', MAE=' num2str(hrMetricsStore.(methodName).VIPL.mae) ', RMSE=' num2str(hrMetricsStore.(methodName).VIPL.rmse) ', Pearson r=' num2str(hrMetricsStore.(methodName).VIPL.pearsonR)]);
end

disp(' ');
disp('--- Segment 6 validation batch complete ---');

function textVal = extractText(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end

function rowLine = formatMetricsRow(prefixParts, metricsStruct)

rowParts = prefixParts;
rowParts{end + 1} = num2str(metricsStruct.n);
rowParts{end + 1} = num2str(metricsStruct.mae);
rowParts{end + 1} = num2str(metricsStruct.rmse);
rowParts{end + 1} = num2str(metricsStruct.pearsonR);
rowLine = strjoin(rowParts, ',');

end
