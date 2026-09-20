% RUN_SEGMENT18_COLORSPACE_EVALUATION Segment 18 Task 2. Pooled + per-dataset
% MAE / RMSE / Pearson r (validation/computeMetrics.m) and median cross-ROI
% PLV for green, CIELab a*, YCbCr Cb, YCbCr Cr, plus honest per-subject
% regression counts vs. green. Reads results/metrics/segment18_colorspace_ablation.csv
% (written by run_segment18_colorspace_ablation_batch.m); reprocesses no video.
%
% Style mirrors run_segment8_action2_promote_wavelet_default.m's metrics
% section. Writes NOTHING that production reads (segment6_hr_pooled_metrics.csv
% is untouched) -- this segment is a diagnostic ablation only.
%
% Outputs:
%   results/metrics/segment18_colorspace_pooled_metrics.csv
%   results/metrics/segment18_colorspace_per_subject_vs_green.csv

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
addpath(genpath(fullfile(fileparts(thisFileDir), 'src')));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
if ~exist('csvSuffix', 'var'), csvSuffix = ''; end  % '' = main pool, '_motion' = VIPL v2 pool

T = readtable(fullfile(metricsRoot, ['segment18_colorspace_ablation' csvSuffix '.csv']), 'TextType', 'string');
fprintf('Loaded %d subjects.\n', height(T));

% --- Regression check: fresh G HR must equal the existing green baseline ---
ubfcB = readtable(fullfile(metricsRoot, 'segment4_hr_summary.csv'), 'TextType', 'string');
viplB = readtable(fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv'), 'TextType', 'string');
baseId = [ubfcB.subjectID; viplB.subjectID];
baseGreen = [ubfcB.HR_green; viplB.HR_green];
[~, ia, ib] = intersect(T.subjectID, baseId);
greenDiff = abs(T.HR_green(ia) - baseGreen(ib));
fprintf('Green regression check vs segment4 baseline HR_green: %d/%d subjects match within 1e-3 bpm (max diff %.6f).\n', ...
    sum(greenDiff < 1e-3), numel(greenDiff), max(greenDiff));

valid = ~isnan(T.HR_groundtruth) & ~isnan(T.HR_green) & ~isnan(T.HR_labA) & ~isnan(T.HR_ycbcrCb) & ~isnan(T.HR_ycbcrCr);
fprintf('Valid (non-NaN GT and all four HR): %d of %d.\n', sum(valid), height(T));
V = T(valid, :);

channels = {'green', 'labA', 'ycbcrCb', 'ycbcrCr'};
hrCols = {'HR_green', 'HR_labA', 'HR_ycbcrCb', 'HR_ycbcrCr'};
plvCols = {'PLV_green', 'PLV_labA', 'PLV_ycbcrCb', 'PLV_ycbcrCr'};
scopes = {'pooled', 'UBFC', 'VIPL'};

pooledCsv = fullfile(metricsRoot, ['segment18_colorspace_pooled_metrics' csvSuffix '.csv']);
writelines("channel,scope,N,MAE,RMSE,Pearson_r,median_PLV,mean_PLV", pooledCsv);

for chPos = 1:numel(channels)
    for scopePos = 1:numel(scopes)
        if strcmp(scopes{scopePos}, 'pooled')
            mask = true(height(V), 1);
        else
            mask = V.dataset == scopes{scopePos};
        end
        m = computeMetrics(V.(hrCols{chPos})(mask), V.HR_groundtruth(mask));
        plvVals = V.(plvCols{chPos})(mask);
        line = strjoin({channels{chPos}, scopes{scopePos}, num2str(m.n), num2str(m.mae, '%.4f'), num2str(m.rmse, '%.4f'), num2str(m.pearsonR, '%.4f'), ...
            num2str(median(plvVals, 'omitnan'), '%.4f'), num2str(mean(plvVals, 'omitnan'), '%.4f')}, ',');
        writelines(line, pooledCsv, 'WriteMode', 'append');
        fprintf('%-8s %-6s N=%3d MAE=%7.3f RMSE=%7.3f r=%6.3f medPLV=%.3f\n', channels{chPos}, scopes{scopePos}, m.n, m.mae, m.rmse, m.pearsonR, median(plvVals, 'omitnan'));
    end
end

% --- Per-subject regressions vs. green (abs HR error) ---
errGreen = abs(V.HR_green - V.HR_groundtruth);
perSubj = table(V.subjectID, V.dataset, V.HR_groundtruth, errGreen, 'VariableNames', {'subjectID', 'dataset', 'HR_groundtruth', 'err_green'});
fprintf('\nPer-subject abs-error change vs. green (positive delta = WORSE than green), N=%d:\n', height(V));
for chPos = 2:numel(channels)
    err = abs(V.(hrCols{chPos}) - V.HR_groundtruth);
    delta = err - errGreen;
    perSubj.(['err_' channels{chPos}]) = err;
    perSubj.(['delta_' channels{chPos}]) = delta;
    perSubj.(['dPLV_' channels{chPos}]) = V.(plvCols{chPos}) - V.PLV_green;
    nBetter = sum(delta < -1);
    nWorse = sum(delta > 1);
    nSevere = sum(delta > 10);
    nSevereBetter = sum(delta < -10);
    pv = NaN;
    try
        pv = signrank(err, errGreen);
    catch
    end
    fprintf('%-8s better(>1bpm)=%d worse(>1bpm)=%d | severe worse(>10)=%d severe better(>10)=%d | median delta=%.2f | signrank p=%.4f\n', ...
        channels{chPos}, nBetter, nWorse, nSevere, nSevereBetter, median(delta), pv);
    dPlv = V.(plvCols{chPos}) - V.PLV_green;
    fprintf('         PLV higher than green in %d/%d subjects (median dPLV=%+.3f)\n', sum(dPlv > 0), numel(dPlv), median(dPlv, 'omitnan'));
    worstIdx = find(delta > 10);
    for k = 1:numel(worstIdx)
        fprintf('           severe regression: %s GT=%.1f green=%.1f %s=%.1f\n', V.subjectID(worstIdx(k)), V.HR_groundtruth(worstIdx(k)), V.HR_green(worstIdx(k)), channels{chPos}, V.(hrCols{chPos})(worstIdx(k)));
    end
end

writetable(perSubj, fullfile(metricsRoot, ['segment18_colorspace_per_subject_vs_green' csvSuffix '.csv']));

% --- Does higher PLV track lower HR error, per channel? (ground-truth-free
% proxy sanity check: Spearman between a subject's PLV and its abs HR error) ---
fprintf('\nSpearman(PLV, abs HR error) per channel (negative = PLV tracks fidelity):\n');
for chPos = 1:numel(channels)
    err = abs(V.(hrCols{chPos}) - V.HR_groundtruth);
    rho = corr(V.(plvCols{chPos}), err, 'Type', 'Spearman', 'Rows', 'complete');
    fprintf('  %-8s rho=%+.3f\n', channels{chPos}, rho);
end

% --- Oracle-free context: how often does each channel land on a harmonic
% (2x or 0.5x GT within 8%) -- the known failure mode of this pipeline ---
fprintf('\nHarmonic-lock count (HR within 8%% of 2xGT or 0.5xGT):\n');
for chPos = 1:numel(channels)
    hrv = V.(hrCols{chPos});
    gt = V.HR_groundtruth;
    isHarm = abs(hrv - 2 * gt) < 0.08 * 2 * gt | abs(hrv - 0.5 * gt) < 0.08 * 0.5 * gt;
    fprintf('  %-8s %d/%d\n', channels{chPos}, sum(isHarm), numel(hrv));
end
