function T = s23_pool(includeV2)
% S23_POOL subject table: subjectID, pool, gt. Pools: UBFC (5), VIPL_v1 (107), VIPL_v2_motion (20).
% MAIN_112 = UBFC + VIPL_v1 (the project's standard pooled set, Segment 8).
if nargin < 1, includeV2 = true; end
mr = fullfile(s23_root(), 'results', 'metrics');
m = readtable(fullfile(mr, 'segment8_task4_wavelet_ablation.csv'), 'TextType', 'string');
pool = repmat("VIPL_v1", height(m), 1); pool(m.dataset == "UBFC") = "UBFC";
T = table(m.subjectID, pool, m.HR_groundtruth, 'VariableNames', {'subjectID', 'pool', 'gt'});
if includeV2
    mot = readtable(fullfile(mr, 'segment6_task_n_region_hr_summary.csv'), 'TextType', 'string');
    mot = mot(mot.scenario == "v2_motion", :);
    T = [T; table(mot.subjectID, repmat("VIPL_v2_motion", height(mot), 1), mot.HR_groundtruth, 'VariableNames', T.Properties.VariableNames)];
end
end
