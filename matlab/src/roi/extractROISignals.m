function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(frames, frameRate, roiMode)
% EXTRACTROISIGNALS Detect face, crop a chosen skin ROI, average per-frame.
%
% Pipeline stage: Stage 1 (face detection + ROI signal extraction) — turns
% a raw video into three 1-D raw color-channel traces R(t), G(t), B(t).
% These feed Stage 2 (filtering/detrending) and then Stage 3 (CHROM/POS
% combination).
%
% Segment 6 Task N adds roiMode on top of the original forehead-only
% version of this function. All four region geometries below are defined
% as fixed fractions of the detected Viola-Jones FACE bounding box (this
% project has no facial-landmark detector, so region placement is a
% face-box-relative approximation, not a landmark-driven crop) — see
% docs/Segment6_Task_N_Multi_Region_ROI.md Action 0/1 for the exact
% fractions and the regression check confirming the default 'forehead'
% mode reproduces the original, pre-Task-N byte-identical R/G/B traces.
%
% Region definitions (all fractions are of faceBBox width/height, same
% [x y width height] convention as the original forehead box):
%   forehead  - x:[0.30,0.70] y:[0.10,0.30] (UNCHANGED from the original,
%               pre-Task-N geometry -- this is the default roiMode).
%   glabella  - x:[0.42,0.58] y:[0.32,0.40], the flat area between the
%               eyebrows: narrower than forehead and shifted down toward
%               eye level, but still above where eyebrows/eyes themselves
%               sit on a typical face-box proportion.
%   malar     - x:[0.15,0.32] (left) and [0.68,0.85] (right),
%               y:[0.45,0.58], the upper cheekbone specifically -- kept
%               well above the jaw/mouth line (y stops at 0.58) since
%               those move more with talking/expression.
%   cheek     - x:[0.10,0.35] (left) and [0.65,0.90] (right),
%               y:[0.55,0.75], the fuller cheek: wider and lower than
%               malar, a separate mode so malar-vs-cheek can be compared
%               directly rather than merged.
%
% Design decision (malar/cheek left+right combination): both are
% bilateral regions, so each has a left-side and a right-side patch.
% Rather than producing two separate traces (which would break the
% "one trace per region" interface this function and its callers share
% with forehead/glabella), the left and right pixel arrays are
% concatenated into a single pool BEFORE averaging, so R/G/B(frameIdx)
% is the spatial mean over both patches combined, not the mean of two
% per-patch means. The two patches are constructed from the same fixed
% fractions of the same face box, so they are close to equal in pixel
% count in practice, but the concatenate-then-average order is stated
% explicitly here so it does not have to be inferred from the code (same
% discipline as chromCombine.m's normalization note). This choice was
% made to (a) pool more pixels for better SNR, which is expected to help
% specifically in the v5-dark-light comparison this task investigates,
% and (b) keep every region's output the same shape (one R/G/B trace)
% so computeRegionAgreement.m/computeRegionSwitchingEstimate.m do not
% need bilateral-region special-casing.
%
% Inputs:
%   frames    - a VideoReader object, as produced by io/loadUBFCVideo.m.
%   frameRate - scalar, frames per second (from loadUBFCVideo.m — needed
%               to build roiTimestamps).
%   roiMode   - (optional) string/char, one of 'forehead' (default),
%               'glabella', 'malar', 'cheek'. Selects which region's
%               pixels are averaged into R/G/B below. Does not change
%               debugFrame's boundaries -- debugFrame always carries all
%               four regions' boxes (see below) regardless of roiMode, so
%               a single sanity PNG can draw all four on one frame.
%
% Outputs:
%   R, G, B         - 1 x numFrames vectors, the spatial average pixel
%                     intensity of the chosen ROI (roiMode) for each
%                     color channel, one value per frame.
%   roiTimestamps   - 1 x numFrames vector, seconds, frame acquisition
%                     time (used later to align against ground-truth
%                     timestamps).
%   droppedFrameIdx - row vector of frame indices where a fresh face
%                     detection attempt failed and a fallback bounding
%                     box (last known good box, or a centered default if
%                     none exists yet) was used instead. Empty if this
%                     never happened.
%   debugFrame      - struct with one representative frame captured for
%                     the sanity-check figure: image (raw H x W x 3
%                     uint8 frame), faceBBox (in [x y width height] pixel
%                     format), regionBBoxes (struct with fields
%                     forehead, glabella, malarLeft, malarRight,
%                     cheekLeft, cheekRight, each a [x y width height]
%                     box, all four regions computed on this same
%                     representative frame regardless of roiMode),
%                     roiBBox (the single box actually used for
%                     R/G/B extraction under roiMode -- kept for
%                     backward compatibility with callers written before
%                     Task N, e.g. the original forehead-only sanity
%                     PNG code), and frameIndex. See
%                     scripts/run_segment2_roi_batch.m (pre-Task-N,
%                     forehead-only) and
%                     scripts/run_segment6_task_n_multi_region_batch.m
%                     (Task N, draws all four regionBBoxes) for how
%                     these are drawn.

if nargin < 3 || isempty(roiMode)
    roiMode = 'forehead';
end

validRoiModes = {'forehead', 'glabella', 'malar', 'cheek'};

if ~ismember(roiMode, validRoiModes)
    error('extractROISignals:badRoiMode', 'roiMode must be one of forehead, glabella, malar, cheek (got %s).', roiMode);
end

detectEveryN = 5;

faceDetector = vision.CascadeObjectDetector();

frames.CurrentTime = 0;

numFrames = frames.NumFrames;

R = zeros(1, numFrames);
G = zeros(1, numFrames);
B = zeros(1, numFrames);
roiTimestamps = zeros(1, numFrames);
frameDroppedFlag = false(1, numFrames);

lastGoodBBox = [];

debugFrame = struct();
debugFrame.image = [];
debugFrame.faceBBox = [];
debugFrame.regionBBoxes = struct();
debugFrame.roiBBox = [];
debugFrame.frameIndex = round(numFrames / 2);

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
            frameDroppedFlag(frameIdx) = true;
            disp(['Frame ' num2str(frameIdx) ': face detector found nothing, reusing last known bounding box.']);
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
        frameDroppedFlag(frameIdx) = true;
        disp(['Frame ' num2str(frameIdx) ': no bounding box available yet, using centered fallback box.']);
        currentBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
    end

    regionBBoxes = computeRegionBBoxes(currentBBox, frameWidth, frameHeight);

    switch roiMode
        case 'forehead'
            pixelPatches = {img(regionBBoxes.forehead(2):regionBBoxes.forehead(2) + regionBBoxes.forehead(4), regionBBoxes.forehead(1):regionBBoxes.forehead(1) + regionBBoxes.forehead(3), :)};
            currentROIBBox = regionBBoxes.forehead;
        case 'glabella'
            pixelPatches = {img(regionBBoxes.glabella(2):regionBBoxes.glabella(2) + regionBBoxes.glabella(4), regionBBoxes.glabella(1):regionBBoxes.glabella(1) + regionBBoxes.glabella(3), :)};
            currentROIBBox = regionBBoxes.glabella;
        case 'malar'
            pixelPatches = {img(regionBBoxes.malarLeft(2):regionBBoxes.malarLeft(2) + regionBBoxes.malarLeft(4), regionBBoxes.malarLeft(1):regionBBoxes.malarLeft(1) + regionBBoxes.malarLeft(3), :), img(regionBBoxes.malarRight(2):regionBBoxes.malarRight(2) + regionBBoxes.malarRight(4), regionBBoxes.malarRight(1):regionBBoxes.malarRight(1) + regionBBoxes.malarRight(3), :)};
            currentROIBBox = regionBBoxes.malarLeft;
        case 'cheek'
            pixelPatches = {img(regionBBoxes.cheekLeft(2):regionBBoxes.cheekLeft(2) + regionBBoxes.cheekLeft(4), regionBBoxes.cheekLeft(1):regionBBoxes.cheekLeft(1) + regionBBoxes.cheekLeft(3), :), img(regionBBoxes.cheekRight(2):regionBBoxes.cheekRight(2) + regionBBoxes.cheekRight(4), regionBBoxes.cheekRight(1):regionBBoxes.cheekRight(1) + regionBBoxes.cheekRight(3), :)};
            currentROIBBox = regionBBoxes.cheekLeft;
    end

    redPool = [];
    greenPool = [];
    bluePool = [];

    for patchIdx = 1:numel(pixelPatches)
        roiPatch = pixelPatches{patchIdx};
        redPool = [redPool; double(reshape(roiPatch(:, :, 1), [], 1))];
        greenPool = [greenPool; double(reshape(roiPatch(:, :, 2), [], 1))];
        bluePool = [bluePool; double(reshape(roiPatch(:, :, 3), [], 1))];
    end

    R(frameIdx) = mean(redPool);
    G(frameIdx) = mean(greenPool);
    B(frameIdx) = mean(bluePool);
    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    if frameIdx == debugFrame.frameIndex
        debugFrame.image = img;
        debugFrame.faceBBox = currentBBox;
        debugFrame.regionBBoxes = regionBBoxes;
        debugFrame.roiBBox = currentROIBBox;
        debugFrame.frameIndex = frameIdx;
    end
end

actualNumFrames = frameIdx;

if actualNumFrames < numFrames
    R = R(1:actualNumFrames);
    G = G(1:actualNumFrames);
    B = B(1:actualNumFrames);
    roiTimestamps = roiTimestamps(1:actualNumFrames);
    frameDroppedFlag = frameDroppedFlag(1:actualNumFrames);
end

droppedFrameIdx = find(frameDroppedFlag);

if isempty(debugFrame.image)
    debugFrame.image = img;
    debugFrame.faceBBox = currentBBox;
    debugFrame.regionBBoxes = regionBBoxes;
    debugFrame.roiBBox = currentROIBBox;
    debugFrame.frameIndex = frameIdx;
end

end

function regionBBoxes = computeRegionBBoxes(faceBBox, frameWidth, frameHeight)

faceX = faceBBox(1);
faceY = faceBBox(2);
faceW = faceBBox(3);
faceH = faceBBox(4);

regionBBoxes = struct();
regionBBoxes.forehead = clampedBBox(faceX, faceY, faceW, faceH, 0.30, 0.70, 0.10, 0.30, frameWidth, frameHeight);
regionBBoxes.glabella = clampedBBox(faceX, faceY, faceW, faceH, 0.42, 0.58, 0.32, 0.40, frameWidth, frameHeight);
regionBBoxes.malarLeft = clampedBBox(faceX, faceY, faceW, faceH, 0.15, 0.32, 0.45, 0.58, frameWidth, frameHeight);
regionBBoxes.malarRight = clampedBBox(faceX, faceY, faceW, faceH, 0.68, 0.85, 0.45, 0.58, frameWidth, frameHeight);
regionBBoxes.cheekLeft = clampedBBox(faceX, faceY, faceW, faceH, 0.10, 0.35, 0.55, 0.75, frameWidth, frameHeight);
regionBBoxes.cheekRight = clampedBBox(faceX, faceY, faceW, faceH, 0.65, 0.90, 0.55, 0.75, frameWidth, frameHeight);

end

function bbox = clampedBBox(faceX, faceY, faceW, faceH, xFracLo, xFracHi, yFracLo, yFracHi, frameWidth, frameHeight)

x1 = max(1, round(faceX + xFracLo * faceW));
x2 = min(frameWidth, round(faceX + xFracHi * faceW));
y1 = max(1, round(faceY + yFracLo * faceH));
y2 = min(frameHeight, round(faceY + yFracHi * faceH));

bbox = [x1, y1, x2 - x1, y2 - y1];

end
