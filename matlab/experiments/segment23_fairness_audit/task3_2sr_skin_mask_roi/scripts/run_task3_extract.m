% RUN_TASK3_EXTRACT Segment 23 Task 3 -- HEAVY video pass (132 videos), run only AFTER Task 2's extraction finishes
% (sequential heavy jobs per the brief). Resumable; caches data/processed/seg23t3_<id>.mat. Parity: fbUnmask mean RGB
% must equal the production cache and fbUnmask C must equal seg22cov's Cseq.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src'));
proc = fullfile(root, 'data', 'processed');
ubfcRoot = fullfile(root, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1'); viplRoot = fullfile(root, 'data', 'raw', 'VIPL-HR');
T = s23_pool(true); N = height(T);
parityFail = {}; failed = {};
for k = 1:N
    id = char(T.subjectID(k)); outPath = fullfile(proc, ['seg23t3_' id '.mat']);
    if isfile(outPath), continue, end
    t0 = tic; fprintf('--- %s (%d/%d) ---\n', id, k, N);
    try
        tok = regexp(id, '^VIPL_p(\d+)_v(\d+)_source(\d+)$', 'tokens', 'once');
        if isempty(tok)
            av = dir(fullfile(ubfcRoot, id, '*.avi'));
            [frames, fs, ~] = loadUBFCVideo(fullfile(ubfcRoot, id, av(1).name));
        else
            [frames, fs, ~, ~] = loadVIPLVideo(viplRoot, str2double(tok{1}), str2double(tok{2}), str2double(tok{3}));
        end
        d = skinMaskExtract(frames, fs);
        ref = load(fullfile(proc, ['seg22cov_' id '.mat']));
        okR = numel(ref.R) == size(d.fbUnmask.rgb, 2) && max(abs(d.fbUnmask.rgb(1, :) - ref.R(:)')) < 1e-9;
        okC = okR && max(abs(d.fbUnmask.C(:) - ref.Cseq(:))) < 1e-6;
        if ~okC, parityFail{end + 1} = id; fprintf('PARITY MISMATCH %s (rgb ok=%d)\n', id, okR); end %#ok<AGROW>
        save(outPath, '-struct', 'd');
        fprintf('%s done %.0fs fs=%.2f fbSkinFrac=%.2f faceSkinFrac=%.2f fbFallback=%d\n', id, toc(t0), fs, mean(d.fbMask.skinFrac), mean(d.faceMask.skinFrac), nnz(d.fbMask.fallback));
    catch err
        fprintf('%s FAILED: %s\n', id, err.message); failed{end + 1} = id; %#ok<AGROW>
    end
end
fprintf('=== Task 3 extraction complete: %d failed, %d parity mismatches ===\n', numel(failed), numel(parityFail));
disp(failed); disp(parityFail);
