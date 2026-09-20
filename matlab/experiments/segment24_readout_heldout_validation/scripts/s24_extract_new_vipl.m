% S24_EXTRACT_NEW_VIPL Segment 24 Step 3: ROI extraction for NEW VIPL-HR-V1 videos never processed by any prior
% segment: scenarios v4 (bright light) and v6 (stable, 1.5 m), source1 (Logitech C310 webcam, same device as MAIN_112's
% v1/source1). Reuses production io/loadVIPLVideo, roi/extractROISignals, io/loadVIPLGroundTruth UNMODIFIED, exactly as
% scripts/run_vipl_v7_integration_batch.m does. NO read-out (HR estimation) is computed here.
% Raw videos were unzipped (only */v4|v6/source1/*) to a scratch tree on I:; caches go to data/processed/ as
% VIPL_p<N>_v<V>_source1_rgb_traces.mat (same convention/schema as every other VIPL cache) and the ground truth + fs
% go to results/s24_new_vipl_manifest.csv so future runs never need the video again. Resumable.
here = fileparts(mfilename('fullpath')); root = fileparts(fileparts(fileparts(fileparts(here))));
addpath(genpath(fullfile(root, 'matlab', 'src')));
scratch = 'I:\EEE 3-1\EEE 312\project\dataset\seg24_scratch\VIPL-HR';
proc = fullfile(root, 'data', 'processed'); outCsv = fullfile(here, '..', 'results', 's24_new_vipl_manifest.csv');
rows = {}; if isfile(outCsv), old = readtable(outCsv, 'TextType', 'string'); rows = table2cell(old); end
done = strings(0, 1); if ~isempty(rows), done = string(rows(:, 1)); end
for v = [4 6]
    for s = 1:107
        id = sprintf('VIPL_p%d_v%d_source1', s, v);
        if ~isfile(fullfile(scratch, sprintf('p%d', s), sprintf('v%d', v), 'source1', 'video.avi')), continue, end
        if any(done == id), continue, end
        try
            [vr, fs, nFr, ~] = loadVIPLVideo(scratch, s, v, 1);
            [R, G, B, ~, dropped, ~] = extractROISignals(vr, fs); numDroppedFrames = numel(dropped); subjectID = id; %#ok<NASGU>
            save(fullfile(proc, [id '_rgb_traces.mat']), 'R', 'G', 'B', 'fs', 'subjectID', 'numDroppedFrames');
            gt = loadVIPLGroundTruth(scratch, s, v, 1);
            fault = gt.hr == 255; hrClean = gt.hr(~fault);
            rows(end+1, :) = {id, s, v, fs, nFr, numel(R), numDroppedFrames, mean(hrClean), nnz(fault)}; %#ok<AGROW>
            T = cell2table(rows, 'VariableNames', {'subjectID','subject','scenario','fs','numFrames','numSamples','numDropped','HR_groundtruth','nFaultHR'});
            writetable(T, outCsv); fprintf('%s ok fs=%.3f n=%d gt=%.1f (%d rows)\n', id, fs, numel(R), mean(hrClean), size(rows,1));
        catch err
            fprintf('%s FAILED: %s\n', id, err.message);
        end
    end
end
disp('DONE');
