% RUN_SEGMENT22_2SR_EVALUATION Segment 22 Tasks 1-3, 5: production CHROM/POS
% (wavelet default) on the v2 motion pool (Tier 0), 2SR
% (pulseextraction/spatialSubspaceRotation.m) on both pools, stratified.
%
% Reads only data/processed/seg22cov_<id>.mat (run
% run_segment22_extract_covariance_batch.m first). Production chain for
% CHROM/POS is exactly run_segment8_task4_wavelet_ablation_batch.m's
% (waveletDenoise -> detrend -> bandpass -> combine -> bandpass -> fft); the
% main-pool result is checked against that batch's saved HR_*_wavelet.
%
% HELD-OUT DESIGN: 2SR's stride is a tunable. It is chosen ONLY on the "dev"
% set = main-pool subjects whose person does not appear in the v2 pool
% (so no person is both tuned on and evaluated on). "Held-out" = the 20 v2
% subjects + those same 20 persons' v1 rows. Stride grid is fixed in advance.
%
% Outputs (results/metrics/):
%   segment22_per_subject.csv, segment22_stratified_summary.csv,
%   segment22_stride_selection.csv

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
addpath(genpath(fullfile(fileparts(thisFileDir), 'src')));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
procRoot = fullfile(projectRoot, 'data', 'processed');

main = readtable(fullfile(metricsRoot, 'segment8_task4_wavelet_ablation.csv'), 'TextType', 'string');
mot = readtable(fullfile(metricsRoot, 'segment6_task_n_region_hr_summary.csv'), 'TextType', 'string');
mot = mot(mot.scenario == "v2_motion", :);

ids = [main.subjectID; mot.subjectID];
gt = [main.HR_groundtruth; mot.HR_groundtruth];
prodWaveChrom = [main.HR_chrom_wavelet; nan(height(mot), 1)];
prodWavePos = [main.HR_pos_wavelet; nan(height(mot), 1)];
pool = [repmat("main", height(main), 1); repmat("motion_v2", height(mot), 1)];
N = numel(ids);

% Grid: 0 = 1-frame stride (the reference implementation's own setting; ADDED
% after the first run showed a comb-filter failure at 1 s -- disclosed in the
% Segment 22 doc). Selection is on dev only, so held-out stays clean.
strideSecGrid = [0, 0.5, 1.0, 2.0];
nS = numel(strideSecGrid);

hrChrom = nan(N, 1); hrPos = nan(N, 1); hrLgi = nan(N, 1); hr2sr = nan(N, nS);
fsAll = nan(N, 1); theta = nan(N, 1);
for k = 1:N
    id = char(ids(k));
    d = load(fullfile(procRoot, ['seg22cov_' id '.mat']));
    fs = d.fs; fsAll(k) = fs;
    R = d.R; G = d.G; B = d.B;
    [~, ~, ~, ~, theta(k)] = cpaceProjection(R, G, B);

    Rw = waveletDenoise(R); Gw = waveletDenoise(G); Bw = waveletDenoise(B);
    [Rd, ~] = detrendSignal(Rw); [Gd, ~] = detrendSignal(Gw); [Bd, ~] = detrendSignal(Bw);
    [Rf, ~] = bandpassClean(Rd, fs); [Gf, ~] = bandpassClean(Gd, fs); [Bf, ~] = bandpassClean(Bd, fs);
    hrChrom(k) = fftHeartRate(bandpassClean(chromCombine(Rf, Gf, Bf, Rw, Gw, Bw), fs), fs);
    hrPos(k) = fftHeartRate(bandpassClean(posCombine(Rf, Gf, Bf, fs, Rw, Gw, Bw), fs), fs);

    [Ld, ~] = detrendSignal(lgiProjection(Rw, Gw, Bw));
    hrLgi(k) = fftHeartRate(bandpassClean(Ld, fs), fs);

    for s = 1:nS
        try
            p = spatialSubspaceRotation(d.Cseq, fs, max(1, round(strideSecGrid(s) * fs)), 3);
            hr2sr(k, s) = fftHeartRate(bandpassClean(p, fs), fs);
        catch err
            fprintf('%s stride %.1f: %s\n', id, strideSecGrid(s), err.message);
        end
    end
end

% --- regression check of the re-derived production chain (main pool) ---
mm = pool == "main";
fprintf('Production check (main pool): max|CHROM diff|=%.4f  max|POS diff|=%.4f bpm\n', ...
    max(abs(hrChrom(mm) - prodWaveChrom(mm))), max(abs(hrPos(mm) - prodWavePos(mm))));

% --- person / dev / held-out flags ---
person = nan(N, 1);
for k = 1:N
    t = regexp(char(ids(k)), '^VIPL_p(\d+)_', 'tokens', 'once');
    if ~isempty(t), person(k) = str2double(t{1}); end
end
v2persons = person(pool == "motion_v2");
isV2Person = ismember(person, v2persons);
isDev = pool == "main" & ~isV2Person;
isHeld = ~isDev;

% --- pick stride on dev only ---
devMae = nan(1, nS);
for s = 1:nS
    devMae(s) = mean(abs(hr2sr(isDev, s) - gt(isDev)), 'omitnan');
end
[~, bestS] = min(devMae);
fprintf('Stride selection on dev set (N=%d): ', nnz(isDev)); fprintf('%.1fs->MAE %.2f  ', [strideSecGrid; devMae]); fprintf('\n=> selected %.1f s\n', strideSecGrid(bestS));
writetable(table(strideSecGrid(:), devMae(:), 'VariableNames', {'strideSec', 'devMAE'}), fullfile(metricsRoot, 'segment22_stride_selection.csv'));
hrSel = hr2sr(:, bestS);
hrDef = hr2sr(:, strideSecGrid == 1.0);

% --- strata ---
src = strings(N, 1);
for k = 1:N
    id = char(ids(k));
    if isnan(person(k)), src(k) = "UBFC"; elseif contains(id, '_source2'), src(k) = "VIPL_source2_phone"; else, src(k) = "VIPL_source1_webcam"; end
end
scen = strings(N, 1);
for k = 1:N
    if isnan(person(k)), scen(k) = "ubfc_static"; elseif contains(char(ids(k)), '_v2_'), scen(k) = "v2_motion"; else, scen(k) = "v1_stable"; end
end
tert = quantile(theta(pool == "main"), [1/3 2/3]);
thetaBin = strings(N, 1);
thetaBin(theta < tert(1)) = sprintf('theta_low(<%.1f)', tert(1));
thetaBin(theta >= tert(1) & theta < tert(2)) = sprintf('theta_mid(%.1f-%.1f)', tert(1), tert(2));
thetaBin(theta >= tert(2)) = sprintf('theta_high(>=%.1f)', tert(2));
fpsBin = repmat("fps_ge22", N, 1); fpsBin(fsAll < 22) = "fps_lt22";
fprintf('fs distribution: min %.1f, <22: %d, >=22: %d\n', min(fsAll), nnz(fsAll < 22), nnz(fsAll >= 22));

% --- per-subject table ---
T = table(ids, pool, scen, src, thetaBin, theta, fsAll, fpsBin, isDev, gt, hrChrom, hrPos, hrSel, hrDef, hrLgi, ...
    abs(hrChrom - gt), abs(hrPos - gt), abs(hrSel - gt), abs(hrDef - gt), abs(hrLgi - gt), ...
    'VariableNames', {'subjectID','pool','scenario','source','thetaBin','thetaDeg','fs','fpsBin','isDev','HR_gt','HR_chrom','HR_pos','HR_2sr_sel','HR_2sr_1s','HR_lgi','err_chrom','err_pos','err_2sr_sel','err_2sr_1s','err_lgi'});
writetable(T, fullfile(metricsRoot, 'segment22_per_subject.csv'));

% --- stratified summaries ---
rows = {};
preds = {hrChrom, hrPos, hrSel, hrDef, hrLgi};
rows = addRows(rows, preds, gt, 'all', 'main_pool_N112', pool == "main");
rows = addRows(rows, preds, gt, 'held', 'heldout_all', isHeld);
rows = addRows(rows, preds, gt, 'held', 'dev_all', isDev);
for sc = ["ubfc_static", "v1_stable", "v2_motion"], rows = addRows(rows, preds, gt, 'scenario', char(sc), scen == sc); end
rows = addRows(rows, preds, gt, 'scenario', 'v1_stable_v2persons_only', scen == "v1_stable" & isV2Person);
for s2 = unique(src)', rows = addRows(rows, preds, gt, 'dataset_source', char(s2), src == s2); end
for tb = unique(thetaBin)', rows = addRows(rows, preds, gt, 'skin_angle', char(tb), thetaBin == tb); for sc = ["v1_stable","v2_motion"], rows = addRows(rows, preds, gt, ['skin_angle_x_' char(sc)], char(tb), thetaBin == tb & scen == sc); end, end
for fb = unique(fpsBin)', rows = addRows(rows, preds, gt, 'fps', char(fb), fpsBin == fb); for sc = ["v1_stable","v2_motion"], rows = addRows(rows, preds, gt, ['fps_x_' char(sc)], char(fb), fpsBin == fb & scen == sc); end, end
S = cell2table(rows, 'VariableNames', {'stratType','stratum','method','N','MAE','medianAbsErr','RMSE','pearsonR'});
writetable(S, fullfile(metricsRoot, 'segment22_stratified_summary.csv'));
disp(S);

% --- per-subject regressions vs production ---
cands = {'2SR_sel', hrSel; 'LGIproj', hrLgi};
for ci = 1:size(cands, 1)
for cmp = {'POS', 'CHROM'}
    base = strcmp(cmp{1}, 'POS') * abs(hrPos - gt) + strcmp(cmp{1}, 'CHROM') * abs(hrChrom - gt);
    for sc = ["v1_stable", "v2_motion", "ubfc_static"]
        m = scen == sc; dlt = abs(cands{ci, 2}(m) - gt(m)) - base(m);
        p = NaN; if nnz(m) >= 6, p = signrank(dlt); end
        fprintf('%s vs %s, %s (N=%d): better>1 %d, worse>1 %d, severe worse>10 %d, severe better>10 %d, signrank p=%.3f, median delta=%.2f\n', ...
            cands{ci, 1}, cmp{1}, sc, nnz(m), nnz(dlt < -1), nnz(dlt > 1), nnz(dlt > 10), nnz(dlt < -10), p, median(dlt));
    end
end
end

function rows = addRows(rows, preds, gt, stratType, stratName, mask)
if nnz(mask) < 1, return, end
names = {'CHROM','POS','2SR_sel','2SR_1s','LGIproj'};
for m = 1:5
    met = computeMetrics(preds{m}(mask), gt(mask));
    e = abs(preds{m}(mask) - gt(mask));
    rows(end + 1, :) = {stratType, stratName, names{m}, met.n, met.mae, median(e, 'omitnan'), met.rmse, met.pearsonR};
end
end
