% RUN_SEGMENT7_TASK_H_FACEMESH_ROI_BATCH Segment 7 Task H -- real DL
% face-mesh ROI (roi/faceMeshROIExtraction.m), teacher-authorized follow-up
% to Task D. Same protocol as
% scripts/run_segment7_task_d_landmark_roi_batch.m (read that script's own
% header first; not re-derived here): same 5 UBFC subjects, same ABPF
% chain at the same pipeline position, same shared-f0 source (the
% EXISTING baseline roi/extractROISignals.m decode, not a fresh estimate
% from the face-mesh ROI's own traces), same CSV column layout -- so this
% run is directly, fairly comparable against Task D's own established
% baseline (4/5 subjects >= 0.3 confidence) and against
% roi/landmarkROIExtraction.m's KLT-proxy result (2/5, then 0/5 frozen).
%
% ONE-TIME SESSION SETUP THIS SCRIPT OWNS: pyenv('ExecutionMode',
% 'OutOfProcess') is called first, before any other py.* touches this
% MATLAB session -- required by roi/faceMeshROIExtraction.m (in-process
% mode crashes on mediapipe's native bindings, see that function's own
% header and matlab/docs/Segment7_Task_H_FaceMesh_ROI.md).
%
% Does NOT modify roi/extractROISignals.m, roi/landmarkROIExtraction.m,
% filtering/detrendSignal.m, morphology/adaptiveHarmonicFilter.m,
% morphology/bandpassMorphology.m, pulseextraction/chromCombine.m,
% morphology/fixPolarityByGroundTruth.m, morphology/resampleUniform.m,
% morphology/ensembleAverageBeats.m, or morphology/notchDetectIEM.m -- new,
% additive script + new, additive roi/faceMeshROIExtraction.m, new,
% separately-named CSV output.
%
% Output: results/metrics/segment7_task_h_facemesh_notch.csv, same
% columns as Task D's own CSV.
%
% RUNTIME NOTE: roi/faceMeshROIExtraction.m calls out to Python
% (OutOfProcess) once per frame -- measured ~0.26 s/frame on this machine
% (see the doc above for why OutOfProcess is slower than in-process would
% have been, if in-process were usable here) -- so each ~2400-frame UBFC
% subject takes roughly 10 minutes. This script is expected to take
% ~45-60 minutes total for all 5 subjects; run it in the background.

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

csvPath = fullfile(metricsRoot, 'segment7_task_h_facemesh_notch.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,effectiveFsHz,hrBpmUsed,beatsAveraged,droppedFrameCount,numFrames";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

facemeshDetectedCount = 0;
facemeshConfidentCount = 0;
confidenceThreshold = 0.3; % same bar as Task B/C/D's own comparisons

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task H face-mesh-ROI batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);
    subjectStartTic = tic;

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_h_facemesh_roi_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_h_facemesh_roi_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % --- Step 1: shared f0, from the EXISTING baseline whole-ROI
        % wide-band CHROM pulse -- same source/method as Task D/B/C. ---
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

        % --- Step 2: real face-mesh ROI decode (fresh VideoReader). ---
        [framesForMesh, frameRateForMesh, ~] = loadUBFCVideo(videoPath);
        [R_fm, G_fm, B_fm, roiTimestampsFm, droppedFrameIdxFm, debugFrameFm] = faceMeshROIExtraction(framesForMesh, frameRateForMesh);

        disp(['Subject ' subjectID ' face-mesh ROI: dropped/no-face frames = ' num2str(numel(droppedFrameIdxFm)) ' / ' num2str(numel(R_fm))]);

        [R_fm_detrended, ~] = detrendSignal(R_fm);
        [G_fm_detrended, ~] = detrendSignal(G_fm);
        [B_fm_detrended, ~] = detrendSignal(B_fm);

        % --- Step 3: ABPF at its correct, unconfounded operating point,
        % SAME shared f0 as Step 1, applied to the face-mesh ROI's
        % traces. ---
        [R_fm_ahf, ~, ~] = adaptiveHarmonicFilter(R_fm_detrended, frameRateForMesh, 6, sharedF0Hz);
        [G_fm_ahf, ~, ~] = adaptiveHarmonicFilter(G_fm_detrended, frameRateForMesh, 6, sharedF0Hz);
        [B_fm_ahf, ~, ~] = adaptiveHarmonicFilter(B_fm_detrended, frameRateForMesh, 6, sharedF0Hz);
        pulseFacemeshAdaptive = chromCombine(R_fm_ahf, G_fm_ahf, B_fm_ahf, R_fm, G_fm, B_fm);

        % --- Step 4: same tail as every other Task B/C/D condition. ---
        [pulseFixed, wasFlipped] = fixPolarityByGroundTruth(pulseFacemeshAdaptive, roiTimestampsFm, gt.ppg, gt.timestamp);
        [sigUniform, ~, uniformFs] = resampleUniform(pulseFixed, roiTimestampsFm);
        [prototype, iqrBand, ~, beatStats] = ensembleAverageBeats(sigUniform, uniformFs);

        hrBpm = fftHeartRate(sigUniform, uniformFs);
        effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

        [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFs);

        elapsedSubjectSec = toc(subjectStartTic);
        disp(['Subject ' subjectID ' face-mesh-ROI+ABPF (wasFlipped=' num2str(wasFlipped) '): notchDetected=' num2str(notchDetected) ...
            ', pos=' num2str(notchPos, '%.4f') ', depth=' num2str(notchDepth, '%.4f') ', confidence=' num2str(confidence, '%.4f') ...
            ', confidenceRaw=' num2str(confidenceRaw, '%.4f') ' (' num2str(elapsedSubjectSec, '%.0f') ' s)']);

        row = {subjectID, num2str(notchDetected), num2str(notchPos, '%.4f'), num2str(notchDepth, '%.4f'), num2str(confidence, '%.4f'), num2str(confidenceRaw, '%.4f'), num2str(effectiveFs, '%.4f'), num2str(hrBpm, '%.4f'), num2str(beatStats.beatsAveraged), num2str(numel(droppedFrameIdxFm)), num2str(numel(R_fm))};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        if notchDetected
            facemeshDetectedCount = facemeshDetectedCount + 1;
            if confidence >= confidenceThreshold
                facemeshConfidentCount = facemeshConfidentCount + 1;
            end
        end

        % --- Sanity figure: prototype waveform + debug ROI frame. ---
        figHandle = figure('Visible', 'off');
        tl = tiledlayout(figHandle, 1, 2, 'TileSpacing', 'compact');

        axDebug = nexttile(tl);
        imshow(debugFrameFm.image, 'Parent', axDebug);
        hold(axDebug, 'on');
        poly = debugFrameFm.roiPolygon;
        plot(axDebug, [poly(:, 1); poly(1, 1)], [poly(:, 2); poly(1, 2)], 'g-', 'LineWidth', 2);
        plot(axDebug, debugFrameFm.faceMeshLandmarksPx(:, 1), debugFrameFm.faceMeshLandmarksPx(:, 2), 'r*', 'MarkerSize', 8);
        title(axDebug, ['Face-mesh ROI, frame ' num2str(debugFrameFm.frameIndex)]);

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

        title(tl, ['Subject ' subjectID ' -- Segment 7 Task H (face-mesh ROI)'], 'Interpreter', 'none');
        pngOutPath = fullfile(figuresRoot, ['segment7_task_h_facemesh_' subjectID '.png']);
        exportgraphics(figHandle, pngOutPath);
        close(figHandle);
        disp(['Subject ' subjectID ': saved ' pngOutPath]);
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task H face-mesh-ROI batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Face-mesh-ROI+ABPF notch detection rate: ' num2str(facemeshDetectedCount) '/' num2str(numSucceeded) ...
    ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(facemeshConfidentCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);
