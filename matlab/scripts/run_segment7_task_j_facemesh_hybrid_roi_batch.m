% RUN_SEGMENT7_TASK_J_FACEMESH_HYBRID_ROI_BATCH Segment 7 Task J -- hybrid
% ROI (roi/faceMeshHybridROIExtraction.m): real face-mesh detection +
% baseline's forehead BOX geometry, isolating detector-robustness from
% ROI-shape after Task H/I found the thin 4-landmark polygon regresses
% notch confidence hard despite tying baseline on HR. Same protocol as
% scripts/run_segment7_task_h_facemesh_roi_batch.m (read that script's own
% header first; not re-derived here): same 5 UBFC subjects, same ABPF
% chain at the same pipeline position, same shared-f0 source (the EXISTING
% baseline roi/extractROISignals.m decode), same CSV column layout -- so
% this run is directly, fairly comparable against baseline (Task B), the
% KLT proxy (Task D), and the real face-mesh polygon (Task H).
%
% ONE-TIME SESSION SETUP THIS SCRIPT OWNS: pyenv('ExecutionMode',
% 'OutOfProcess') -- required by roi/faceMeshHybridROIExtraction.m
% (reuses roi/faceMeshROIExtraction.m's mediapipe setup pattern).
%
% Does NOT modify roi/extractROISignals.m, roi/faceMeshROIExtraction.m,
% roi/landmarkROIExtraction.m, filtering/detrendSignal.m,
% morphology/adaptiveHarmonicFilter.m, morphology/bandpassMorphology.m,
% pulseextraction/chromCombine.m, morphology/fixPolarityByGroundTruth.m,
% morphology/resampleUniform.m, morphology/ensembleAverageBeats.m, or
% morphology/notchDetectIEM.m -- new, additive script + new, additive
% roi/faceMeshHybridROIExtraction.m, new, separately-named CSV output.
%
% Output: results/metrics/segment7_task_j_facemesh_hybrid_notch.csv, same
% columns as Task D/H's own CSVs.
%
% RUNTIME NOTE: roi/faceMeshHybridROIExtraction.m calls out to Python
% (OutOfProcess) once per frame, same per-frame cost as Task H's
% roi/faceMeshROIExtraction.m -- expect a comparable ~45-60 minutes total
% for all 5 subjects; run it in the background.

pyenv('ExecutionMode', 'OutOfProcess');

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end
if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_j_facemesh_hybrid_notch.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,effectiveFsHz,hrBpmUsed,beatsAveraged,droppedFrameCount,numFrames";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

hybridDetectedCount = 0;
hybridConfidentCount = 0;
confidenceThreshold = 0.3; % same bar as Task B/C/D/H's own comparisons

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task J hybrid-ROI batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);
    subjectStartTic = tic;

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_j_facemesh_hybrid_roi_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_j_facemesh_hybrid_roi_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % --- Step 1: shared f0, from the EXISTING baseline whole-ROI
        % wide-band CHROM pulse -- same source/method as Task D/H. ---
        [framesForF0, frameRateForF0, ~] = loadUBFCVideo(videoPath);
        [R_base, G_base, B_base, ~, ~, ~] = extractROISignals(framesForF0, frameRateForF0);

        [R_base_detrended, ~] = detrendSignal(R_base);
        [G_base_detrended, ~] = detrendSignal(G_base);
        [B_base_detrended, ~] = detrendSignal(B_base);

        [R_base_wide, ~, ~] = bandpassMorphology(R_base_detrended, frameRateForF0, 'wide');
        [G_base_wide, ~, ~] = bandpassMorphology(G_base_detrended, frameRateForF0, 'wide');
        [B_base_wide, ~, ~] = bandpassMorphology(B_base_detrended, frameRateForF0, 'wide');
        pulseBaseWide = chromCombine(R_base_wide, G_base_wide, B_base_wide, R_base, G_base, B_base);
        sharedF0Hz = fftHeartRate(pulseBaseWide, frameRateForF0) / 60; %#ok<NASGU>

        % --- Step 2: hybrid ROI decode (fresh VideoReader). ---
        [framesForHybrid, frameRateForHybrid, ~] = loadUBFCVideo(videoPath);
        [R_hy, G_hy, B_hy, roiTimestampsHy, droppedFrameIdxHy, debugFrameHy] = faceMeshHybridROIExtraction(framesForHybrid, frameRateForHybrid);

        disp(['Subject ' subjectID ' hybrid ROI: dropped/no-face frames = ' num2str(numel(droppedFrameIdxHy)) ' / ' num2str(numel(R_hy))]);

        [R_hy_detrended, ~] = detrendSignal(R_hy);
        [G_hy_detrended, ~] = detrendSignal(G_hy);
        [B_hy_detrended, ~] = detrendSignal(B_hy);

        % --- Step 3: ABPF at its correct, unconfounded operating point,
        % SAME shared f0 as Step 1, applied to the hybrid ROI's traces. ---
        [R_hy_ahf, ~, ~] = adaptiveHarmonicFilter(R_hy_detrended, frameRateForHybrid, 6, sharedF0Hz);
        [G_hy_ahf, ~, ~] = adaptiveHarmonicFilter(G_hy_detrended, frameRateForHybrid, 6, sharedF0Hz);
        [B_hy_ahf, ~, ~] = adaptiveHarmonicFilter(B_hy_detrended, frameRateForHybrid, 6, sharedF0Hz);
        pulseHybridAdaptive = chromCombine(R_hy_ahf, G_hy_ahf, B_hy_ahf, R_hy, G_hy, B_hy);

        % --- Step 4: same tail as every other Task B/C/D/H condition. ---
        [pulseFixed, wasFlipped] = fixPolarityByGroundTruth(pulseHybridAdaptive, roiTimestampsHy, gt.ppg, gt.timestamp);
        [sigUniform, ~, uniformFs] = resampleUniform(pulseFixed, roiTimestampsHy);
        [prototype, iqrBand, ~, beatStats] = ensembleAverageBeats(sigUniform, uniformFs);

        hrBpm = fftHeartRate(sigUniform, uniformFs);
        effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

        [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFs);

        elapsedSubjectSec = toc(subjectStartTic);
        disp(['Subject ' subjectID ' hybrid-ROI+ABPF (wasFlipped=' num2str(wasFlipped) '): notchDetected=' num2str(notchDetected) ...
            ', pos=' num2str(notchPos, '%.4f') ', depth=' num2str(notchDepth, '%.4f') ', confidence=' num2str(confidence, '%.4f') ...
            ', confidenceRaw=' num2str(confidenceRaw, '%.4f') ' (' num2str(elapsedSubjectSec, '%.0f') ' s)']);

        row = {subjectID, num2str(notchDetected), num2str(notchPos, '%.4f'), num2str(notchDepth, '%.4f'), num2str(confidence, '%.4f'), num2str(confidenceRaw, '%.4f'), num2str(effectiveFs, '%.4f'), num2str(hrBpm, '%.4f'), num2str(beatStats.beatsAveraged), num2str(numel(droppedFrameIdxHy)), num2str(numel(R_hy))};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        if notchDetected
            hybridDetectedCount = hybridDetectedCount + 1;
            if confidence >= confidenceThreshold
                hybridConfidentCount = hybridConfidentCount + 1;
            end
        end

        % --- Sanity figure: prototype waveform + debug ROI frame (face
        % bbox + forehead roi bbox rectangles, extractROISignals.m-style,
        % not Task H's polygon/landmark-star drawing). ---
        figHandle = figure('Visible', 'off');
        tl = tiledlayout(figHandle, 1, 2, 'TileSpacing', 'compact');

        axDebug = nexttile(tl);
        annotatedImg = insertObjectAnnotation(debugFrameHy.image, 'rectangle', debugFrameHy.faceBBox, 'Face-mesh bbox', 'Color', 'yellow', 'LineWidth', 3);
        annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrameHy.roiBBox, 'ROI (forehead)', 'Color', 'green', 'LineWidth', 3);
        imshow(annotatedImg, 'Parent', axDebug);
        title(axDebug, ['Hybrid ROI, frame ' num2str(debugFrameHy.frameIndex)]);

        axProto = nexttile(tl);
        cycleFrac = linspace(0, 1, numel(prototype.trimmedMean));
        hold(axProto, 'on');
        fill(axProto, [cycleFrac, fliplr(cycleFrac)], [iqrBand.q3, fliplr(iqrBand.q1)], [0.75 0.80 0.95], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
        plot(axProto, cycleFrac, prototype.trimmedMean, 'LineWidth', 1.8, 'Color', [0.10 0.15 0.45]);
        if notchDetected
            xline(axProto, cycleFrac(round(notchPos * (numel(cycleFrac) - 1)) + 1), 'r--', 'LineWidth', 1.5);
        end
        title(axProto, ['Prototype, conf=' num2str(confidence, '%.3f')]);
        xlabel(axProto, 'Cycle fraction');
        ylabel(axProto, 'Amplitude');

        title(tl, ['Subject ' subjectID ' -- Segment 7 Task J (face-mesh hybrid ROI)'], 'Interpreter', 'none');
        pngOutPath = fullfile(figuresRoot, ['segment7_task_j_facemesh_hybrid_' subjectID '.png']);
        exportgraphics(figHandle, pngOutPath);
        close(figHandle);
        disp(['Subject ' subjectID ': saved ' pngOutPath]);
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task J hybrid-ROI batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Hybrid-ROI+ABPF notch detection rate: ' num2str(hybridDetectedCount) '/' num2str(numSucceeded) ...
    ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(hybridConfidentCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);
