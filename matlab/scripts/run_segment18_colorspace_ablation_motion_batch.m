% RUN_SEGMENT18_COLORSPACE_ABLATION_MOTION_BATCH Segment 18 follow-up: the
% same G / a* / Cb / Cr ablation as run_segment18_colorspace_ablation_batch.m,
% but on VIPL scenario v2 ("Motion: large head movements, otherwise same as
% v1", docs/VIPL_DATA_FORMAT.md Section 2), source1, the 20 subjects already
% extracted (Segment 6 Task N's v2 pool). The main batch's v1/UBFC pool has NO
% deliberate head motion, so it cannot test the motion-robustness claim that
% motivates chroma channels; this batch can.
%
% Identical per-subject chain and CSV columns to the main batch (forehead HR
% via detrend->bandpass->fft; 4-region cross-ROI PLV). Ground truth is the
% HR_groundtruth column of results/metrics/segment6_task_n_region_hr_summary.csv
% (scenario v2_motion), the same GT Task N used (mean of fault-cleaned VIPL
% HR). v9 (phone motion) is not extracted locally and is out of scope.
%
% Output: results/metrics/segment18_colorspace_ablation_motion.csv (resumable).

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
addpath(genpath(fullfile(fileparts(thisFileDir), 'src')));
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

taskN = readtable(fullfile(metricsRoot, 'segment6_task_n_region_hr_summary.csv'), 'TextType', 'string');
taskN = taskN(taskN.scenario == "v2_motion", :);

outCsvPath = fullfile(metricsRoot, 'segment18_colorspace_ablation_motion.csv');
headerLine = "subjectID,HR_green,HR_labA,HR_ycbcrCb,HR_ycbcrCr,HR_groundtruth,PLV_green,PLV_labA,PLV_ycbcrCb,PLV_ycbcrCr,dataset";
alreadyDoneIds = {};
if isfile(outCsvPath)
    ex = readtable(outCsvPath, 'TextType', 'string');
    if height(ex) > 0, alreadyDoneIds = cellstr(ex.subjectID); end
else
    writelines(headerLine, outCsvPath);
end

channelKeys = {'G', 'a', 'Cb', 'Cr'};
regionNames = {'forehead', 'glabella', 'malar', 'cheek'};
failed = {};

for k = 1:height(taskN)
    subjectID = char(taskN.subjectID(k));
    if any(strcmp(alreadyDoneIds, subjectID)), continue, end
    tok = regexp(subjectID, '^VIPL_p(\d+)_v(\d+)_source(\d+)$', 'tokens', 'once');
    subjectNum = str2double(tok{1}); scenarioNum = str2double(tok{2}); sourceNum = str2double(tok{3});
    fprintf('--- Segment 18 motion ablation: %s (%d/%d) ---\n', subjectID, k, height(taskN));
    tSubj = tic;
    try
        [frames, fs, ~, ~] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum);
        [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, allRegions] = extractROISignalsLab(frames, fs);
        hr = nan(1, 4); plv = nan(1, 4);
        for c = 1:4
            key = channelKeys{c};
            [d, ~] = detrendSignal(allRegions.forehead.(key));
            [f, ~] = bandpassClean(d, fs);
            hr(c) = fftHeartRate(f, fs);
            rs = cell(1, 4);
            for r = 1:4
                [d, ~] = detrendSignal(allRegions.(regionNames{r}).(key));
                [rs{r}, ~] = bandpassClean(d, fs);
            end
            plv(c) = computeCrossROIPLV(rs, regionNames);
        end
        gt = taskN.HR_groundtruth(k);
        fprintf('%s: GT=%.2f G=%.2f a*=%.2f Cb=%.2f Cr=%.2f | PLV G=%.3f a*=%.3f Cb=%.3f Cr=%.3f (%.0fs)\n', subjectID, gt, hr, plv, toc(tSubj));
        row = {subjectID, num2str(hr(1), '%.4f'), num2str(hr(2), '%.4f'), num2str(hr(3), '%.4f'), num2str(hr(4), '%.4f'), num2str(gt, '%.4f'), ...
            num2str(plv(1), '%.4f'), num2str(plv(2), '%.4f'), num2str(plv(3), '%.4f'), num2str(plv(4), '%.4f'), 'VIPL'};
        writelines(strjoin(row, ','), outCsvPath, 'WriteMode', 'append');
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failed{end + 1} = subjectID; %#ok<SAGROW>
    end
end
disp(['--- motion ablation complete, ' num2str(numel(failed)) ' failed. Saved ' outCsvPath ' ---']);
