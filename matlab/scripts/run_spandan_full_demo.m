% RUN_SPANDAN_FULL_DEMO Segment 7 Task F, Action 3a. The single
% presentation-facing driver for the supervisor demo: runs
% pipeline/estimateVitalsAndMorphology.m (BOTH branches, one shared ROI
% extraction) on every UBFC DATASET_1 ground-truth subject and produces
% ONE combined 5-panel figure per subject:
%   (i)   raw ROI trace (raw G(t), the channel every earlier sanity
%         figure in this project has used for this purpose)
%   (ii)  production pulse (Branch 1's CHROM pulse, after
%         filtering/bandpassClean.m) with HR annotated
%   (iii) morphology ensemble-averaged waveform (Branch 2's
%         prototype.trimmedMean) with the IQR stability band shaded and
%         the detected notch position marked -- ONE beat by construction
%   (iv)  multi-cycle continuous waveform (Segment 8 follow-up, NEW): a
%         real, continuously-sampled ~NUM_CYCLES_MULTIPANEL-cycle stretch
%         of Branch 2's own pre-ensemble-averaging signal
%         (result.branch2.sigUniform, morphology/resampleUniform.m's
%         output -- BEFORE morphology/ensembleAverageBeats.m collapses it
%         to one cycle), reusing the SAME windowing/peak-marking approach
%         as scripts/run_segment7_fig7_multicycle_waveform_batch.m (that
%         script's own reference implementation is NOT modified and NOT
%         re-derived from scratch here -- see extractMultiCycleWindow
%         below, a separate local copy for the same reason
%         run_spandan_interactive.m's renderInteractiveFigure is a
%         separate implementation from this file's own
%         renderSpandanDemoFigure: MATLAB script-local functions cannot be
%         imported across files). Panel (iii) and (iv) are captioned to
%         make their relationship explicit -- see panel (iv)'s title.
%   (v)   a text panel: HR (chrom/pos/green, bpm), SpO2 (%), and notch
%         confidence
% Saved to results/figures/spandan_demo_<subjectID>.png.
%
% Does NOT modify pipeline/estimateVitalsAndMorphology.m,
% morphology/resampleUniform.m, morphology/ensembleAverageBeats.m,
% heartrate/fftHeartRate.m, or scripts/run_segment7_fig7_multicycle_waveform_batch.m
% -- this script only calls them and plots their output. Does NOT touch
% any existing Segment 6/7 script, figure, or doc; every output path here
% is new (same filenames as before -- spandan_demo_<subjectID>.png -- but
% with one additional panel, since that PNG was never a tracked/validated
% metrics artifact the way the CSVs are).
%
% FORBIDDEN approach, stated explicitly (see this task's own brief): panel
% (iv) is NEVER built by tiling/repeating panel (iii)'s single averaged
% beat -- that would fabricate a clean repeating notch from one averaged
% beat presented as several measured beats. It always plots genuinely
% consecutive samples of result.branch2.sigUniform.
%
% SpO2 calibration: pipeline/estimateVitalsAndMorphology.m never fits its
% own calibration (spo2/calibrateSpO2.m's own header explains why -- the
% caller must guarantee a subject never calibrates and predicts itself).
% This script fits that calibration itself, the SAME 5-subject leave-
% one-out loop scripts/run_segment5_dataset1_calibration_batch.m already
% uses (fit spo2/calibrateSpO2.m on the other 4 UBFC subjects, predict
% the one being demoed) -- calibrateSpO2.m itself is unmodified. Ground-
% truth SpO2 for the fit uses the SAME clip-duration-windowed averaging
% that script uses (mean of gtdump.xmp's SpO2 column over timestamps
% falling inside this subject's own video duration), not a naive whole-
% file mean.

NUM_CYCLES_MULTIPANEL = 8; % tunable: how many real cardiac cycles panel (iv) shows (fig7 used 12)
MULTIPANEL_START_OFFSET_SEC = 5; % skip filter-startup transient, same convention as fig7

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

numSubjects = numel(subjectList);

%% === Pass 1: decode every subject once, compute Branch 1's Rvalue and
% each subject's clip-windowed ground-truth SpO2, so Pass 2 can run a
% proper leave-one-out SpO2 calibration (never fit and predict on the
% same subject) without decoding any video a second time. ===
disp('=== Pass 1: decoding all subjects, running both branches (SpO2 uncalibrated for now) ===');

results = cell(1, numSubjects);
rValues = zeros(1, numSubjects);
spo2True = zeros(1, numSubjects);
failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Pass 1: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_spandan_full_demo:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_spandan_full_demo:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        thisResult = estimateVitalsAndMorphology(videoPath, gt, [], struct('subjectID', subjectID));

        videoDurationSec = numel(thisResult.R) / thisResult.frameRate;
        inClipMask = gt.timestamp <= videoDurationSec;
        spo2InClip = gt.spo2(inClipMask);
        if isempty(spo2InClip)
            error('run_spandan_full_demo:emptyGTWindow', 'No gtdump.xmp rows fell inside the video duration (%.2f s) for %s.', videoDurationSec, subjectID);
        end

        results{subjectPos} = thisResult;
        rValues(subjectPos) = thisResult.branch1.Rvalue;
        spo2True(subjectPos) = mean(spo2InClip);

        disp(['Subject ' subjectID ': HR_chrom=' num2str(thisResult.hrBpm.chrom, '%.2f') ' bpm, HR_pos=' num2str(thisResult.hrBpm.pos, '%.2f') ' bpm, notchDetected=' num2str(thisResult.notch.detected) ', Rvalue=' num2str(rValues(subjectPos), '%.5f') ', SpO2_true=' num2str(spo2True(subjectPos), '%.4f')]);
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        results{subjectPos} = [];
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

validMask = ~cellfun(@isempty, results);
numValid = sum(validMask);

disp(' ');
disp(['Pass 1 complete: ' num2str(numValid) ' of ' num2str(numSubjects) ' subjects usable.']);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

if numValid < 3
    error('run_spandan_full_demo:tooFewSubjects', 'Fewer than 3 usable subjects -- leave-one-out SpO2 calibration needs at least 3.');
end

%% === Pass 2: leave-one-out SpO2 calibration + the combined demo figure,
% for every usable subject. ===
disp(' ');
disp('=== Pass 2: leave-one-out SpO2 calibration + combined demo figures ===');

validIdx = find(validMask);

for k = 1:numel(validIdx)
    subjectPos = validIdx(k);
    subjectID = subjectList{subjectPos};
    thisResult = results{subjectPos};

    trainMask = validMask;
    trainMask(subjectPos) = false;

    R_train = rValues(trainMask);
    SpO2_train = spo2True(trainMask);

    [~, calibParamsThis] = calibrateSpO2(R_train, SpO2_train, []);
    [spo2PredThis, ~] = calibrateSpO2(rValues(subjectPos), [], calibParamsThis);

    disp(['Subject ' subjectID ': SpO2_predicted (leave-one-out) = ' num2str(spo2PredThis, '%.2f') ' %, HR_chrom=' num2str(thisResult.hrBpm.chrom, '%.2f') ' bpm, notch confidence=' num2str(thisResult.notch.confidence, '%.4f')]);

    demoPngPath = fullfile(figuresRoot, ['spandan_demo_' subjectID '.png']);
    renderSpandanDemoFigure(thisResult, subjectID, spo2PredThis, demoPngPath, NUM_CYCLES_MULTIPANEL, MULTIPANEL_START_OFFSET_SEC);

    disp(['Saved ' demoPngPath]);
end

disp(' ');
disp('--- Spandan full demo complete ---');

function renderSpandanDemoFigure(result, subjectID, spo2PredThis, pngOutPath, numCyclesToShow, startOffsetSec)
% RENDERSPANDANDEMOFIGURE Builds the 5-panel combined demo figure for one
% subject and saves it to pngOutPath. Reads only from result (this
% function's own arguments), never re-runs any pipeline stage except the
% cheap fftHeartRate.m call panel (iv) needs to convert cycles -> seconds
% (result.branch2.hrBpmUsed is already exactly that call's output and is
% reused directly, not recomputed).

figHandle = figure('Visible', 'off', 'Position', [80 80 1400 1350]);
tl = tiledlayout(figHandle, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- Panel (i): raw ROI trace (raw G(t)) ---
axRaw = nexttile(tl);
rawTimeAxis = result.roiTimestamps;
plot(axRaw, rawTimeAxis, result.G, 'LineWidth', 1.1, 'Color', [0.20 0.45 0.20]);
xlabel(axRaw, 'Time (s)');
ylabel(axRaw, 'Raw pixel intensity');
title(axRaw, '(i) Raw ROI trace, G(t)');
xlim(axRaw, [rawTimeAxis(1), rawTimeAxis(end)]);
box(axRaw, 'on');

% --- Panel (ii): production pulse (Branch 1, CHROM) with HR annotated ---
axProd = nexttile(tl);
prodPulse = result.branch1.pulseChromFiltered;
prodTimeAxis = (0:(numel(prodPulse) - 1)) / result.frameRate;
plot(axProd, prodTimeAxis, prodPulse, 'LineWidth', 1.1, 'Color', [0.15 0.25 0.55]);
xlabel(axProd, 'Time (s)');
ylabel(axProd, 'Pulse amplitude (a.u.)');
title(axProd, ['(ii) Production pulse (CHROM), HR = ' num2str(result.hrBpm.chrom, '%.1f') ' bpm']);
xlim(axProd, [prodTimeAxis(1), prodTimeAxis(end)]);
box(axProd, 'on');

% --- Panel (iii): morphology ensemble-averaged waveform, IQR band
% shaded, notch position marked ---
axMorph = nexttile(tl);
cycleFrac = linspace(0, 1, numel(result.prototype.trimmedMean));
hold(axMorph, 'on');
fill(axMorph, [cycleFrac, fliplr(cycleFrac)], [result.iqrBand.q3, fliplr(result.iqrBand.q1)], ...
    [0.75 0.80 0.95], 'EdgeColor', 'none', 'FaceAlpha', 0.6, 'DisplayName', 'IQR band (beat-to-beat spread)');
plot(axMorph, cycleFrac, result.prototype.trimmedMean, 'LineWidth', 1.8, 'Color', [0.10 0.15 0.45], 'DisplayName', 'Ensemble-averaged beat');
if result.notch.detected
    xline(axMorph, cycleFrac(round(result.notch.position * (numel(cycleFrac) - 1)) + 1), '--', 'Color', [0.80 0.15 0.15], 'LineWidth', 1.6, 'DisplayName', 'Detected notch');
    notchLabel = ['notch detected @ ' num2str(result.notch.position, '%.3f') ' (conf ' num2str(result.notch.confidence, '%.2f') ')'];
else
    notchLabel = 'no notch detected';
end
hold(axMorph, 'off');
xlabel(axMorph, 'Cycle fraction (systolic peak anchored at 0.25)');
ylabel(axMorph, 'Pulse amplitude (a.u.)');
title(axMorph, {'(iii) Single-cycle prototype (ensemble-averaged beat)', ...
    [notchLabel ' -- resolvable HERE (averaging raises SNR)']}, 'FontSize', 10);
legend(axMorph, 'Location', 'best', 'FontSize', 7);
xlim(axMorph, [0 1]);
box(axMorph, 'on');

% --- Panel (iv): multi-cycle continuous waveform (NEW, Segment 8
% follow-up). Reuses result.branch2.sigUniform/uniformFs -- the SAME
% pre-ensemble-averaging signal scripts/run_segment7_fig7_multicycle_waveform_batch.m
% plots, since estimateVitalsAndMorphology.m's Branch 2 is byte-identical
% to that script's own chain up to (and including) resampleUniform.m. Real
% continuous samples only -- never tiles/repeats panel (iii). ---
axMulti = nexttile(tl);
[timeWindowMulti, sigWindowMulti, peakTimesMulti, peakValsMulti, actualCyclesShownMulti] = ...
    extractMultiCycleWindow(result.branch2.sigUniform, result.branch2.uniformFs, numCyclesToShow, startOffsetSec);
hold(axMulti, 'on');
plot(axMulti, timeWindowMulti, sigWindowMulti, 'LineWidth', 1.2, 'Color', [0.15 0.25 0.55]);
plot(axMulti, peakTimesMulti, peakValsMulti, 'o', 'MarkerSize', 6, 'MarkerFaceColor', [0.85 0.20 0.20], ...
    'MarkerEdgeColor', 'k', 'LineStyle', 'none', 'DisplayName', 'Systolic peaks (visual aid)');
hold(axMulti, 'off');
xlabel(axMulti, 'Time (s)');
ylabel(axMulti, 'Pulse amplitude (a.u.)');
title(axMulti, {['(iv) Multi-cycle waveform, real time, ~' num2str(actualCyclesShownMulti) ' measured cycles'], ...
    'Same signal as (iii), pre-averaging -- notch LESS visible per-beat (SNR limit, not a regression)'}, 'FontSize', 10);
xlim(axMulti, [timeWindowMulti(1), timeWindowMulti(end)]);
box(axMulti, 'on');

% --- Panel (v): text summary ---
axText = nexttile(tl, 5, [1 2]);
axis(axText, 'off');
if result.notch.detected
    notchLine = ['Notch: detected, position ' num2str(result.notch.position, '%.3f') ', depth ' num2str(result.notch.depth, '%.3f') ', confidence ' num2str(result.notch.confidence, '%.3f')];
else
    notchLine = 'Notch: not detected';
end
summaryLines = { ...
    ['Subject: ' subjectID], ...
    '', ...
    'Heart rate:', ...
    ['  CHROM: ' num2str(result.hrBpm.chrom, '%.1f') ' bpm'], ...
    ['  POS:   ' num2str(result.hrBpm.pos, '%.1f') ' bpm'], ...
    ['  Green: ' num2str(result.hrBpm.green, '%.1f') ' bpm'], ...
    '', ...
    ['SpO2 (leave-one-out calibrated): ' num2str(spo2PredThis, '%.1f') ' %'], ...
    '', ...
    notchLine, ...
    ['Beats averaged: ' num2str(result.branch2.beatStats.beatsAveraged)] ...
    };
text(axText, 0.02, 0.95, summaryLines, 'VerticalAlignment', 'top', 'FontSize', 12, 'Interpreter', 'none');
title(axText, '(v) Summary');

title(tl, ['Spandan full-pipeline demo -- subject ' subjectID], 'Interpreter', 'none', 'FontWeight', 'bold');

exportgraphics(figHandle, pngOutPath);
close(figHandle);

end

function [timeWindow, sigWindow, peakTimes, peakVals, actualCyclesShown] = extractMultiCycleWindow(sigUniform, uniformFs, numCyclesToShow, startOffsetSec)
% EXTRACTMULTICYCLEWINDOW Picks a numCyclesToShow-cardiac-cycle window of
% a continuous uniform-grid signal, starting startOffsetSec seconds in to
% skip filter-startup transients, and marks systolic peaks with a plain
% findpeaks() scan (annotation only, gated by this signal's own HR) purely
% so a reader can visually count cycles. Local re-implementation of
% scripts/run_segment7_fig7_multicycle_waveform_batch.m's own per-subject
% windowing logic (that script is not modified and not called from here --
% see this file's header for why) -- same formulas, reused deliberately
% rather than re-derived.

hrBpm = fftHeartRate(sigUniform, uniformFs);
cycleDurationSec = 60 / hrBpm;
windowDurationSec = numCyclesToShow * cycleDurationSec;

totalDurationSec = numel(sigUniform) / uniformFs;
windowStartSec = min(startOffsetSec, max(0, totalDurationSec - windowDurationSec - 1));
if windowStartSec + windowDurationSec > totalDurationSec
    windowDurationSec = totalDurationSec - windowStartSec;
end

startSample = max(1, round(windowStartSec * uniformFs) + 1);
endSample = min(numel(sigUniform), startSample + round(windowDurationSec * uniformFs) - 1);

sigWindow = sigUniform(startSample:endSample);
timeWindow = (0:(numel(sigWindow) - 1)) / uniformFs; % window-relative time, seconds

minPeakDistSamples = max(1, round(0.5 * cycleDurationSec * uniformFs));
[peakVals, peakLocs] = findpeaks(sigWindow, 'MinPeakDistance', minPeakDistSamples);
peakTimes = timeWindow(peakLocs);
actualCyclesShown = numel(peakVals);

end
