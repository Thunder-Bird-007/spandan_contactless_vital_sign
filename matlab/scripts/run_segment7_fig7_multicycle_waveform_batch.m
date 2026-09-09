% RUN_SEGMENT7_FIG7_MULTICYCLE_WAVEFORM_BATCH Segment 7, new
% visualization-only task. Unlike segment7_fig6 (a SINGLE beat-averaged
% prototype cycle), this shows a continuous, multi-cycle stretch (~12
% real cardiac cycles) of the actual rPPG waveform for direct visual
% "does this look like a PPG trace" inspection.
%
% Uses the SAME adopted-best pipeline as
% scripts/run_segment7_fig6_labeled_prototype_batch.m and
% scripts/run_segment7_task_b_branch2_batch.m's "adaptiveHarmonic"
% condition -- baseline (non-tiled) ROI + wide-band CHROM
% (morphology/bandpassMorphology.m, 'wide') + morphology/adaptiveHarmonicFilter.m
% (ABPF, per-channel, pre-CHROM) + GT-anchored polarity fix
% (morphology/fixPolarityByGroundTruth.m) -- but stops at the CONTINUOUS
% uniform-grid signal (morphology/resampleUniform.m's output), i.e.
% BEFORE morphology/ensembleAverageBeats.m's beat-segmentation/averaging
% step, since that step is what collapses everything down to one cycle.
%
% Does NOT modify morphology/bandpassMorphology.m,
% morphology/adaptiveHarmonicFilter.m, morphology/fixPolarityByGroundTruth.m,
% morphology/resampleUniform.m, or pulseextraction/chromCombine.m -- new,
% additive script, new, separately-named outputs only. Does not call
% morphology/ensembleAverageBeats.m or morphology/notchDetectIEM.m at all
% (no beat-averaging, no notch detection here -- pure raw-trace
% visualization).
%
% Per subject: picks a ~12-cardiac-cycle window (using that subject's own
% fftHeartRate.m estimate to convert cycles -> seconds), starting a few
% seconds in to skip filter-startup transients, and plots the windowed
% signal against real time (seconds) -- NOT the cycle-fraction axis
% fig1-fig6 use. Systolic-peak locations within the window are marked via
% a plain findpeaks() scan (annotation only, min-distance gated by the
% subject's own HR) purely so a reader can visually count cycles; this is
% NOT morphology/notchDetectIEM.m and does not detect notches.
%
% Outputs (results/figures/), all NEW files, fig1-fig6 untouched:
%   segment7_fig7_multicycle_waveform_<subjectID>.png - one per subject.
%   segment7_fig7_multicycle_waveform_gallery.png     - all 5 subjects as
%     a small-multiples summary panel.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
numCyclesToShow = 12;
startOffsetSec = 5; % skip filter-startup transient at the very beginning

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

galleryData = cell(1, numSubjects);

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 FIG 7 multi-cycle batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_fig7_multicycle_waveform_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_fig7_multicycle_waveform_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % === Adopted-best pipeline, same call sequence as
        % run_segment7_fig6_labeled_prototype_batch.m, stopping at the
        % continuous uniform-grid signal (no beat averaging). ===
        [frames, frameRate, ~] = loadUBFCVideo(videoPath);
        [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate);

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        [R_wide, ~, ~] = bandpassMorphology(R_detrended, frameRate, 'wide');
        [G_wide, ~, ~] = bandpassMorphology(G_detrended, frameRate, 'wide');
        [B_wide, ~, ~] = bandpassMorphology(B_detrended, frameRate, 'wide');
        pulseWide = chromCombine(R_wide, G_wide, B_wide, R, G, B);
        sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;

        [R_ahf, ~, ~] = adaptiveHarmonicFilter(R_detrended, frameRate, 6, sharedF0Hz);
        [G_ahf, ~, ~] = adaptiveHarmonicFilter(G_detrended, frameRate, 6, sharedF0Hz);
        [B_ahf, ~, ~] = adaptiveHarmonicFilter(B_detrended, frameRate, 6, sharedF0Hz);
        pulseAdaptive = chromCombine(R_ahf, G_ahf, B_ahf, R, G, B);

        [pulseFixed, wasFlipped] = fixPolarityByGroundTruth(pulseAdaptive, roiTimestamps, gt.ppg, gt.timestamp);
        [sigUniform, ~, fsUniform] = resampleUniform(pulseFixed, roiTimestamps);

        hrBpm = fftHeartRate(sigUniform, fsUniform);
        cycleDurationSec = 60 / hrBpm;
        windowDurationSec = numCyclesToShow * cycleDurationSec;

        totalDurationSec = numel(sigUniform) / fsUniform;
        windowStartSec = min(startOffsetSec, max(0, totalDurationSec - windowDurationSec - 1));
        if windowStartSec + windowDurationSec > totalDurationSec
            windowDurationSec = totalDurationSec - windowStartSec;
        end

        startSample = max(1, round(windowStartSec * fsUniform) + 1);
        endSample = min(numel(sigUniform), startSample + round(windowDurationSec * fsUniform) - 1);

        sigWindow = sigUniform(startSample:endSample);
        timeWindow = (0:(numel(sigWindow) - 1)) / fsUniform; % window-relative time, seconds

        % Peak markers, purely to help a reader visually count cycles --
        % not a detection algorithm, just findpeaks() with a min-distance
        % gate from this subject's own HR.
        minPeakDistSamples = max(1, round(0.5 * cycleDurationSec * fsUniform));
        [peakVals, peakLocs] = findpeaks(sigWindow, 'MinPeakDistance', minPeakDistSamples);
        peakTimes = timeWindow(peakLocs);
        actualCyclesShown = numel(peakVals);

        disp(['Subject ' subjectID ' (wasFlipped=' num2str(wasFlipped) '): hrBpm=' num2str(hrBpm, '%.2f') ', window=' num2str(windowDurationSec, '%.2f') 's starting at ' num2str(windowStartSec, '%.2f') 's, peaks found=' num2str(actualCyclesShown)]);

        % === FIG 7 (per subject): multi-cycle continuous waveform. ===
        figHandle = figure('Visible', 'off', 'Position', [100 100 1400 500]);
        axHandle = axes(figHandle);
        titleLines = {['Subject ' subjectID ' -- Segment 7 FIG 7: continuous rPPG waveform, ~' num2str(actualCyclesShown) ' cycles'], ...
            '(adopted-best pipeline: CHROM+wide+ABPF+GT-polarity, no beat-averaging)'};
        drawMultiCycleWaveform(axHandle, timeWindow, sigWindow, peakTimes, peakVals, titleLines, false);
        fig7Path = fullfile(figuresRoot, ['segment7_fig7_multicycle_waveform_' subjectID '.png']);
        exportgraphics(figHandle, fig7Path);
        close(figHandle);
        disp(['Saved ' fig7Path]);

        galleryData{subjectPos} = struct('subjectID', subjectID, 'timeWindow', timeWindow, ...
            'sigWindow', sigWindow, 'peakTimes', peakTimes, 'peakVals', peakVals, ...
            'actualCyclesShown', actualCyclesShown);
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
        galleryData{subjectPos} = [];
    end
end

% === Gallery: all 5 subjects stacked (multi-cycle traces are wide, so
% stack vertically rather than a 2x3 grid). ===
validGallery = ~cellfun(@isempty, galleryData);
if any(validGallery)
    figHandleGallery = figure('Visible', 'off', 'Position', [100 100 1400 1400]);
    tl = tiledlayout(figHandleGallery, numSubjects, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    for subjectPos = 1:numSubjects
        if isempty(galleryData{subjectPos})
            continue
        end
        d = galleryData{subjectPos};
        axHandle = nexttile(tl);
        subjectTitle = [d.subjectID ' (~' num2str(d.actualCyclesShown) ' cycles)'];
        drawMultiCycleWaveform(axHandle, d.timeWindow, d.sigWindow, d.peakTimes, d.peakVals, subjectTitle, true);
    end
    title(tl, 'Segment 7 FIG 7: continuous multi-cycle rPPG waveforms, all 5 ground-truth UBFC subjects (adopted-best pipeline)');
    galleryPath = fullfile(figuresRoot, 'segment7_fig7_multicycle_waveform_gallery.png');
    exportgraphics(figHandleGallery, galleryPath);
    close(figHandleGallery);
    disp(['Saved ' galleryPath]);
end

disp('--- Segment 7 FIG 7 multi-cycle batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

function drawMultiCycleWaveform(axHandle, timeWindow, sigWindow, peakTimes, peakVals, titleStr, compact)
% DRAWMULTICYCLEWAVEFORM Plots a continuous multi-cycle waveform segment
% with systolic-peak markers overlaid purely as a visual cycle-counting
% aid (findpeaks() result passed straight through, no new algorithm).
axes(axHandle); %#ok<LAXES>
hold(axHandle, 'on');
plot(axHandle, timeWindow, sigWindow, 'LineWidth', 1.3, 'Color', [0.15 0.25 0.55]);
if compact
    markerSize = 5;
    fontSize = 8;
else
    markerSize = 7;
    fontSize = 10;
end
plot(axHandle, peakTimes, peakVals, 'o', 'MarkerSize', markerSize, ...
    'MarkerFaceColor', [0.85 0.20 0.20], 'MarkerEdgeColor', 'k', 'LineStyle', 'none');
hold(axHandle, 'off');
xlabel(axHandle, 'Time (s)');
ylabel(axHandle, 'Pulse amplitude (a.u.)');
title(axHandle, titleStr, 'Interpreter', 'none', 'FontSize', fontSize + 2);
set(axHandle, 'FontSize', fontSize);
xlim(axHandle, [timeWindow(1), timeWindow(end)]);
box(axHandle, 'on');
end
