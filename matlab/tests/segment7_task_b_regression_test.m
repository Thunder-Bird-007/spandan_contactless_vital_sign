% SEGMENT7_TASK_B_REGRESSION_TEST Segment 7 Task B, Action 6. Confirms
% that adding the optional `groundTruth` argument to
% morphology/extractMorphologyWaveform.m (Task B, Action 1) did not
% change that function's original 2-arg (no ground truth) behaviour, and
% re-confirms the Task A HR-path regression check still passes.
%
% Part 1: re-runs morphology/extractMorphologyWaveform.m on subject 5-gt
% with the ORIGINAL 2-arg call (videoPath, 'wide') -- i.e. groundTruth
% omitted, which per the new code must take the heuristic
% morphology/fixPolarity.m branch, exactly Task A's own behaviour -- and
% compares beatMatrix, prototype.trimmedMean, prototype.median,
% wasFlipped, and skewValue via isequal() against
% data/processed/segment7_task_a_regression_snapshot_5gt.mat, a snapshot
% saved from this exact function BEFORE Task B's Action 1 edit was made.
%
% Part 2: re-runs tests/segment7_regression_test.m (Task A's own HR-path
% regression check) to reconfirm the pre-existing HR path
% (filtering/bandpassClean.m, filtering/detrendSignal.m,
% pulseextraction/chromCombine.m, pulseextraction/posCombine.m,
% heartrate/fftHeartRate.m) is still untouched -- Task B, like Task A,
% never opens any of those files.
%
% Both parts must PASS (isequal true, no error) for Task B's Actions 1-5
% to be considered non-regressive. Run via
% matlab -batch "startup; run('tests/segment7_task_b_regression_test.m')".

subjectID = '5-gt';

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');

snapshotPath = fullfile(processedDataRoot, ['segment7_task_a_regression_snapshot_' subjectID '.mat']);
if ~isfile(snapshotPath)
    error('segment7_task_b_regression_test:missingSnapshot', 'Pre-Task-B snapshot not found: %s', snapshotPath);
end
snapshot = load(snapshotPath);

subjectDir = fullfile(dataset1Root, subjectID);
aviFiles = dir(fullfile(subjectDir, '*.avi'));
if isempty(aviFiles)
    error('segment7_task_b_regression_test:missingVideo', 'No .avi file found under: %s', subjectDir);
end
videoPath = fullfile(subjectDir, aviFiles(1).name);

disp('=== Part 1: extractMorphologyWaveform.m 2-arg (no ground truth) regression ===');
disp(['Recomputing subject ' subjectID ' via the ORIGINAL 2-arg call (groundTruth omitted) ...']);

result = extractMorphologyWaveform(videoPath, 'wide');

beatMatrixMatch = isequal(result.beatMatrix, snapshot.beatMatrix);
trimmedMeanMatch = isequal(result.prototype.trimmedMean, snapshot.prototype.trimmedMean);
medianMatch = isequal(result.prototype.median, snapshot.prototype.median);
wasFlippedMatch = isequal(result.wasFlipped, snapshot.wasFlipped);
skewValueMatch = isequal(result.skewValue, snapshot.skewValue);

disp(['beatMatrix isequal:            ' num2str(beatMatrixMatch)]);
disp(['prototype.trimmedMean isequal: ' num2str(trimmedMeanMatch)]);
disp(['prototype.median isequal:      ' num2str(medianMatch)]);
disp(['wasFlipped isequal:            ' num2str(wasFlippedMatch) ' (' num2str(result.wasFlipped) ' vs ' num2str(snapshot.wasFlipped) ')']);
disp(['skewValue isequal:             ' num2str(skewValueMatch) ' (' num2str(result.skewValue, '%.6f') ' vs ' num2str(snapshot.skewValue, '%.6f') ')']);

part1Pass = beatMatrixMatch && trimmedMeanMatch && medianMatch && wasFlippedMatch && skewValueMatch;

if ~part1Pass
    error('segment7_task_b_regression_test:part1Failed', 'extractMorphologyWaveform.m''s 2-arg (no ground truth) behaviour changed for subject %s -- Task B''s Action 1 edit leaked into the no-ground-truth code path. Must be reverted.', subjectID);
end

disp('=== Part 1 PASS ===');

disp('=== Part 2: re-running tests/segment7_regression_test.m (Task A HR-path check) ===');
run(fullfile(thisFileDir, 'segment7_regression_test.m'));

disp('=== Segment 7 Task B regression test: ALL PASS ===');
