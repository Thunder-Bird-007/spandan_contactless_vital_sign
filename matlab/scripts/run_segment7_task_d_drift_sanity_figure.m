% RUN_SEGMENT7_TASK_D_DRIFT_SANITY_FIGURE Segment 7 Task D, Action 4.
%
% Draws roi/landmarkROIExtraction.m's debugFrame.samples on 4 frames
% spanning the largest single-step head-bbox movement found across its 8
% evenly-spaced sample frames, comparing the OLD axis-aligned forehead
% box (debugFrame.samples(k).axisAlignedForeheadBBox -- exactly what
% roi/extractROISignals.m would have used on that same frame) against the
% NEW rotation-tracked polygon (debugFrame.samples(k).roiPolygon) on the
% SAME 4 frames. This is the visual evidence for whether ROI drift was
% really happening in the first place -- if the yellow (old) and green
% (new) boxes are visually indistinguishable across all 4 frames, that
% itself is a finding (little rotation in this subject's clip), not a
% failure of the figure.
%
% FIG_SUBJECT_ID is 'after-exercise' rather than the usual '5-gt' figure
% subject convention (see e.g.
% scripts/run_segment7_task_b_branch2_batch.m's FIG_SUBJECT_ID) --
% deliberate choice, documented here: this subject's own filename implies
% post-exertion footage, the UBFC subject most likely to show visible
% head movement, which is what this specific figure needs to be a
% meaningful comparison rather than two overlapping static boxes.
%
% Does NOT modify roi/landmarkROIExtraction.m, roi/extractROISignals.m,
% or any other Task A/B/C/D file -- new, additive script, new output
% only.
%
% Output: results/figures/segment7_task_d_drift_sanity_<subjectID>.png

FIG_SUBJECT_ID = 'after-exercise';

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

subjectDir = fullfile(dataset1Root, FIG_SUBJECT_ID);
aviFiles = dir(fullfile(subjectDir, '*.avi'));
if isempty(aviFiles)
    error('run_segment7_task_d_drift_sanity_figure:missingVideo', 'No .avi file found under: %s', subjectDir);
end
videoPath = fullfile(subjectDir, aviFiles(1).name);

disp(['--- Segment 7 Task D drift sanity figure: subject ' FIG_SUBJECT_ID ' ---']);

[frames, frameRate, ~] = loadUBFCVideo(videoPath);
[~, ~, ~, ~, droppedFrameIdx, debugFrame] = landmarkROIExtraction(frames, frameRate);

disp(['Dropped/fallback frames: ' num2str(numel(droppedFrameIdx))]);
disp(['Debug samples captured: ' num2str(numel(debugFrame.samples)) ' at frame indices: ' num2str(debugFrame.frameIndices)]);

numSamples = numel(debugFrame.samples);
if numSamples < 4
    error('run_segment7_task_d_drift_sanity_figure:tooFewSamples', 'Only %d debug samples captured -- need at least 4 to build the comparison figure.', numSamples);
end

% --- Find the 4 consecutive samples spanning the largest single-step
% face-bbox center movement, so the figure actually shows a head
% movement rather than 4 arbitrarily-spaced static frames. ---
bboxCenters = zeros(numSamples, 2);
for sampleIdx = 1:numSamples
    thisBBox = debugFrame.samples(sampleIdx).faceBBox;
    bboxCenters(sampleIdx, :) = [thisBBox(1) + thisBBox(3) / 2, thisBBox(2) + thisBBox(4) / 2];
end

stepDisplacement = zeros(numSamples - 1, 1);
for stepIdx = 1:(numSamples - 1)
    stepDisplacement(stepIdx) = norm(bboxCenters(stepIdx + 1, :) - bboxCenters(stepIdx, :));
end

[~, maxStepIdx] = max(stepDisplacement);

% Center the 4-frame window on the largest movement step, clipped to the
% valid sample range.
windowStart = max(1, maxStepIdx - 1);
windowStart = min(windowStart, numSamples - 3);
selectedIdx = windowStart:(windowStart + 3);

disp(['Largest single-step bbox displacement: ' num2str(stepDisplacement(maxStepIdx), '%.1f') ' px, between debug samples ' num2str(maxStepIdx) ' and ' num2str(maxStepIdx + 1)]);
disp(['Selected debug sample indices for the figure: ' num2str(selectedIdx) ' (frame indices: ' num2str([debugFrame.samples(selectedIdx).frameIndex]) ')']);

annotatedTiles = cell(1, 4);
for tileIdx = 1:4
    sample = debugFrame.samples(selectedIdx(tileIdx));

    tile = insertShape(sample.image, 'Rectangle', sample.axisAlignedForeheadBBox, 'Color', 'yellow', 'LineWidth', 3);

    polygonRow = reshape(sample.roiPolygon', 1, []);
    tile = insertShape(tile, 'Polygon', double(polygonRow), 'Color', 'green', 'LineWidth', 3);

    tile = insertShape(tile, 'Rectangle', sample.faceBBox, 'Color', 'red', 'LineWidth', 2);

    tile = insertText(tile, [10, 10], ['frame ' num2str(sample.frameIndex)], 'BoxOpacity', 0.6, 'FontSize', 14);

    annotatedTiles{tileIdx} = tile;
end

figHandle = figure('Visible', 'off', 'Position', [0, 0, 1200, 900]);
for tileIdx = 1:4
    subplot(2, 2, tileIdx);
    imshow(annotatedTiles{tileIdx});
    title(['Frame ' num2str(debugFrame.samples(selectedIdx(tileIdx)).frameIndex)]);
end
sgtitle({['Subject ' FIG_SUBJECT_ID ' -- Segment 7 Task D drift sanity check'], ...
    'Yellow = OLD axis-aligned forehead box (extractROISignals.m equivalent)   |   Green = NEW KLT-tracked rotation-compensated polygon   |   Red = detected face bbox'});

pngPath = fullfile(figuresRoot, ['segment7_task_d_drift_sanity_' FIG_SUBJECT_ID '.png']);
exportgraphics(figHandle, pngPath);
close(figHandle);

disp(['Saved ' pngPath]);
