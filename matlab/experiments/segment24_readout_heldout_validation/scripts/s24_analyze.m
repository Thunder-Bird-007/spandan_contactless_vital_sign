% S24_ANALYZE pre-declared analysis (PREREGISTRATION.md sec.5-6). No choices are made here from results.
here = fileparts(mfilename('fullpath')); resDir = fullfile(here, '..', 'results'); root = fileparts(fileparts(fileparts(fileparts(here))));
addpath(fullfile(root, 'matlab', 'experiments', 'segment23_fairness_audit', 'common'));
H = readtable(fullfile(resDir, 's24_hr_per_video.csv'), 'TextType', 'string');
conds = ["HR_a" "HR_bW" "HR_cW" "HR_bT" "HR_cT"]; combs = ["CHROM" "POS"];
% ---- per-stratum + per-set tables (never pooled-only) ----
rows = {}; groups = unique(H(:, {'set','stratum'}), 'rows');
for g = 1:height(groups) + 3
    if g <= height(groups), mk = H.set == groups.set(g) & H.stratum == groups.stratum(g); nm = [groups.set(g) groups.stratum(g)];
    elseif g == height(groups) + 1, mk = H.set == "PRIMARY"; nm = ["PRIMARY" "ALL_PRIMARY"];
    elseif g == height(groups) + 2, mk = H.set == "SECONDARY_D2"; nm = ["SECONDARY_D2" "ALL_D2"];
    else, mk = H.set == "EXPLORATORY_PHONE"; nm = ["EXPLORATORY_PHONE" "ALL_PHONE"]; end
    for cb = combs
        for c = conds
            x = H(mk & H.combiner == cb, :); m = s23_metrics(x.(c), x.gt);
            rows(end+1, :) = {nm(1), nm(2), cb, c, m.n, m.mae, m.rmse, m.r, m.severe, mean(x.gt)}; %#ok<AGROW>
        end
    end
end
Tm = cell2table(rows, 'VariableNames', {'set','stratum','combiner','condition','n','MAE','RMSE','r','severe_gt10','meanGT'});
writetable(Tm, fullfile(resDir, 's24_metrics_by_stratum.csv'));
% ---- PRIMARY verdict tests: person-level, paired Wilcoxon, Holm over 8 ----
P = H(H.set == "PRIMARY", :); P.person = extractBefore(extractAfter(P.id, 'VIPL_'), '_v'); persons = unique(P.person);
V = {}; pv = []; 
for mech = ["W" "T"]
    for cb = combs
        for kind = ["b" "c"]
            cnd = "HR_" + kind + mech; x = P(P.combiner == cb, :);
            ea = abs(x.HR_a - x.gt); ec = abs(x.(cnd) - x.gt);
            pa = nan(numel(persons), 1); pc = pa;
            for k = 1:numel(persons), ii = x.person == persons(k) & isfinite(ea) & isfinite(ec); pa(k) = mean(ea(ii)); pc(k) = mean(ec(ii)); end
            ok = isfinite(pa) & isfinite(pc); d = pc(ok) - pa(ok);
            p = signrank(d); pv(end+1) = p; %#ok<AGROW>
            rmA = sqrt(mean((x.HR_a - x.gt).^2, 'omitnan')); rmC = sqrt(mean((x.(cnd) - x.gt).^2, 'omitnan'));
            V(end+1, :) = {mech, cb, kind, nnz(ok), mean(pa(ok)), mean(pc(ok)), mean(pa(ok)) - mean(pc(ok)), nnz(d < 0), nnz(d > 0), p, rmA, rmC}; %#ok<AGROW>
        end
    end
end
[~, o] = sort(pv); m = numel(pv); padj = nan(1, m); run = 0;
for k = 1:m, run = max(run, min(1, (m - k + 1) * pv(o(k)))); padj(o(k)) = run; end
Tv = cell2table(V, 'VariableNames', {'mechanism','combiner','condition','nPersons','personMAE_a','personMAE_cand','gain_bpm','nBetter','nWorse','p_raw','RMSE_a','RMSE_cand'});
Tv.p_holm = padj(:); Tv.clearlyBeats = Tv.gain_bpm >= 0.5 & Tv.p_holm < 0.05 & Tv.RMSE_cand <= Tv.RMSE_a;
writetable(Tv, fullfile(resDir, 's24_primary_verdict_tests.csv')); disp(Tv);
% ---- descriptive per-stratum Wilcoxon (PRIMARY) + win/loss on PHONE and D2 (no verdict) ----
R = {}; sets = unique(H.stratum);
for s = sets'
    for cb = combs
        x = H(H.stratum == s & H.combiner == cb, :);
        for c = conds(2:end)
            d = abs(x.(c) - x.gt) - abs(x.HR_a - x.gt); d = d(isfinite(d)); if numel(d) >= 6, p = signrank(d); else, p = NaN; end
            R(end+1, :) = {s, cb, c, numel(d), mean(d), nnz(d < 0), nnz(d > 0), p}; %#ok<AGROW>
        end
    end
end
writetable(cell2table(R, 'VariableNames', {'stratum','combiner','condition','n','meanDiffAbsErr_vs_a','nBetter','nWorse','p_descriptive'}), fullfile(resDir, 's24_descriptive_paired_by_stratum.csv'));
