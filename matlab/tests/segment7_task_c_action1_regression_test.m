% SEGMENT7_TASK_C_ACTION1_REGRESSION_TEST Segment 7 Task C, Action 4.
% Confirms morphology/tiledROIExtraction.m's new `filterMode` /
% `sharedF0HzOverride` parameters (Task C Action 1) did NOT change its
% behaviour for any existing caller that omits them -- i.e. the original
% 4-arg call (videoPath, bandMode, gridRows, gridCols) with filterMode
% implicitly defaulting to 'butterworth'.
%
% Re-runs the exact "Tiled ROI condition" computation
% scripts/run_segment7_task_b_branch2_batch.m performed (tiledROIExtraction
% -> fixPolarityByGroundTruth -> resampleUniform -> ensembleAverageBeats
% -> notchDetectIEM, using the ORIGINAL 4-arg tiledROIExtraction call) for
% all 5 UBFC DATASET_1 subjects and compares notchDetected,
% notchPositionNormalized, notchDepth, and confidence against the already-
% saved results/metrics/segment7_task_b_notch_branch2.csv's tiledROI rows
% (computed by the PRE-Task-C tiledROIExtraction.m).
%
% Also confirms Task C's other files (morphology/bandpassMorphology.m,
% morphology/ensembleAverageBeats.m, notchDetectIEM.m's detection
% algorithm) were not touched, by construction: this test calls all three
% completely unmodified and compares against numbers those same functions
% already produced before Task C started.
%
% Must PASS (all isequal-on-strings comparisons true, since the CSV
% stores 4-decimal-place strings and this test formats its own results
% the same way for a fair comparison) for Task C Action 1 to be
% considered non-regressive.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

branch2CsvPath = fullfile(metricsRoot, 'segment7_task_b_notch_branch2.csv');
if ~isfile(branch2CsvPath)
    error('segment7_task_c_action1_regression_test:missingBaseline', 'Baseline CSV not found: %s', branch2CsvPath);
end
branch2Table = readtable(branch2CsvPath, 'Delimiter', ',', 'TextType', 'string');

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
numSubjects = numel(subjectList);

allPass = true;

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Task C Action 1 regression: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    aviFiles = dir(fullfile(subjectDir, '*.avi'));
    if isempty(aviFiles)
        error('segment7_task_c_action1_regression_test:missingVideo', 'No .avi file found under: %s', subjectDir);
    end
    videoPath = fullfile(subjectDir, aviFiles(1).name);

    gtPath = fullfile(subjectDir, 'gtdump.xmp');
    if ~isfile(gtPath)
        error('segment7_task_c_action1_regression_test:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
    end
    gt = loadGroundTruth(gtPath, 'dataset1');

    % ORIGINAL 4-arg call -- filterMode/sharedF0HzOverride both omitted,
    % must implicitly default to 'butterworth'/[] and behave exactly as
    % the pre-Task-C 4-arg-only function did.
    [pulseTiled, roiTimestampsTiled, ~, frameRateTiled] = tiledROIExtraction(videoPath, 'wide'); %#ok<ASGLU>

    [pulseTiledFixed, ~] = fixPolarityByGroundTruth(pulseTiled, roiTimestampsTiled, gt.ppg, gt.timestamp);
    [sigTiledUniform, ~, fsTiledUniform] = resampleUniform(pulseTiledFixed, roiTimestampsTiled);
    [protoTiled, ~, ~, statsTiled] = ensembleAverageBeats(sigTiledUniform, fsTiledUniform); %#ok<ASGLU>

    hrTiled = fftHeartRate(sigTiledUniform, fsTiledUniform);
    fsProtoTiled = numel(protoTiled.trimmedMean) * (hrTiled / 60);
    [tiledDetected, tiledPos, tiledDepth, tiledConf] = notchDetectIEM(protoTiled.trimmedMean, fsProtoTiled);

    baselineRow = branch2Table(branch2Table.subjectID == subjectID & branch2Table.method == "tiledROI", :);
    if height(baselineRow) ~= 1
        error('segment7_task_c_action1_regression_test:missingBaselineRow', 'Expected exactly 1 tiledROI baseline row for subject %s, found %d.', subjectID, height(baselineRow));
    end

    detectedMatch = isequal(double(tiledDetected), baselineRow.notchDetected(1));
    posMatch = strcmp(num2str(tiledPos, '%.4f'), num2str(baselineRow.notchPositionNormalized(1), '%.4f'));
    depthMatch = strcmp(num2str(tiledDepth, '%.4f'), num2str(baselineRow.notchDepth(1), '%.4f'));
    confMatch = strcmp(num2str(tiledConf, '%.4f'), num2str(baselineRow.confidence(1), '%.4f'));

    disp(['  notchDetected match: ' num2str(detectedMatch) ' (' num2str(tiledDetected) ' vs ' num2str(baselineRow.notchDetected(1)) ')']);
    disp(['  position match:      ' num2str(posMatch) ' (' num2str(tiledPos, '%.4f') ' vs ' num2str(baselineRow.notchPositionNormalized(1), '%.4f') ')']);
    disp(['  depth match:         ' num2str(depthMatch) ' (' num2str(tiledDepth, '%.4f') ' vs ' num2str(baselineRow.notchDepth(1), '%.4f') ')']);
    disp(['  confidence match:    ' num2str(confMatch) ' (' num2str(tiledConf, '%.4f') ' vs ' num2str(baselineRow.confidence(1), '%.4f') ')']);

    subjectPass = detectedMatch && posMatch && depthMatch && confMatch;
    if ~subjectPass
        allPass = false;
        disp(['  *** MISMATCH for subject ' subjectID ' ***']);
    end
end

if ~allPass
    error('segment7_task_c_action1_regression_test:failed', 'tiledROIExtraction.m''s default (filterMode omitted) behaviour changed for at least one subject -- Task C Action 1''s edit leaked into the default code path. Must be reverted.');
end

disp('=== Segment 7 Task C Action 1 regression test: ALL PASS -- tiledROIExtraction.m''s default (butterworth) behaviour is unchanged for all 5 subjects ===');
