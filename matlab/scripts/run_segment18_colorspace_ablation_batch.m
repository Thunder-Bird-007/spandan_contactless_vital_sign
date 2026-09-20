% RUN_SEGMENT18_COLORSPACE_ABLATION_BATCH Segment 18 (MATLAB colour-space
% ablation). Diagnostic ablation only: does a CIELab a* channel, or YCbCr
% Cb / Cr, work as a pulse-extraction channel as well as / better than green?
%
% Same subject pool as run_segment8_task4_wavelet_ablation_batch.m (5 UBFC-D1
% + 107 VIPL v1/source1 triples). For each subject: one decode pass through
% roi/extractROISignalsLab.m (forehead = primary channel for HR; all four Task
% N regions returned from the SAME pass for cross-ROI PLV), then, INDEPENDENTLY
% for G, a*, Cb, Cr:
%     detrendSignal -> bandpassClean -> fftHeartRate         (HR)
%     per region: detrendSignal -> bandpassClean, then
%     validation/computeCrossROIPLV.m over the 4 regions     (PLV)
%
% DELIBERATE CHOICES, stated so they are not rediscovered:
%   * No waveletDenoise pre-step -- the task specifies the bare
%     detrend->bandpass->fft chain, and this is what makes "G" identical to the
%     existing green-only baseline (segment4_hr_summary*.csv HR_green, which
%     was also computed without wavelet). Green was never wavelet-promoted.
%   * HR_groundtruth is read from the same segment4 baseline CSVs the Segment 8
%     ablation used (matched by subjectID), not recomputed.
%   * The first subject processed also runs the ORIGINAL extractROISignals.m
%     and asserts R/G/B are bit-identical (parity check on the new extractor).
%   * The PLV input is a single-channel detrended+bandpassed trace per region
%     (no CHROM/POS combination exists for a single chroma channel), so PLV
%     values here are comparable ACROSS the four channels in this table, not
%     directly to Segment 10/11's post-CHROM/POS PLV numbers.
%
% Does NOT modify extractROISignals.m, detrendSignal.m, bandpassClean.m,
% fftHeartRate.m, computeCrossROIPLV.m, chromCombine.m, posCombine.m, or
% pipeline/estimateVitalsAndMorphology.m.
%
% Output: results/metrics/segment18_colorspace_ablation.csv (resumable).

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
addpath(genpath(fullfile(fileparts(thisFileDir), 'src')));

ubfcD1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

ubfcBaselineTable = readtable(fullfile(metricsRoot, 'segment4_hr_summary.csv'), 'TextType', 'string');
viplBaselineTable = readtable(fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv'), 'TextType', 'string');

outCsvPath = fullfile(metricsRoot, 'segment18_colorspace_ablation.csv');
headerLine = "subjectID,HR_green,HR_labA,HR_ycbcrCb,HR_ycbcrCr,HR_groundtruth,PLV_green,PLV_labA,PLV_ycbcrCb,PLV_ycbcrCr,dataset";

alreadyDoneIds = {};
if isfile(outCsvPath)
    existingTable = readtable(outCsvPath, 'TextType', 'string');
    if height(existingTable) > 0
        alreadyDoneIds = cellstr(existingTable.subjectID);
    end
    fprintf('Resuming: %d subjects already in %s, will be skipped.\n', numel(alreadyDoneIds), outCsvPath);
else
    writelines(headerLine, outCsvPath);
end

ubfcSubjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

viplSubjectTriples = [1,1,1;2,1,1;3,1,1;4,1,1;5,1,1;6,1,1;7,1,1;8,1,1;9,1,1;10,1,1;
    11,1,1;12,1,1;13,1,1;14,1,1;15,1,1;16,1,1;17,1,1;18,1,1;19,1,1;20,1,1;
    21,1,1;22,1,1;23,1,1;24,1,1;25,1,1;26,1,1;27,1,1;28,1,1;29,1,1;30,1,1;
    31,1,1;32,1,1;33,1,1;34,1,1;35,1,1;36,1,1;37,1,1;38,1,1;39,1,1;40,1,1;
    41,1,1;42,1,1;43,1,1;44,1,1;45,1,1;46,1,1;47,1,1;48,1,1;49,1,1;50,1,1;
    51,1,1;52,1,1;53,1,1;54,1,1;55,1,1;56,1,1;57,1,1;58,1,1;59,1,1;60,1,1;
    61,1,1;62,1,1;63,1,1;64,1,1;65,1,1;66,1,1;67,1,1;68,1,1;69,1,1;70,1,1;
    71,1,1;72,1,1;73,1,1;74,1,1;75,1,1;76,1,1;77,1,1;78,1,1;79,1,1;80,1,1;
    81,1,1;82,1,1;83,1,1;84,1,2;85,1,1;86,1,1;87,1,1;88,1,1;89,1,1;90,1,1;
    91,1,1;92,1,1;93,1,1;94,1,1;95,1,1;96,1,1;97,1,2;98,1,2;99,1,2;100,1,2;
    101,1,2;102,1,2;103,1,2;104,1,2;105,1,2;106,1,2;107,1,2];

% Build one job list so UBFC and VIPL share the same per-subject code path.
jobs = struct('subjectID', {}, 'dataset', {}, 'videoArgs', {});
for k = 1:numel(ubfcSubjectList)
    jobs(end + 1) = struct('subjectID', ubfcSubjectList{k}, 'dataset', 'UBFC', 'videoArgs', {{ubfcSubjectList{k}}}); %#ok<SAGROW>
end
for k = 1:size(viplSubjectTriples, 1)
    sN = viplSubjectTriples(k, 1); scN = viplSubjectTriples(k, 2); soN = viplSubjectTriples(k, 3);
    jobs(end + 1) = struct('subjectID', ['VIPL_p' num2str(sN) '_v' num2str(scN) '_source' num2str(soN)], 'dataset', 'VIPL', 'videoArgs', {{[sN scN soN]}}); %#ok<SAGROW>
end

channelKeys = {'G', 'a', 'Cb', 'Cr'};
regionNames = {'forehead', 'glabella', 'malar', 'cheek'};

failedSubjects = {};
processedCount = 0;
parityChecked = false;

for jobPos = 1:numel(jobs)
    subjectID = jobs(jobPos).subjectID;
    dataset = jobs(jobPos).dataset;

    if any(strcmp(alreadyDoneIds, subjectID))
        continue
    end

    fprintf('--- Segment 18 colour-space ablation: %s (%d/%d, %s) ---\n', subjectID, jobPos, numel(jobs), dataset);
    tSubj = tic;

    try
        if strcmp(dataset, 'UBFC')
            subjDir = fullfile(ubfcD1Root, subjectID);
            aviFiles = dir(fullfile(subjDir, '*.avi'));
            videoPath = fullfile(subjDir, aviFiles(1).name);
            [frames, fs, ~] = loadUBFCVideo(videoPath);
        else
            t = jobs(jobPos).videoArgs{1};
            [frames, fs, ~, ~] = loadVIPLVideo(viplRoot, t(1), t(2), t(3));
        end

        [R, G, B, ~, ~, ~, ~, ~, ~, ~, ~, allRegions] = extractROISignalsLab(frames, fs);

        if ~parityChecked
            % Fresh reader so extractROISignals starts from frame 1 too.
            if strcmp(dataset, 'UBFC')
                [frames2, ~, ~] = loadUBFCVideo(videoPath);
            else
                [frames2, ~, ~, ~] = loadVIPLVideo(viplRoot, t(1), t(2), t(3));
            end
            [R0, G0, B0, ~, ~, ~] = extractROISignals(frames2, fs);
            if ~isequal(R, R0) || ~isequal(G, G0) || ~isequal(B, B0)
                error('run_segment18_colorspace_ablation_batch:parityFailed', ...
                    'extractROISignalsLab R/G/B differ from extractROISignals for %s (max |dG|=%g).', subjectID, max(abs(G - G0)));
            end
            fprintf('PARITY OK on %s: R/G/B bit-identical to extractROISignals.m (%d frames).\n', subjectID, numel(G));
            parityChecked = true;
        end

        hr = nan(1, numel(channelKeys));
        plv = nan(1, numel(channelKeys));

        for chPos = 1:numel(channelKeys)
            key = channelKeys{chPos};

            % --- HR from the primary (forehead) channel ---
            sig = allRegions.forehead.(key);
            [sigD, ~] = detrendSignal(sig);
            [sigF, ~] = bandpassClean(sigD, fs);
            hr(chPos) = fftHeartRate(sigF, fs);

            % --- Cross-ROI PLV over the four regions ---
            regionSigs = cell(1, numel(regionNames));
            for regionPos = 1:numel(regionNames)
                rs = allRegions.(regionNames{regionPos}).(key);
                [rsD, ~] = detrendSignal(rs);
                [rsF, ~] = bandpassClean(rsD, fs);
                regionSigs{regionPos} = rsF;
            end
            plv(chPos) = computeCrossROIPLV(regionSigs, regionNames);
        end

        baselineRow = ubfcBaselineTable(ubfcBaselineTable.subjectID == subjectID, :);
        if height(baselineRow) ~= 1
            baselineRow = viplBaselineTable(viplBaselineTable.subjectID == subjectID, :);
        end
        if height(baselineRow) ~= 1
            error('run_segment18_colorspace_ablation_batch:noBaseline', 'No baseline row for %s', subjectID);
        end
        HR_groundtruth = baselineRow.HR_groundtruth(1);
        HR_green_baseline = baselineRow.HR_green(1);

        fprintf('%s: GT=%.2f G=%.2f (baseline CSV %.2f) a*=%.2f Cb=%.2f Cr=%.2f | PLV G=%.3f a*=%.3f Cb=%.3f Cr=%.3f (%.0fs)\n', ...
            subjectID, HR_groundtruth, hr(1), HR_green_baseline, hr(2), hr(3), hr(4), plv(1), plv(2), plv(3), plv(4), toc(tSubj));

        row = {subjectID, num2str(hr(1), '%.4f'), num2str(hr(2), '%.4f'), num2str(hr(3), '%.4f'), num2str(hr(4), '%.4f'), ...
            num2str(HR_groundtruth, '%.4f'), num2str(plv(1), '%.4f'), num2str(plv(2), '%.4f'), num2str(plv(3), '%.4f'), num2str(plv(4), '%.4f'), dataset};
        writelines(strjoin(row, ','), outCsvPath, 'WriteMode', 'append');
        processedCount = processedCount + 1;
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<SAGROW>
    end
end

disp(' ');
disp(['--- Segment 18 colour-space ablation complete: ' num2str(processedCount) ' subjects processed, ' num2str(numel(failedSubjects)) ' failed ---']);
for k = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{k}]);
end
disp(['Saved ' outCsvPath]);
