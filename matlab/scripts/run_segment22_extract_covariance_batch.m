% RUN_SEGMENT22_EXTRACT_COVARIANCE_BATCH Re-decode the 112-subject main pool
% (5 UBFC-D1 + 107 VIPL v1) and the 20-subject VIPL v2 motion pool ONCE, and
% cache forehead R/G/B plus the per-frame 3x3 pixel correlation matrices that
% 2SR needs (roi/extractROICovariance.m). Output per subject:
%   data/processed/seg22cov_<subjectID>.mat  (Cseq, R, G, B, fs)
% Resumable (skips subjects already cached). Parity check: R/G/B must equal
% the existing production cache (<id>_rgb_traces.mat, or
% <id>_forehead_rgb_traces.mat for v2) to <1e-9; mismatches are logged, not
% silently accepted.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
addpath(genpath(fullfile(fileparts(thisFileDir), 'src')));
ubfcD1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
procRoot = fullfile(projectRoot, 'data', 'processed');

main = readtable(fullfile(metricsRoot, 'segment8_task4_wavelet_ablation.csv'), 'TextType', 'string');
mot = readtable(fullfile(metricsRoot, 'segment6_task_n_region_hr_summary.csv'), 'TextType', 'string');
mot = mot(mot.scenario == "v2_motion", :);
ids = [cellstr(main.subjectID); cellstr(mot.subjectID)];

parityFail = {}; failed = {};
for k = 1:numel(ids)
    id = ids{k};
    outPath = fullfile(procRoot, ['seg22cov_' id '.mat']);
    if isfile(outPath), continue, end
    fprintf('--- %s (%d/%d) ---\n', id, k, numel(ids));
    t0 = tic;
    try
        tok = regexp(id, '^VIPL_p(\d+)_v(\d+)_source(\d+)$', 'tokens', 'once');
        if isempty(tok)
            aviFiles = dir(fullfile(ubfcD1Root, id, '*.avi'));
            [frames, fs, ~] = loadUBFCVideo(fullfile(ubfcD1Root, id, aviFiles(1).name));
            refPath = fullfile(procRoot, [id '_rgb_traces.mat']);
        else
            [frames, fs, ~, ~] = loadVIPLVideo(viplRoot, str2double(tok{1}), str2double(tok{2}), str2double(tok{3}));
            if str2double(tok{2}) == 2
                refPath = fullfile(procRoot, [id '_forehead_rgb_traces.mat']);
            else
                refPath = fullfile(procRoot, [id '_rgb_traces.mat']);
            end
        end
        [R, G, B, Cseq, ~, ~] = extractROICovariance(frames, fs);
        ref = load(refPath);
        if numel(ref.R) ~= numel(R) || max(abs([R(:) - ref.R(:); G(:) - ref.G(:); B(:) - ref.B(:)])) > 1e-9
            parityFail{end + 1} = id; %#ok<SAGROW>
            fprintf('PARITY MISMATCH %s\n', id);
        end
        save(outPath, 'Cseq', 'R', 'G', 'B', 'fs');
        fprintf('%s done (%.0fs, fs=%.2f)\n', id, toc(t0), fs);
    catch err
        fprintf('%s FAILED: %s\n', id, err.message);
        failed{end + 1} = id; %#ok<SAGROW>
    end
end
fprintf('=== extraction complete: %d failed, %d parity mismatches ===\n', numel(failed), numel(parityFail));
if ~isempty(parityFail), disp(parityFail); end
if ~isempty(failed), disp(failed); end
