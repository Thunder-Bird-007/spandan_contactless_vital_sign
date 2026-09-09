% TASK_SOURCE2_FPSFIX_REPROCESS Segment 8 (post-review follow-up), Action
% 2. Re-runs ONLY the 12 VIPL-HR source2 (HUAWEI P9 phone) subjects
% already in results/metrics/segment4_hr_summary_vipl.csv through the
% EXACT SAME production HR path as scripts/run_vipl_integration_batch.m
% (detrendSignal -> bandpassClean -> chromCombine/posCombine ->
% fftHeartRate, same functions, same parameters, same 'forehead' ROI
% mode), with ONE difference: fs is the source2 true frame rate derived in
% task_source2_fps_investigation.m (from a sibling source's time.txt),
% not the container's 25 fps that io/loadVIPLVideo.m falls back to for
% source2.
%
% Does NOT modify loadVIPLVideo.m, extractROISignals.m, detrendSignal.m,
% bandpassClean.m, chromCombine.m, posCombine.m, or fftHeartRate.m -- all
% called unmodified, exactly as run_vipl_integration_batch.m calls them.
% Does NOT touch results/metrics/segment4_hr_summary_vipl.csv or any other
% existing metrics file -- writes ONLY to the new
% results/metrics/segment4_hr_summary_vipl_source2_fpsfix.csv.
%
% Requires results/metrics/segment8_source2_fps_investigation.csv (Action
% 1's output) to already exist -- run task_source2_fps_investigation.m
% first. Ground truth (gt_HR.csv) is read here ONLY to compute the new
% abs_error columns for reporting, exactly as run_vipl_integration_batch.m
% already does for the old numbers -- it plays no role in choosing fs
% (that was fixed already, in Action 1, without ever looking at gt_HR.csv).

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

fpsCsvPath = fullfile(metricsRoot, 'segment8_source2_fps_investigation.csv');
oldCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');
newCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl_source2_fpsfix.csv');

if ~isfile(fpsCsvPath)
    error('task_source2_fpsfix_reprocess:missingFpsTable', ...
        'Run task_source2_fps_investigation.m first -- %s not found.', fpsCsvPath);
end

fpsTable = readtable(fpsCsvPath, 'TextType', 'string');
oldTable = readtable(oldCsvPath, 'TextType', 'string');

newHeaderLine = "subjectID,dataset,fps_old_container,fps_new_truefps,HR_chrom_old,HR_pos_old,HR_chrom_new,HR_pos_new,HR_groundtruth,abs_error_chrom_old,abs_error_pos_old,abs_error_chrom_new,abs_error_pos_new";
writelines(newHeaderLine, newCsvPath);

numFpsSubjects = height(fpsTable);
resultsAll = struct('subjectID', {}, 'HR_chrom_old', {}, 'HR_pos_old', {}, ...
    'HR_chrom_new', {}, 'HR_pos_new', {}, 'HR_groundtruth', {});

failedSubjects = {};
failedReasons = {};

fprintf('%-24s %10s %10s %10s %10s %10s %10s\n', 'subjectID', 'HR_c_old', 'HR_c_new', 'HR_p_old', 'HR_p_new', 'GT', 'newFps');

for idx = 1:numFpsSubjects
    subjectID = char(fpsTable.subjectID(idx));
    trueFps = fpsTable.trueFps_source2(idx);
    containerFps = fpsTable.containerFps(idx);

    % subjectID is e.g. "VIPL_p97_v1_source2" -- parse it back out.
    tok = regexp(subjectID, '^VIPL_p(\d+)_v(\d+)_source2$', 'tokens', 'once');
    if isempty(tok)
        disp([subjectID ': subjectID does not match expected VIPL_pN_vN_source2 pattern -- skipping.']);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = 'unparseable subjectID'; %#ok<AGROW>
        continue;
    end
    subjectNum = str2double(tok{1});
    scenarioNum = str2double(tok{2});

    disp(['--- Reprocessing ' subjectID ' with corrected fps = ' num2str(trueFps, '%.4f') ' (was ' num2str(containerFps, '%.4f') ') ---']);

    try
        videoPath = fullfile(viplRoot, ['p' num2str(subjectNum)], ['v' num2str(scenarioNum)], 'source2', 'video.avi');
        if ~isfile(videoPath)
            error('task_source2_fpsfix_reprocess:missingVideo', 'Video not found: %s', videoPath);
        end

        videoReaderObj = VideoReader(videoPath); % same object type loadVIPLVideo.m returns; fs overridden below

        % Same call as run_vipl_integration_batch.m -- 'forehead' is
        % extractROISignals.m's own default roiMode, passed explicitly
        % here for clarity, same as elsewhere in this project.
        [R, G, B, ~, droppedFrameIdx, ~] = extractROISignals(videoReaderObj, trueFps, 'forehead');

        disp([subjectID ': dropped/reused-bbox frames = ' num2str(numel(droppedFrameIdx))]);

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        [R_filtered, ~] = bandpassClean(R_detrended, trueFps);
        [G_filtered, ~] = bandpassClean(G_detrended, trueFps);
        [B_filtered, ~] = bandpassClean(B_detrended, trueFps);

        pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
        pulseChromFiltered = bandpassClean(pulseChrom, trueFps);
        [HR_chrom_new, ~, ~] = fftHeartRate(pulseChromFiltered, trueFps);

        pulsePos = posCombine(R_filtered, G_filtered, B_filtered, trueFps, R, G, B);
        pulsePosFiltered = bandpassClean(pulsePos, trueFps);
        [HR_pos_new, ~, ~] = fftHeartRate(pulsePosFiltered, trueFps);

        gt = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, 2);
        HR_groundtruth = mean(gt.hr);

        oldRow = oldTable(oldTable.subjectID == subjectID, :);
        if height(oldRow) ~= 1
            error('task_source2_fpsfix_reprocess:oldRowNotFound', 'Expected exactly 1 row for %s in %s, found %d.', subjectID, oldCsvPath, height(oldRow));
        end
        HR_chrom_old = oldRow.HR_chrom(1);
        HR_pos_old = oldRow.HR_pos(1);

        absErrorChromOld = abs(HR_chrom_old - HR_groundtruth);
        absErrorPosOld = abs(HR_pos_old - HR_groundtruth);
        absErrorChromNew = abs(HR_chrom_new - HR_groundtruth);
        absErrorPosNew = abs(HR_pos_new - HR_groundtruth);

        fprintf('%-24s %10.2f %10.2f %10.2f %10.2f %10.2f %10.4f\n', subjectID, HR_chrom_old, HR_chrom_new, HR_pos_old, HR_pos_new, HR_groundtruth, trueFps);

        rowParts = {subjectID, 'VIPL', num2str(containerFps, '%.4f'), num2str(trueFps, '%.4f'), ...
            num2str(HR_chrom_old), num2str(HR_pos_old), num2str(HR_chrom_new), num2str(HR_pos_new), ...
            num2str(HR_groundtruth), num2str(absErrorChromOld), num2str(absErrorPosOld), ...
            num2str(absErrorChromNew), num2str(absErrorPosNew)};
        rowLine = strjoin(rowParts, ',');
        writelines(rowLine, newCsvPath, 'WriteMode', 'append');

        resultsAll(end + 1) = struct('subjectID', subjectID, 'HR_chrom_old', HR_chrom_old, ...
            'HR_pos_old', HR_pos_old, 'HR_chrom_new', HR_chrom_new, 'HR_pos_new', HR_pos_new, ...
            'HR_groundtruth', HR_groundtruth); %#ok<AGROW>
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp(' ');
disp(['--- Reprocessing complete. Saved ' newCsvPath ' ---']);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for k = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{k} ': ' failedReasons{k}]);
end

% === Hypothetical pooled-107 metrics if these subjects' CHROM/POS were
% replaced with the corrected-fps values -- computed and printed only, NOT
% written to results/metrics/segment6_hr_pooled_metrics.csv or any other
% existing/validated metrics file. ===
disp(' ');
disp('=== HYPOTHETICAL pooled VIPL 107-subject metrics if these 12 source2 rows were replaced (NOT a validated update) ===');

pooledChromOld = oldTable.HR_chrom;
pooledPosOld = oldTable.HR_pos;
pooledGT = oldTable.HR_groundtruth;
pooledSubjectID = oldTable.subjectID;

pooledChromHypo = pooledChromOld;
pooledPosHypo = pooledPosOld;

for k = 1:numel(resultsAll)
    rowMask = pooledSubjectID == string(resultsAll(k).subjectID);
    pooledChromHypo(rowMask) = resultsAll(k).HR_chrom_new;
    pooledPosHypo(rowMask) = resultsAll(k).HR_pos_new;
end

printPooledMetrics('CHROM, ORIGINAL (all 107, container fps for source2)', pooledChromOld, pooledGT);
printPooledMetrics('CHROM, HYPOTHETICAL (12 source2 subjects fps-corrected)', pooledChromHypo, pooledGT);
printPooledMetrics('POS,   ORIGINAL (all 107, container fps for source2)', pooledPosOld, pooledGT);
printPooledMetrics('POS,   HYPOTHETICAL (12 source2 subjects fps-corrected)', pooledPosHypo, pooledGT);

function printPooledMetrics(label, estimates, groundtruth)
validMask = ~isnan(estimates) & ~isnan(groundtruth);
err = estimates(validMask) - groundtruth(validMask);
mae = mean(abs(err));
rmse = sqrt(mean(err.^2));
rMatrix = corrcoef(estimates(validMask), groundtruth(validMask));
rVal = rMatrix(1, 2);
disp([label ': n=' num2str(sum(validMask)) ', MAE=' num2str(mae, '%.4f') ' bpm, RMSE=' num2str(rmse, '%.4f') ' bpm, r=' num2str(rVal, '%.4f')]);
end
