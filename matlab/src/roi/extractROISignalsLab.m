function [R, G, B, L, a, b, Cb, Cr, roiTimestamps, droppedFrameIdx, debugFrame, allRegions] = extractROISignalsLab(frames, frameRate, roiMode)
% EXTRACTROISIGNALSLAB Same face detection / ROI cropping as
% extractROISignals.m, but ALSO returns CIELab (L, a*, b*) and YCbCr (Cb, Cr)
% spatial-mean traces alongside R, G, B.
%
% Pipeline stage: Segment 18 (NEW, additive -- extractROISignals.m is
% untouched and remains the production extractor). Face detection, the
% detect-every-5-frames cadence, the largest-box rule, the fallback-box
% behaviour, and all four region geometries are duplicated verbatim from
% extractROISignals.m so that R/G/B here are bit-identical to that
% function's output for the same roiMode (verified in
% scripts/run_segment18_colorspace_ablation_batch.m's parity check).
%
% Colour-space conversion happens PER FRAME on the cropped ROI pixel patch,
% BEFORE spatial averaging (not on the already-averaged R/G/B mean -- rgb2lab
% is nonlinear, so converting the mean colour is not the same as averaging
% the converted pixels). Patches are converted from double [0,1] so that
% rgb2ycbcr does not quantize to uint8. Scaling notes:
%   L      - 0..100 (CIE lightness), a/b - roughly -128..127 (CIE a*, b*).
%   Cb, Cr - rgb2ycbcr's double convention (studio range, 16/255..240/255).
% Neither scale matters downstream (detrend + bandpass + FFT peak are
% amplitude-invariant); they are documented only so raw values are readable.
%
% Bilateral regions (malar, cheek): left+right pixel arrays are pooled
% BEFORE averaging, same discipline as extractROISignals.m.
%
% Inputs:
%   frames    - VideoReader (as from io/loadUBFCVideo.m / io/loadVIPLVideo.m).
%   frameRate - scalar fps (only used for roiTimestamps).
%   roiMode   - (optional) 'forehead' (default), 'glabella', 'malar',
%               'cheek'. Selects which region fills the primary outputs.
%
% Outputs:
%   R,G,B,L,a,b,Cb,Cr - 1 x numFrames per-frame ROI means for roiMode.
%   roiTimestamps, droppedFrameIdx, debugFrame - same meaning as
%               extractROISignals.m (debugFrame.regionBBoxes carries all
%               four regions regardless of roiMode).
%   allRegions - struct with one field per region (forehead, glabella,
%               malar, cheek), each a struct with fields R,G,B,L,a,b,Cb,Cr.
%               Filled in the SAME single decode pass, so cross-ROI PLV
%               (validation/computeCrossROIPLV.m) needs no second video
%               read. Always contains all four regions regardless of roiMode.

if nargin < 3 || isempty(roiMode)
    roiMode = 'forehead';
end

regionNames = {'forehead', 'glabella', 'malar', 'cheek'};
channelNames = {'R', 'G', 'B', 'L', 'a', 'b', 'Cb', 'Cr'};

if ~ismember(roiMode, regionNames)
    error('extractROISignalsLab:badRoiMode', 'roiMode must be one of forehead, glabella, malar, cheek (got %s).', roiMode);
end

detectEveryN = 5;

faceDetector = vision.CascadeObjectDetector();

frames.CurrentTime = 0;

numFrames = frames.NumFrames;

traces = struct();
for regionPos = 1:numel(regionNames)
    for chPos = 1:numel(channelNames)
        traces.(regionNames{regionPos}).(channelNames{chPos}) = zeros(1, numFrames);
    end
end

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

    for regionPos = 1:numel(regionNames)
        regionName = regionNames{regionPos};
        switch regionName
            case 'forehead'
                patches = {cropPatch(img, regionBBoxes.forehead)};
            case 'glabella'
                patches = {cropPatch(img, regionBBoxes.glabella)};
            case 'malar'
                patches = {cropPatch(img, regionBBoxes.malarLeft), cropPatch(img, regionBBoxes.malarRight)};
            case 'cheek'
                patches = {cropPatch(img, regionBBoxes.cheekLeft), cropPatch(img, regionBBoxes.cheekRight)};
        end

        means = poolAndAverage(patches);
        for chPos = 1:numel(channelNames)
            traces.(regionName).(channelNames{chPos})(frameIdx) = means(chPos);
        end
    end

    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    if frameIdx == debugFrame.frameIndex
        debugFrame.image = img;
        debugFrame.faceBBox = currentBBox;
        debugFrame.regionBBoxes = regionBBoxes;
        debugFrame.roiBBox = primaryROIBBox(regionBBoxes, roiMode);
        debugFrame.frameIndex = frameIdx;
    end
end

actualNumFrames = frameIdx;

if actualNumFrames < numFrames
    for regionPos = 1:numel(regionNames)
        for chPos = 1:numel(channelNames)
            v = traces.(regionNames{regionPos}).(channelNames{chPos});
            traces.(regionNames{regionPos}).(channelNames{chPos}) = v(1:actualNumFrames);
        end
    end
    roiTimestamps = roiTimestamps(1:actualNumFrames);
    frameDroppedFlag = frameDroppedFlag(1:actualNumFrames);
end

droppedFrameIdx = find(frameDroppedFlag);

if isempty(debugFrame.image)
    debugFrame.image = img;
    debugFrame.faceBBox = currentBBox;
    debugFrame.regionBBoxes = regionBBoxes;
    debugFrame.roiBBox = primaryROIBBox(regionBBoxes, roiMode);
    debugFrame.frameIndex = frameIdx;
end

allRegions = traces;

primary = traces.(roiMode);
R = primary.R;
G = primary.G;
B = primary.B;
L = primary.L;
a = primary.a;
b = primary.b;
Cb = primary.Cb;
Cr = primary.Cr;

end

function patch = cropPatch(img, bbox)
patch = img(bbox(2):bbox(2) + bbox(4), bbox(1):bbox(1) + bbox(3), :);
end

function bbox = primaryROIBBox(regionBBoxes, roiMode)
switch roiMode
    case 'forehead'
        bbox = regionBBoxes.forehead;
    case 'glabella'
        bbox = regionBBoxes.glabella;
    case 'malar'
        bbox = regionBBoxes.malarLeft;
    case 'cheek'
        bbox = regionBBoxes.cheekLeft;
end
end

function means = poolAndAverage(patches)
% Returns [R G B L a b Cb Cr] pixel-pool means. RGB pooled as double 0..255
% exactly as extractROISignals.m does (so R/G/B match it bit-for-bit); Lab
% and YCbCr are computed per patch on the [0,1] double image, then pooled.
redPool = [];
greenPool = [];
bluePool = [];
lPool = [];
aPool = [];
bPool = [];
cbPool = [];
crPool = [];

for patchIdx = 1:numel(patches)
    roiPatch = patches{patchIdx};
    redPool = [redPool; double(reshape(roiPatch(:, :, 1), [], 1))]; %#ok<AGROW>
    greenPool = [greenPool; double(reshape(roiPatch(:, :, 2), [], 1))]; %#ok<AGROW>
    bluePool = [bluePool; double(reshape(roiPatch(:, :, 3), [], 1))]; %#ok<AGROW>

    patchD = im2double(roiPatch);
    lab = rgb2lab(patchD);
    ycc = rgb2ycbcr(patchD);
    lPool = [lPool; reshape(lab(:, :, 1), [], 1)]; %#ok<AGROW>
    aPool = [aPool; reshape(lab(:, :, 2), [], 1)]; %#ok<AGROW>
    bPool = [bPool; reshape(lab(:, :, 3), [], 1)]; %#ok<AGROW>
    cbPool = [cbPool; reshape(ycc(:, :, 2), [], 1)]; %#ok<AGROW>
    crPool = [crPool; reshape(ycc(:, :, 3), [], 1)]; %#ok<AGROW>
end

means = [mean(redPool), mean(greenPool), mean(bluePool), mean(lPool), mean(aPool), mean(bPool), mean(cbPool), mean(crPool)];
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
