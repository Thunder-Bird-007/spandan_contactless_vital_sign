% RUN_SEGMENT7_TASK_J_FACEMESH_HYBRID_BRANCH1_BATCH Segment 7 Task J --
% does the hybrid ROI (roi/faceMeshHybridROIExtraction.m: real face-mesh
% detection + baseline's forehead box geometry) still match baseline on
% the PRODUCTION HR path (Branch 1: detrendSignal -> bandpassClean ->
% chromCombine/posCombine -> fftHeartRate), same question Task I asked of
% the thin-polygon face-mesh ROI and found bit-identical.
%
% Does NOT modify roi/extractROISignals.m, roi/faceMeshROIExtraction.m,
% roi/faceMeshHybridROIExtraction.m, filtering/detrendSignal.m,
% filtering/bandpassClean.m, pulseextraction/chromCombine.m,
% pulseextraction/posCombine.m, or heartrate/fftHeartRate.m -- new,
% additive script only, reusing all of the above exactly as
% scripts/run_segment7_task_i_facemesh_branch1_batch.m does.
%
% Same 5 UBFC subjects as every other Segment 7 comparison
% (5-gt/6-gt/7-gt/12-gt/after-exercise), for direct comparability.
%
% ONE-TIME SESSION SETUP: pyenv('ExecutionMode', 'OutOfProcess') --
% required by roi/faceMeshHybridROIExtraction.m.
%
% Also SAVES the raw hybrid R/G/B traces to
% data/processed/<subjectID>_facemesh_hybrid_rgb_traces.mat (NEW filename,
% doesn't collide with the baseline's <subjectID>_rgb_traces.mat or Task
% I's <subjectID>_facemesh_rgb_traces.mat).
%
% Output: results/metrics/segment7_task_j_facemesh_hybrid_branch1_hr.csv.

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

csvPath = fullfile(metricsRoot, 'segment7_task_j_facemesh_hybrid_branch1_hr.csv');
headerLine = "subjectID,HR_groundtruth,HR_chrom_baseline,HR_chrom_hybrid,HR_pos_baseline,HR_pos_hybrid,HR_green_baseline,HR_green_hybrid,abs_error_chrom_baseline,abs_error_chrom_hybrid,abs_error_pos_baseline,abs_error_pos_hybrid,droppedFrames_hybrid,numFrames_hybrid";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task J hybrid Branch-1 batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);
    subjectStartTic = tic;

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_j_facemesh_hybrid_branch1_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_j_facemesh_hybrid_branch1_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
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

        % --- Hybrid ROI + Branch 1 (the new, expensive decode). ---
        hybridCachePath = fullfile(processedRoot, [subjectID '_facemesh_hybrid_rgb_traces.mat']);
        if isfile(hybridCachePath)
            cachedHy = load(hybridCachePath);
            R_hy = cachedHy.R; G_hy = cachedHy.G; B_hy = cachedHy.B; frameRateHy = cachedHy.fs;
            droppedFrameIdxHy = cachedHy.droppedFrameIdx;
            disp(['Subject ' subjectID ': reused cached hybrid traces from ' hybridCachePath]);
        else
            [framesHy, frameRateHy, ~] = loadUBFCVideo(videoPath);
            [R_hy, G_hy, B_hy, ~, droppedFrameIdxHy, ~] = faceMeshHybridROIExtraction(framesHy, frameRateHy);
            % Save with the plain names (R/G/B/fs/droppedFrameIdx) the
            % reload branch above expects, so a later reload needs no
            % special-case renaming.
            R = R_hy; G = G_hy; B = B_hy; fs = frameRateHy; droppedFrameIdx = droppedFrameIdxHy; %#ok<NASGU>
            save(hybridCachePath, 'R', 'G', 'B', 'fs', 'droppedFrameIdx', '-v7');
        end

        disp(['Subject ' subjectID ' hybrid ROI: dropped/no-face frames = ' num2str(numel(droppedFrameIdxHy)) ' / ' num2str(numel(R_hy))]);

        [R_hy_d, ~] = detrendSignal(R_hy);
        [G_hy_d, ~] = detrendSignal(G_hy);
        [B_hy_d, ~] = detrendSignal(B_hy);
        [R_hy_f, ~] = bandpassClean(R_hy_d, frameRateHy);
        [G_hy_f, ~] = bandpassClean(G_hy_d, frameRateHy);
        [B_hy_f, ~] = bandpassClean(B_hy_d, frameRateHy);

        pulseChromHy = chromCombine(R_hy_f, G_hy_f, B_hy_f, R_hy, G_hy, B_hy);
        pulseChromHyF = bandpassClean(pulseChromHy, frameRateHy);
        HR_chrom_hybrid = fftHeartRate(pulseChromHyF, frameRateHy);

        pulsePosHy = posCombine(R_hy_f, G_hy_f, B_hy_f, frameRateHy, R_hy, G_hy, B_hy);
        pulsePosHyF = bandpassClean(pulsePosHy, frameRateHy);
        HR_pos_hybrid = fftHeartRate(pulsePosHyF, frameRateHy);

        HR_green_hybrid = fftHeartRate(G_hy_f, frameRateHy);

        elapsedSubjectSec = toc(subjectStartTic);
        disp(['Subject ' subjectID ' HYBRID: HR_chrom=' num2str(HR_chrom_hybrid) ' HR_pos=' num2str(HR_pos_hybrid) ' HR_green=' num2str(HR_green_hybrid) ' (' num2str(elapsedSubjectSec, '%.0f') ' s)']);

        % --- Ground truth, windowed to this clip's duration (baseline
        % frame count as the reference duration -- same convention as
        % every prior HR batch script). ---
        videoDurationSec = numel(R_base) / frameRateBase;
        inClipMask = gt.timestamp <= videoDurationSec;
        HR_groundtruth = mean(gt.hr(inClipMask));

        absErrorChromBaseline = abs(HR_chrom_baseline - HR_groundtruth);
        absErrorChromHybrid = abs(HR_chrom_hybrid - HR_groundtruth);
        absErrorPosBaseline = abs(HR_pos_baseline - HR_groundtruth);
        absErrorPosHybrid = abs(HR_pos_hybrid - HR_groundtruth);

        disp(['Subject ' subjectID ' vs GT (' num2str(HR_groundtruth, '%.2f') ' bpm): ' ...
            'CHROM baseline err=' num2str(absErrorChromBaseline, '%.2f') ', hybrid err=' num2str(absErrorChromHybrid, '%.2f') ' | ' ...
            'POS baseline err=' num2str(absErrorPosBaseline, '%.2f') ', hybrid err=' num2str(absErrorPosHybrid, '%.2f')]);

        row = {subjectID, num2str(HR_groundtruth, '%.4f'), num2str(HR_chrom_baseline, '%.4f'), num2str(HR_chrom_hybrid, '%.4f'), ...
            num2str(HR_pos_baseline, '%.4f'), num2str(HR_pos_hybrid, '%.4f'), num2str(HR_green_baseline, '%.4f'), num2str(HR_green_hybrid, '%.4f'), ...
            num2str(absErrorChromBaseline, '%.4f'), num2str(absErrorChromHybrid, '%.4f'), num2str(absErrorPosBaseline, '%.4f'), num2str(absErrorPosHybrid, '%.4f'), ...
            num2str(numel(droppedFrameIdxHy)), num2str(numel(R_hy))};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task J hybrid Branch-1 batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

disp(['Saved ' csvPath]);
