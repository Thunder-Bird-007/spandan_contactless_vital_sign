function m = s23_metrics(pred, gt)
% S23_METRICS NaN-safe MAE/median/RMSE/Pearson r + severe (>10 bpm) count. n = pairs used.
pred = pred(:); gt = gt(:);
ok = isfinite(pred) & isfinite(gt); p = pred(ok); g = gt(ok);
e = abs(p - g);
m.n = numel(p); m.nFail = nnz(~ok);
m.mae = mean(e); m.medae = median(e); m.rmse = sqrt(mean((p - g) .^ 2));
m.r = NaN;
if numel(p) > 2 && std(p) > 0 && std(g) > 0
    c = corrcoef(p, g); m.r = c(1, 2);
end
m.severe = nnz(e > 10);
end
