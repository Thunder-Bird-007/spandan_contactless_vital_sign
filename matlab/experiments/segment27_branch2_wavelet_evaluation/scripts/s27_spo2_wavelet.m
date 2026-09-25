% S27_SPO2_WAVELET Segment 27 Item B (PREREGISTRATION.md). Whether the
% SpO2 pin (Branch 1's ratio-of-ratios chain always uses pre-wavelet R/G/B,
% see pipeline/estimateVitalsAndMorphology.m's SpO2 PIN note) should be
% lifted, i.e. whether wavelet denoising (filtering/waveletDenoise.m, db4,
% 3-level) helps or hurts SpO2 prediction.
%
% No video decode: loads each of the 112 pooled subjects' cached
% data/processed/<subjectID>_rgb_traces.mat (raw R/G/B, saved once at
% Segment 2/VIPL-integration time -- NOT the possibly-already-wavelet'd
% *_filtered_traces.mat, since scripts/run_vipl_integration_batch.m's
% useWaveletDenoise default flipped to true on 2026-09-13 and may have
% regenerated those since the frozen calibration CSVs were written).
% Subject list, dataset labels, and SpO2_true all come from the frozen
% results/metrics/segment5_dataset1_calibration.csv (5 UBFC) and
% segment5_vipl_calibration.csv (107 VIPL) -- the same pooling
% run_segment6_validation.m already does -- never recomputed.
%
% Two chains are rebuilt from each subject's raw cached R/G/B:
%   pre-wavelet: detrendSignal -> bandpassClean -> ratioOfRatios (DC from
%     the untouched raw trace). Regenerated first as a PARITY CHECK: must
%     reproduce the frozen CSV's R_value column, and reproducing
%     runLOSO.m's calibration on this chain must reproduce
%     results/metrics/segment6_spo2_loso_metrics.csv's pooled MAE/RMSE/
%     Pearson_r. Stop if either parity check fails.
%   wavelet-on: waveletDenoise -> detrendSignal -> bandpassClean ->
%     ratioOfRatios, with R/G/B reassigned to the wavelet-denoised version
%     in place BEFORE both the filter chain and the DC term -- the same
%     "reassigned in place" convention estimateVitalsAndMorphology.m's own
%     header already documents for Branch 1/2 when useWaveletDenoise is
%     on, applied consistently here to the SpO2 chain it normally pins.
%
% validation/runLOSO.m is used unmodified for both chains -- it already
% refits spo2/calibrateSpO2.m fresh inside every fold, so passing it the
% wavelet-on R vector already satisfies "recalibrating in-fold, no reuse
% of pre-wavelet coefficients."
%
% Decision rule (fixed in PREREGISTRATION.md, not re-derived here): pooled
% N=112 LOSO MAE, paired per-subject |error|, two-sided Wilcoxon
% signed-rank test, alpha=0.05.
%
% Outputs (this experiment folder only):
%   results/s27_spo2_per_subject.csv   - per-subject R (both chains), SpO2_true
%   results/s27_spo2_wavelet_metrics.csv - MAE/RMSE/Pearson_r, both chains
%                                          + trivial baseline, pooled/UBFC/VIPL
%
% Invoke via: matlab -batch "startup; run('experiments/segment27_branch2_wavelet_evaluation/scripts/s27_spo2_wavelet.m')"

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(fileparts(fileparts(thisFileDir))));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
outRoot = fullfile(fileparts(thisFileDir), 'results');

if ~isfolder(outRoot)
    mkdir(outRoot);
end

% === Load the pooled 112-subject list, dataset labels, frozen R, and
% SpO2_true from the two frozen calibration CSVs -- exactly
% scripts/run_segment6_validation.m's own loading loop. ===
subjectID = {};
datasetLabel = {};
frozenR = [];
spo2True = [];

ubfcPath = fullfile(metricsRoot, 'segment5_dataset1_calibration.csv');
ubfcTable = readtable(ubfcPath);
for i = 1:height(ubfcTable)
    subjectID{end + 1} = char(extractTextS27(ubfcTable.subjectID, i)); %#ok<AGROW>
    datasetLabel{end + 1} = 'UBFC'; %#ok<AGROW>
    frozenR(end + 1) = ubfcTable.R_value(i); %#ok<AGROW>
    spo2True(end + 1) = ubfcTable.SpO2_true(i); %#ok<AGROW>
end
disp(['Loaded ' num2str(height(ubfcTable)) ' UBFC subjects from ' ubfcPath]);

viplPath = fullfile(metricsRoot, 'segment5_vipl_calibration.csv');
viplTable = readtable(viplPath);
for i = 1:height(viplTable)
    subjectID{end + 1} = char(extractTextS27(viplTable.subjectID, i)); %#ok<AGROW>
    datasetLabel{end + 1} = char(extractTextS27(viplTable.dataset, i)); %#ok<AGROW>
    frozenR(end + 1) = viplTable.R_value(i); %#ok<AGROW>
    spo2True(end + 1) = viplTable.SpO2_true(i); %#ok<AGROW>
end
disp(['Loaded ' num2str(height(viplTable)) ' VIPL subjects from ' viplPath]);

numSubjects = numel(subjectID);
disp(['Pooled: ' num2str(numSubjects) ' subjects.']);

if numSubjects ~= 112
    error('s27_spo2_wavelet:unexpectedPoolSize', 'Expected 112 pooled subjects (5 UBFC + 107 VIPL), found %d. Stopping -- PREREGISTRATION.md is fixed on N=112.', numSubjects);
end

% === Regenerate both chains from cached raw R/G/B. ===
R_preWavelet = nan(1, numSubjects);
R_wavelet = nan(1, numSubjects);
parityMismatch = {};

for i = 1:numSubjects
    sid = subjectID{i};
    rgbPath = fullfile(processedDataRoot, [sid '_rgb_traces.mat']);

    if ~isfile(rgbPath)
        error('s27_spo2_wavelet:missingCache', 'Cached rgb_traces.mat not found for %s: %s', sid, rgbPath);
    end

    rgbData = load(rgbPath);
    R0 = rgbData.R;
    G0 = rgbData.G;
    B0 = rgbData.B;
    fs = rgbData.fs;

    % --- Pre-wavelet chain (parity target). ---
    [Rd, ~] = detrendSignal(R0);
    [Gd, ~] = detrendSignal(G0);
    [Bd, ~] = detrendSignal(B0);
    [Rf, ~] = bandpassClean(Rd, fs);
    [Gf, ~] = bandpassClean(Gd, fs);
    [Bf, ~] = bandpassClean(Bd, fs);
    R_preWavelet(i) = ratioOfRatios(Rf, Gf, Bf, R0, G0, B0, fs);

    if ~strcmp(num2str(R_preWavelet(i)), num2str(frozenR(i)))
        parityMismatch{end + 1} = sprintf('%s: regenerated R=%s vs frozen R=%s', sid, num2str(R_preWavelet(i)), num2str(frozenR(i))); %#ok<AGROW>
    end

    % --- Wavelet-on chain: R/G/B reassigned to the wavelet-denoised
    % version in place, upstream of BOTH the filter chain and the DC term
    % ratioOfRatios uses -- same convention estimateVitalsAndMorphology.m
    % documents for Branch 1/2 when useWaveletDenoise is true. ---
    Rw = waveletDenoise(R0);
    Gw = waveletDenoise(G0);
    Bw = waveletDenoise(B0);
    [Rdw, ~] = detrendSignal(Rw);
    [Gdw, ~] = detrendSignal(Gw);
    [Bdw, ~] = detrendSignal(Bw);
    [Rfw, ~] = bandpassClean(Rdw, fs);
    [Gfw, ~] = bandpassClean(Gdw, fs);
    [Bfw, ~] = bandpassClean(Bdw, fs);
    R_wavelet(i) = ratioOfRatios(Rfw, Gfw, Bfw, Rw, Gw, Bw, fs);
end

if ~isempty(parityMismatch)
    disp('PARITY GATE FAILED -- regenerated pre-wavelet R does not match the frozen calibration CSVs:');
    for k = 1:numel(parityMismatch)
        disp(['  ' parityMismatch{k}]);
    end
    error('s27_spo2_wavelet:parityGateFailed', '%d/%d subjects failed the pre-wavelet R parity gate. Stopping per PREREGISTRATION.md guardrails.', numel(parityMismatch), numSubjects);
end
disp(['Parity gate (per-subject R): PASSED, all ' num2str(numSubjects) ' subjects.']);

perSubjectCsvPath = fullfile(outRoot, 's27_spo2_per_subject.csv');
perSubjectHeader = "subjectID,dataset,R_preWavelet,R_wavelet,SpO2_true";
writelines(perSubjectHeader, perSubjectCsvPath);
for i = 1:numSubjects
    rowLine = strjoin({subjectID{i}, datasetLabel{i}, num2str(R_preWavelet(i)), num2str(R_wavelet(i)), num2str(spo2True(i))}, ',');
    writelines(rowLine, perSubjectCsvPath, 'WriteMode', 'append');
end
disp(['Saved ' perSubjectCsvPath]);

% === LOSO, both chains -- runLOSO.m unmodified, refits calibrateSpO2.m
% fresh per fold either way. ===
resultsPre = runLOSO(subjectID, datasetLabel, R_preWavelet, spo2True);
resultsWav = runLOSO(subjectID, datasetLabel, R_wavelet, spo2True);

predPre = [resultsPre.SpO2_predicted];
predWav = [resultsWav.SpO2_predicted];
predBaseline = [resultsPre.SpO2_predicted_baseline]; % baseline is chain-independent (R ignored)
absErrPre = [resultsPre.abs_error];
absErrWav = [resultsWav.abs_error];
truthAll = spo2True;
datasetAll = datasetLabel;

metricsPooledPre = computeMetrics(predPre, truthAll);
metricsPooledWav = computeMetrics(predWav, truthAll);
metricsPooledBaseline = computeMetrics(predBaseline, truthAll);

disp(' ');
disp('=== Segment 27 Item B: pooled LOSO metrics ===');
disp(['Pre-wavelet: N=' num2str(metricsPooledPre.n) ', MAE=' num2str(metricsPooledPre.mae) ', RMSE=' num2str(metricsPooledPre.rmse) ', Pearson r=' num2str(metricsPooledPre.pearsonR)]);
disp(['Wavelet-on:  N=' num2str(metricsPooledWav.n) ', MAE=' num2str(metricsPooledWav.mae) ', RMSE=' num2str(metricsPooledWav.rmse) ', Pearson r=' num2str(metricsPooledWav.pearsonR)]);
disp(['Baseline:    N=' num2str(metricsPooledBaseline.n) ', MAE=' num2str(metricsPooledBaseline.mae) ', RMSE=' num2str(metricsPooledBaseline.rmse) ', Pearson r=' num2str(metricsPooledBaseline.pearsonR)]);

% --- Second parity check: pre-wavelet pooled metrics must reproduce
% results/metrics/segment6_spo2_loso_metrics.csv's pooled row. ---
existingMetricsPath = fullfile(metricsRoot, 'segment6_spo2_loso_metrics.csv');
existingMetricsTable = readtable(existingMetricsPath);
pooledRowIdx = find(strcmp(existingMetricsTable.scope, 'pooled'), 1);
if isempty(pooledRowIdx)
    error('s27_spo2_wavelet:missingPooledRow', 'No pooled row found in %s', existingMetricsPath);
end
existingMAE = existingMetricsTable.MAE(pooledRowIdx);
existingRMSE = existingMetricsTable.RMSE(pooledRowIdx);
existingPearsonR = existingMetricsTable.Pearson_r(pooledRowIdx);

% MAE/RMSE must match at num2str precision (same convention as the
% per-subject R parity gate above). Pearson_r gets a small absolute
% tolerance instead of exact num2str matching: it is a variance-normalized
% statistic, far more sensitive to sub-num2str-precision noise than
% MAE/RMSE, and the frozen segment6_spo2_loso_metrics.csv's own Pearson_r
% was itself computed from R values already rounded to ~5 significant
% digits by num2str when segment5_*_calibration.csv was written -- so a
% freshly regenerated, full-double-precision R feeding a weak (r~-0.38)
% correlation is EXPECTED to diverge from the text-rounded original by a
% small amount, even though the per-subject R values themselves already
% passed the num2str parity check above. The preregistered decision rule
% for Item B depends on MAE and a Wilcoxon test on |error|, not on
% Pearson_r, so this tolerance does not affect what the decision rule sees.
pearsonRTolerance = 0.001;
if ~strcmp(num2str(metricsPooledPre.mae), num2str(existingMAE)) || ...
   ~strcmp(num2str(metricsPooledPre.rmse), num2str(existingRMSE))
    error('s27_spo2_wavelet:losoParityGateFailed', ...
        'Regenerated pre-wavelet pooled LOSO MAE/RMSE (MAE=%s, RMSE=%s) do not match %s (MAE=%s, RMSE=%s). Stopping per PREREGISTRATION.md guardrails.', ...
        num2str(metricsPooledPre.mae), num2str(metricsPooledPre.rmse), ...
        existingMetricsPath, num2str(existingMAE), num2str(existingRMSE));
end
if abs(metricsPooledPre.pearsonR - existingPearsonR) > pearsonRTolerance
    error('s27_spo2_wavelet:losoParityGateFailed', ...
        'Regenerated pre-wavelet pooled LOSO Pearson_r (%s) differs from %s (%s) by more than the %.3g tolerance. Stopping per PREREGISTRATION.md guardrails.', ...
        num2str(metricsPooledPre.pearsonR), existingMetricsPath, num2str(existingPearsonR), pearsonRTolerance);
end
disp(['Parity gate (pooled LOSO metrics vs ' existingMetricsPath '): PASSED (MAE/RMSE exact; Pearson_r within ' num2str(pearsonRTolerance) ', regenerated=' num2str(metricsPooledPre.pearsonR) ' vs frozen=' num2str(existingPearsonR) ').']);

% === Per-dataset scopes, both chains + baseline. ===
scopes = {'UBFC', 'VIPL'};
metricsCsvPath = fullfile(outRoot, 's27_spo2_wavelet_metrics.csv');
metricsHeader = "chain,scope,N,MAE,RMSE,Pearson_r";
writelines(metricsHeader, metricsCsvPath);
writelines(strjoin({'preWavelet', 'pooled', num2str(metricsPooledPre.n), num2str(metricsPooledPre.mae), num2str(metricsPooledPre.rmse), num2str(metricsPooledPre.pearsonR)}, ','), metricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'wavelet', 'pooled', num2str(metricsPooledWav.n), num2str(metricsPooledWav.mae), num2str(metricsPooledWav.rmse), num2str(metricsPooledWav.pearsonR)}, ','), metricsCsvPath, 'WriteMode', 'append');
writelines(strjoin({'baseline', 'pooled', num2str(metricsPooledBaseline.n), num2str(metricsPooledBaseline.mae), num2str(metricsPooledBaseline.rmse), num2str(metricsPooledBaseline.pearsonR)}, ','), metricsCsvPath, 'WriteMode', 'append');

for s = 1:numel(scopes)
    scopeName = scopes{s};
    mask = strcmp(datasetAll, scopeName);

    mPre = computeMetrics(predPre(mask), truthAll(mask));
    mWav = computeMetrics(predWav(mask), truthAll(mask));
    mBase = computeMetrics(predBaseline(mask), truthAll(mask));

    writelines(strjoin({'preWavelet', scopeName, num2str(mPre.n), num2str(mPre.mae), num2str(mPre.rmse), num2str(mPre.pearsonR)}, ','), metricsCsvPath, 'WriteMode', 'append');
    writelines(strjoin({'wavelet', scopeName, num2str(mWav.n), num2str(mWav.mae), num2str(mWav.rmse), num2str(mWav.pearsonR)}, ','), metricsCsvPath, 'WriteMode', 'append');
    writelines(strjoin({'baseline', scopeName, num2str(mBase.n), num2str(mBase.mae), num2str(mBase.rmse), num2str(mBase.pearsonR)}, ','), metricsCsvPath, 'WriteMode', 'append');

    disp([scopeName ' -- pre-wavelet: N=' num2str(mPre.n) ', MAE=' num2str(mPre.mae) '; wavelet: MAE=' num2str(mWav.mae) '; baseline: MAE=' num2str(mBase.mae)]);
end
disp(['Saved ' metricsCsvPath]);

% === Decision: two-sided Wilcoxon signed-rank test on paired per-subject
% |error|, pooled N=112, alpha=0.05 (fixed in PREREGISTRATION.md). ===
maeDiffPP = metricsPooledPre.mae - metricsPooledWav.mae; % positive => wavelet has lower (better) MAE
[pValue, ~, statsWilcoxon] = signrank(absErrPre, absErrWav);

disp(' ');
disp('=== Segment 27 Item B: decision ===');
disp(['MAE(pre-wavelet) = ' num2str(metricsPooledPre.mae) ' pp, MAE(wavelet) = ' num2str(metricsPooledWav.mae) ' pp, diff (pre - wavelet) = ' num2str(maeDiffPP) ' pp']);
disp(['Wilcoxon signed-rank (paired |error|, pre-wavelet vs wavelet), two-sided: p = ' num2str(pValue)]);

if maeDiffPP >= 0.10 && pValue < 0.05
    verdict = 'WAVELET HELPS';
elseif maeDiffPP <= -0.10 && pValue < 0.05
    verdict = 'WAVELET HURTS';
else
    verdict = 'NO DEMONSTRATED DIFFERENCE';
end

disp(['VERDICT: ' verdict]);
disp(['Caveat (carried in from PREREGISTRATION.md): SpO2''s existing verdict is already weak (pooled Pearson r = ' num2str(metricsPooledPre.pearsonR) ', baseline MAE = ' num2str(metricsPooledBaseline.mae) ' pp). Beating a weak baseline is not evidence SpO2 is good; compare both arms against the trivial baseline above, not just against each other.']);

function textVal = extractTextS27(tableColumn, rowPos)
if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end
end
