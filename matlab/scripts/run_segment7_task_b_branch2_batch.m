% RUN_SEGMENT7_TASK_B_BRANCH2_BATCH Segment 7 Task B, Action 5 branch 2
% (run ONLY because that branch's decision-gate condition fired -- see
% docs/Segment7_Task_B_Notch_Quantification.md). Adds two new,
% independent pulse-extraction variants -- morphology/adaptiveHarmonicFilter.m
% and morphology/tiledROIExtraction.m -- on top of the existing
% CHROM+wide-band+ground-truth-anchored-polarity pipeline, for all 5 UBFC
% subjects, then reruns morphology/notchDetectIEM.m on each to check
% whether either recovers the notch more reliably than the Task B
% baseline did. Also rebuilds the FIG 1 ablation for the fixed figure
% subject (5-gt) with these two as additional panels.
%
% Does NOT modify morphology/bandpassMorphology.m, morphology/ensembleAverageBeats.m,
% scripts/run_segment7_morphology_batch.m (Task A), or
% scripts/run_segment7_task_b_notch_batch.m (Task B baseline) -- this is
% a new, additive script producing new, separately-named outputs.

FIG_SUBJECT_ID = '5-gt';
subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end
if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_b_notch_branch2.csv');
headerLine = "subjectID,method,notchDetected,notchPositionNormalized,notchDepth,confidence,effectiveFsHz,hrBpmUsed,beatsAveraged";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

adaptiveDetectedCount = 0;
adaptiveConfidentCount = 0;
tiledDetectedCount = 0;
tiledConfidentCount = 0;

confidenceThreshold = 1.0; % see docs/Segment7_Task_B_Notch_Quantification.md for why

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task B branch-2 batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_b_branch2_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_b_branch2_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        isFigSubject = strcmp(subjectID, FIG_SUBJECT_ID);

        % === Decode once, reuse for the existing 'wide' condition AND
        % the new adaptive-harmonic condition (both operate on the same
        % ROI R/G/B traces). Tiled ROI needs its own separate decode
        % (different pixel regions entirely) via
        % morphology/tiledROIExtraction.m below.
        [frames, frameRate, ~] = loadUBFCVideo(videoPath);
        [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate);

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        % --- Shared f0 for the harmonic comb: from the existing
        % wide-band CHROM pulse (already-validated cardiac estimate),
        % NOT a fresh per-channel estimate -- see
        % morphology/adaptiveHarmonicFilter.m's f0HzOverride doc.
        [R_wide, ~, ~] = bandpassMorphology(R_detrended, frameRate, 'wide');
        [G_wide, ~, ~] = bandpassMorphology(G_detrended, frameRate, 'wide');
        [B_wide, ~, ~] = bandpassMorphology(B_detrended, frameRate, 'wide');
        pulseWide = chromCombine(R_wide, G_wide, B_wide, R, G, B);
        sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;

        % === Adaptive harmonic filter condition ===
        [R_ahf, ~, ~] = adaptiveHarmonicFilter(R_detrended, frameRate, 6, sharedF0Hz);
        [G_ahf, ~, ~] = adaptiveHarmonicFilter(G_detrended, frameRate, 6, sharedF0Hz);
        [B_ahf, ~, ~] = adaptiveHarmonicFilter(B_detrended, frameRate, 6, sharedF0Hz);
        pulseAdaptive = chromCombine(R_ahf, G_ahf, B_ahf, R, G, B);

        [pulseAdaptiveFixed, ~] = fixPolarityByGroundTruth(pulseAdaptive, roiTimestamps, gt.ppg, gt.timestamp);
        [sigAdaptiveUniform, ~, fsAdaptiveUniform] = resampleUniform(pulseAdaptiveFixed, roiTimestamps);
        [protoAdaptive, ~, ~, statsAdaptive] = ensembleAverageBeats(sigAdaptiveUniform, fsAdaptiveUniform);

        hrAdaptive = fftHeartRate(sigAdaptiveUniform, fsAdaptiveUniform);
        fsProtoAdaptive = numel(protoAdaptive.trimmedMean) * (hrAdaptive / 60);
        [adaptiveDetected, adaptivePos, adaptiveDepth, adaptiveConf] = notchDetectIEM(protoAdaptive.trimmedMean, fsProtoAdaptive);

        disp(['Subject ' subjectID ' adaptive-harmonic: notchDetected=' num2str(adaptiveDetected) ', pos=' num2str(adaptivePos, '%.4f') ', depth=' num2str(adaptiveDepth, '%.4f') ', confidence=' num2str(adaptiveConf, '%.4f')]);

        rowAdaptive = {subjectID, 'adaptiveHarmonic', num2str(adaptiveDetected), num2str(adaptivePos, '%.4f'), num2str(adaptiveDepth, '%.4f'), num2str(adaptiveConf, '%.4f'), num2str(fsProtoAdaptive, '%.4f'), num2str(hrAdaptive, '%.4f'), num2str(statsAdaptive.beatsAveraged)};
        writelines(strjoin(rowAdaptive, ','), csvPath, 'WriteMode', 'append');

        if adaptiveDetected
            adaptiveDetectedCount = adaptiveDetectedCount + 1;
            if adaptiveConf >= confidenceThreshold
                adaptiveConfidentCount = adaptiveConfidentCount + 1;
            end
        end

        % === Tiled ROI condition (own decode) ===
        [pulseTiled, roiTimestampsTiled, tileWeights, frameRateTiled] = tiledROIExtraction(videoPath, 'wide'); %#ok<ASGLU>

        [pulseTiledFixed, ~] = fixPolarityByGroundTruth(pulseTiled, roiTimestampsTiled, gt.ppg, gt.timestamp);
        [sigTiledUniform, ~, fsTiledUniform] = resampleUniform(pulseTiledFixed, roiTimestampsTiled);
        [protoTiled, ~, ~, statsTiled] = ensembleAverageBeats(sigTiledUniform, fsTiledUniform);

        hrTiled = fftHeartRate(sigTiledUniform, fsTiledUniform);
        fsProtoTiled = numel(protoTiled.trimmedMean) * (hrTiled / 60);
        [tiledDetected, tiledPos, tiledDepth, tiledConf] = notchDetectIEM(protoTiled.trimmedMean, fsProtoTiled);

        disp(['Subject ' subjectID ' tiled-ROI: notchDetected=' num2str(tiledDetected) ', pos=' num2str(tiledPos, '%.4f') ', depth=' num2str(tiledDepth, '%.4f') ', confidence=' num2str(tiledConf, '%.4f')]);

        rowTiled = {subjectID, 'tiledROI', num2str(tiledDetected), num2str(tiledPos, '%.4f'), num2str(tiledDepth, '%.4f'), num2str(tiledConf, '%.4f'), num2str(fsProtoTiled, '%.4f'), num2str(hrTiled, '%.4f'), num2str(statsTiled.beatsAveraged)};
        writelines(strjoin(rowTiled, ','), csvPath, 'WriteMode', 'append');

        if tiledDetected
            tiledDetectedCount = tiledDetectedCount + 1;
            if tiledConf >= confidenceThreshold
                tiledConfidentCount = tiledConfidentCount + 1;
            end
        end

        % === FIG 1 v2 for the figure subject: 6 conditions ===
        if isFigSubject
            bandConditions = {'legacy', 'mid', 'wide'};
            conditionPrototypes = struct();

            for condIdx = 1:numel(bandConditions)
                bandMode = bandConditions{condIdx};
                [R_f, ~, ~] = bandpassMorphology(R_detrended, frameRate, bandMode);
                [G_f, ~, ~] = bandpassMorphology(G_detrended, frameRate, bandMode);
                [B_f, ~, ~] = bandpassMorphology(B_detrended, frameRate, bandMode);
                pulse = chromCombine(R_f, G_f, B_f, R, G, B);
                [sigU, ~, fsU] = resampleUniform(pulse, roiTimestamps);
                [proto, ~, ~, ~] = ensembleAverageBeats(sigU, fsU);
                conditionPrototypes.(bandMode) = proto.trimmedMean;
            end

            [pulseWideFixed, ~] = fixPolarityByGroundTruth(pulseWide, roiTimestamps, gt.ppg, gt.timestamp);
            [sigWideUniform, ~, fsWideUniform] = resampleUniform(pulseWideFixed, roiTimestamps);
            [protoWideFixed, ~, ~, ~] = ensembleAverageBeats(sigWideUniform, fsWideUniform);
            conditionPrototypes.wideFixed = protoWideFixed.trimmedMean;

            conditionPrototypes.adaptiveHarmonic = protoAdaptive.trimmedMean;
            conditionPrototypes.tiledROI = protoTiled.trimmedMean;

            conditionLabels = {'legacy (0.7-4 Hz)', 'mid (0.6-6 Hz)', 'wide (0.5-8 Hz)', 'wide+GT-polarity', 'adaptive harmonic comb', 'tiled ROI (4x4)'};
            cycleFrac = linspace(0, 1, numel(conditionPrototypes.legacy));

            figHandle = figure('Visible', 'off');
            hold on;
            plot(cycleFrac, conditionPrototypes.legacy, 'LineWidth', 1.0);
            plot(cycleFrac, conditionPrototypes.mid, 'LineWidth', 1.0);
            plot(cycleFrac, conditionPrototypes.wide, 'LineWidth', 1.0);
            plot(cycleFrac, conditionPrototypes.wideFixed, 'LineWidth', 1.6);
            plot(cycleFrac, zscoreToScale(conditionPrototypes.adaptiveHarmonic, conditionPrototypes.wideFixed), 'LineWidth', 1.6, 'LineStyle', '--');
            plot(cycleFrac, zscoreToScale(conditionPrototypes.tiledROI, conditionPrototypes.wideFixed), 'LineWidth', 1.6, 'LineStyle', ':');
            hold off;
            legend(conditionLabels, 'Location', 'best');
            xlabel('Cycle fraction (systolic peak anchored at 0.25)');
            ylabel('Pulse amplitude (a.u., adaptive/tiled rescaled to wide+GT-polarity''s own scale for visual comparability)');
            title(['Subject ' subjectID ' -- Segment 7 Task B FIG 1v2: 6-condition ablation']);
            fig1v2Path = fullfile(figuresRoot, ['segment7_task_b_fig1v2_ablation_' subjectID '.png']);
            exportgraphics(figHandle, fig1v2Path);
            close(figHandle);
            disp(['Saved ' fig1v2Path]);
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task B branch-2 batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Adaptive-harmonic notch detection rate: ' num2str(adaptiveDetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(adaptiveConfidentCount) '/' num2str(numSucceeded) ')']);
disp(['Tiled-ROI notch detection rate:         ' num2str(tiledDetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(tiledConfidentCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);

function scaled = zscoreToScale(vec, referenceVec)
% Rescales vec (z-scored) onto referenceVec's own mean/std, purely for
% overlaying differently-scaled conditions on one comparable axis in
% FIG 1v2 -- does not affect any notch-detection computation, which
% always runs on each condition's own untouched prototype.
vecZ = (vec - mean(vec)) / std(vec);
scaled = vecZ * std(referenceVec) + mean(referenceVec);
end
