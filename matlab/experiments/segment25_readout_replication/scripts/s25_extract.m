% S25_EXTRACT Segment 25: ROI extraction (NO read-out) for VIPL v3/source1, v5/source1, v1/source3 from the scratch tree.
% Same unmodified loaders as s24_extract_new_vipl.m. Caches: data/processed/VIPL_p<N>_v<V>_source<K>_rgb_traces.mat
% (refuses to overwrite an existing file). Manifest: results/s25_new_vipl_manifest.csv. Resumable.
here = fileparts(mfilename('fullpath')); root = fileparts(fileparts(fileparts(fileparts(here))));
addpath(genpath(fullfile(root, 'matlab', 'src')));
scratch = 'I:\EEE 3-1\EEE 312\project\dataset\seg24_scratch\VIPL-HR';
proc = fullfile(root, 'data', 'processed'); outCsv = fullfile(here, '..', 'results', 's25_new_vipl_manifest.csv');
rows = {}; done = strings(0, 1); if isfile(outCsv), rows = table2cell(readtable(outCsv, 'TextType', 'string')); done = string(rows(:, 1)); end
jobs = [3 1; 5 1; 1 3];   % [scenario source]
for j = 1:size(jobs, 1)
    v = jobs(j, 1); k = jobs(j, 2);
    for s = 1:107
        id = sprintf('VIPL_p%d_v%d_source%d', s, v, k);
        if ~isfile(fullfile(scratch, sprintf('p%d', s), sprintf('v%d', v), sprintf('source%d', k), 'video.avi')), continue, end
        if any(done == id), continue, end
        cf = fullfile(proc, [id '_rgb_traces.mat']);
        if isfile(cf), fprintf('%s: cache already exists, REFUSING to overwrite\n', id); continue, end
        try
            [vr, fs, nFr, ~] = loadVIPLVideo(scratch, s, v, k);
            [R, G, B, ~, dropped, ~] = extractROISignals(vr, fs); numDroppedFrames = numel(dropped); subjectID = id; %#ok<NASGU>
            save(cf, 'R', 'G', 'B', 'fs', 'subjectID', 'numDroppedFrames');
            gt = loadVIPLGroundTruth(scratch, s, v, k); fault = gt.hr == 255; hrClean = gt.hr(~fault);
            rows(end+1, :) = {id, s, v, k, fs, nFr, numel(R), numDroppedFrames, mean(hrClean), nnz(fault)}; %#ok<AGROW>
            T = cell2table(rows, 'VariableNames', {'subjectID','subject','scenario','source','fs','numFrames','numSamples','numDropped','HR_groundtruth','nFaultHR'});
            writetable(T, outCsv); fprintf('%s ok fs=%.3f n=%d gt=%.1f (%d rows)\n', id, fs, numel(R), mean(hrClean), size(rows, 1));
        catch err
            fprintf('%s FAILED: %s\n', id, err.message);
        end
    end
end
disp('DONE');
