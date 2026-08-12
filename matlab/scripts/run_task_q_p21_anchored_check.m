% RUN_TASK_Q_P21_ANCHORED_CHECK Segment 6 Task Q, Part 1 Action 2: does
% quality-anchored harmonic continuity (validation/
% selectHarmonicConsistentHR_anchored.m) still correct the known
% VIPL_p21/v1/forehead CHROM harmonic-confusion failure (whole-clip CHROM
% ~127 bpm against a true 68 bpm) the same way Task P's window-1-anchored
% version did, and where does the highest-quality anchor land on this
% subject -- window 1 still, or somewhere else?
%
% Same isolation discipline as scripts/run_task_p_p21_isolated_check.m:
% no gating applied, loads already-cached data/processed/
% VIPL_p21_v1_source1_rgb_traces.mat and _filtered_traces.mat, does NOT
% modify heartrate/fftHeartRate.m, heartrate/windowedHeartRate.m,
% filtering/bandpassClean.m, pulseextraction/chromCombine.m, or
% validation/selectHarmonicConsistentHR.m.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');

subjectID = 'VIPL_p21_v1_source1';

disp(['=== Segment 6 Task Q Part 1 Action 2 anchored check: ' subjectID ' ===']);

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

disp(['HR_wholeClip = ' num2str(HR_wholeClip) ' bpm. HR_groundtruth = ' num2str(HR_groundtruth) ' bpm.']);

disp(' ');
disp('=== Windowing (heartrate/windowedHeartRate.m, unmodified) ===');

[hrBpmNaiveWindowed, windowResults] = windowedHeartRate(pulseChromFiltered, fs);

disp([subjectID ': fs = ' num2str(fs) ' Hz, numWindows = ' num2str(windowResults.numWindows)]);

disp(' ');
disp('Per-window top-3 candidates (bpm) and quality score:');

for windowIdx = 1:windowResults.numWindows
    candidateStr = [num2str(windowResults.candidateBpm(windowIdx, 1)) ', ' num2str(windowResults.candidateBpm(windowIdx, 2)) ', ' num2str(windowResults.candidateBpm(windowIdx, 3))];
    disp(['  window ' num2str(windowIdx) ' (start ' num2str(windowResults.windowStartSec(windowIdx)) 's): top-3 = [' candidateStr '] bpm, quality = ' num2str(windowResults.qualityScore(windowIdx))]);
end

disp(' ');
disp('=== Task P (existing): window-1-anchored continuity, validation/selectHarmonicConsistentHR.m (unmodified) ===');

[chosenBpmWindow1Anchor, overrideFiredWindow1Anchor] = selectHarmonicConsistentHR(windowResults.candidateBpm, windowResults.candidateMagnitude);

HR_window1Anchor = mean(chosenBpmWindow1Anchor);

disp(['Window-1-anchored final HR (Task P): ' num2str(HR_window1Anchor) ' bpm.']);

disp(' ');
disp('=== Task Q Part 1 (new): quality-anchored continuity, validation/selectHarmonicConsistentHR_anchored.m ===');

[chosenBpmAnchored, overrideFiredAnchored, anchorWindowIdx] = selectHarmonicConsistentHR_anchored(windowResults.candidateBpm, windowResults.candidateMagnitude, windowResults.qualityScore);

disp(['Anchor window selected: window ' num2str(anchorWindowIdx) ' (quality score = ' num2str(windowResults.qualityScore(anchorWindowIdx)) ', start ' num2str(windowResults.windowStartSec(anchorWindowIdx)) 's).']);

if anchorWindowIdx == 1
    disp('Anchor is STILL window 1 on this subject.');
else
    disp('Anchor is DIFFERENT from window 1 on this subject.');
end

disp(' ');
disp('Per-window chosen HR after anchored continuity, and whether the continuity rule overrode the tallest-peak choice:');

numOverridesFiredAnchored = 0;

for windowIdx = 1:windowResults.numWindows
    overrideStr = 'no';

    if overrideFiredAnchored(windowIdx)
        overrideStr = 'YES';
        numOverridesFiredAnchored = numOverridesFiredAnchored + 1;
    end

    anchorTag = '';

    if windowIdx == anchorWindowIdx
        anchorTag = ' (ANCHOR)';
    end

    disp(['  window ' num2str(windowIdx) anchorTag ': chosen = ' num2str(chosenBpmAnchored(windowIdx)) ' bpm, tallest-peak was = ' num2str(windowResults.candidateBpm(windowIdx, 1)) ' bpm, continuity override fired = ' overrideStr]);
end

HR_anchored = mean(chosenBpmAnchored);

disp(' ');
disp(['Anchored continuity override fired on ' num2str(numOverridesFiredAnchored) ' of ' num2str(windowResults.numWindows) ' windows (anchor window can never fire, by definition).']);
disp(['Final HR with anchored continuity, no gating: ' num2str(HR_anchored) ' bpm.']);

disp(' ');
disp('=== Verdict ===');

absErrorWholeClip = abs(HR_wholeClip - HR_groundtruth);
absErrorNaiveWindowed = abs(hrBpmNaiveWindowed - HR_groundtruth);
absErrorWindow1Anchor = abs(HR_window1Anchor - HR_groundtruth);
absErrorAnchored = abs(HR_anchored - HR_groundtruth);

disp(['abs_error whole-clip single FFT         = ' num2str(absErrorWholeClip) ' bpm (' num2str(HR_wholeClip) ' vs ' num2str(HR_groundtruth) ')']);
disp(['abs_error naive windowed (no continuity) = ' num2str(absErrorNaiveWindowed) ' bpm (' num2str(hrBpmNaiveWindowed) ' vs ' num2str(HR_groundtruth) ')']);
disp(['abs_error window-1-anchored continuity   = ' num2str(absErrorWindow1Anchor) ' bpm (' num2str(HR_window1Anchor) ' vs ' num2str(HR_groundtruth) ')']);
disp(['abs_error quality-anchored continuity    = ' num2str(absErrorAnchored) ' bpm (' num2str(HR_anchored) ' vs ' num2str(HR_groundtruth) ')']);

if absErrorAnchored < absErrorWholeClip && absErrorAnchored < absErrorNaiveWindowed
    disp('READING: quality-anchored continuity selection CORRECTS the known ~1.9x harmonic error on p21 -- its final HR is closer to ground truth than both the whole-clip single-FFT estimate and the naive windowed baseline.');
elseif absErrorAnchored < absErrorWholeClip
    disp('READING: quality-anchored continuity selection improves on the whole-clip estimate, but is not clearly better than the naive windowed baseline alone.');
else
    disp('READING: quality-anchored continuity selection does NOT correct the known harmonic error on p21.');
end

disp(' ');
disp('--- Task Q Part 1 Action 2 anchored p21 check complete ---');
