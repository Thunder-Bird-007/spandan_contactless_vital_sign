% RUN_SEGMENT7_TASK_C2_TRUE_COMBINED_BATCH Segment 7 Task C, Action 2.
% Fixes a confound in scripts/run_segment7_task_c_combined_batch.m
% (Task C's first combined-methods test, "Combined-v1"): that script ran
% morphology/adaptiveHarmonicFilter.m on morphology/tiledROIExtraction.m's
% OUTPUT -- a pipeline position that has already been through a flat
% 'wide' Butterworth bandpass AND chromCombine.m AND cross-tile weighted
% averaging. This is NOT the pipeline position adaptiveHarmonicFilter.m
% occupies in ABPF-only (scripts/run_segment7_task_b_branch2_batch.m),
% where it substitutes for morphology/bandpassMorphology.m BEFORE
% chromCombine.m, per-channel. Combined-v1's "not additive" conclusion
% was confounded by this mismatch and is marked SUPERSEDED in
% docs/Segment7_Task_B_Notch_Quantification.md (not deleted).
%
% This script ("Combined-v2", the TRUE combined test) instead calls
% morphology/tiledROIExtraction.m with its new filterMode='harmonic'
% option (Task C Action 1), which makes the harmonic-comb substitution
% at the correct pipeline position, per-tile -- the same operating point
% ABPF-only itself uses, just tiled instead of whole-ROI.
%
% Per subject:
%   1. One whole-ROI (non-tiled) decode via loadUBFCVideo.m ->
%      roi/extractROISignals.m, EXACTLY as
%      scripts/run_segment7_task_b_branch2_batch.m does for its own
%      sharedF0Hz -- detrend -> bandpassMorphology.m('wide') ->
%      chromCombine.m -> fftHeartRate.m/60. This is a single f0 estimate
%      from the whole-ROI wide-band CHROM pulse, the SAME source and
%      method ABPF-only's own sharedF0Hz uses, so Combined-v2 is
%      evaluated at ABPF-only's own operating point, not a new one.
%   2. tiledROIExtraction(videoPath, [], gridRows, gridCols, 'harmonic',
%      sharedF0Hz) -- bandMode is [] because it is ignored in 'harmonic'
%      mode (see that function's own header). This performs its own,
%      separate tiled decode internally (same as every other tiled-ROI
%      condition in this project).
%   3. fixPolarityByGroundTruth.m -> resampleUniform.m ->
%      ensembleAverageBeats.m -> notchDetectIEM.m, identical tail to
%      every other Task B/C condition.
%
% Does NOT modify morphology/bandpassMorphology.m, morphology/ensembleAverageBeats.m,
% notchDetectIEM.m's detection algorithm, or either existing Task B/C
% batch script -- new, additive script, new, separately-named output.
%
% Output: results/metrics/segment7_task_c2_true_combined_notch.csv, same
% columns as segment7_task_c_combined_notch.csv (Combined-v1), including
% confidenceRaw.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
gridRows = 4;
gridCols = 4;

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_c2_true_combined_notch.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,effectiveFsHz,hrBpmUsed,beatsAveraged";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

combinedV2DetectedCount = 0;
combinedV2ConfidentCount = 0;
confidenceThreshold = 1.0; % same bar as every other Task B/C batch

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task C2 true-combined batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_c2_true_combined_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_c2_true_combined_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % --- Step 1: shared f0, from the whole-ROI wide-band CHROM
        % pulse -- EXACTLY run_segment7_task_b_branch2_batch.m's own
        % sharedF0Hz computation, so Combined-v2 uses ABPF-only's own
        % f0 estimation convention, not a new one invented for this
        % script. ---
        [frames, frameRate, ~] = loadUBFCVideo(videoPath);
        [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate); %#ok<ASGLU>

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        [R_wide, ~, ~] = bandpassMorphology(R_detrended, frameRate, 'wide');
        [G_wide, ~, ~] = bandpassMorphology(G_detrended, frameRate, 'wide');
        [B_wide, ~, ~] = bandpassMorphology(B_detrended, frameRate, 'wide');
        pulseWide = chromCombine(R_wide, G_wide, B_wide, R, G, B);
        sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;

        % --- Step 2: tiled ROI extraction with the harmonic-comb
        % substitution made at the CORRECT pipeline position (per-tile,
        % before each tile's own chromCombine.m call) -- Task C Action
        % 1's fix. bandMode passed as [] since it is ignored in
        % 'harmonic' mode. ---
        [pulseTiledHarmonic, roiTimestampsTiled, ~, frameRateTiled] = tiledROIExtraction(videoPath, [], gridRows, gridCols, 'harmonic', sharedF0Hz); %#ok<ASGLU>

        % --- Step 3: same tail as every other Task B/C condition. ---
        [pulseFixed, wasFlipped] = fixPolarityByGroundTruth(pulseTiledHarmonic, roiTimestampsTiled, gt.ppg, gt.timestamp);
        [sigUniform, ~, uniformFs] = resampleUniform(pulseFixed, roiTimestampsTiled);
        [prototype, ~, ~, beatStats] = ensembleAverageBeats(sigUniform, uniformFs);

        hrBpm = fftHeartRate(sigUniform, uniformFs);
        effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

        [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFs);

        disp(['Subject ' subjectID ' combined-v2 (true, tiled-harmonic, wasFlipped=' num2str(wasFlipped) '): notchDetected=' num2str(notchDetected) ', pos=' num2str(notchPos, '%.4f') ', depth=' num2str(notchDepth, '%.4f') ', confidence=' num2str(confidence, '%.4f') ', confidenceRaw=' num2str(confidenceRaw, '%.4f')]);

        row = {subjectID, num2str(notchDetected), num2str(notchPos, '%.4f'), num2str(notchDepth, '%.4f'), num2str(confidence, '%.4f'), num2str(confidenceRaw, '%.4f'), num2str(effectiveFs, '%.4f'), num2str(hrBpm, '%.4f'), num2str(beatStats.beatsAveraged)};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        if notchDetected
            combinedV2DetectedCount = combinedV2DetectedCount + 1;
            if confidence >= confidenceThreshold
                combinedV2ConfidentCount = combinedV2ConfidentCount + 1;
            end
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task C2 true-combined batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Combined-v2 (true, tiled-harmonic) notch detection rate: ' num2str(combinedV2DetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(combinedV2ConfidentCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);
