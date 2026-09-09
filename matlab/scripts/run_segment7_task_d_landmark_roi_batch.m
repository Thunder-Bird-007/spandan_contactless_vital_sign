% RUN_SEGMENT7_TASK_D_LANDMARK_ROI_BATCH Segment 7 Task D, Action 2.
%
% Segment 7 Task D asked (per the uploaded thesis's Section 3.2.1) for a
% forehead ROI built from 4 named face-mesh landmarks (indices 67, 297,
% 105, 334 on a 468-point mesh). Action 0 confirmed this MATLAB R2024b
% installation has NO facial-landmark / face-mesh detector of any kind
% (checked Deep Learning Toolbox Model support packages, Computer Vision
% Toolbox functions, and direct exist() probes -- see
% roi/landmarkROIExtraction.m's own header for the full list checked and
% docs/Segment7_Task_D_Landmark_ROI.md for the writeup), so this script
% runs the documented fallback instead: roi/landmarkROIExtraction.m's
% KLT-tracked, rotation-compensated forehead ROI, in place of
% roi/extractROISignals.m as the ROI stage, through the SAME
% already-validated ABPF chain scripts/run_segment7_task_b_branch2_batch.m
% established (detrend -> adaptiveHarmonicFilter, per-channel,
% pre-projection, shared f0 -> chromCombine -> fixPolarityByGroundTruth
% -> resampleUniform -> ensembleAverageBeats -> notchDetectIEM).
%
% CONFOUND AVOIDANCE (per this task's explicit brief, and Task C1's own
% lesson): roi/landmarkROIExtraction.m returns raw, per-channel R/G/B
% traces -- NOT a pre-combined pulse signal -- and adaptiveHarmonicFilter
% + chromCombine run at their SAME validated pipeline position (per-
% channel, before projection), exactly as in
% scripts/run_segment7_task_b_branch2_batch.m's own adaptive-harmonic
% condition. Nothing about that chain is changed here; only the ROI
% stage feeding it is swapped.
%
% Shared f0 for the harmonic comb is computed from the EXISTING,
% established baseline (roi/extractROISignals.m + bandpassMorphology.m
% 'wide' + chromCombine.m), the SAME source and method
% scripts/run_segment7_task_b_branch2_batch.m and
% scripts/run_segment7_task_c2_true_combined_batch.m both already use --
% NOT a fresh estimate from the landmark-ROI traces. This means both the
% Baseline-ROI+ABPF condition and the Landmark/KLT-ROI+ABPF condition
% compared in Action 3 share the exact same f0 operating point, so any
% difference in notch-detection outcome is attributable to the ROI stage
% alone, not to a shifted f0 estimate. This requires two separate
% per-subject decodes (one via extractROISignals.m for f0, one via
% landmarkROIExtraction.m for the actual traces this script evaluates) --
% the same two-decode pattern
% scripts/run_segment7_task_c2_true_combined_batch.m already established
% for an analogous reason (its own tiled-ROI decode there).
%
% Does NOT modify roi/extractROISignals.m, filtering/detrendSignal.m,
% morphology/adaptiveHarmonicFilter.m, pulseextraction/chromCombine.m,
% morphology/fixPolarityByGroundTruth.m, morphology/resampleUniform.m,
% morphology/ensembleAverageBeats.m, or morphology/notchDetectIEM.m's
% detection algorithm (only its header comment changed, see Segment 7
% Task D's one-line doc fix) -- new, additive script, new,
% separately-named output.
%
% Output: results/metrics/segment7_task_d_landmark_notch.csv, same
% columns as scripts/run_segment7_task_c2_true_combined_batch.m's CSV
% (Combined-v2), including confidenceRaw.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_d_landmark_notch.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,effectiveFsHz,hrBpmUsed,beatsAveraged,droppedFrameCount,numFrames";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

landmarkDetectedCount = 0;
landmarkConfidentCount = 0;
confidenceThreshold = 1.0; % same bar as every other Task B/C batch

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task D landmark-ROI batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_d_landmark_roi_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_d_landmark_roi_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % --- Step 1: shared f0, from the EXISTING baseline whole-ROI
        % wide-band CHROM pulse -- same source/method as
        % run_segment7_task_b_branch2_batch.m's and
        % run_segment7_task_c2_true_combined_batch.m's own sharedF0Hz, so
        % Task D's comparison is evaluated at the established operating
        % point, not a new one. ---
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

        % --- Step 2: landmark/KLT-ROI decode (Task D's own, separate
        % decode -- roi/landmarkROIExtraction.m takes a VideoReader same
        % as roi/extractROISignals.m, so it needs its own fresh one; the
        % first VideoReader above was already consumed by
        % extractROISignals.m). ---
        [framesForLandmark, frameRateForLandmark, ~] = loadUBFCVideo(videoPath);
        [R_lm, G_lm, B_lm, roiTimestampsLm, droppedFrameIdxLm, ~] = landmarkROIExtraction(framesForLandmark, frameRateForLandmark);

        disp(['Subject ' subjectID ' landmark-ROI: dropped/fallback frames = ' num2str(numel(droppedFrameIdxLm)) ' / ' num2str(numel(R_lm))]);

        [R_lm_detrended, ~] = detrendSignal(R_lm);
        [G_lm_detrended, ~] = detrendSignal(G_lm);
        [B_lm_detrended, ~] = detrendSignal(B_lm);

        % --- Step 3: ABPF at its correct, uncounfounded operating point
        % -- per-channel, before chromCombine.m -- using the SHARED f0
        % from Step 1, exactly the substitution
        % run_segment7_task_b_branch2_batch.m makes for its own
        % adaptive-harmonic condition, applied here to the landmark/KLT
        % ROI's traces instead of the baseline ROI's traces. ---
        [R_lm_ahf, ~, ~] = adaptiveHarmonicFilter(R_lm_detrended, frameRateForLandmark, 6, sharedF0Hz);
        [G_lm_ahf, ~, ~] = adaptiveHarmonicFilter(G_lm_detrended, frameRateForLandmark, 6, sharedF0Hz);
        [B_lm_ahf, ~, ~] = adaptiveHarmonicFilter(B_lm_detrended, frameRateForLandmark, 6, sharedF0Hz);
        pulseLandmarkAdaptive = chromCombine(R_lm_ahf, G_lm_ahf, B_lm_ahf, R_lm, G_lm, B_lm);

        % --- Step 4: same tail as every other Task B/C condition. ---
        [pulseFixed, wasFlipped] = fixPolarityByGroundTruth(pulseLandmarkAdaptive, roiTimestampsLm, gt.ppg, gt.timestamp);
        [sigUniform, ~, uniformFs] = resampleUniform(pulseFixed, roiTimestampsLm);
        [prototype, ~, ~, beatStats] = ensembleAverageBeats(sigUniform, uniformFs);

        hrBpm = fftHeartRate(sigUniform, uniformFs);
        effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

        [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFs);

        disp(['Subject ' subjectID ' landmark-ROI+ABPF (wasFlipped=' num2str(wasFlipped) '): notchDetected=' num2str(notchDetected) ', pos=' num2str(notchPos, '%.4f') ', depth=' num2str(notchDepth, '%.4f') ', confidence=' num2str(confidence, '%.4f') ', confidenceRaw=' num2str(confidenceRaw, '%.4f')]);

        row = {subjectID, num2str(notchDetected), num2str(notchPos, '%.4f'), num2str(notchDepth, '%.4f'), num2str(confidence, '%.4f'), num2str(confidenceRaw, '%.4f'), num2str(effectiveFs, '%.4f'), num2str(hrBpm, '%.4f'), num2str(beatStats.beatsAveraged), num2str(numel(droppedFrameIdxLm)), num2str(numel(R_lm))};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        if notchDetected
            landmarkDetectedCount = landmarkDetectedCount + 1;
            if confidence >= confidenceThreshold
                landmarkConfidentCount = landmarkConfidentCount + 1;
            end
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task D landmark-ROI batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Landmark/KLT-ROI+ABPF notch detection rate: ' num2str(landmarkDetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(landmarkConfidentCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);
