function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(frames, frameRate)
% EXTRACTROISIGNALS Detect face, crop forehead/cheek ROI, average per-frame.
%
% Pipeline stage: Stage 1 (face detection + ROI signal extraction) — turns
% a raw video into three 1-D raw color-channel traces R(t), G(t), B(t).
% These feed Stage 2 (filtering/detrending) and then Stage 3 (CHROM/POS
% combination).
%
% Inputs:
%   frames    - a VideoReader object, as produced by io/loadUBFCVideo.m.
%   frameRate - scalar, frames per second (from loadUBFCVideo.m — needed
%               to build roiTimestamps).
%
% Outputs:
%   R, G, B         - 1 x numFrames vectors, the spatial average pixel
%                     intensity of the chosen ROI (forehead skin patch)
%                     for each color channel, one value per frame.
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
%                     uint8 frame), faceBBox and roiBBox (both in
%                     [x y width height] pixel format), and frameIndex.
%                     See scripts/run_segment2_roi_batch.m, which draws
%                     these two boxes on the image and saves it as a PNG.

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

    faceX = currentBBox(1);
    faceY = currentBBox(2);
    faceW = currentBBox(3);
    faceH = currentBBox(4);

    roiX1 = max(1, round(faceX + 0.30 * faceW));
    roiX2 = min(frameWidth, round(faceX + 0.70 * faceW));
    roiY1 = max(1, round(faceY + 0.10 * faceH));
    roiY2 = min(frameHeight, round(faceY + 0.30 * faceH));

    roiPatch = img(roiY1:roiY2, roiX1:roiX2, :);

    redChannel = double(roiPatch(:, :, 1));
    greenChannel = double(roiPatch(:, :, 2));
    blueChannel = double(roiPatch(:, :, 3));

    R(frameIdx) = mean(redChannel(:));
    G(frameIdx) = mean(greenChannel(:));
    B(frameIdx) = mean(blueChannel(:));
    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    currentROIBBox = [roiX1, roiY1, roiX2 - roiX1, roiY2 - roiY1];

    if frameIdx == debugFrame.frameIndex
        debugFrame.image = img;
        debugFrame.faceBBox = currentBBox;
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
    debugFrame.roiBBox = currentROIBBox;
    debugFrame.frameIndex = frameIdx;
end

end
