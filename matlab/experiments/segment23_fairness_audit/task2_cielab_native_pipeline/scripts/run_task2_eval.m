% RUN_TASK2_EVAL Segment 23 Task 2 evaluation on the cached seg23t2_*.mat (run after run_task2_extract.m).
% Ablation ladder so the effect of each NATIVE component is separable (all reported):
%  A0 originally tested (Seg 18): forehead box, per-pixel rgb2lab/rgb2ycbcr then mean          [regression-checked vs Seg 18 CSV]
%  A1 forehead box + paper's sum-normalised Lab (colour transform ONLY)
%  A2 + uniformity-ranked ROI with KLT translation (no frame pruning)
%  A3 + 30%-loss frame pruning (gaps linearly interpolated)  = FULL native pipeline
%  A3w = A3 with the project's waveletDenoise pre-step (production-style tuning symmetry)
% Controls on the same native ROI: GREEN, and production CHROM/POS (wavelet default) -- is ROI/pruning the lever, or colour space?
% Every arm ends in detrendSignal -> bandpassClean -> fftHeartRate (whole-clip), identical to Seg 18's chain.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src'));
outDir = fullfile(here, '..', 'results'); proc = fullfile(root, 'data', 'processed');
T = s23_pool(true); N = height(T);
arms = {'A0_box_perpixel','A1_box_sumnormLab','A2_uniformROI_KLT','A3_FULL_native','A3w_native_wavelet'};
ch = {'a','Cb','Cr'};
HR = nan(N, numel(arms), 3); HRgreenBox = nan(N,1); HRgreenNative = nan(N,1); HRchromNative = nan(N,1); HRposNative = nan(N,1);
HRchromProd = nan(N,1); HRposProd = nan(N,1); prunedFrac = nan(N,1); nInit = nan(N,1); fsAll = nan(N,1);
pulses = struct();
hr = @(x, fs) fftHeartRate(bandpassClean(detrendSignal(x), fs), fs);
for i = 1:N
    id = char(T.subjectID(i));
    try
        d = load(fullfile(proc, ['seg23t2_' id '.mat'])); fs = d.fs; fsAll(i) = fs;
        prunedFrac(i) = mean(~d.keep); nInit(i) = numel(d.initFrames);
        sig = cell(numel(arms), 3);
        sig(1, :) = {d.boxLab(1, :), d.boxLab(2, :), d.boxLab(3, :)};
        [a, cb, cr] = labFromSumNorm(d.boxRGB(1, :), d.boxRGB(2, :), d.boxRGB(3, :)); sig(2, :) = {a, cb, cr};
        rr = d.roiRGB; [a, cb, cr] = labFromSumNorm(rr(1, :), rr(2, :), rr(3, :)); sig(3, :) = {a, cb, cr};
        k = d.keep; if nnz(k) < 10, k = true(size(k)); end
        fill = @(x) interp1(find(k), x(k), 1:numel(x), 'linear', 'extrap');
        rf = [fill(rr(1, :)); fill(rr(2, :)); fill(rr(3, :))];
        [a, cb, cr] = labFromSumNorm(rf(1, :), rf(2, :), rf(3, :)); sig(4, :) = {a, cb, cr};
        [a, cb, cr] = labFromSumNorm(waveletDenoise(rf(1, :)), waveletDenoise(rf(2, :)), waveletDenoise(rf(3, :))); sig(5, :) = {a, cb, cr};
        for m = 1:numel(arms)
            for c = 1:3
                HR(i, m, c) = hr(sig{m, c}, fs);
            end
        end
        pulses.(matlab.lang.makeValidName(id)) = struct('fs', fs, 'A0_a', bandpassClean(detrendSignal(sig{1,1}), fs), 'A0_Cb', bandpassClean(detrendSignal(sig{1,2}), fs), 'A0_Cr', bandpassClean(detrendSignal(sig{1,3}), fs), ...
            'A3_a', bandpassClean(detrendSignal(sig{4,1}), fs), 'A3_Cb', bandpassClean(detrendSignal(sig{4,2}), fs), 'A3_Cr', bandpassClean(detrendSignal(sig{4,3}), fs));
        HRgreenBox(i) = hr(d.boxRGB(2, :), fs); HRgreenNative(i) = hr(rf(2, :), fs);
        cn = s23_chain(rf(1, :), rf(2, :), rf(3, :), fs, true); HRchromNative(i) = fftHeartRate(cn.chrom, fs); HRposNative(i) = fftHeartRate(cn.pos, fs);
        cp = s23_chain(d.boxRGB(1, :), d.boxRGB(2, :), d.boxRGB(3, :), fs, true); HRchromProd(i) = fftHeartRate(cp.chrom, fs); HRposProd(i) = fftHeartRate(cp.pos, fs);
    catch err
        fprintf('%s FAILED: %s\n', id, err.message);
    end
end
save(fullfile(outDir, 'task2_pulses_for_task5.mat'), 'pulses', '-v7.3');
hrTab = T;
for m = 1:numel(arms), for c = 1:3, hrTab.(sprintf('%s_%s', arms{m}, ch{c})) = HR(:, m, c); end, end
hrTab.greenBox = HRgreenBox; hrTab.greenNativeROI = HRgreenNative; hrTab.chromNativeROI = HRchromNative; hrTab.posNativeROI = HRposNative;
hrTab.chromProd = HRchromProd; hrTab.posProd = HRposProd; hrTab.prunedFrac = prunedFrac; hrTab.nInit = nInit; hrTab.fs = fsAll;
writetable(hrTab, fullfile(outDir, 'task2_per_subject.csv'));
rows = {};
for m = 1:numel(arms), for c = 1:3, rows{end+1} = s23_poolTable(HR(:, m, c), T, sprintf('%s [%s]', arms{m}, ch{c})); end, end %#ok<AGROW>
rows{end+1} = s23_poolTable(HRgreenBox, T, 'GREEN forehead box'); rows{end+1} = s23_poolTable(HRgreenNative, T, 'GREEN native ROI');
rows{end+1} = s23_poolTable(HRchromProd, T, 'CHROM production (box)'); rows{end+1} = s23_poolTable(HRposProd, T, 'POS production (box)');
rows{end+1} = s23_poolTable(HRchromNative, T, 'CHROM on native ROI'); rows{end+1} = s23_poolTable(HRposNative, T, 'POS on native ROI');
S = vertcat(rows{:}); writetable(S, fullfile(outDir, 'task2_summary_by_pool.csv'));
% regression check vs Segment 18 (arm A0)
s18 = readtable(fullfile(root, 'results', 'metrics', 'segment18_colorspace_ablation.csv'), 'TextType', 'string');
[tf, loc] = ismember(s18.subjectID, T.subjectID);
fprintf('REGRESSION vs Seg18 A0: a* max|diff|=%.4f  Cb %.4f  Cr %.4f  (n=%d)\n', max(abs(s18.HR_labA(tf) - HR(loc(tf), 1, 1)), [], 'omitnan'), max(abs(s18.HR_ycbcrCb(tf) - HR(loc(tf), 1, 2)), [], 'omitnan'), max(abs(s18.HR_ycbcrCr(tf) - HR(loc(tf), 1, 3)), [], 'omitnan'), nnz(tf));
mk = T.pool ~= "VIPL_v2_motion";
fprintf('KLT pruning: median pruned fraction %.3f, subjects with >20%% pruned: %d, >50%%: %d\n', median(prunedFrac, 'omitnan'), nnz(prunedFrac > 0.2), nnz(prunedFrac > 0.5));
for cmp = {'chromProd', HRchromProd; 'posProd', HRposProd}'
    for m = [1 4]
        d = abs(HR(mk, m, 1) - T.gt(mk)) - abs(cmp{2}(mk) - T.gt(mk)); d = d(isfinite(d));
        fprintf('a* arm %s vs %s (MAIN_112): better>1 %d worse>1 %d severe-worse>10 %d signrank p=%.4f\n', arms{m}, cmp{1}, nnz(d < -1), nnz(d > 1), nnz(d > 10), signrank(d));
    end
end
disp(S(S.pool == "MAIN_112" | S.pool == "VIPL_v2_motion", :));
