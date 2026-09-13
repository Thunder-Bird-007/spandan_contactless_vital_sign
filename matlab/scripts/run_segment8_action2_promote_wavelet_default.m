% RUN_SEGMENT8_ACTION2_PROMOTE_WAVELET_DEFAULT Segment 8 (post-review
% follow-up), Action 2. Promotes filtering/waveletDenoise.m from an
% "available additive option" (Action 4's own framing) to the actual
% default production Branch 1 HR pipeline result recorded in
% results/metrics/segment6_hr_pooled_metrics.csv.
%
% Does NOT reprocess any video. CHROM/POS "with wavelet" values are taken
% directly from results/metrics/segment8_task4_wavelet_ablation.csv's
% HR_chrom_wavelet / HR_pos_wavelet columns -- those numbers were already
% computed by scripts/run_segment8_task4_wavelet_ablation_batch.m using
% EXACTLY the chain now wired into scripts/run_segment3_filtering_batch.m
% and scripts/run_vipl_integration_batch.m (waveletDenoise -> detrendSignal
% -> bandpassClean -> chromCombine/posCombine -> fftHeartRate), on the same
% 112-subject pool (5 UBFC-D1 + 107 VIPL) -- so reusing them here is exact,
% not an approximation, and re-decoding all 112 videos again would only
% reproduce the identical numbers at a large, unnecessary time cost.
%
% Green-only HR is left UNCHANGED (still the pre-wavelet numbers from
% results/metrics/segment4_hr_summary.csv / segment4_hr_summary_vipl.csv).
% Action 4's ablation never covered the green-only method (only CHROM and
% POS are this project's validated Branch 1 production outputs -- green is
% a diagnostic comparison method, never the shipped result, see
% docs/Spandan_Final_Pipeline_Report.md), so there is no wavelet-denoised
% green number to promote. This is stated explicitly rather than silently
% implied by an unchanged number.
%
% Before writing anything, the CURRENT (pre-wavelet)
% segment6_hr_pooled_metrics.csv is copied to
% segment6_hr_pooled_metrics_prewavelet.csv -- "mark superseded, don't
% delete", same convention used throughout this project.
%
% Output: results/metrics/segment6_hr_pooled_metrics.csv (overwritten,
% pre-wavelet copy preserved as above).

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

hrMetricsCsvPath = fullfile(metricsRoot, 'segment6_hr_pooled_metrics.csv');
prewaveletCsvPath = fullfile(metricsRoot, 'segment6_hr_pooled_metrics_prewavelet.csv');
ablationCsvPath = fullfile(metricsRoot, 'segment8_task4_wavelet_ablation.csv');
ubfcGreenPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');
viplGreenPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');

if ~isfile(hrMetricsCsvPath)
    error('run_segment8_action2_promote_wavelet_default:noExisting', ...
        'Expected an existing %s to back up -- not found.', hrMetricsCsvPath);
end

copyfile(hrMetricsCsvPath, prewaveletCsvPath);
disp(['Backed up pre-wavelet ' hrMetricsCsvPath ' -> ' prewaveletCsvPath]);

% --- CHROM / POS: read the already-computed wavelet ablation numbers. ---
ablationTable = readtable(ablationCsvPath, 'TextType', 'string');
numAblation = height(ablationTable);
disp(['Loaded ' num2str(numAblation) ' subjects from ' ablationCsvPath]);

chromPredicted = ablationTable.HR_chrom_wavelet;
posPredicted = ablationTable.HR_pos_wavelet;
groundTruthAblation = ablationTable.HR_groundtruth;
datasetAblation = ablationTable.dataset;

% --- Green-only: read the UNCHANGED pre-wavelet summary CSVs, same
% pooling logic as scripts/run_segment6_validation.m's own HR section. ---
greenPredicted = [];
greenGroundtruth = [];
greenDataset = {};

if isfile(ubfcGreenPath)
    ubfcGreenTable = readtable(ubfcGreenPath);
    for rowPos = 1:height(ubfcGreenTable)
        greenPredicted(end + 1) = ubfcGreenTable.HR_green(rowPos); %#ok<AGROW>
        greenGroundtruth(end + 1) = ubfcGreenTable.HR_groundtruth(rowPos); %#ok<AGROW>
        greenDataset{end + 1} = 'UBFC'; %#ok<AGROW>
    end
    disp(['Loaded ' num2str(height(ubfcGreenTable)) ' UBFC green-only rows (unchanged, pre-wavelet) from ' ubfcGreenPath]);
end

if isfile(viplGreenPath)
    viplGreenTable = readtable(viplGreenPath, 'TextType', 'string');
    for rowPos = 1:height(viplGreenTable)
        greenPredicted(end + 1) = viplGreenTable.HR_green(rowPos); %#ok<AGROW>
        greenGroundtruth(end + 1) = viplGreenTable.HR_groundtruth(rowPos); %#ok<AGROW>
        greenDataset{end + 1} = char(viplGreenTable.dataset(rowPos)); %#ok<AGROW>
    end
    disp(['Loaded ' num2str(height(viplGreenTable)) ' VIPL green-only rows (unchanged, pre-wavelet) from ' viplGreenPath]);
end

greenValidMask = ~isnan(greenGroundtruth);
greenPredicted = greenPredicted(greenValidMask);
greenGroundtruth = greenGroundtruth(greenValidMask);
greenDataset = greenDataset(greenValidMask);

% --- Write the new segment6_hr_pooled_metrics.csv. ---
hrMetricsHeaderLine = "method,scope,N,MAE,RMSE,Pearson_r";
writelines(hrMetricsHeaderLine, hrMetricsCsvPath);

hrMethodNames = {'chrom', 'pos', 'green'};
hrMethodPredicted = {chromPredicted, posPredicted, greenPredicted};
hrMethodGroundtruth = {groundTruthAblation, groundTruthAblation, greenGroundtruth};
hrMethodDataset = {datasetAblation, datasetAblation, greenDataset};
hrDatasetScopes = {'UBFC', 'VIPL'};

for methodPos = 1:numel(hrMethodNames)
    methodName = hrMethodNames{methodPos};
    methodPredicted = hrMethodPredicted{methodPos};
    methodGroundtruth = hrMethodGroundtruth{methodPos};
    methodDataset = hrMethodDataset{methodPos};

    pooledMetrics = computeMetrics(methodPredicted, methodGroundtruth);
    rowLine = strjoin({methodName, 'pooled', num2str(pooledMetrics.n), num2str(pooledMetrics.mae), num2str(pooledMetrics.rmse), num2str(pooledMetrics.pearsonR)}, ',');
    writelines(rowLine, hrMetricsCsvPath, 'WriteMode', 'append');

    disp([methodName ' pooled (with wavelet default): N=' num2str(pooledMetrics.n) ', MAE=' num2str(pooledMetrics.mae) ', RMSE=' num2str(pooledMetrics.rmse) ', Pearson r=' num2str(pooledMetrics.pearsonR)]);

    for scopePos = 1:numel(hrDatasetScopes)
        scopeName = hrDatasetScopes{scopePos};

        if iscell(methodDataset)
            scopeMask = strcmp(methodDataset, scopeName);
        else
            scopeMask = (methodDataset == scopeName);
        end

        scopeMetrics = computeMetrics(methodPredicted(scopeMask), methodGroundtruth(scopeMask));
        rowLine = strjoin({methodName, scopeName, num2str(scopeMetrics.n), num2str(scopeMetrics.mae), num2str(scopeMetrics.rmse), num2str(scopeMetrics.pearsonR)}, ',');
        writelines(rowLine, hrMetricsCsvPath, 'WriteMode', 'append');
    end
end

disp(['Saved ' hrMetricsCsvPath ' (wavelet denoising now the default for CHROM/POS; green-only unchanged, see this script''s own header comment).']);

% --- Verification against docs/Segment8_Task4_Wavelet_Denoise_Ablation.md's
% already-reported pooled table. ---
expected = struct( ...
    'chrom_mae', 7.8344, 'chrom_rmse', 11.8676, 'chrom_r', 0.5319, ...
    'pos_mae', 7.2217, 'pos_rmse', 10.8493, 'pos_r', 0.6234);

chromPooled = computeMetrics(chromPredicted, groundTruthAblation);
posPooled = computeMetrics(posPredicted, groundTruthAblation);

tol = 0.01;
mismatches = {};

if abs(chromPooled.mae - expected.chrom_mae) > tol
    mismatches{end+1} = sprintf('CHROM MAE %.4f vs expected %.4f', chromPooled.mae, expected.chrom_mae); %#ok<AGROW>
end
if abs(chromPooled.rmse - expected.chrom_rmse) > tol
    mismatches{end+1} = sprintf('CHROM RMSE %.4f vs expected %.4f', chromPooled.rmse, expected.chrom_rmse); %#ok<AGROW>
end
if abs(chromPooled.pearsonR - expected.chrom_r) > tol
    mismatches{end+1} = sprintf('CHROM r %.4f vs expected %.4f', chromPooled.pearsonR, expected.chrom_r); %#ok<AGROW>
end
if abs(posPooled.mae - expected.pos_mae) > tol
    mismatches{end+1} = sprintf('POS MAE %.4f vs expected %.4f', posPooled.mae, expected.pos_mae); %#ok<AGROW>
end
if abs(posPooled.rmse - expected.pos_rmse) > tol
    mismatches{end+1} = sprintf('POS RMSE %.4f vs expected %.4f', posPooled.rmse, expected.pos_rmse); %#ok<AGROW>
end
if abs(posPooled.pearsonR - expected.pos_r) > tol
    mismatches{end+1} = sprintf('POS r %.4f vs expected %.4f', posPooled.pearsonR, expected.pos_r); %#ok<AGROW>
end

if isempty(mismatches)
    disp('VERIFICATION PASSED: new pooled CHROM/POS numbers match docs/Segment8_Task4_Wavelet_Denoise_Ablation.md exactly (within 0.01 rounding tolerance).');
else
    disp('VERIFICATION FAILED -- mismatches found:');
    for k = 1:numel(mismatches)
        disp(['  ' mismatches{k}]);
    end
    error('run_segment8_action2_promote_wavelet_default:verificationFailed', 'New pooled numbers do not match the ablation doc -- see mismatches above.');
end
