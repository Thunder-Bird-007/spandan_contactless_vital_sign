% RUN_SEGMENT7_TASK_D2_FROZEN_CADENCE_BATCH Segment 7 Task D2, Action 2.
%
% Task D found that Landmark/KLT-ROI+ABPF (continuous per-frame
% transform + re-rasterization) badly regresses ABPF-only baseline: 4/5
% -> 2/5 subjects above the >=0.3 confidence bar, with 0 dropped/fallback
% frames on every subject (so not explained by lost tracking). The
% leading hypothesis (docs/Segment7_Task_D_Landmark_ROI.md, Task D2
% section): roi/extractROISignals.m only recomputes its ROI box at
% detectEveryN=5 anchor frames and reuses it UNCHANGED between anchors;
% roi/landmarkROIExtraction.m's default (freezeCadence=false) mode
% instead calls estimateGeometricTransform2D + poly2mask on EVERY frame,
% so per-frame tracking noise flips a ring of boundary pixels in and out
% of the spatial mean every single frame -- a noise source the
% fixed-box baseline structurally cannot have, and one ABPF's narrow
% harmonic-comb filter is especially sensitive to.
%
% This script reruns all 5 subjects with roi/landmarkROIExtraction.m's
% NEW freezeCadence=true mode (Task D2, Action 1) -- still
% rotation-compensated, but updated only once per detectEveryN=5 cycle,
% mirroring roi/extractROISignals.m's own currentBBox = lastGoodBBox
% cadence exactly -- through the IDENTICAL downstream chain
% scripts/run_segment7_task_d_landmark_roi_batch.m already established
% (detrend -> adaptiveHarmonicFilter with shared f0 -> chromCombine ->
% fixPolarityByGroundTruth -> resampleUniform -> ensembleAverageBeats ->
% notchDetectIEM). Only the ROI stage's update cadence differs from
% Task D's own script; everything else -- including the shared-f0 source
% -- is unchanged, so the three-way comparison in
% docs/Segment7_Task_D_Landmark_ROI.md isolates the cadence variable
% alone.
%
% Does NOT modify roi/landmarkROIExtraction.m's freezeCadence=false code
% path (see that function's own Action 4/5-equivalent regression check),
% roi/extractROISignals.m, filtering/detrendSignal.m,
% morphology/adaptiveHarmonicFilter.m, pulseextraction/chromCombine.m,
% morphology/fixPolarityByGroundTruth.m, morphology/resampleUniform.m,
% morphology/ensembleAverageBeats.m, or morphology/notchDetectIEM.m --
% new, additive script, new, separately-named output.
%
% Output: results/metrics/segment7_task_d2_frozen_cadence_notch.csv,
% same columns as segment7_task_d_landmark_notch.csv, including
% confidenceRaw.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_d2_frozen_cadence_notch.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,effectiveFsHz,hrBpmUsed,beatsAveraged,droppedFrameCount,numFrames";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

frozenDetectedCount = 0;
frozenConfidentCount = 0;
confidenceThreshold = 1.0; % same bar as every other Task B/C/D batch

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task D2 frozen-cadence batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_d2_frozen_cadence_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_d2_frozen_cadence_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % --- Step 1: shared f0, from the EXISTING baseline whole-ROI
        % wide-band CHROM pulse -- IDENTICAL source/method to
        % run_segment7_task_d_landmark_roi_batch.m's own sharedF0Hz, so
        % all three conditions in the Task D2 comparison table share the
        % exact same f0 operating point. ---
        [framesForF0, frameRateForF0, ~] = loadUBFCVideo(videoPath);
        [R_base, G_base, B_base, roiTimestampsBase, ~, ~] = extractROISignals(framesForF0, frameRateForF0);

        [R_base_detrended, ~] = detrendSignal(R_base);
        [G_base_detrended, ~] = detrendSignal(G_base);
        [B_base_detrended, ~] = detrendSignal(B_base);

        [R_base_wide, ~, ~] = bandpassMorphology(R_base_detrended, frameRateForF0, 'wide');
        [G_base_wide, ~, ~] = bandpassMorphology(G_base_detrended, frameRateForF0, 'wide');
        [B_base_wide, ~, ~] = bandpassMorphology(B_base_detrended, frameRateForF0, 'wide');
        pulseBaseWide = chromCombine(R_base_wide, G_base_wide, B_base_wide, R_base, G_base, B_base);
        sharedF0Hz = fftHeartRate(pulseBaseWide, frameRateForF0) / 60; %#ok<NASGU>

        % --- Step 2: frozen-cadence landmark/KLT-ROI decode (own,
        % separate decode -- fresh VideoReader, same reasoning
        % run_segment7_task_d_landmark_roi_batch.m already documents for
        % why its own second decode is necessary). freezeCadence=true is
        % the ONLY difference from Task D's own script. ---
        [framesForLandmark, frameRateForLandmark, ~] = loadUBFCVideo(videoPath);
        [R_lm, G_lm, B_lm, roiTimestampsLm, droppedFrameIdxLm, ~] = landmarkROIExtraction(framesForLandmark, frameRateForLandmark, true);

        disp(['Subject ' subjectID ' frozen-cadence landmark-ROI: dropped/fallback frames = ' num2str(numel(droppedFrameIdxLm)) ' / ' num2str(numel(R_lm))]);

        [R_lm_detrended, ~] = detrendSignal(R_lm);
        [G_lm_detrended, ~] = detrendSignal(G_lm);
        [B_lm_detrended, ~] = detrendSignal(B_lm);

        % --- Step 3: ABPF at its correct, unconfounded operating point
        % -- per-channel, before chromCombine.m -- using the SHARED f0
        % from Step 1, identical substitution to Task D's own script. ---
        [R_lm_ahf, ~, ~] = adaptiveHarmonicFilter(R_lm_detrended, frameRateForLandmark, 6, sharedF0Hz);
        [G_lm_ahf, ~, ~] = adaptiveHarmonicFilter(G_lm_detrended, frameRateForLandmark, 6, sharedF0Hz);
        [B_lm_ahf, ~, ~] = adaptiveHarmonicFilter(B_lm_detrended, frameRateForLandmark, 6, sharedF0Hz);
        pulseLandmarkAdaptive = chromCombine(R_lm_ahf, G_lm_ahf, B_lm_ahf, R_lm, G_lm, B_lm);

        % --- Step 4: same tail as every other Task B/C/D condition. ---
        [pulseFixed, wasFlipped] = fixPolarityByGroundTruth(pulseLandmarkAdaptive, roiTimestampsLm, gt.ppg, gt.timestamp);
        [sigUniform, ~, uniformFs] = resampleUniform(pulseFixed, roiTimestampsLm);
        [prototype, ~, ~, beatStats] = ensembleAverageBeats(sigUniform, uniformFs);

        hrBpm = fftHeartRate(sigUniform, uniformFs);
        effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

        [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFs);

        disp(['Subject ' subjectID ' frozen-cadence landmark-ROI+ABPF (wasFlipped=' num2str(wasFlipped) '): notchDetected=' num2str(notchDetected) ', pos=' num2str(notchPos, '%.4f') ', depth=' num2str(notchDepth, '%.4f') ', confidence=' num2str(confidence, '%.4f') ', confidenceRaw=' num2str(confidenceRaw, '%.4f')]);

        row = {subjectID, num2str(notchDetected), num2str(notchPos, '%.4f'), num2str(notchDepth, '%.4f'), num2str(confidence, '%.4f'), num2str(confidenceRaw, '%.4f'), num2str(effectiveFs, '%.4f'), num2str(hrBpm, '%.4f'), num2str(beatStats.beatsAveraged), num2str(numel(droppedFrameIdxLm)), num2str(numel(R_lm))};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        if notchDetected
            frozenDetectedCount = frozenDetectedCount + 1;
            if confidence >= confidenceThreshold
                frozenConfidentCount = frozenConfidentCount + 1;
            end
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task D2 frozen-cadence batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Frozen-cadence landmark-ROI+ABPF notch detection rate: ' num2str(frozenDetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(frozenConfidentCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);
