function [R, G, B, Cseq, numPixels, droppedFrameIdx] = extractROICovariance(frames, frameRate) %#ok<INUSD>
% EXTRACTROICOVARIANCE Forehead ROI mean R/G/B PLUS the per-frame 3x3 pixel
% correlation matrix, for pulseextraction/spatialSubspaceRotation.m (2SR).
%
% Segment 22 (NEW, additive). Face detection and forehead geometry are
% duplicated verbatim from roi/extractROISignals.m (same detector, same
% every-5-frames cadence, same largest-box rule, same fallback boxes, same
% forehead fractions x:[0.30,0.70] y:[0.10,0.30]) so R/G/B here are
% bit-identical to extractROISignals(frames, fs, 'forehead') -- the batch
% script checks this parity against the cached production traces. The
% original is untouched.
%
% Why this exists: 2SR (Wang, Stuijk & de Haan 2016) works on the PIXEL
% correlation matrix C_t = V_t' * V_t / N of each frame (V_t = N x 3 skin
% pixels), not on the spatially averaged RGB trace the cache holds. C_t is
% all 2SR needs from the pixels, so it is stored (3 x 3 x numFrames) and
% 2SR can then be re-run at any stride without re-decoding video.
%
% Note (paper's own stated limitation): 2SR wants a skin-pixel mask. The
% forehead box is a fixed geometric crop, not a segmented skin mask, so
% hairline/shadow pixels are included, exactly as they are for CHROM/POS.
% Kept identical on purpose so 2SR-vs-CHROM/POS is a same-pixels comparison.
%
% Outputs:
%   R, G, B   - 1 x numFrames, spatial mean of the forehead ROI (as production).
%   Cseq      - 3 x 3 x numFrames, uncentered pixel correlation matrix per frame.
%   numPixels - 1 x numFrames, pixel count N used for each frame.

detectEveryN = 5;
faceDetector = vision.CascadeObjectDetector();
frames.CurrentTime = 0;
numFrames = frames.NumFrames;

R = zeros(1, numFrames); G = R; B = R;
numPixels = zeros(1, numFrames);
Cseq = zeros(3, 3, numFrames);
frameDroppedFlag = false(1, numFrames);
lastGoodBBox = [];
frameIdx = 0;

while hasFrame(frames)
    frameIdx = frameIdx + 1;
    if frameIdx > numFrames, break, end

    img = readFrame(frames);
    [frameHeight, frameWidth, ~] = size(img);

    if mod(frameIdx - 1, detectEveryN) == 0
        bboxes = step(faceDetector, img);
        if isempty(bboxes)
            frameDroppedFlag(frameIdx) = true;
            currentBBox = lastGoodBBox;
        else
            [~, bestRow] = max(bboxes(:, 3) .* bboxes(:, 4));
            currentBBox = bboxes(bestRow, :);
            lastGoodBBox = currentBBox;
        end
    else
        currentBBox = lastGoodBBox;
    end

    if isempty(currentBBox)
        frameDroppedFlag(frameIdx) = true;
        currentBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
    end

    fb = clampedBBox(currentBBox(1), currentBBox(2), currentBBox(3), currentBBox(4), 0.30, 0.70, 0.10, 0.30, frameWidth, frameHeight);
    patch = img(fb(2):fb(2) + fb(4), fb(1):fb(1) + fb(3), :);
    V = double(reshape(patch, [], 3));
    n = size(V, 1);

    R(frameIdx) = mean(V(:, 1));
    G(frameIdx) = mean(V(:, 2));
    B(frameIdx) = mean(V(:, 3));
    Cseq(:, :, frameIdx) = (V' * V) / n;
    numPixels(frameIdx) = n;
end

if frameIdx < numFrames
    R = R(1:frameIdx); G = G(1:frameIdx); B = B(1:frameIdx);
    Cseq = Cseq(:, :, 1:frameIdx); numPixels = numPixels(1:frameIdx);
    frameDroppedFlag = frameDroppedFlag(1:frameIdx);
end
droppedFrameIdx = find(frameDroppedFlag);

end

function bbox = clampedBBox(faceX, faceY, faceW, faceH, xFracLo, xFracHi, yFracLo, yFracHi, frameWidth, frameHeight)
x1 = max(1, round(faceX + xFracLo * faceW));
x2 = min(frameWidth, round(faceX + xFracHi * faceW));
y1 = max(1, round(faceY + yFracLo * faceH));
y2 = min(frameHeight, round(faceY + yFracHi * faceH));
bbox = [x1, y1, x2 - x1, y2 - y1];
end
