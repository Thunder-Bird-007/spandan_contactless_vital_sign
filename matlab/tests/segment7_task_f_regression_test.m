% SEGMENT7_TASK_F_REGRESSION_TEST Segment 7 Task F, Action 2. Confirms
% pipeline/estimateVitalsAndMorphology.m's two branches reproduce the
% already-saved, already-validated numbers this project has reported
% elsewhere, using ONLY the cached inputs those earlier scripts already
% produced (no video is re-decoded, same convention as
% tests/segment7_regression_test.m). If ANY part below fails, this
% errors out immediately -- per the Task F handoff, Action 3 (the demo
% script + report) must NOT be attempted on a broken wiring.
%
% Part 1 (Branch 1, bit-for-bit): re-runs Branch 1 on subject 5-gt from
% its cached data/processed/5-gt_rgb_traces.mat and compares
% result.hrBpm.chrom/.pos/.green against data/processed/5-gt_hr_estimates.mat
% via isequal() -- exactly tests/segment7_regression_test.m's own method,
% since Branch 1's call sequence in estimateVitalsAndMorphology.m is
% byte-identical to that test's own recomputation.
%
% Part 2 (Branch 1 SpO2 path, all 5 UBFC ground-truth subjects): for each
% subject, Branch 1's own spo2/ratioOfRatios.m output (Rvalue) is checked
% against results/metrics/segment5_dataset1_calibration.csv's already-
% saved R_value (same num2str() string formatting the original script
% used, since that CSV was never written to higher precision than that).
% Then the SAME 5-subject leave-one-out loop
% scripts/run_segment5_dataset1_calibration_batch.m ran (fit
% spo2/calibrateSpO2.m on the other 4 subjects, predict the held-out
% one) is re-run using Branch 1's own Rvalue outputs as the R values,
% with ground-truth SpO2 labels RECOMPUTED from gtdump.xmp with that
% script's own clip-duration windowing (NOT read back from the CSV's
% SpO2_true column, which is written at only 4 decimal digits -- feeding
% that already-rounded text back in as a training target was tried
% first and measurably drifted the fitted A/B by enough to flip the
% last digit of 2 of 5 held-out predictions; this is a lossy-round-trip
% artifact of the CSV's own text precision, not a Branch 1 bug, and is
% avoided by recomputing the full-precision ground truth directly). The
% resulting SpO2_predicted is compared against the CSV's already-saved
% SpO2_predicted column via num2str() string match.
%
% Part 3 (Branch 2, all 5 UBFC ground-truth subjects): for each subject,
% Branch 2 is re-run WITH ground truth supplied (fixPolarityByGroundTruth.m
% branch, matching scripts/run_segment7_task_b_branch2_batch.m's own
% "adaptiveHarmonic" condition exactly) and
% result.notch.detected/.position/.depth/.confidence is compared against
% results/metrics/segment7_task_b_notch_branch2.csv's already-saved
% 'adaptiveHarmonic' row for that subject, via the SAME '%.4f' string
% formatting that CSV was originally written with (notchDetected via
% num2str() on the logical, matching that script's own convention).
%
% Run via: matlab -batch "startup; run('tests/segment7_task_f_regression_test.m')".
% A clean run with no error, ending in the final PASS message, IS the
% passing result.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');

%% === Part 1: Branch 1, bit-for-bit, subject 5-gt ===
disp('=== Part 1: Branch 1 (HR) bit-for-bit regression, subject 5-gt ===');

subjectID = '5-gt';
rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
hrEstimatesPath = fullfile(processedDataRoot, [subjectID '_hr_estimates.mat']);

if ~isfile(rgbMatPath)
    error('segment7_task_f_regression_test:missingInput', 'Cached rgb_traces.mat not found: %s', rgbMatPath);
end
if ~isfile(hrEstimatesPath)
    error('segment7_task_f_regression_test:missingInput', 'Cached hr_estimates.mat not found: %s', hrEstimatesPath);
end

rgbData = load(rgbMatPath);
previouslySavedHR = load(hrEstimatesPath);

videoInput = struct('R', rgbData.R, 'G', rgbData.G, 'B', rgbData.B, 'fs', rgbData.fs);
result5gt = estimateVitalsAndMorphology(videoInput, [], [], struct('subjectID', subjectID));

chromMatch = isequal(result5gt.hrBpm.chrom, previouslySavedHR.HR_chrom);
posMatch = isequal(result5gt.hrBpm.pos, previouslySavedHR.HR_pos);
greenMatch = isequal(result5gt.hrBpm.green, previouslySavedHR.HR_green);

disp(['HR_chrom: recomputed = ' num2str(result5gt.hrBpm.chrom, '%.10f') ', saved = ' num2str(previouslySavedHR.HR_chrom, '%.10f') ', byte-identical = ' num2str(chromMatch)]);
disp(['HR_pos:   recomputed = ' num2str(result5gt.hrBpm.pos, '%.10f') ', saved = ' num2str(previouslySavedHR.HR_pos, '%.10f') ', byte-identical = ' num2str(posMatch)]);
disp(['HR_green: recomputed = ' num2str(result5gt.hrBpm.green, '%.10f') ', saved = ' num2str(previouslySavedHR.HR_green, '%.10f') ', byte-identical = ' num2str(greenMatch)]);

part1Pass = chromMatch && posMatch && greenMatch;

if ~part1Pass
    error('segment7_task_f_regression_test:part1Failed', 'Branch 1 HR output is NOT byte-identical to the already-saved hr_estimates.mat for subject %s.', subjectID);
end

disp('=== Part 1 PASS ===');
disp(' ');

%% === Part 2: Branch 1 SpO2 path, all 5 UBFC ground-truth subjects ===
disp('=== Part 2: Branch 1 (SpO2 path) regression, all 5 UBFC ground-truth subjects ===');

calibCsvPath = fullfile(metricsRoot, 'segment5_dataset1_calibration.csv');
if ~isfile(calibCsvPath)
    error('segment7_task_f_regression_test:missingInput', 'Cached calibration CSV not found: %s', calibCsvPath);
end
calibTable = readtable(calibCsvPath);

numSubjects = numel(subjectList);
orchestratorRvalue = zeros(1, numSubjects);
csvSpo2True = zeros(1, numSubjects);
csvRvalueStr = cell(1, numSubjects);
csvSpo2PredictedStr = cell(1, numSubjects);

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
    gtPath = fullfile(dataset1Root, subjectID, 'gtdump.xmp');

    if ~isfile(rgbMatPath)
        error('segment7_task_f_regression_test:missingInput', 'Cached rgb_traces.mat not found: %s', rgbMatPath);
    end
    if ~isfile(gtPath)
        error('segment7_task_f_regression_test:missingInput', 'gtdump.xmp not found: %s', gtPath);
    end

    rgbData = load(rgbMatPath);
    videoInput = struct('R', rgbData.R, 'G', rgbData.G, 'B', rgbData.B, 'fs', rgbData.fs);
    resultThis = estimateVitalsAndMorphology(videoInput, [], [], struct('subjectID', subjectID));

    orchestratorRvalue(subjectPos) = resultThis.branch1.Rvalue;

    % Recompute SpO2_true at full precision -- exactly
    % scripts/run_segment5_dataset1_calibration_batch.m's own
    % clip-duration-windowed mean, NOT the CSV's rounded text column.
    gt = loadGroundTruth(gtPath, 'dataset1');
    videoDurationSec = numel(rgbData.R) / rgbData.fs;
    inClipMask = gt.timestamp <= videoDurationSec;
    csvSpo2True(subjectPos) = mean(gt.spo2(inClipMask));

    rowMask = strcmp(calibTable.subjectID, subjectID);
    if ~any(rowMask)
        error('segment7_task_f_regression_test:missingRow', 'No row for subject %s in %s.', subjectID, calibCsvPath);
    end

    csvRvalueStr{subjectPos} = num2str(calibTable.R_value(rowMask));
    csvSpo2PredictedStr{subjectPos} = num2str(calibTable.SpO2_predicted(rowMask));

    thisRvalueStr = num2str(orchestratorRvalue(subjectPos));
    rvalueMatch = strcmp(thisRvalueStr, csvRvalueStr{subjectPos});

    disp(['Subject ' subjectID ': Rvalue recomputed = ' thisRvalueStr ', saved = ' csvRvalueStr{subjectPos} ', match = ' num2str(rvalueMatch)]);

    if ~rvalueMatch
        error('segment7_task_f_regression_test:part2RvalueFailed', 'Branch 1 Rvalue does not match the already-saved %s for subject %s.', calibCsvPath, subjectID);
    end
end

disp('All 5 Rvalue outputs match the already-saved calibration CSV.');

part2Pass = true;

for holdoutPos = 1:numSubjects
    trainMask = true(1, numSubjects);
    trainMask(holdoutPos) = false;

    R_train = orchestratorRvalue(trainMask);
    SpO2_train = csvSpo2True(trainMask);

    [~, calibParamsThis] = calibrateSpO2(R_train, SpO2_train, []);
    [spo2PredThis, ~] = calibrateSpO2(orchestratorRvalue(holdoutPos), [], calibParamsThis);

    spo2PredStr = num2str(spo2PredThis);
    spo2Match = strcmp(spo2PredStr, csvSpo2PredictedStr{holdoutPos});

    disp(['Held out ' subjectList{holdoutPos} ': SpO2_predicted recomputed = ' spo2PredStr ', saved = ' csvSpo2PredictedStr{holdoutPos} ', match = ' num2str(spo2Match)]);

    part2Pass = part2Pass && spo2Match;
end

if ~part2Pass
    error('segment7_task_f_regression_test:part2Failed', 'Branch 1 leave-one-out SpO2_predicted does not match the already-saved %s for at least one subject.', calibCsvPath);
end

disp('=== Part 2 PASS ===');
disp(' ');

%% === Part 3: Branch 2, all 5 UBFC ground-truth subjects, vs Task B branch2 CSV ===
disp('=== Part 3: Branch 2 (morphology/notch) regression, all 5 UBFC ground-truth subjects ===');

notchCsvPath = fullfile(metricsRoot, 'segment7_task_b_notch_branch2.csv');
if ~isfile(notchCsvPath)
    error('segment7_task_f_regression_test:missingInput', 'Cached notch branch2 CSV not found: %s', notchCsvPath);
end
notchTable = readtable(notchCsvPath);

part3Pass = true;

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
    gtPath = fullfile(dataset1Root, subjectID, 'gtdump.xmp');

    if ~isfile(rgbMatPath)
        error('segment7_task_f_regression_test:missingInput', 'Cached rgb_traces.mat not found: %s', rgbMatPath);
    end
    if ~isfile(gtPath)
        error('segment7_task_f_regression_test:missingInput', 'gtdump.xmp not found: %s', gtPath);
    end

    rgbData = load(rgbMatPath);
    gt = loadGroundTruth(gtPath, 'dataset1');

    videoInput = struct('R', rgbData.R, 'G', rgbData.G, 'B', rgbData.B, 'fs', rgbData.fs);
    resultThis = estimateVitalsAndMorphology(videoInput, gt, [], struct('subjectID', subjectID));

    rowMask = strcmp(notchTable.subjectID, subjectID) & strcmp(notchTable.method, 'adaptiveHarmonic');
    if ~any(rowMask)
        error('segment7_task_f_regression_test:missingRow', 'No adaptiveHarmonic row for subject %s in %s.', subjectID, notchCsvPath);
    end

    savedDetected = notchTable.notchDetected(rowMask);
    savedPosition = notchTable.notchPositionNormalized(rowMask);
    savedDepth = notchTable.notchDepth(rowMask);
    savedConfidence = notchTable.confidence(rowMask);

    detectedMatch = strcmp(num2str(resultThis.notch.detected), num2str(savedDetected));
    positionMatch = strcmp(num2str(resultThis.notch.position, '%.4f'), num2str(savedPosition, '%.4f'));
    depthMatch = strcmp(num2str(resultThis.notch.depth, '%.4f'), num2str(savedDepth, '%.4f'));
    confidenceMatch = strcmp(num2str(resultThis.notch.confidence, '%.4f'), num2str(savedConfidence, '%.4f'));

    disp(['Subject ' subjectID ': notchDetected recomputed=' num2str(resultThis.notch.detected) ' saved=' num2str(savedDetected) ...
        ', position recomputed=' num2str(resultThis.notch.position, '%.4f') ' saved=' num2str(savedPosition, '%.4f') ...
        ', depth recomputed=' num2str(resultThis.notch.depth, '%.4f') ' saved=' num2str(savedDepth, '%.4f') ...
        ', confidence recomputed=' num2str(resultThis.notch.confidence, '%.4f') ' saved=' num2str(savedConfidence, '%.4f')]);

    subjectPass = detectedMatch && positionMatch && depthMatch && confidenceMatch;
    disp(['Subject ' subjectID ': match = ' num2str(subjectPass)]);

    part3Pass = part3Pass && subjectPass;
end

if ~part3Pass
    error('segment7_task_f_regression_test:part3Failed', 'Branch 2 notch output does not match the already-saved %s for at least one subject.', notchCsvPath);
end

disp('=== Part 3 PASS ===');
disp(' ');

disp('=== Segment 7 Task F regression test: ALL PASS (Parts 1-3) ===');
