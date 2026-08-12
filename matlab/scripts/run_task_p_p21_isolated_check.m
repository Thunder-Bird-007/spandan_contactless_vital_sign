% RUN_TASK_P_P21_ISOLATED_CHECK Segment 6 Task P, Action 3 isolated test:
% does harmonic-continuity peak selection (validation/
% selectHarmonicConsistentHR.m) correct the known VIPL_p21/v1/forehead
% CHROM harmonic-confusion failure (whole-clip CHROM estimated ~127 bpm
% against a true 68 bpm, roughly 1.9x, first found in Task H1/I and
% recurring in Task N Section 5b)?
%
% This script tests Action 3 ALONE, isolated from Action 2 quality
% gating, so any correction (or lack of one) can be attributed
% specifically to harmonic continuity rather than to window exclusion.
% It does NOT reprocess p21's video -- it loads the already-cached
% data/processed/VIPL_p21_v1_source1_rgb_traces.mat and
% _filtered_traces.mat (same files run_vipl_integration_batch.m already
% produced) and does NOT modify heartrate/fftHeartRate.m,
% heartrate/windowedHeartRate.m, filtering/bandpassClean.m, or
% pulseextraction/chromCombine.m.
%
% Only after this isolated check is reported does
% run_task_p_windowed_batch.m run the full gating+continuity pipeline on
% the full 107-subject pool (Action 4).

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');

subjectID = 'VIPL_p21_v1_source1';

disp(['=== Segment 6 Task P Action 3 isolated check: ' subjectID ' ===']);

rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
filteredMatPath = fullfile(processedDataRoot, [subjectID '_filtered_traces.mat']);

rgbData = load(rgbMatPath);
filteredData = load(filteredMatPath);

fs = filteredData.fs;

pulseChrom = chromCombine(filteredData.R_filtered, filteredData.G_filtered, filteredData.B_filtered, rgbData.R, rgbData.G, rgbData.B);
pulseChromFiltered = bandpassClean(pulseChrom, fs);

disp(' ');
disp('=== Baseline: whole-clip single FFT (fftHeartRate.m, unmodified) ===');

[HR_wholeClip, freqSpectrumWholeClip, powerSpectrumWholeClip] = fftHeartRate(pulseChromFiltered, fs);

HR_groundtruth = 68;

disp(['HR_wholeClip = ' num2str(HR_wholeClip) ' bpm (known Task H1/I/N result: ~127 bpm). HR_groundtruth = ' num2str(HR_groundtruth) ' bpm.']);
disp(['Whole-clip ratio to ground truth: ' num2str(HR_wholeClip / HR_groundtruth) 'x.']);

disp(' ');
disp('=== Action 1: windowing (heartrate/windowedHeartRate.m, unmodified) ===');

[hrBpmNaiveWindowed, windowResults] = windowedHeartRate(pulseChromFiltered, fs);

disp([subjectID ': fs = ' num2str(fs) ' Hz, windowLengthSec = ' num2str(windowResults.windowLengthSec) ', overlapFraction = ' num2str(windowResults.overlapFraction) ', hopSec = ' num2str(windowResults.hopSec) ', numWindows = ' num2str(windowResults.numWindows)]);

disp(' ');
disp('Per-window top-3 candidates (bpm) and quality score, no continuity applied yet:');

for windowIdx = 1:windowResults.numWindows
    candidateStr = [num2str(windowResults.candidateBpm(windowIdx, 1)) ', ' num2str(windowResults.candidateBpm(windowIdx, 2)) ', ' num2str(windowResults.candidateBpm(windowIdx, 3))];
    disp(['  window ' num2str(windowIdx) ' (start ' num2str(windowResults.windowStartSec(windowIdx)) 's): top-3 = [' candidateStr '] bpm, quality = ' num2str(windowResults.qualityScore(windowIdx))]);
end

disp(' ');
disp(['Naive windowed baseline (mean of each window''s own tallest peak, no continuity): ' num2str(hrBpmNaiveWindowed) ' bpm.']);

disp(' ');
disp('=== Action 3: harmonic-continuity peak selection (validation/selectHarmonicConsistentHR.m), ISOLATED from quality gating ===');

[chosenBpmContinuity, overrideFired] = selectHarmonicConsistentHR(windowResults.candidateBpm, windowResults.candidateMagnitude);

disp('Per-window chosen HR after continuity, and whether the continuity rule overrode the tallest-peak choice:');

numOverridesFired = 0;

for windowIdx = 1:windowResults.numWindows
    overrideStr = 'no';

    if overrideFired(windowIdx)
        overrideStr = 'YES';
        numOverridesFired = numOverridesFired + 1;
    end

    disp(['  window ' num2str(windowIdx) ': chosen = ' num2str(chosenBpmContinuity(windowIdx)) ' bpm, tallest-peak was = ' num2str(windowResults.candidateBpm(windowIdx, 1)) ' bpm, continuity override fired = ' overrideStr]);
end

HR_continuityOnly = mean(chosenBpmContinuity);

disp(' ');
disp(['Continuity override fired on ' num2str(numOverridesFired) ' of ' num2str(windowResults.numWindows) ' windows (window 1 can never fire, by definition).']);
disp(['Final HR with continuity, no gating: ' num2str(HR_continuityOnly) ' bpm.']);

disp(' ');
disp('=== Verdict ===');

absErrorWholeClip = abs(HR_wholeClip - HR_groundtruth);
absErrorNaiveWindowed = abs(hrBpmNaiveWindowed - HR_groundtruth);
absErrorContinuity = abs(HR_continuityOnly - HR_groundtruth);

disp(['abs_error whole-clip single FFT       = ' num2str(absErrorWholeClip) ' bpm (' num2str(HR_wholeClip) ' vs ' num2str(HR_groundtruth) ')']);
disp(['abs_error naive windowed (no continuity) = ' num2str(absErrorNaiveWindowed) ' bpm (' num2str(hrBpmNaiveWindowed) ' vs ' num2str(HR_groundtruth) ')']);
disp(['abs_error windowed + harmonic continuity = ' num2str(absErrorContinuity) ' bpm (' num2str(HR_continuityOnly) ' vs ' num2str(HR_groundtruth) ')']);

if absErrorContinuity < absErrorWholeClip && absErrorContinuity < absErrorNaiveWindowed
    disp('READING: harmonic-continuity selection CORRECTS the known ~1.9x harmonic error on p21 -- its final HR is closer to ground truth than both the whole-clip single-FFT estimate and the naive (no-continuity) windowed baseline.');
elseif absErrorContinuity < absErrorWholeClip
    disp('READING: harmonic-continuity selection improves on the whole-clip estimate, but is not clearly better than the naive windowed baseline alone -- windowing itself may already be doing most of the work here, not continuity specifically.');
else
    disp('READING: harmonic-continuity selection does NOT correct the known harmonic error on p21 -- it does not beat the whole-clip single-FFT estimate on this subject.');
end

disp(' ');
disp('--- Task P Action 3 isolated p21 check complete ---');
