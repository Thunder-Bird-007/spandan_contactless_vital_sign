% RUN_SEGMENT7_FIG6_LABELED_PROTOTYPE_BATCH Segment 7, new visualization-
% only task. Produces a labeled beat-prototype figure (systolic peak,
% dicrotic notch, second wave, end-of-cycle/diastolic point) for the
% ADOPTED BEST single configuration established by Task B/C2 -- baseline
% (non-tiled) ROI + wide-band CHROM (morphology/bandpassMorphology.m,
% 'wide') + morphology/adaptiveHarmonicFilter.m (ABPF, applied per-channel
% BEFORE pulseextraction/chromCombine.m) + GT-anchored polarity fix
% (morphology/fixPolarityByGroundTruth.m, available for all 5 DATASET_1
% ground-truth subjects) + morphology/ensembleAverageBeats.m. This is
% EXACTLY the "adaptiveHarmonic" condition/call sequence already run and
% reported by scripts/run_segment7_task_b_branch2_batch.m (confirmed as
% ABPF-only's own operating point in
% docs/Segment7_Task_B_Notch_Quantification.md's Combined-v2 discussion,
% Task C2) -- this script does not change that call sequence in any way,
% it only adds plotting/annotation on top of the same outputs.
%
% Does NOT modify morphology/bandpassMorphology.m,
% morphology/adaptiveHarmonicFilter.m, morphology/fixPolarityByGroundTruth.m,
% morphology/fixPolarity.m, morphology/ensembleAverageBeats.m,
% pulseextraction/chromCombine.m, or morphology/notchDetectIEM.m -- new,
% additive script, new, separately-named outputs only.
%
% Per subject, on the trimmed-mean prototype (morphology/ensembleAverageBeats.m's
% prototype.trimmedMean, cycle-fraction grid 0..1, systolic peak anchored
% at 0.25 by construction):
%   - Systolic peak marker: at cycle-fraction 0.25 (nearest grid sample),
%     always plotted -- known by construction, not a detection result.
%   - Dicrotic notch marker: at notchPositionNormalized, ONLY IF
%     notchDetected is true for that subject (morphology/notchDetectIEM.m's
%     own boolean) -- no marker fabricated when false.
%   - "Second wave" marker: the first local maximum of the prototype
%     AFTER the notch index -- pure plotting annotation via a simple
%     local-max scan of the already-computed prototype values, NOT a new
%     detection algorithm. Only searched for when a notch was detected
%     (there is no "after the notch" otherwise). If no local max exists
%     after the notch (e.g. prototype falls monotonically to the end of
%     the cycle), no second-wave marker is plotted and that is reported,
%     not hidden.
%   - End-of-cycle / diastolic point marker: at cycle-fraction 1.0 (last
%     sample), always plotted.
%
% Outputs (results/figures/), all NEW files, fig1-fig5 untouched:
%   segment7_fig6_labeled_prototype_<subjectID>.png - one per subject.
%   segment7_fig6_labeled_prototype_gallery.png     - all 5 subjects as a
%     small-multiples summary panel.
%
% Outputs (results/metrics/):
%   segment7_fig6_labeled_prototype_notch.csv - one row per subject:
%     notchDetected, notchPositionNormalized, notchDepth, confidence,
%     confidenceRaw (see morphology/notchDetectIEM.m for what confidence
%     vs. confidenceRaw means -- confidence is clipped to [0,1],
%     confidenceRaw is not), plus whether a second-wave local max was
%     found and, if so, its cycle-fraction location.

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

csvPath = fullfile(metricsRoot, 'segment7_fig6_labeled_prototype_notch.csv');
headerLine = "subjectID,notchDetected,notchPositionNormalized,notchDepth,confidence,confidenceRaw,secondWaveFound,secondWaveCycleFraction,effectiveFsHz,hrBpmUsed,beatsAveraged";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

galleryData = cell(1, numSubjects);

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 FIG 6 labeled-prototype batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_fig6_labeled_prototype_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_fig6_labeled_prototype_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        % === Adopted-best pipeline: EXACTLY
        % run_segment7_task_b_branch2_batch.m's "adaptiveHarmonic"
        % condition call sequence. ===
        [frames, frameRate, ~] = loadUBFCVideo(videoPath);
        [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate);

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        % Shared f0 for the harmonic comb: from the wide-band CHROM
        % pulse, same as branch2/C2.
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
        [prototype, ~, ~, beatStats] = ensembleAverageBeats(sigUniform, fsUniform);

        hrBpm = fftHeartRate(sigUniform, fsUniform);
        effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

        [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFs);

        disp(['Subject ' subjectID ' adaptive-harmonic (wasFlipped=' num2str(wasFlipped) '): notchDetected=' num2str(notchDetected) ', pos=' num2str(notchPos, '%.4f') ', depth=' num2str(notchDepth, '%.4f') ', confidence=' num2str(confidence, '%.4f') ', confidenceRaw=' num2str(confidenceRaw, '%.4f')]);

        % === Compute the (purely annotation-level) cycle markers. ===
        proto = prototype.trimmedMean;
        N = numel(proto);
        cycleFrac = linspace(0, 1, N);

        markers = computeCycleMarkers(proto, cycleFrac, notchDetected, notchPos);

        % === FIG 6 (per subject): labeled prototype. ===
        figHandle = figure('Visible', 'off', 'Position', [100 100 900 650]);
        axHandle = axes(figHandle);
        titleLines = {['Subject ' subjectID ' -- Segment 7 FIG 6: labeled beat prototype'], ...
            '(adopted-best pipeline: CHROM+wide+ABPF+GT-polarity+ensemble)'};
        drawLabeledPrototype(axHandle, cycleFrac, proto, markers, titleLines, false);
        fig6Path = fullfile(figuresRoot, ['segment7_fig6_labeled_prototype_' subjectID '.png']);
        exportgraphics(figHandle, fig6Path);
        close(figHandle);
        disp(['Saved ' fig6Path]);

        galleryData{subjectPos} = struct('subjectID', subjectID, 'cycleFrac', cycleFrac, 'proto', proto, 'markers', markers);

        secondWaveFoundStr = num2str(markers.secondWave.found);
        if markers.secondWave.found
            secondWaveFracStr = num2str(markers.secondWave.x, '%.4f');
        else
            secondWaveFracStr = 'NaN';
        end

        row = {subjectID, num2str(notchDetected), num2str(notchPos, '%.4f'), num2str(notchDepth, '%.4f'), num2str(confidence, '%.4f'), num2str(confidenceRaw, '%.4f'), secondWaveFoundStr, secondWaveFracStr, num2str(effectiveFs, '%.4f'), num2str(hrBpm, '%.4f'), num2str(beatStats.beatsAveraged)};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
        galleryData{subjectPos} = [];
    end
end

% === Gallery: all 5 subjects as small multiples. ===
validGallery = ~cellfun(@isempty, galleryData);
if any(validGallery)
    figHandleGallery = figure('Visible', 'off', 'Position', [100 100 1500 900]);
    tl = tiledlayout(figHandleGallery, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for subjectPos = 1:numSubjects
        if isempty(galleryData{subjectPos})
            continue
        end
        d = galleryData{subjectPos};
        axHandle = nexttile(tl);
        drawLabeledPrototype(axHandle, d.cycleFrac, d.proto, d.markers, d.subjectID, true);
    end
    title(tl, 'Segment 7 FIG 6: labeled beat prototypes, all 5 ground-truth UBFC subjects (adopted-best pipeline)');
    galleryPath = fullfile(figuresRoot, 'segment7_fig6_labeled_prototype_gallery.png');
    exportgraphics(figHandleGallery, galleryPath);
    close(figHandleGallery);
    disp(['Saved ' galleryPath]);
end

disp('--- Segment 7 FIG 6 labeled-prototype batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

disp(['Saved ' csvPath]);

function markers = computeCycleMarkers(proto, cycleFrac, notchDetected, notchPositionNormalized)
% COMPUTECYCLEMARKERS Pure plotting-annotation helper -- locates the four
% cycle landmarks on an already-computed prototype waveform. Does NOT
% implement any new detection algorithm: the systolic-peak and
% end-of-cycle positions are fixed by ensembleAverageBeats.m's own
% construction (systolic anchor fraction 0.25, cycle spans [0,1]); the
% notch position is notchDetectIEM.m's own output, passed straight
% through; the "second wave" is a plain local-max scan of proto's values
% strictly after the notch index.
N = numel(proto);

% --- Systolic peak: nearest grid sample to cycle-fraction 0.25. ---
[~, sysIdx] = min(abs(cycleFrac - 0.25));
markers.systolic.idx = sysIdx;
markers.systolic.x = cycleFrac(sysIdx);
markers.systolic.y = proto(sysIdx);

% --- End of cycle / diastolic point: last sample, cycle-fraction 1.0. ---
markers.diastolicEnd.idx = N;
markers.diastolicEnd.x = cycleFrac(N);
markers.diastolicEnd.y = proto(N);

% --- Dicrotic notch: only if notchDetectIEM.m reported one. ---
markers.notch.found = logical(notchDetected);
if markers.notch.found
    notchIdx = round(notchPositionNormalized * (N - 1)) + 1;
    notchIdx = min(max(notchIdx, 1), N);
    markers.notch.idx = notchIdx;
    markers.notch.x = cycleFrac(notchIdx);
    markers.notch.y = proto(notchIdx);
else
    markers.notch.idx = NaN;
    markers.notch.x = NaN;
    markers.notch.y = NaN;
end

% --- Second wave: first local max strictly after the notch index. Only
% searched for when a notch exists (no "after the notch" otherwise). ---
markers.secondWave.found = false;
markers.secondWave.idx = NaN;
markers.secondWave.x = NaN;
markers.secondWave.y = NaN;
if markers.notch.found
    for j = (markers.notch.idx + 1):(N - 1)
        if proto(j - 1) < proto(j) && proto(j) > proto(j + 1)
            markers.secondWave.found = true;
            markers.secondWave.idx = j;
            markers.secondWave.x = cycleFrac(j);
            markers.secondWave.y = proto(j);
            break
        end
    end
end
end

function drawLabeledPrototype(axHandle, cycleFrac, proto, markers, titleStr, compact)
% DRAWLABELEDPROTOTYPE Plots the trimmed-mean prototype with small
% labeled markers at the four cycle landmarks, styled like a standard
% annotated PPG-cycle diagram. `compact` shrinks fonts/labels for the
% gallery's small-multiples tiles.
axes(axHandle); %#ok<LAXES>
hold(axHandle, 'on');

plot(axHandle, cycleFrac, proto, 'LineWidth', 1.8, 'Color', [0.15 0.25 0.55]);

if compact
    markerSize = 6;
    fontSize = 7;
    labelDy = 0.06 * range(proto);
else
    markerSize = 9;
    fontSize = 10;
    labelDy = 0.05 * range(proto);
end

% Systolic peak.
plot(axHandle, markers.systolic.x, markers.systolic.y, 'o', 'MarkerSize', markerSize, ...
    'MarkerFaceColor', [0.85 0.20 0.20], 'MarkerEdgeColor', 'k');
text(axHandle, markers.systolic.x, markers.systolic.y + labelDy, 'Systolic peak', ...
    'FontSize', fontSize, 'HorizontalAlignment', 'center', 'Color', [0.85 0.20 0.20]);

% Dicrotic notch, only if detected.
if markers.notch.found
    plot(axHandle, markers.notch.x, markers.notch.y, 'v', 'MarkerSize', markerSize, ...
        'MarkerFaceColor', [0.95 0.60 0.10], 'MarkerEdgeColor', 'k');
    text(axHandle, markers.notch.x, markers.notch.y - labelDy, 'Dicrotic notch', ...
        'FontSize', fontSize, 'HorizontalAlignment', 'center', 'Color', [0.80 0.50 0.05]);
end

% Second wave, only if a post-notch local max was found.
if markers.secondWave.found
    plot(axHandle, markers.secondWave.x, markers.secondWave.y, '^', 'MarkerSize', markerSize, ...
        'MarkerFaceColor', [0.20 0.55 0.30], 'MarkerEdgeColor', 'k');
    text(axHandle, markers.secondWave.x, markers.secondWave.y + labelDy, 'Second wave', ...
        'FontSize', fontSize, 'HorizontalAlignment', 'center', 'Color', [0.15 0.45 0.25]);
end

% End of cycle / diastolic point.
plot(axHandle, markers.diastolicEnd.x, markers.diastolicEnd.y, 's', 'MarkerSize', markerSize, ...
    'MarkerFaceColor', [0.30 0.30 0.30], 'MarkerEdgeColor', 'k');
text(axHandle, markers.diastolicEnd.x, markers.diastolicEnd.y + labelDy, 'Diastolic end', ...
    'FontSize', fontSize, 'HorizontalAlignment', 'right', 'Color', [0.25 0.25 0.25]);

hold(axHandle, 'off');
xlabel(axHandle, 'Cycle fraction (systolic peak anchored at 0.25)');
ylabel(axHandle, 'Pulse amplitude (a.u.)');
title(axHandle, titleStr, 'Interpreter', 'none');
xlim(axHandle, [0 1]);
box(axHandle, 'on');
end
