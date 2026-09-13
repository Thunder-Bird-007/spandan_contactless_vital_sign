% RUN_SEGMENT7_TASK_I_FACEMESH_BRANCH1_BATCH Segment 7 Task I -- does the
% real DL face-mesh ROI (roi/faceMeshROIExtraction.m, built in Task H)
% help the PRODUCTION HR path (Branch 1: detrendSignal -> bandpassClean ->
% chromCombine/posCombine -> fftHeartRate), as opposed to the
% notch/morphology branch Task H already tested (and found a clear
% regression on)?
%
% WHY THIS IS A SEPARATE, CHEAPER QUESTION: Branch 1 uses
% filtering/bandpassClean.m's WIDE(-ish), 0.7-4 Hz band with no harmonic
% comb -- a much less noise-sensitive consumer of the ROI signal than
% Branch 2's morphology/adaptiveHarmonicFilter.m (narrow +/-1-FFT-bin
% combs). Task H's working hypothesis for its own regression (smaller,
% more precise ROI -> fewer pooled pixels -> noisier signal -> Branch 2's
% narrow filter is unusually intolerant of that noise) may simply not
% apply here. This script tests that directly rather than assuming either
% way.
%
% Does NOT modify roi/extractROISignals.m, roi/faceMeshROIExtraction.m,
% filtering/detrendSignal.m, filtering/bandpassClean.m,
% pulseextraction/chromCombine.m, pulseextraction/posCombine.m, or
% heartrate/fftHeartRate.m -- new, additive script only, reusing all of
% the above exactly as scripts/run_segment4_heartrate_batch.m does.
%
% Same 5 UBFC subjects as every other Segment 7 comparison
% (5-gt/6-gt/7-gt/12-gt/after-exercise), for direct comparability.
%
% ONE-TIME SESSION SETUP: pyenv('ExecutionMode', 'OutOfProcess') --
% required by roi/faceMeshROIExtraction.m, see that function's own header.
%
% Also SAVES the raw face-mesh R/G/B traces to
% data/processed/<subjectID>_facemesh_rgb_traces.mat (NEW filename,
% doesn't collide with the baseline's own <subjectID>_rgb_traces.mat) so
% any future analysis (e.g. a Branch-1 SpO2 comparison) doesn't need to
% re-run the ~10-40-minute-per-subject face-mesh decode again.
%
% Output: results/metrics/segment7_task_i_facemesh_branch1_hr.csv.

pyenv('ExecutionMode', 'OutOfProcess');

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
processedRoot = fullfile(projectRoot, 'data', 'processed');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end
if ~isfolder(processedRoot)
    mkdir(processedRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_i_facemesh_branch1_hr.csv');
headerLine = "subjectID,HR_groundtruth,HR_chrom_baseline,HR_chrom_facemesh,HR_pos_baseline,HR_pos_facemesh,HR_green_baseline,HR_green_facemesh,abs_error_chrom_baseline,abs_error_chrom_facemesh,abs_error_pos_baseline,abs_error_pos_facemesh,droppedFrames_facemesh,numFrames_facemesh";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task I face-mesh Branch-1 batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);
    subjectStartTic = tic;

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_i_facemesh_branch1_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_i_facemesh_branch1_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % --- Baseline ROI + Branch 1 (fast, reuses cached rgb_traces.mat
        % if a prior segment already produced one for this subject). ---
        cachedRgbPath = fullfile(processedRoot, [subjectID '_rgb_traces.mat']);
        if isfile(cachedRgbPath)
            cached = load(cachedRgbPath);
            R_base = cached.R; G_base = cached.G; B_base = cached.B; frameRateBase = cached.fs;
            disp(['Subject ' subjectID ': reused cached baseline traces from ' cachedRgbPath]);
        else
            [framesBase, frameRateBase, ~] = loadUBFCVideo(videoPath);
            [R_base, G_base, B_base, ~, ~, ~] = extractROISignals(framesBase, frameRateBase);
        end

        [R_base_d, ~] = detrendSignal(R_base);
        [G_base_d, ~] = detrendSignal(G_base);
        [B_base_d, ~] = detrendSignal(B_base);
        [R_base_f, ~] = bandpassClean(R_base_d, frameRateBase);
        [G_base_f, ~] = bandpassClean(G_base_d, frameRateBase);
        [B_base_f, ~] = bandpassClean(B_base_d, frameRateBase);

        pulseChromBase = chromCombine(R_base_f, G_base_f, B_base_f, R_base, G_base, B_base);
        pulseChromBaseF = bandpassClean(pulseChromBase, frameRateBase);
        HR_chrom_baseline = fftHeartRate(pulseChromBaseF, frameRateBase);

        pulsePosBase = posCombine(R_base_f, G_base_f, B_base_f, frameRateBase, R_base, G_base, B_base);
        pulsePosBaseF = bandpassClean(pulsePosBase, frameRateBase);
        HR_pos_baseline = fftHeartRate(pulsePosBaseF, frameRateBase);

        HR_green_baseline = fftHeartRate(G_base_f, frameRateBase);

        disp(['Subject ' subjectID ' BASELINE: HR_chrom=' num2str(HR_chrom_baseline) ' HR_pos=' num2str(HR_pos_baseline) ' HR_green=' num2str(HR_green_baseline)]);

        % --- Face-mesh ROI + Branch 1 (the new, expensive decode). ---
        facemeshCachePath = fullfile(processedRoot, [subjectID '_facemesh_rgb_traces.mat']);
        if isfile(facemeshCachePath)
            cachedFm = load(facemeshCachePath);
            R_fm = cachedFm.R; G_fm = cachedFm.G; B_fm = cachedFm.B; frameRateFm = cachedFm.fs;
            droppedFrameIdxFm = cachedFm.droppedFrameIdx;
            disp(['Subject ' subjectID ': reused cached face-mesh traces from ' facemeshCachePath]);
        else
            [framesFm, frameRateFm, ~] = loadUBFCVideo(videoPath);
            [R_fm, G_fm, B_fm, ~, droppedFrameIdxFm, ~] = faceMeshROIExtraction(framesFm, frameRateFm);
            % Save with the plain names (R/G/B/fs/droppedFrameIdx) the
            % reload branch above expects, so a later reload needs no
            % special-case renaming.
            R = R_fm; G = G_fm; B = B_fm; fs = frameRateFm; droppedFrameIdx = droppedFrameIdxFm; %#ok<NASGU>
            save(facemeshCachePath, 'R', 'G', 'B', 'fs', 'droppedFrameIdx', '-v7');
        end

        disp(['Subject ' subjectID ' face-mesh ROI: dropped/no-face frames = ' num2str(numel(droppedFrameIdxFm)) ' / ' num2str(numel(R_fm))]);

        [R_fm_d, ~] = detrendSignal(R_fm);
        [G_fm_d, ~] = detrendSignal(G_fm);
        [B_fm_d, ~] = detrendSignal(B_fm);
        [R_fm_f, ~] = bandpassClean(R_fm_d, frameRateFm);
        [G_fm_f, ~] = bandpassClean(G_fm_d, frameRateFm);
        [B_fm_f, ~] = bandpassClean(B_fm_d, frameRateFm);

        pulseChromFm = chromCombine(R_fm_f, G_fm_f, B_fm_f, R_fm, G_fm, B_fm);
        pulseChromFmF = bandpassClean(pulseChromFm, frameRateFm);
        HR_chrom_facemesh = fftHeartRate(pulseChromFmF, frameRateFm);

        pulsePosFm = posCombine(R_fm_f, G_fm_f, B_fm_f, frameRateFm, R_fm, G_fm, B_fm);
        pulsePosFmF = bandpassClean(pulsePosFm, frameRateFm);
        HR_pos_facemesh = fftHeartRate(pulsePosFmF, frameRateFm);

        HR_green_facemesh = fftHeartRate(G_fm_f, frameRateFm);

        elapsedSubjectSec = toc(subjectStartTic);
        disp(['Subject ' subjectID ' FACE-MESH: HR_chrom=' num2str(HR_chrom_facemesh) ' HR_pos=' num2str(HR_pos_facemesh) ' HR_green=' num2str(HR_green_facemesh) ' (' num2str(elapsedSubjectSec, '%.0f') ' s)']);

        % --- Ground truth, windowed to this clip's duration (baseline
        % frame count as the reference duration -- same convention as
        % every prior HR batch script). ---
        videoDurationSec = numel(R_base) / frameRateBase;
        inClipMask = gt.timestamp <= videoDurationSec;
        HR_groundtruth = mean(gt.hr(inClipMask));

        absErrorChromBaseline = abs(HR_chrom_baseline - HR_groundtruth);
        absErrorChromFacemesh = abs(HR_chrom_facemesh - HR_groundtruth);
        absErrorPosBaseline = abs(HR_pos_baseline - HR_groundtruth);
        absErrorPosFacemesh = abs(HR_pos_facemesh - HR_groundtruth);

        disp(['Subject ' subjectID ' vs GT (' num2str(HR_groundtruth, '%.2f') ' bpm): ' ...
            'CHROM baseline err=' num2str(absErrorChromBaseline, '%.2f') ', facemesh err=' num2str(absErrorChromFacemesh, '%.2f') ' | ' ...
            'POS baseline err=' num2str(absErrorPosBaseline, '%.2f') ', facemesh err=' num2str(absErrorPosFacemesh, '%.2f')]);

        row = {subjectID, num2str(HR_groundtruth, '%.4f'), num2str(HR_chrom_baseline, '%.4f'), num2str(HR_chrom_facemesh, '%.4f'), ...
            num2str(HR_pos_baseline, '%.4f'), num2str(HR_pos_facemesh, '%.4f'), num2str(HR_green_baseline, '%.4f'), num2str(HR_green_facemesh, '%.4f'), ...
            num2str(absErrorChromBaseline, '%.4f'), num2str(absErrorChromFacemesh, '%.4f'), num2str(absErrorPosBaseline, '%.4f'), num2str(absErrorPosFacemesh, '%.4f'), ...
            num2str(numel(droppedFrameIdxFm)), num2str(numel(R_fm))};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task I face-mesh Branch-1 batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

disp(['Saved ' csvPath]);
