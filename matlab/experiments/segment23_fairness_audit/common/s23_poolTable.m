function tbl = s23_poolTable(pred, T, name)
% S23_POOLTABLE per-subject-pool metrics rows (never a single pooled number alone):
% UBFC, VIPL_v1, MAIN_112 (UBFC+VIPL_v1), VIPL_v2_motion.
pools = {'UBFC', 'VIPL_v1', 'MAIN_112', 'VIPL_v2_motion'};
rows = {};
for k = 1:numel(pools)
    switch pools{k}
        case 'MAIN_112', mask = T.pool == "UBFC" | T.pool == "VIPL_v1";
        otherwise, mask = T.pool == string(pools{k});
    end
    if ~any(mask), continue, end
    m = s23_metrics(pred(mask), T.gt(mask));
    rows(end + 1, :) = {string(name), string(pools{k}), m.n, m.nFail, m.mae, m.medae, m.rmse, m.r, m.severe}; %#ok<AGROW>
end
tbl = cell2table(rows, 'VariableNames', {'method', 'pool', 'n', 'nFail', 'MAE', 'medianAE', 'RMSE', 'pearsonR', 'severeGT10'});
end
