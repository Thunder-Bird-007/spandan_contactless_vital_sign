% RUN_SEGMENT7_TASK_B_NOTCH_BATCH Segment 7 Task B, Actions 3-5. Runs
% morphology/notchDetectIEM.m on both the UBFC ground-truth contact-PPG
% ensemble prototype AND our own rPPG ensemble prototype (now built with
% Action 1's ground-truth-anchored polarity default), for all 5 locally-
% available UBFC DATASET_1 subjects, then applies the Action 5 decision
% gate.
%
% Runs tests/segment7_task_b_regression_test.m FIRST and hard-stops
% (propagates its error, does not catch it) if that fails -- same
% "confirmed, not assumed" discipline as
% docs/Segment6_Task_O_Detrend_And_Adaptive_Bandpass.md's regression
% check and Segment 7 Task A's own Action 7.
%
% Outputs (results/metrics/):
%   segment7_task_b_notch_groundtruth.csv - one row per subject:
%     notchDetected, notchPositionNormalized, notchDepth, confidence,
%     confidenceRaw, effectiveFsHz, hrBpmUsed, beatsAveraged -- from the
%     UBFC ground-truth contact-PPG's own ensemble prototype.
%   segment7_task_b_notch_rppg.csv - same columns, from OUR rPPG
%     ensemble prototype (CHROM + wide band + ground-truth-anchored
%     polarity, per Task B Action 1).
%
% Segment 7 Task C, Action 1 update: notchDetectIEM.m gained a 5th,
% unclipped output (confidenceRaw) so subjects that clip at confidence
% = 1.0000 can still be ranked/compared -- see that function's header.
% This is additive only: notchDetected/notchPositionNormalized/
% notchDepth/confidence are computed exactly as before (confirmed
% byte-identical by tests/segment7_task_b_regression_test.m /
% Task C's own regression check).
%
% See docs/Segment7_Task_B_Notch_Quantification.md for which decision-
% gate branch fired and why.

disp('=== Running tests/segment7_task_b_regression_test.m first (hard-stop on failure) ===');
thisFileDir = fileparts(mfilename('fullpath'));
run(fullfile(fileparts(thisFileDir), 'tests', 'segment7_task_b_regression_test.m'));
disp('=== Regression test passed -- proceeding with Task B notch batch ===');

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

gtCsvPath = fullfile(metricsRoot, 'segment7_task_b_notch_groundtruth.csv');
rppgCsvPath = fullfile(metricsRoot, 'segment7_task_b_notch_rppg.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,effectiveFsHz,hrBpmUsed,beatsAveraged";
writelines(headerLine, gtCsvPath);
writelines(headerLine, rppgCsvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

gtDetectedCount = 0;
rppgDetectedCount = 0;
gtRows = {};
rppgRows = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 Task B notch batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_b_notch_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_task_b_notch_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');
        groundTruth = struct('ppg', gt.ppg, 'timestamp', gt.timestamp);

        % --- Our rPPG, ground-truth-anchored polarity (Task B Action 1 default) ---
        result = extractMorphologyWaveform(videoPath, 'wide', struct(), groundTruth);

        rppgHrBpm = fftHeartRate(result.sigUniform, result.uniformFs);
        rppgBeatSamples = numel(result.prototype.trimmedMean);
        rppgEffectiveFs = rppgBeatSamples * (rppgHrBpm / 60);

        [rppgNotchDetected, rppgNotchPos, rppgNotchDepth, rppgConfidence, rppgConfidenceRaw] = notchDetectIEM(result.prototype.trimmedMean, rppgEffectiveFs);

        disp(['Subject ' subjectID ' rPPG (GT-anchored polarity, wasFlipped=' num2str(result.wasFlipped) '): notchDetected=' num2str(rppgNotchDetected) ', pos=' num2str(rppgNotchPos, '%.4f') ', depth=' num2str(rppgNotchDepth, '%.4f') ', confidence=' num2str(rppgConfidence, '%.4f') ', confidenceRaw=' num2str(rppgConfidenceRaw, '%.4f')]);

        rppgRow = {subjectID, num2str(rppgNotchDetected), num2str(rppgNotchPos, '%.4f'), num2str(rppgNotchDepth, '%.4f'), num2str(rppgConfidence, '%.4f'), num2str(rppgConfidenceRaw, '%.4f'), num2str(rppgEffectiveFs, '%.4f'), num2str(rppgHrBpm, '%.4f'), num2str(result.beatStats.beatsAveraged)};
        writelines(strjoin(rppgRow, ','), rppgCsvPath, 'WriteMode', 'append');
        rppgRows{end + 1} = rppgRow; %#ok<AGROW>

        if rppgNotchDetected
            rppgDetectedCount = rppgDetectedCount + 1;
        end

        % --- UBFC ground-truth contact PPG's own ensemble prototype ---
        [gtPrototype, ~, ~, gtBeatStats, gtFixed, gtUniformFs] = buildGroundTruthPrototypeWithSignal(gt, result.uniformFs);

        gtHrBpm = fftHeartRate(gtFixed, gtUniformFs);
        gtBeatSamples = numel(gtPrototype.trimmedMean);
        gtEffectiveFs = gtBeatSamples * (gtHrBpm / 60);

        [gtNotchDetected, gtNotchPos, gtNotchDepth, gtConfidence, gtConfidenceRaw] = notchDetectIEM(gtPrototype.trimmedMean, gtEffectiveFs);

        disp(['Subject ' subjectID ' ground truth: notchDetected=' num2str(gtNotchDetected) ', pos=' num2str(gtNotchPos, '%.4f') ', depth=' num2str(gtNotchDepth, '%.4f') ', confidence=' num2str(gtConfidence, '%.4f') ', confidenceRaw=' num2str(gtConfidenceRaw, '%.4f')]);

        gtRow = {subjectID, num2str(gtNotchDetected), num2str(gtNotchPos, '%.4f'), num2str(gtNotchDepth, '%.4f'), num2str(gtConfidence, '%.4f'), num2str(gtConfidenceRaw, '%.4f'), num2str(gtEffectiveFs, '%.4f'), num2str(gtHrBpm, '%.4f'), num2str(gtBeatStats.beatsAveraged)};
        writelines(strjoin(gtRow, ','), gtCsvPath, 'WriteMode', 'append');
        gtRows{end + 1} = gtRow; %#ok<AGROW>

        if gtNotchDetected
            gtDetectedCount = gtDetectedCount + 1;
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 Task B notch batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

disp(['Saved ' gtCsvPath]);
disp(['Saved ' rppgCsvPath]);

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Ground-truth notch detection rate: ' num2str(gtDetectedCount) '/' num2str(numSucceeded)]);
disp(['rPPG notch detection rate:         ' num2str(rppgDetectedCount) '/' num2str(numSucceeded)]);

if gtDetectedCount < 3
    branchFired = 1;
    disp('=== DECISION GATE: BRANCH 1 fired -- ground truth itself shows notchDetected=false (or below-threshold) for the majority of subjects (< 3/5). Notch prominence is being treated as a subject/dataset characteristic, not a fixable pipeline defect. Stopping here per the handoff -- no adaptiveHarmonicFilter.m / tiledROIExtraction.m this round. ===');
elseif rppgDetectedCount < 3
    branchFired = 2;
    disp('=== DECISION GATE: BRANCH 2 fired -- ground truth shows a notch reliably (>= 3/5) but our rPPG does not (< 3/5). Real notch information exists in these subjects and the pipeline is still losing it. Proceeding to implement adaptiveHarmonicFilter.m and tiledROIExtraction.m. ===');
else
    branchFired = 0;
    disp('=== DECISION GATE: neither named branch fired -- both ground truth AND our rPPG detect a notch reliably (>= 3/5 each). This case was not explicitly named in the handoff; treated as a third, implicit "no further action needed" outcome (the pipeline is already recovering the notch about as often as it exists), documented as such rather than silently forced into one of the two named branches. ===');
end

function [gtPrototype, gtIqrBand, gtBeatMatrix, gtBeatStats, gtFixed, gtUniformFs] = buildGroundTruthPrototypeWithSignal(gt, targetFs)
% Same chain as run_segment7_morphology_batch.m's buildGroundTruthPrototype
% local helper (Task A), with two extra outputs (gtFixed, gtUniformFs) so
% this script can independently estimate the ground-truth signal's own
% HR (via heartrate/fftHeartRate.m, unmodified) for
% morphology/notchDetectIEM.m's effective-sample-rate input.
[gtUniform, ~, gtUniformFs] = resampleUniform(gt.ppg, gt.timestamp, targetFs);
[gtDetrended, ~] = detrendSignal(gtUniform);
[gtFiltered, ~, ~] = bandpassMorphology(gtDetrended, gtUniformFs, 'wide');
[gtFixed, ~, ~] = fixPolarity(gtFiltered, gtUniformFs);
[gtPrototype, gtIqrBand, gtBeatMatrix, gtBeatStats] = ensembleAverageBeats(gtFixed, gtUniformFs);
end
