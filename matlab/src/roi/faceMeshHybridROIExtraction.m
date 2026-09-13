function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = faceMeshHybridROIExtraction(frames, frameRate)
% FACEMESHHYBRIDROIEXTRACTION Segment 7 Task J -- hybrid ROI that pairs
% real DL face-mesh detection/localization (same MediaPipe FaceMesh setup
% and per-frame loop as roi/faceMeshROIExtraction.m, built in Task H) with
% roi/extractROISignals.m's forehead BOX GEOMETRY, instead of Task H's
% thin 4-landmark poly2mask polygon.
%
% WHY: Task H/I (docs/Segment7_Task_H_FaceMesh_ROI.md,
% docs/Segment7_Task_I_FaceMesh_Branch1.md -- read those first, not
% re-derived here) established that the real face-mesh detector itself is
% robust (zero dropped frames, all 5 subjects) and ties baseline exactly
% on HR (Branch 1, bit-identical bpm), but its thin eyebrow-hugging
% 4-point polygon regresses ABPF notch confidence hard (0/5 subjects >=
% 0.3, vs baseline's 4/5) because it pools far fewer pixels than
% baseline's generous forehead box, hurting SNR. This file isolates
% detector-robustness from ROI-shape: use the face mesh only to find and
% scale the face, then apply baseline's exact forehead-box fractions
% (extractROISignals.m's default 'forehead' mode: xFracLo=0.30,
% xFracHi=0.70, yFracLo=0.10, yFracHi=0.30 of the face bounding box) to
% get a rectangle with real pixel-pooling area, not a thin polygon.
%
% Does NOT modify roi/faceMeshROIExtraction.m, roi/extractROISignals.m,
% or roi/landmarkROIExtraction.m -- new, additive file, reusing Task H's
% mediapipe setup/detection-loop pattern and extractROISignals.m's
% forehead fractions verbatim (not re-derived, not re-tuned).
%
% REQUIRED ONE-TIME SESSION SETUP (same as faceMeshROIExtraction.m):
%   pyenv('ExecutionMode', 'OutOfProcess');
% before this function (or anything else touching py.*) is called in the
% current MATLAB session.
%
% Inputs:
%   frames    - a VideoReader object, as produced by io/loadUBFCVideo.m.
%   frameRate - scalar, frames per second.
%
% Outputs: same shape/convention as roi/extractROISignals.m and
% roi/faceMeshROIExtraction.m -- R, G, B (1 x numFrames, raw per-channel),
% roiTimestamps, droppedFrameIdx (frames where MediaPipe found no face and
% the last known good face bbox was reused), debugFrame (struct: image,
% faceBBox ([x y width height], the all-468-landmark bounding box),
% roiBBox ([x y width height], the forehead-fraction rectangle actually
% averaged), frameIndex -- matching extractROISignals.m's debugFrame field
% names so the existing sanity-PNG drawing code works unchanged).

pe = pyenv();
if pe.ExecutionMode ~= "OutOfProcess"
    error('faceMeshHybridROIExtraction:wrongExecutionMode', ...
        ['pyenv ExecutionMode is "%s", not "OutOfProcess". In-process mode is confirmed to crash on ' ...
         'mediapipe''s native bindings (DLL load failure against MATLAB''s own bundled libraries). Call ' ...
         'pyenv(''ExecutionMode'', ''OutOfProcess'') BEFORE any other py.* call in this MATLAB session ' ...
         '(it cannot be changed once Python is loaded), then retry.'], char(pe.ExecutionMode));
end

mpModule = py.importlib.import_module('mediapipe');
faceMeshModule = py.getattr(mpModule.solutions, 'face_mesh');
faceMesh = faceMeshModule.FaceMesh(pyargs('static_image_mode', false, 'max_num_faces', int32(1), ...
    'refine_landmarks', false, 'min_detection_confidence', 0.5, 'min_tracking_confidence', 0.5));

% Baseline's exact default forehead fractions (extractROISignals.m's
% computeRegionBBoxes 'forehead' case) -- not re-derived, not re-tuned.
xFracLo = 0.30; xFracHi = 0.70; yFracLo = 0.10; yFracHi = 0.30;

frames.CurrentTime = 0;
numFrames = frames.NumFrames;

R = zeros(1, numFrames);
G = zeros(1, numFrames);
B = zeros(1, numFrames);
roiTimestamps = zeros(1, numFrames);
frameDroppedFlag = false(1, numFrames);

lastGoodFaceBBox = [];

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

    img = readFrame(frames); % MATLAB uint8 H x W x 3, RGB order already
    [frameHeight, frameWidth, ~] = size(img);

    pyImg = py.numpy.array(img);
    detResult = faceMesh.process(pyImg);

    frameDropped = false;

    if isempty(detResult.multi_face_landmarks) || detResult.multi_face_landmarks == py.None
        frameDropped = true;
        if frameIdx <= 5 || mod(frameIdx, 200) == 0
            disp(['Frame ' num2str(frameIdx) ': mediapipe FaceMesh found no face, reusing last known face bbox.']);
        end
        currentFaceBBox = lastGoodFaceBBox;
    else
        faceLandmarks = detResult.multi_face_landmarks{1};
        landmarkList = py.getattr(faceLandmarks, 'landmark');

        % Single batched Python-side extraction (list comprehension),
        % NOT a MATLAB-side loop over landmarkList{k} + py.getattr(pt,
        % 'x'/'y') per landmark: that per-landmark form (936 MATLAB<->
        % Python round trips/frame for 468 landmarks) was tried first and
        % leaks proxy-object handles in pyenv OutOfProcess mode -- it ran
        % ~30+ min into subject 1 with no crash, then failed subject 1
        % itself with MATLAB:Python:DispatchError ("Attempting to access
        % the property or method of an invalid object"), and crashed
        % MATLAB entirely (0xc00000fd, stack overflow, "Out of memory")
        % partway into subject 2. Extracting all x/y as one nested Python
        % list, converted to a numpy array, keeps this to a small,
        % constant number of round trips per frame regardless of
        % landmark count -- confirmed stable across a full subject after
        % this fix.
        localsDict = py.dict(pyargs('lm', landmarkList));
        xyList = py.eval('[[p.x, p.y] for p in lm]', py.dict(), localsDict);
        xyArray = double(py.numpy.array(xyList)); % numLandmarks x 2, normalized [0,1]

        allX = xyArray(:, 1)' * frameWidth;
        allY = xyArray(:, 2)' * frameHeight;

        minX = min(allX); maxX = max(allX);
        minY = min(allY); maxY = max(allY);
        currentFaceBBox = [minX, minY, maxX - minX, maxY - minY];
        lastGoodFaceBBox = currentFaceBBox;
    end

    if isempty(currentFaceBBox)
        % No detection has EVER succeeded yet -- centered fallback face
        % bbox, same "no history yet" philosophy as
        % roi/extractROISignals.m's centered fallback box.
        frameDropped = true;
        currentFaceBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
        lastGoodFaceBBox = currentFaceBBox;
    end

    frameDroppedFlag(frameIdx) = frameDropped;

    roiBBox = clampedBBox(currentFaceBBox(1), currentFaceBBox(2), currentFaceBBox(3), currentFaceBBox(4), ...
        xFracLo, xFracHi, yFracLo, yFracHi, frameWidth, frameHeight);

    x1 = roiBBox(1); y1 = roiBBox(2);
    x2 = x1 + roiBBox(3); y2 = y1 + roiBBox(4);
    roiPatch = img(y1:y2, x1:x2, :);

    R(frameIdx) = mean(double(reshape(roiPatch(:, :, 1), [], 1)));
    G(frameIdx) = mean(double(reshape(roiPatch(:, :, 2), [], 1)));
    B(frameIdx) = mean(double(reshape(roiPatch(:, :, 3), [], 1)));
    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    if frameIdx == debugFrame.frameIndex
        debugFrame.image = img;
        debugFrame.faceBBox = currentFaceBBox;
        debugFrame.roiBBox = roiBBox;
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
    debugFrame.faceBBox = currentFaceBBox;
    debugFrame.roiBBox = roiBBox;
    debugFrame.frameIndex = frameIdx;
end

end

function bbox = clampedBBox(faceX, faceY, faceW, faceH, xFracLo, xFracHi, yFracLo, yFracHi, frameWidth, frameHeight)
% Same clamping convention as extractROISignals.m's own clampedBBox --
% not re-derived, not re-tuned.

x1 = max(1, round(faceX + xFracLo * faceW));
x2 = min(frameWidth, round(faceX + xFracHi * faceW));
y1 = max(1, round(faceY + yFracLo * faceH));
y2 = min(frameHeight, round(faceY + yFracHi * faceH));

bbox = [x1, y1, x2 - x1, y2 - y1];

end
