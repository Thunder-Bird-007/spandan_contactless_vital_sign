% RUN_TASK5_ESTIMATOR_SWAP Segment 23 Task 5: combiner x estimator matrix. Every combiner's pulse trace is rebuilt
% "as originally tested" (each with its own original pre-processing chain, flagged in the table) from cached data --
% no ROI extraction here; the a*/Cb/Cr, native-a* and skin-masked-2SR traces are the byproducts of Tasks 2/3.
% Estimators: E1 whole-clip fftHeartRate | E2 naive windowedHeartRate (mean of per-window tallest peaks, 10 s/50%)
%   | E3 RAKF native (Task 7 fix: Eq.12 exponent, beta=1, R0=25, Q=0.03) | extras: E4 RAKF original (division),
%   E5 LGI paper's own read-out (256-sample/90% FFT peak-pick, 0.5-2 Hz, Task 4), E6 state-space tracker (Task 4).
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', '..', 'task7_rakf_native_form', 'src')); addpath(fullfile(here, '..', '..', 'task4_lgi_state_space_tracker', 'src'));
outDir = fullfile(here, '..', 'results'); proc = fullfile(root, 'data', 'processed');
T = s23_pool(true); N = height(T);
sel = readtable(fullfile(root, 'results', 'metrics', 'segment22_stride_selection.csv')); [~, bi] = min(sel.devMAE); strideSel = sel.strideSec(bi);
t2 = struct(); if isfile(fullfile(root, 'matlab', 'experiments', 'segment23_fairness_audit', 'task2_cielab_native_pipeline', 'results', 'task2_pulses_for_task5.mat'))
    t2 = load(fullfile(root, 'matlab', 'experiments', 'segment23_fairness_audit', 'task2_cielab_native_pipeline', 'results', 'task2_pulses_for_task5.mat')); end
combNames = {'CHROM (prod, wavelet)','POS (prod, wavelet)','CHROM (no wavelet)','POS (no wavelet)','GREEN (Seg4/18 form)', ...
    'cPACE Stage1+CHROM (global q)','cPACE Stage1+POS (global q)','cPACE Full bw0.30','cPACE Full bw0.15', ...
    'CIELab a* (orig, Seg18)','YCbCr Cb (orig, Seg18)','YCbCr Cr (orig, Seg18)','2SR (Seg22, forehead box)','LGI projection (Seg22)', ...
    'a* NATIVE (Task2)','Cb NATIVE (Task2)','Cr NATIVE (Task2)','2SR skin-masked forehead (Task3)','2SR skin-masked face (Task3)'};
estNames = {'E1 whole-clip fft','E2 naive windowed','E3 RAKF native (exp, b=1)','E4 RAKF original (division)','E5 LGI-paper readout 256/90%','E6 state-space tracker'};
nC = numel(combNames); nE = numel(estNames);
HR = nan(N, nC, nE);
for i = 1:N
    id = char(T.subjectID(i));
    try
        [R, G, B, fs] = s23_loadRGB(T.subjectID(i), T.pool(i));
        pulses = cell(1, nC);
        c1 = s23_chain(R, G, B, fs, true); c0 = s23_chain(R, G, B, fs, false);
        pulses{1} = c1.chrom; pulses{2} = c1.pos; pulses{3} = c0.chrom; pulses{4} = c0.pos;
        pulses{5} = c0.green;
        [Rc, Gc, Bc] = cpaceProjection(R, G, B);
        [a, ~] = detrendSignal(Rc); [b, ~] = detrendSignal(Gc); [c, ~] = detrendSignal(Bc);
        [a, ~] = bandpassClean(a, fs); [b, ~] = bandpassClean(b, fs); [c, ~] = bandpassClean(c, fs);
        pulses{6} = bandpassClean(chromCombine(a, b, c, R, G, B), fs); pulses{7} = bandpassClean(posCombine(a, b, c, fs, R, G, B), fs);
        try, pulses{8} = cpaceHomodyneNormalize(cpaceEigenExtract(Rc, Gc, Bc, fs, 0.30), fs); catch, end
        try, pulses{9} = cpaceHomodyneNormalize(cpaceEigenExtract(Rc, Gc, Bc, fs, 0.15), fs); catch, end
        fld = matlab.lang.makeValidName(id);
        if isfield(t2, 'pulses') && isfield(t2.pulses, fld)
            q = t2.pulses.(fld); pulses{10} = q.A0_a; pulses{11} = q.A0_Cb; pulses{12} = q.A0_Cr; pulses{15} = q.A3_a; pulses{16} = q.A3_Cb; pulses{17} = q.A3_Cr;
        end
        cv = load(fullfile(proc, ['seg22cov_' id '.mat']), 'Cseq');
        pulses{13} = bandpassClean(spatialSubspaceRotation(cv.Cseq, fs, max(1, round(strideSel * fs)), 3), fs);
        [Ld, ~] = detrendSignal(lgiProjection(c1.Rw, c1.Gw, c1.Bw)); pulses{14} = bandpassClean(Ld, fs);
        f3 = fullfile(proc, ['seg23t3_' id '.mat']);
        if isfile(f3)
            d3 = load(f3);
            pulses{18} = bandpassClean(spatialSubspaceRotation(d3.fbMask.C, fs, max(1, round(strideSel * fs)), 3), fs);
            pulses{19} = bandpassClean(spatialSubspaceRotation(d3.faceMask.C, fs, max(1, round(strideSel * fs)), 3), fs);
        end
        for k = 1:nC
            p = pulses{k};
            if isempty(p) || any(~isfinite(p)), continue, end
            try, HR(i, k, 1) = fftHeartRate(p, fs); catch, end
            try
                [hn, wr] = windowedHeartRate(p, fs); HR(i, k, 2) = hn;
                z = wr.candidateBpm(:, 1); qs = wr.qualityScore;
                HR(i, k, 3) = residualAdaptiveKalmanHR_exp(z, qs, struct('form', 'exponent', 'R0', 25, 'Q', 0.03, 'beta', 1.0));
                HR(i, k, 4) = residualAdaptiveKalmanHR(z, qs);
            catch, end
            try, HR(i, k, 5) = lgiPaperReadout(p, fs); catch, end
            try, HR(i, k, 6) = lgiStateSpaceTracker(p, fs); catch, end
        end
    catch err
        fprintf('%s FAILED: %s\n', id, err.message);
    end
    if mod(i, 10) == 0, fprintf('%d/%d\n', i, N); end
end
save(fullfile(outDir, 'task5_HR_cube.mat'), 'HR', 'T', 'combNames', 'estNames');
rows = {};
for k = 1:nC
    for e = 1:nE
        t = s23_poolTable(HR(:, k, e), T, combNames{k}); t.estimator = repmat(string(estNames{e}), height(t), 1); rows{end+1} = t; %#ok<AGROW>
    end
end
S = vertcat(rows{:}); writetable(S, fullfile(outDir, 'task5_matrix_long.csv'));
% wide MAE matrices + rank-vs-CHROM/POS analysis, per pool (never pooled-only)
pools = {'UBFC', 'VIPL_v1', 'MAIN_112', 'VIPL_v2_motion'}; fid = fopen(fullfile(outDir, 'task5_rank_analysis.txt'), 'w');
for pi = 1:numel(pools)
    M = nan(nC, nE);
    for k = 1:nC, for e = 1:nE, r = S(S.method == combNames{k} & S.estimator == estNames{e} & S.pool == pools{pi}, :); if ~isempty(r), M(k, e) = r.MAE; end, end, end
    W = array2table(M, 'VariableNames', matlab.lang.makeValidName(estNames), 'RowNames', combNames);
    writetable(W, fullfile(outDir, sprintf('task5_MAE_matrix_%s.csv', pools{pi})), 'WriteRowNames', true);
    fprintf(fid, '\n=== MAE matrix (bpm), pool %s ===\n', pools{pi}); fprintf(fid, '%s', evalc('disp(W)'));
    for e = 1:nE
        [~, ord] = sort(M(:, e)); rk = nan(nC, 1); rk(ord) = 1:nC; rk(isnan(M(:, e))) = NaN;
        fprintf(fid, 'rank under %-32s: ', estNames{e}); fprintf(fid, '%d ', rk); fprintf(fid, '\n');
    end
    for k = 3:nC
        gaps = M(k, :) - M(1, :);   % gap vs production CHROM UNDER THE SAME ESTIMATOR
        gapsP = M(k, :) - M(2, :);
        fprintf(fid, '%-38s gap vs CHROM per estimator: %s | vs POS: %s | sign flips vs CHROM: %d\n', combNames{k}, mat2str(round(gaps, 2)), mat2str(round(gapsP, 2)), (any(gaps < 0) && any(gaps > 0)));
    end
end
% paired signrank of each combiner vs production CHROM and POS under E1 and E2, MAIN_112 and v2
refNames = {'CHROM','POS'}; mk = T.pool ~= "VIPL_v2_motion"; v2 = ~mk;
fprintf(fid, '\n=== Paired per-subject tests vs production CHROM(k=1)/POS(k=2), same estimator ===\n');
for e = [1 2 3]
    for k = 3:nC
        for sc = {'MAIN_112', mk; 'V2', v2}'
            for ref = 1:2
                d = abs(HR(sc{2}, k, e) - T.gt(sc{2})) - abs(HR(sc{2}, ref, e) - T.gt(sc{2})); d = d(isfinite(d));
                if numel(d) >= 6, pv = signrank(d); else, pv = NaN; end
                fprintf(fid, '%-30s vs %s | %-4s | %-30s | n=%d better>1 %d worse>1 %d severe-worse %d p=%.4f\n', estNames{e}, refNames{ref}, sc{1}, combNames{k}, numel(d), nnz(d < -1), nnz(d > 1), nnz(d > 10), pv);
            end
        end
    end
end
fclose(fid); disp(fileread(fullfile(outDir, 'task5_rank_analysis.txt')));
