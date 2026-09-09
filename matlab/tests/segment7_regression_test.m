% SEGMENT7_REGRESSION_TEST Segment 7 Task A, Action 7. Proves the
% pre-existing HR path is byte-for-byte untouched by every file Segment 7
% Task A added or reused (morphology/bandpassMorphology.m,
% morphology/fixPolarity.m, morphology/fixPolarityByGroundTruth.m,
% morphology/resampleUniform.m, morphology/ensembleAverageBeats.m,
% morphology/extractMorphologyWaveform.m).
%
% Method: re-run the EXACT original Pass-1 HR chain (filtering/
% detrendSignal.m -> filtering/bandpassClean.m -> pulseextraction/
% chromCombine.m and pulseextraction/posCombine.m -> heartrate/
% fftHeartRate.m -- exactly scripts/run_segment4_heartrate_batch.m's own
% sequence) on a single cached subject's already-extracted
% data/processed/<subject>_rgb_traces.mat, and compare the resulting
% HR_chrom/HR_pos/HR_green against the values Segment 4 already saved to
% data/processed/<subject>_hr_estimates.mat BEFORE Segment 7 Task A
% existed. No video is re-decoded (matches
% scripts/run_segment6_task_o_adaptive_refine.m's precedent for a cheap,
% reproducible regression check using cached traces).
%
% Uses isequal() -- bit-for-bit, not tolerance-based -- matching
% docs/Segment6_Task_O_Detrend_And_Adaptive_Bandpass.md's own
% "byte-identical, not assumed" regression-check convention. If ANY
% comparison fails, this errors out immediately: something in Segment 7
% Task A's morphology/ files leaked into the HR path and must be
% reverted (it should not have, since every morphology/ file is
% additive/new and none of them modify or are called by
% filtering/bandpassClean.m, filtering/detrendSignal.m,
% pulseextraction/chromCombine.m, pulseextraction/posCombine.m, or
% heartrate/fftHeartRate.m).
%
% Not a formal unit-test-framework test (this project has none as of
% Segment 7 -- see tests/sanity_test.m); run this file directly, e.g.
% via matlab -batch "startup; run('tests/segment7_regression_test.m')".
% A clean run with no error IS the passing result.

subjectID = '5-gt';

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');

rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
hrEstimatesPath = fullfile(processedDataRoot, [subjectID '_hr_estimates.mat']);

if ~isfile(rgbMatPath)
    error('segment7_regression_test:missingInput', 'Cached rgb_traces.mat not found: %s', rgbMatPath);
end
if ~isfile(hrEstimatesPath)
    error('segment7_regression_test:missingInput', 'Cached hr_estimates.mat not found: %s -- run scripts/run_segment4_heartrate_batch.m first.', hrEstimatesPath);
end

rgbData = load(rgbMatPath);
previouslySaved = load(hrEstimatesPath);

R = rgbData.R;
G = rgbData.G;
B = rgbData.B;
fs = rgbData.fs;

disp(['Segment 7 regression test: recomputing HR path for subject ' subjectID ' from cached rgb_traces.mat ...']);

[R_detrended, ~] = detrendSignal(R);
[G_detrended, ~] = detrendSignal(G);
[B_detrended, ~] = detrendSignal(B);

[R_filtered, ~] = bandpassClean(R_detrended, fs);
[G_filtered, ~] = bandpassClean(G_detrended, fs);
[B_filtered, ~] = bandpassClean(B_detrended, fs);

pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
pulseChromFiltered = bandpassClean(pulseChrom, fs);
[HR_chrom_recomputed, ~, ~] = fftHeartRate(pulseChromFiltered, fs);

pulsePos = posCombine(R_filtered, G_filtered, B_filtered, fs, R, G, B);
pulsePosFiltered = bandpassClean(pulsePos, fs);
[HR_pos_recomputed, ~, ~] = fftHeartRate(pulsePosFiltered, fs);

[HR_green_recomputed, ~, ~] = fftHeartRate(G_filtered, fs);

chromMatch = isequal(HR_chrom_recomputed, previouslySaved.HR_chrom);
posMatch = isequal(HR_pos_recomputed, previouslySaved.HR_pos);
greenMatch = isequal(HR_green_recomputed, previouslySaved.HR_green);

disp(['HR_chrom: recomputed = ' num2str(HR_chrom_recomputed, '%.10f') ', saved = ' num2str(previouslySaved.HR_chrom, '%.10f') ', byte-identical = ' num2str(chromMatch)]);
disp(['HR_pos:   recomputed = ' num2str(HR_pos_recomputed, '%.10f') ', saved = ' num2str(previouslySaved.HR_pos, '%.10f') ', byte-identical = ' num2str(posMatch)]);
disp(['HR_green: recomputed = ' num2str(HR_green_recomputed, '%.10f') ', saved = ' num2str(previouslySaved.HR_green, '%.10f') ', byte-identical = ' num2str(greenMatch)]);

allMatch = chromMatch && posMatch && greenMatch;

if ~allMatch
    error('segment7_regression_test:regressionFailed', 'HR path is NOT byte-identical to its pre-Segment-7 output for subject %s -- something in Segment 7 Task A leaked into the HR path and must be reverted. See the comparison above for which method(s) diverged.', subjectID);
end

disp(['=== PASS: HR path for subject ' subjectID ' is byte-identical to its pre-Segment-7-Task-A output (HR_chrom, HR_pos, HR_green all isequal). ===']);
