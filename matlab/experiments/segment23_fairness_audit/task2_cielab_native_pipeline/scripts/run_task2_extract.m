% RUN_TASK2_EXTRACT Segment 23 Task 2 -- the HEAVY video pass (132 videos: 5 UBFC + 107 VIPL v1 + 20 VIPL v2).
% Resumable; caches data/processed/seg23t2_<id>.mat. Parity check: forehead-box R/G/B must equal the production
% cache to <1e-9 (mismatches are logged, never silently accepted).
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src'));
proc = fullfile(root, 'data', 'processed');
ubfcRoot = fullfile(root, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1'); viplRoot = fullfile(root, 'data', 'raw', 'VIPL-HR');
T = s23_pool(true); N = height(T);
if exist('ONLY_FIRST', 'var'), N = min(N, ONLY_FIRST); end   %#ok<NODEF>
parityFail = {}; failed = {};
for k = 1:N
    id = char(T.subjectID(k)); outPath = fullfile(proc, ['seg23t2_' id '.mat']);
    if isfile(outPath), continue, end
    t0 = tic; fprintf('--- %s (%d/%d) ---\n', id, k, N);
    try
        tok = regexp(id, '^VIPL_p(\d+)_v(\d+)_source(\d+)$', 'tokens', 'once');
        if isempty(tok)
            av = dir(fullfile(ubfcRoot, id, '*.avi'));
            [frames, fs, ~] = loadUBFCVideo(fullfile(ubfcRoot, id, av(1).name)); ref = fullfile(proc, [id '_rgb_traces.mat']);
        else
            [frames, fs, ~, ~] = loadVIPLVideo(viplRoot, str2double(tok{1}), str2double(tok{2}), str2double(tok{3}));
            if str2double(tok{2}) == 2, ref = fullfile(proc, [id '_forehead_rgb_traces.mat']); else, ref = fullfile(proc, [id '_rgb_traces.mat']); end
        end
        d = cielabNativeExtract(frames, fs);
        rr = load(ref);
        if numel(rr.R) ~= size(d.boxRGB, 2) || max(abs([d.boxRGB(1, :) - rr.R(:)'; d.boxRGB(2, :) - rr.G(:)'; d.boxRGB(3, :) - rr.B(:)']), [], 'all') > 1e-9
            parityFail{end + 1} = id; fprintf('PARITY MISMATCH %s\n', id); %#ok<AGROW>
        end
        save(outPath, '-struct', 'd');
        fprintf('%s done %.0fs fs=%.2f frames=%d pruned=%d inits=%d\n', id, toc(t0), fs, size(d.boxRGB, 2), nnz(~d.keep), numel(d.initFrames));
    catch err
        fprintf('%s FAILED: %s\n', id, err.message); failed{end + 1} = id; %#ok<AGROW>
    end
end
fprintf('=== Task 2 extraction complete: %d failed, %d parity mismatches ===\n', numel(failed), numel(parityFail));
disp(failed); disp(parityFail);
