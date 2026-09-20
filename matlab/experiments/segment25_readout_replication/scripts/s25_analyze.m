% S25_ANALYZE pre-declared analysis: 6 paired Wilcoxon tests (3 sets x 2 combiners), ONE Holm correction across all six.
here = fileparts(mfilename('fullpath')); resDir = fullfile(here, '..', 'results'); root = fileparts(fileparts(fileparts(fileparts(here))));
addpath(fullfile(root, 'matlab', 'experiments', 'segment23_fairness_audit', 'common'));
H = readtable(fullfile(resDir, 's25_hr_per_video.csv'), 'TextType', 'string'); combs = ["CHROM" "POS"];
% metric tables per set / stratum (never pooled-only)
strata = {"A_MAIN112","UBFC"; "A_MAIN112","VIPL_v1"; "A_MAIN112","ALL"; "B_SCENARIO","B_v3"; "B_SCENARIO","B_v5"; "B_SCENARIO","ALL"; "C_DEVICE","ALL"};
rows = {};
for s = 1:size(strata, 1)
    mk = H.set == strata{s, 1}; if strata{s, 2} ~= "ALL", mk = mk & H.stratum == strata{s, 2}; end
    for cb = combs
        x = H(mk & H.combiner == cb, :);
        for cond = ["HR_a" "HR_c"]
            m = s23_metrics(x.(cond), x.gt); rows(end+1, :) = {strata{s, 1}, strata{s, 2}, cb, cond, m.n, m.mae, m.rmse, m.r, m.severe, mean(x.gt)}; %#ok<AGROW>
        end
    end
end
writetable(cell2table(rows, 'VariableNames', {'set','stratum','combiner','condition','n','MAE','RMSE','r','severe_gt10','meanGT'}), fullfile(resDir, 's25_metrics_by_stratum.csv'));
% six verdict tests; unit = subject (A), person mean over clips (B), person (C)
sets = ["A_MAIN112" "B_SCENARIO" "C_DEVICE"]; V = {}; pv = [];
dd = dir(fullfile(root, 'data', 'processed', 'VIPL_p*_v5_source1_forehead_rgb_traces.mat'));
task20 = string(extractBetween(string({dd.name}), 'VIPL_', '_v5'));
for st = sets
    for cb = combs
        x = H(H.set == st & H.combiner == cb, :); persons = unique(x.person); pa = nan(numel(persons), 1); pc = pa;
        ea = abs(x.HR_a - x.gt); ec = abs(x.HR_c - x.gt);
        for k = 1:numel(persons), ii = x.person == persons(k) & isfinite(ea) & isfinite(ec); pa(k) = mean(ea(ii)); pc(k) = mean(ec(ii)); end
        ok = isfinite(pa) & isfinite(pc); d = pc(ok) - pa(ok); p = signrank(d); pv(end+1) = p; %#ok<AGROW>
        rmA = sqrt(mean((x.HR_a - x.gt).^2, 'omitnan')); rmC = sqrt(mean((x.HR_c - x.gt).^2, 'omitnan'));
        V(end+1, :) = {st, cb, nnz(ok), mean(pa(ok)), mean(pc(ok)), mean(pa(ok)) - mean(pc(ok)), nnz(d < 0), nnz(d > 0), p, rmA, rmC}; %#ok<AGROW>
    end
end
[~, o] = sort(pv); m = numel(pv); padj = nan(1, m); run = 0;
for k = 1:m, run = max(run, min(1, (m - k + 1) * pv(o(k)))); padj(o(k)) = run; end
Tv = cell2table(V, 'VariableNames', {'set','combiner','nUnits','MAE_a','MAE_c','gain_bpm','nBetter','nWorse','p_raw','RMSE_a','RMSE_c'}); Tv.p_holm6 = padj(:);
Tv.replicates = Tv.gain_bpm >= 0.5 & Tv.p_holm6 < 0.05 & Tv.RMSE_c <= Tv.RMSE_a;
Tv.holds = Tv.MAE_c <= Tv.MAE_a & ~(Tv.p_holm6 < 0.05 & Tv.gain_bpm < 0);
writetable(Tv, fullfile(resDir, 's25_verdict_tests_holm6.csv')); disp(Tv);
% descriptive per-stratum Wilcoxon + B sensitivity (drop the 20 Task-N v5 clips)
R = {};
for s = 1:size(strata, 1)
    for cb = combs
        mk = H.set == strata{s, 1} & H.combiner == cb; if strata{s, 2} ~= "ALL", mk = mk & H.stratum == strata{s, 2}; end
        x = H(mk, :); d = abs(x.HR_c - x.gt) - abs(x.HR_a - x.gt); d = d(isfinite(d));
        R(end+1, :) = {strata{s, 1}, strata{s, 2}, cb, numel(d), mean(d), nnz(d < 0), nnz(d > 0), signrank(d)}; %#ok<AGROW>
    end
end
for cb = combs
    x = H(H.set == "B_SCENARIO" & H.combiner == cb, :); drop = x.stratum == "B_v5" & ismember(x.person, task20); x = x(~drop, :);
    persons = unique(x.person); pa = nan(numel(persons), 1); pc = pa;
    for k = 1:numel(persons), ii = x.person == persons(k); pa(k) = mean(abs(x.HR_a(ii) - x.gt(ii))); pc(k) = mean(abs(x.HR_c(ii) - x.gt(ii))); end
    d = pc - pa; R(end+1, :) = {"B_SCENARIO", "B_minus_TaskN_v5_20", cb, numel(d), mean(d), nnz(d < 0), nnz(d > 0), signrank(d)}; %#ok<AGROW>
end
writetable(cell2table(R, 'VariableNames', {'set','stratum','combiner','n','meanDiffAbsErr_c_minus_a','nBetter','nWorse','p_descriptive'}), fullfile(resDir, 's25_descriptive_paired.csv'));
