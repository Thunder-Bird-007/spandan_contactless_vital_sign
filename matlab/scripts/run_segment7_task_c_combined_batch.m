% RUN_SEGMENT7_TASK_C_COMBINED_BATCH Segment 7 Task C, Action 3. Combines
% the two Task B branch-2 methods that were tested SEPARATELY --
% morphology/tiledROIExtraction.m (correlation-weighted 4x4 tiled ROI)
% and morphology/adaptiveHarmonicFilter.m (harmonic-comb filtering) --
% into ONE pipeline, applied to all 5 locally-available UBFC DATASET_1
% subjects, then reruns morphology/notchDetectIEM.m to check whether
% combining the two is additive (reaches subjects neither alone reached)
% or not.
%
% Per subject:
%   1. tiledROIExtraction.m (bandMode='wide') -> pulseCombined (already a
%      single combined pulse signal, NOT raw R/G/B -- see that
%      function's own header. adaptiveHarmonicFilter.m is therefore run
%      on this single combined pulse, not on per-tile/per-channel R/G/B).
%   2. adaptiveHarmonicFilter.m on that combined pulse, using a shared f0
%      estimated from the SAME combined pulse (fftHeartRate.m), same
%      convention as scripts/run_segment7_task_b_branch2_batch.m's
%      sharedF0Hz for its own adaptive-harmonic condition.
%   3. fixPolarityByGroundTruth.m -> resampleUniform.m ->
%      ensembleAverageBeats.m -> notchDetectIEM.m, same chain as every
%      other Task B/C condition.
%
% Does NOT modify tiledROIExtraction.m, adaptiveHarmonicFilter.m,
% notchDetectIEM.m's algorithm, morphology/bandpassMorphology.m,
% morphology/ensembleAverageBeats.m, or either existing Task B batch
% script -- this is a new, additive script producing a new, separately-
% named output.
%
% Output: results/metrics/segment7_task_c_combined_notch.csv, one row
% per subject: notchDetected, notchPositionNormalized, notchDepth,
% confidence, confidenceRaw, effectiveFsHz, hrBpmUsed, beatsAveraged.
%
% See docs/Segment7_Task_B_Notch_Quantification.md for the side-by-side
% baseline / ABPF-only / tiled-only / combined comparison table this
% script's output feeds.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_c_combined_notch.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,effectiveFsHz,hrBpmUsed,beatsAveraged";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

combinedDetectedCount = 0;
combinedConfidentCount = 0;
confidenceThreshold = 1.0; % same bar as run_segment7_task_b_branch2_batch.m

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task C combined batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_c_combined_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_c_combined_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % --- Step 1: tiled ROI extraction, already a single combined
        % pulse signal (correlation-weighted across 16 tiles). ---
        [pulseTiled, roiTimestampsTiled, ~, frameRateTiled] = tiledROIExtraction(videoPath, 'wide');

        % --- Step 2: adaptive harmonic-comb filter applied to THAT
        % combined pulse (not raw R/G/B -- there is no separate R/G/B to
        % filter once tiledROIExtraction.m has already combined tiles
        % into one pulse). f0 is estimated from this same combined pulse
        % via fftHeartRate.m (unmodified), then passed back in as
        % f0HzOverride so the filter's internal re-estimation step is
        % skipped in favor of this single, already-computed value --
        % there is only one signal here, so there is no cross-channel
        % misalignment risk to guard against the way
        % run_segment7_task_b_branch2_batch.m's R/G/B case has.
        sharedF0Hz = fftHeartRate(pulseTiled, frameRateTiled) / 60;
        [pulseCombinedFiltered, ~, ~] = adaptiveHarmonicFilter(pulseTiled, frameRateTiled, 6, sharedF0Hz);

        % --- Step 3: same tail as every other Task B/C condition. ---
        [pulseFixed, wasFlipped] = fixPolarityByGroundTruth(pulseCombinedFiltered, roiTimestampsTiled, gt.ppg, gt.timestamp);
        [sigUniform, ~, uniformFs] = resampleUniform(pulseFixed, roiTimestampsTiled);
        [prototype, ~, ~, beatStats] = ensembleAverageBeats(sigUniform, uniformFs);

        hrBpm = fftHeartRate(sigUniform, uniformFs);
        effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

        [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFs);

        disp(['Subject ' subjectID ' combined (tiled+adaptive, wasFlipped=' num2str(wasFlipped) '): notchDetected=' num2str(notchDetected) ', pos=' num2str(notchPos, '%.4f') ', depth=' num2str(notchDepth, '%.4f') ', confidence=' num2str(confidence, '%.4f') ', confidenceRaw=' num2str(confidenceRaw, '%.4f')]);

        row = {subjectID, num2str(notchDetected), num2str(notchPos, '%.4f'), num2str(notchDepth, '%.4f'), num2str(confidence, '%.4f'), num2str(confidenceRaw, '%.4f'), num2str(effectiveFs, '%.4f'), num2str(hrBpm, '%.4f'), num2str(beatStats.beatsAveraged)};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        if notchDetected
            combinedDetectedCount = combinedDetectedCount + 1;
            if confidence >= confidenceThreshold
                combinedConfidentCount = combinedConfidentCount + 1;
            end
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task C combined batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Combined (tiled ROI + adaptive harmonic) notch detection rate: ' num2str(combinedDetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(combinedConfidentCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);
