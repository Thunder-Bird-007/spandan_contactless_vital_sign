% RUN_TASK3_EVAL Segment 23 Task 3: 2SR (Wang, Stuijk & de Haan 2016) restricted to REAL skin pixels.
% PRIMARY stride = the one Segment 22 selected on its dev set (read from segment22_stride_selection.csv), so the ONLY thing
% that changes vs Segment 22's 2SR row is the pixel set. The whole stride grid is reported too (not selected on).
% Pixel sets: fbUnmask (Seg 22 parity) | fbMask | faceUnmask | faceMask. Same-pixel CHROM/POS (wavelet default) on each
% set's mean RGB is reported so masking's effect on the incumbents is visible (a mask could help CHROM/POS as well).
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src'));
outDir = fullfile(here, '..', 'results'); proc = fullfile(root, 'data', 'processed');
T = s23_pool(true); N = height(T);
sel = readtable(fullfile(root, 'results', 'metrics', 'segment22_stride_selection.csv')); [~, bi] = min(sel.devMAE); strideSel = sel.strideSec(bi);
grid = [0 0.5 1.0 2.0]; if ~any(grid == strideSel), grid(end + 1) = strideSel; end
sets = {'fbUnmask', 'fbMask', 'faceUnmask', 'faceMask'};
HR2 = nan(N, 4, numel(grid)); HR2w = nan(N, 4); HRc = nan(N, 4); HRp = nan(N, 4);
skinFb = nan(N, 1); skinFace = nan(N, 1); fbFb = nan(N, 1); fbFace = nan(N, 1);
for i = 1:N
    id = char(T.subjectID(i));
    try
        d = load(fullfile(proc, ['seg23t3_' id '.mat'])); fs = d.fs;
        skinFb(i) = mean(d.fbMask.skinFrac); skinFace(i) = mean(d.faceMask.skinFrac);
        fbFb(i) = mean(d.fbMask.fallback); fbFace(i) = mean(d.faceMask.fallback);
        for s = 1:4
            S = d.(sets{s});
            for g = 1:numel(grid)
                try
                    p = spatialSubspaceRotation(S.C, fs, max(1, round(grid(g) * fs)), 3);
                    HR2(i, s, g) = fftHeartRate(bandpassClean(p, fs), fs);
                    if grid(g) == strideSel, HR2w(i, s) = fftHeartRate(bandpassClean(waveletDenoise(p), fs), fs); end
                catch
                end
            end
            cc = s23_chain(S.rgb(1, :), S.rgb(2, :), S.rgb(3, :), fs, true); HRc(i, s) = fftHeartRate(cc.chrom, fs); HRp(i, s) = fftHeartRate(cc.pos, fs);
        end
    catch err
        fprintf('%s FAILED: %s\n', id, err.message);
    end
end
gsel = find(grid == strideSel, 1);
per = T; per.skinFracForeheadBox = skinFb; per.skinFracFaceBox = skinFace; per.fbFallbackFrac = fbFb; per.faceFallbackFrac = fbFace;
for s = 1:4, per.(['twoSR_' sets{s}]) = HR2(:, s, gsel); per.(['twoSRwavelet_' sets{s}]) = HR2w(:, s); per.(['chrom_' sets{s}]) = HRc(:, s); per.(['pos_' sets{s}]) = HRp(:, s); end
writetable(per, fullfile(outDir, 'task3_per_subject.csv'));
rows = {};
for s = 1:4
    rows{end+1} = s23_poolTable(HR2(:, s, gsel), T, sprintf('2SR %s stride=%.1fs [PRIMARY]', sets{s}, strideSel)); %#ok<AGROW>
    rows{end+1} = s23_poolTable(HR2w(:, s), T, sprintf('2SR+waveletOut %s', sets{s})); %#ok<AGROW>
    for g = 1:numel(grid), if g ~= gsel, rows{end+1} = s23_poolTable(HR2(:, s, g), T, sprintf('2SR %s stride=%.1fs (grid, not selected)', sets{s}, grid(g))); end, end %#ok<AGROW>
    rows{end+1} = s23_poolTable(HRc(:, s), T, ['CHROM on ' sets{s}]); rows{end+1} = s23_poolTable(HRp(:, s), T, ['POS on ' sets{s}]); %#ok<AGROW>
end
Sm = vertcat(rows{:}); writetable(Sm, fullfile(outDir, 'task3_summary_by_pool.csv'));
s22 = readtable(fullfile(root, 'results', 'metrics', 'segment22_per_subject.csv'), 'TextType', 'string');
[tf, loc] = ismember(s22.subjectID, T.subjectID);
fprintf('REGRESSION vs Seg22 2SR_sel (fbUnmask, stride %.1fs): max|diff|=%.4f bpm (n=%d)\n', strideSel, max(abs(s22.HR_2sr_sel(tf) - HR2(loc(tf), 1, gsel)), [], 'omitnan'), nnz(tf));
fprintf('Forehead-box skin fraction (mask keeps): median %.2f, IQR [%.2f %.2f]; subjects with >30%% non-skin: %d/%d; face-box median %.2f\n', median(skinFb, 'omitnan'), quantile(skinFb, .25), quantile(skinFb, .75), nnz(skinFb < 0.7), nnz(isfinite(skinFb)), median(skinFace, 'omitnan'));
mk = T.pool ~= "VIPL_v2_motion"; v2 = ~mk;
for s = 2:4
    for scope = {'MAIN_112', mk; 'V2', v2}'
        d = abs(HR2(scope{2}, s, gsel) - T.gt(scope{2})) - abs(HR2(scope{2}, 1, gsel) - T.gt(scope{2})); d = d(isfinite(d));
        fprintf('2SR %s vs fbUnmask [%s]: better>1 %d worse>1 %d severe-worse %d signrank p=%.4f\n', sets{s}, scope{1}, nnz(d < -1), nnz(d > 1), nnz(d > 10), signrank(d));
    end
end
[rho, pr] = corr(1 - skinFb(mk), abs(HR2(mk, 1, gsel) - T.gt(mk)) - abs(HR2(mk, 2, gsel) - T.gt(mk)), 'Type', 'Spearman', 'Rows', 'complete');
fprintf('Spearman(non-skin fraction in forehead box, 2SR improvement from masking) = %.3f (p=%.4f)\n', rho, pr);
disp(Sm(Sm.pool == "MAIN_112" | Sm.pool == "VIPL_v2_motion", :));
