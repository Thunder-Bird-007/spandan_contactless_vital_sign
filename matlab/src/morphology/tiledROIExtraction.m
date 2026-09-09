function [pulseCombined, roiTimestamps, tileWeights, frameRate] = tiledROIExtraction(videoPath, bandMode, gridRows, gridCols, filterMode, sharedF0HzOverride)
% TILEDROIEXTRACTION Tile the forehead ROI into a grid, run CHROM per
% tile, and combine tiles with correlation-based quality weighting
% instead of a flat spatial mean.
%
% Pipeline stage: Segment 7 Task B, Action 5 branch-2 (NEW, additive --
% implemented ONLY because the branch-2 decision-gate condition fired,
% see docs/Segment7_Task_B_Notch_Quantification.md). Does not modify
% roi/extractROISignals.m, morphology/bandpassMorphology.m, or
% morphology/ensembleAverageBeats.m.
%
% Segment 7 Task C, Action 1 update: gained an optional per-tile
% `filterMode` ('butterworth', the original/default behaviour, or
% 'harmonic') and `sharedF0HzOverride`. This exists to fix a confound
% found in Task C's first combined-methods test: that test ran
% adaptiveHarmonicFilter.m on tiledROIExtraction.m's already-tiled,
% already-CHROM-combined OUTPUT, a pipeline position ABPF-only never
% actually occupies (ABPF-only substitutes adaptiveHarmonicFilter.m for
% bandpassMorphology.m, i.e. BEFORE chromCombine.m, per-channel).
% `filterMode='harmonic'` makes that substitution correctly: each tile's
% own detrended R/G/B is run through adaptiveHarmonicFilter.m (not
% bandpassMorphology.m) before that tile's own chromCombine.m call --
% the exact substitution scripts/run_segment7_task_b_branch2_batch.m
% makes for its whole-ROI adaptive-harmonic condition, just applied
% per-tile instead of once for the whole ROI. `filterMode='butterworth'`
% (the default) is byte-for-byte the pre-Task-C behaviour and is
% unaffected by this change -- confirmed by Segment 7 Task C's own
% regression check.
%
% Reference: Volynsky M, Margaryants N, Mamontov O, Kamshilin A (2016,
% PMC5175558) found that dicrotic-notch-carrying pulsatile information
% is spatially and temporally STOCHASTIC across the face -- a beat's
% notch may be strong in one patch of skin and absent in another on that
% same beat, and which patch "wins" changes beat to beat. A flat
% whole-ROI spatial mean (roi/extractROISignals.m's approach, and every
% earlier Segment 7 function's assumption) averages all patches
% together every frame regardless of which ones actually carry usable
% signal that frame, which can incoherently CANCEL a notch that only a
% subset of tiles are actually showing. Weighting tiles by how well each
% one's own CHROM pulse agrees with the cross-tile consensus is a cheap,
% data-driven way to down-weight tiles that are mostly capturing noise
% for a given clip, instead of averaging them in at full strength.
%
% WHY THIS DUPLICATES roi/extractROISignals.m's FACE-DETECTION LOGIC
% (does not import it): that function returns one already spatially-
% averaged trace per channel -- there is no per-tile pixel data left to
% recover from its output. Same reasoning already used for
% scripts/run_segment7_task_a_saturation_check.m's own duplicated
% detection loop (see that script's header).
%
% Method:
%   1. Detect the face (same convention as roi/extractROISignals.m:
%      Viola-Jones every 5th frame, largest bounding box, last-known-good
%      fallback) and crop the forehead box (same fractions as
%      roi/extractROISignals.m's default 'forehead' roiMode:
%      x:[0.30,0.70], y:[0.10,0.30] of the face box).
%   2. Subdivide that forehead box into a gridRows x gridCols grid
%      (default 4x4 = 16 tiles) and record each tile's own mean R/G/B
%      per frame.
%   3. For each tile independently: filtering/detrendSignal.m ->
%      morphology/bandpassMorphology.m (bandMode) ->
%      pulseextraction/chromCombine.m -> one pulse signal per tile.
%   4. Build an initial consensus reference (the plain mean of all 16
%      tile pulses), correlate each tile against it (Pearson r, manual
%      calculation, same convention as
%      morphology/ensembleAverageBeats.m's internal quality gate),
%      clip negative correlations to zero (an anti-correlated tile
%      should not actively subtract signal), normalize the clipped
%      correlations to sum to 1, and combine tiles with those weights.
%      This is a single reweighting pass, not an iterative refinement --
%      documented as a deliberate scope choice, not an oversight.
%
% Inputs:
%   videoPath    - string/char, full path to a subject's UBFC .avi file.
%   bandMode     - (optional) string/char, forwarded to
%                  morphology/bandpassMorphology.m for each tile.
%                  Defaults to 'wide'. IGNORED when filterMode='harmonic'
%                  (bandpassMorphology.m is not called at all in that
%                  mode) -- pass [] or '' for clarity at the call site
%                  when using 'harmonic', though any value is silently
%                  ignored either way.
%   gridRows     - (optional) scalar, number of tile rows. Defaults to 4.
%   gridCols     - (optional) scalar, number of tile columns. Defaults
%                  to 4.
%   filterMode   - (optional) string/char, 'butterworth' (default, the
%                  original behaviour: morphology/bandpassMorphology.m
%                  per tile) or 'harmonic' (morphology/adaptiveHarmonicFilter.m
%                  per tile instead, per-channel, in the same pipeline
%                  position bandpassMorphology.m normally occupies --
%                  see the Task C Action 1 note above).
%   sharedF0HzOverride - (optional) scalar, Hz. Only used when
%                  filterMode='harmonic'; forwarded as-is to EVERY tile's
%                  morphology/adaptiveHarmonicFilter.m call as its own
%                  f0HzOverride, so all 16 tiles lock onto the SAME
%                  cardiac fundamental instead of each tile re-estimating
%                  its own (which would reintroduce the cross-tile
%                  misalignment risk scripts/run_segment7_task_b_branch2_batch.m's
%                  own sharedF0Hz already exists to avoid). If empty/
%                  omitted, each tile's adaptiveHarmonicFilter.m call
%                  estimates its own f0 independently (that function's
%                  own default behaviour) -- allowed, but not the
%                  convention Segment 7 Task C's own combined-methods
%                  script actually uses. Ignored when
%                  filterMode='butterworth'.
%
% Outputs:
%   pulseCombined  - 1 x numFrames vector, the quality-weighted combined
%                    pulse signal, at the native video frame rate (NOT
%                    yet polarity-fixed or uniformly resampled -- callers
%                    should still run morphology/fixPolarity.m or
%                    morphology/fixPolarityByGroundTruth.m and
%                    morphology/resampleUniform.m on this output, same as
%                    pulseextraction/chromCombine.m's own output).
%   roiTimestamps  - 1 x numFrames vector, seconds, real per-frame
%                    acquisition times (same convention as
%                    roi/extractROISignals.m's own output).
%   tileWeights    - 1 x (gridRows*gridCols) vector, the normalized
%                    correlation-based weight actually used for each
%                    tile (row-major order), returned for
%                    debugging/plotting.
%   frameRate      - scalar, Hz, from io/loadUBFCVideo.m.

if nargin < 2 || isempty(bandMode)
    bandMode = 'wide';
end
if nargin < 3 || isempty(gridRows)
    gridRows = 4;
end
if nargin < 4 || isempty(gridCols)
    gridCols = 4;
end
if nargin < 5 || isempty(filterMode)
    filterMode = 'butterworth';
end
if nargin < 6
    sharedF0HzOverride = [];
end
if ~(strcmp(filterMode, 'butterworth') || strcmp(filterMode, 'harmonic'))
    error('tiledROIExtraction:invalidFilterMode', 'filterMode must be ''butterworth'' or ''harmonic'', got: %s', filterMode);
end

numTiles = gridRows * gridCols;
detectEveryN = 5;

% Same forehead fractions as roi/extractROISignals.m's default mode.
foreheadXFracLo = 0.30;
foreheadXFracHi = 0.70;
foreheadYFracLo = 0.10;
foreheadYFracHi = 0.30;

[frames, frameRate, ~] = loadUBFCVideo(videoPath);
frames.CurrentTime = 0;
numFrames = frames.NumFrames;

tileR = zeros(numTiles, numFrames);
tileG = zeros(numTiles, numFrames);
tileB = zeros(numTiles, numFrames);
roiTimestamps = zeros(1, numFrames);

faceDetector = vision.CascadeObjectDetector();
lastGoodBBox = [];
frameIdx = 0;

while hasFrame(frames)
    frameIdx = frameIdx + 1;
    if frameIdx > numFrames
        break
    end

    img = readFrame(frames);
    [frameHeight, frameWidth, ~] = size(img);

    runDetectionThisFrame = mod(frameIdx - 1, detectEveryN) == 0;

    if runDetectionThisFrame
        bboxes = step(faceDetector, img);
        if isempty(bboxes)
            currentBBox = lastGoodBBox;
        else
            bestBBox = bboxes(1, :);
            bestArea = bboxes(1, 3) * bboxes(1, 4);
            for boxRow = 2:size(bboxes, 1)
                thisArea = bboxes(boxRow, 3) * bboxes(boxRow, 4);
                if thisArea > bestArea
                    bestArea = thisArea;
                    bestBBox = bboxes(boxRow, :);
                end
            end
            currentBBox = bestBBox;
            lastGoodBBox = currentBBox;
        end
    else
        currentBBox = lastGoodBBox;
    end

    if isempty(currentBBox)
        currentBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
    end

    faceX = currentBBox(1);
    faceY = currentBBox(2);
    faceW = currentBBox(3);
    faceH = currentBBox(4);

    foreheadX1 = max(1, round(faceX + foreheadXFracLo * faceW));
    foreheadX2 = min(frameWidth, round(faceX + foreheadXFracHi * faceW));
    foreheadY1 = max(1, round(faceY + foreheadYFracLo * faceH));
    foreheadY2 = min(frameHeight, round(faceY + foreheadYFracHi * faceH));

    tileEdgesX = round(linspace(foreheadX1, foreheadX2, gridCols + 1));
    tileEdgesY = round(linspace(foreheadY1, foreheadY2, gridRows + 1));

    tileIdx = 0;
    for rowIdx = 1:gridRows
        for colIdx = 1:gridCols
            tileIdx = tileIdx + 1;

            y1 = tileEdgesY(rowIdx);
            y2 = max(tileEdgesY(rowIdx + 1), y1 + 1);
            x1 = tileEdgesX(colIdx);
            x2 = max(tileEdgesX(colIdx + 1), x1 + 1);

            y2 = min(y2, frameHeight);
            x2 = min(x2, frameWidth);

            tilePatch = img(y1:y2, x1:x2, :);

            tileR(tileIdx, frameIdx) = mean(double(reshape(tilePatch(:, :, 1), [], 1)));
            tileG(tileIdx, frameIdx) = mean(double(reshape(tilePatch(:, :, 2), [], 1)));
            tileB(tileIdx, frameIdx) = mean(double(reshape(tilePatch(:, :, 3), [], 1)));
        end
    end

    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;
end

actualNumFrames = frameIdx;
if actualNumFrames < numFrames
    tileR = tileR(:, 1:actualNumFrames);
    tileG = tileG(:, 1:actualNumFrames);
    tileB = tileB(:, 1:actualNumFrames);
    roiTimestamps = roiTimestamps(1:actualNumFrames);
end

tilePulses = zeros(numTiles, actualNumFrames);

% Task C Action 1: filterMode selects which per-channel filter sits
% immediately ahead of this tile's own chromCombine.m call --
% morphology/bandpassMorphology.m (original, 'butterworth') or
% morphology/adaptiveHarmonicFilter.m ('harmonic', the exact
% substitution ABPF-only makes, applied per-tile). numHarmonics=6
% matches scripts/run_segment7_task_b_branch2_batch.m's own call so
% 'harmonic' mode is the same operating point as ABPF-only, not a
% different, undocumented one.
useHarmonic = strcmp(filterMode, 'harmonic');
numHarmonicsPerTile = 6;

for tileIdx = 1:numTiles
    [Rd, ~] = detrendSignal(tileR(tileIdx, :));
    [Gd, ~] = detrendSignal(tileG(tileIdx, :));
    [Bd, ~] = detrendSignal(tileB(tileIdx, :));

    if useHarmonic
        [Rf, ~, ~] = adaptiveHarmonicFilter(Rd, frameRate, numHarmonicsPerTile, sharedF0HzOverride);
        [Gf, ~, ~] = adaptiveHarmonicFilter(Gd, frameRate, numHarmonicsPerTile, sharedF0HzOverride);
        [Bf, ~, ~] = adaptiveHarmonicFilter(Bd, frameRate, numHarmonicsPerTile, sharedF0HzOverride);
    else
        [Rf, ~, ~] = bandpassMorphology(Rd, frameRate, bandMode);
        [Gf, ~, ~] = bandpassMorphology(Gd, frameRate, bandMode);
        [Bf, ~, ~] = bandpassMorphology(Bd, frameRate, bandMode);
    end

    tilePulses(tileIdx, :) = chromCombine(Rf, Gf, Bf, tileR(tileIdx, :), tileG(tileIdx, :), tileB(tileIdx, :));
end

consensusReference = mean(tilePulses, 1);

rawWeights = zeros(1, numTiles);
for tileIdx = 1:numTiles
    rawWeights(tileIdx) = max(0, pearsonCorrRow(tilePulses(tileIdx, :), consensusReference));
end

if sum(rawWeights) <= 0
    % Degenerate case: no tile positively correlates with the consensus
    % (should not happen in practice since every tile contributed to
    % that consensus, but guarded rather than dividing by zero) -- fall
    % back to an equal-weight flat average.
    tileWeights = ones(1, numTiles) / numTiles;
else
    tileWeights = rawWeights / sum(rawWeights);
end

pulseCombined = tileWeights * tilePulses;

end

function r = pearsonCorrRow(x, y)
% Manual Pearson correlation, same convention as
% morphology/ensembleAverageBeats.m's internal quality-gate helper.
xc = x - mean(x);
yc = y - mean(y);
r = sum(xc .* yc) / sqrt(sum(xc.^2) * sum(yc.^2));
end
