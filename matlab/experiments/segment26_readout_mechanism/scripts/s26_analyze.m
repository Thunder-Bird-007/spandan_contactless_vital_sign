% S26_ANALYZE pre-declared analysis (PREREGISTRATION_addendum.md sec.1-3). No choices made here from results.
here = fileparts(mfilename('fullpath')); resDir = fullfile(here, '..', 'results');
H = readtable(fullfile(resDir, 's26_per_clip.csv'), 'TextType', 'string'); combs = ["CHROM" "POS"];
% ---- stratum labels used by the addendum ----
H.S = strings(height(H), 1);
H.S(H.set5 == "S25_A") = "MAIN_112"; H.S(H.set5 == "S25_C") = "C_v1_source3";
H.S(H.set5 == "S25_B" & H.stratum == "B_v3") = "v3"; H.S(H.set5 == "S25_B" & H.stratum == "B_v5") = "v5";
H.S(H.set5 == "S24_PRIMARY" & H.stratum == "V4_source1") = "v4"; H.S(H.set5 == "S24_PRIMARY" & H.stratum == "V6_source1") = "v6";
H.S(H.set5 == "S24_PRIMARY" & H.stratum == "V7_source1") = "v7"; H.S(H.set5 == "S24_SECONDARY_D2") = "D2_desc";
DEG = ["v4" "v6" "v5"]; CLEAN = ["MAIN_112" "v3" "C_v1_source3"]; UNCL = "v7"; TESTED = [DEG CLEAN UNCL];
ea = abs(H.HR_a - H.gt); em = abs(H.HR_med - H.gt); en = abs(H.HR_mean - H.gt);
% ---- STEP 1: 7 strata x 2 combiners, mean vs median, Holm over 14 ----
R = {}; pv = [];
for s = TESTED
    for cb = combs
        k = H.S == s & H.combiner == cb; d = en(k) - em(k); p = signrank(d); pv(end+1) = p; %#ok<AGROW>
        R(end+1, :) = {s, cb, nnz(k), mean(ea(k)), mean(em(k)), mean(en(k)), mean(en(k)) - mean(em(k)), nnz(d < 0), nnz(d > 0), p, ...
            sqrt(mean((H.HR_a(k)-H.gt(k)).^2)), sqrt(mean((H.HR_med(k)-H.gt(k)).^2)), sqrt(mean((H.HR_mean(k)-H.gt(k)).^2))}; %#ok<AGROW>
    end
end
[~, o] = sort(pv); m = numel(pv); padj = nan(1, m); run = 0;
for k = 1:m, run = max(run, min(1, (m - k + 1) * pv(o(k)))); padj(o(k)) = run; end
T1 = cell2table(R, 'VariableNames', {'stratum','combiner','n','MAE_fft','MAE_median','MAE_mean','gap_mean_minus_median','nMeanBetter','nMeanWorse','p_raw','RMSE_fft','RMSE_median','RMSE_mean'}); T1.p_holm14 = padj(:);
cls = strings(height(T1), 1); cls(ismember(T1.stratum, DEG)) = "DEGRADED"; cls(ismember(T1.stratum, CLEAN)) = "CLEAN"; cls(T1.stratum == UNCL) = "unclassified"; T1.class = cls;
writetable(T1, fullfile(resDir, 's26_step1_mean_vs_median.csv')); disp(T1);
% descriptive: each aggregate vs fftHeartRate, per stratum (uncorrected) incl. D2 and v7
D = {};
for s = [TESTED "D2_desc"]
    for cb = combs
        k = H.S == s & H.combiner == cb; D(end+1, :) = {s, cb, nnz(k), mean(ea(k)), mean(em(k)), mean(en(k)), signrank(em(k) - ea(k)), signrank(en(k) - ea(k))}; end %#ok<AGROW>
end
writetable(cell2table(D, 'VariableNames', {'stratum','combiner','n','MAE_fft','MAE_median','MAE_mean','p_median_vs_fft_uncorr','p_mean_vs_fft_uncorr'}), fullfile(resDir, 's26_step1_descriptive_vs_fft.csv'));
% rules per combiner
F = {};
for cb = combs
    t = T1(T1.combiner == cb, :); gd = t.gap_mean_minus_median(t.class == "DEGRADED"); pd = t.p_holm14(t.class == "DEGRADED");
    gc = t.gap_mean_minus_median(t.class == "CLEAN"); gall = t.gap_mean_minus_median(t.class ~= "unclassified");
    R1 = nnz(gd >= 0.5) >= 2 && any(pd < 0.05 & gd > 0);
    R2 = nnz(abs(gc) < 0.5) >= 2;
    R3 = nnz(abs(gall) < 0.5) >= 5 && ~any(t.p_holm14 < 0.05);
    kd = H.combiner == cb & ismember(H.S, DEG); rec = (mean(ea(kd)) - mean(en(kd))) / (mean(ea(kd)) - mean(em(kd)));
    F(end+1, :) = {cb, R1, R2, R3, rec, mean(ea(kd)) - mean(em(kd)), mean(ea(kd)) - mean(en(kd))}; %#ok<AGROW>
end
T1f = cell2table(F, 'VariableNames', {'combiner','R1_median_beats_mean_degraded','R2_tie_clean','R3_mean_equals_median_everywhere','fractionOfGainRecoveredByMean_degraded','pooledDegradedGain_median','pooledDegradedGain_mean'});
writetable(T1f, fullfile(resDir, 's26_step1_rule_flags.csv')); disp(T1f);
% ---- STEP 2: 6 Spearman tests (3 proxies x 2 combiners), pooled over all five sets, Holm over 6 ----
prox = ["fs" "dropFrac" "meanG"]; Q = {}; pq = [];
for cb = combs
    k = H.combiner == cb; y = ea(k) - em(k);
    for px = prox
        x = H.(px)(k); ok = isfinite(x) & isfinite(y); [rho, p] = corr(x(ok), y(ok), 'Type', 'Spearman'); pq(end+1) = p; %#ok<AGROW>
        Q(end+1, :) = {cb, px, nnz(ok), rho, p}; %#ok<AGROW>
    end
end
[~, o] = sort(pq); m = numel(pq); padj = nan(1, m); run = 0;
for k = 1:m, run = max(run, min(1, (m - k + 1) * pq(o(k)))); padj(o(k)) = run; end
T2 = cell2table(Q, 'VariableNames', {'combiner','proxy','n','spearman_rho','p_raw'}); T2.p_holm6 = padj(:);
pred = strings(height(T2), 1); pred(T2.proxy == "fs") = "rho<0"; pred(T2.proxy == "dropFrac") = "rho>0"; pred(T2.proxy == "meanG") = "either";
dirOK = (T2.proxy == "fs" & T2.spearman_rho < 0) | (T2.proxy == "dropFrac" & T2.spearman_rho > 0) | T2.proxy == "meanG";
T2.predicted = pred; T2.correlates = T2.p_holm6 < 0.05 & abs(T2.spearman_rho) >= 0.10 & dirOK;
writetable(T2, fullfile(resDir, 's26_step2_spearman_pooled.csv')); disp(T2);
% descriptive within-set Spearman
W = {};
for s = unique(H.S)'
    for cb = combs
        k = H.S == s & H.combiner == cb; y = ea(k) - em(k);
        for px = prox
            x = H.(px)(k); ok = isfinite(x) & isfinite(y);
            if nnz(ok) >= 10 && std(x(ok)) > 0, [rho, p] = corr(x(ok), y(ok), 'Type', 'Spearman'); else, rho = NaN; p = NaN; end
            W(end+1, :) = {s, cb, px, nnz(ok), rho, p}; %#ok<AGROW>
        end
    end
end
writetable(cell2table(W, 'VariableNames', {'stratum','combiner','proxy','n','spearman_rho','p_uncorr'}), fullfile(resDir, 's26_step2_spearman_within_stratum.csv'));
% proxy summary by stratum (for the report)
P = {};
for s = unique(H.S)'
    k = H.S == s & H.combiner == "CHROM"; P(end+1, :) = {s, nnz(k), mean(H.fs(k)), median(H.fs(k)), nanmean(H.dropFrac(k)), nnz(isfinite(H.dropFrac(k))), mean(H.meanG(k))}; end %#ok<AGROW>
writetable(cell2table(P, 'VariableNames', {'stratum','n','meanFs','medianFs','meanDropFrac','nWithDropFrac','meanG'}), fullfile(resDir, 's26_proxy_summary_by_stratum.csv'));
