function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = faceMeshROIExtraction(frames, frameRate)
% FACEMESHROIEXTRACTION Real 468-point DL face-mesh forehead ROI, built
% from the uploaded thesis's exact Section 3.2.1 landmark indices
% (67, 297, 105, 334) -- a drop-in alternative to roi/extractROISignals.m
% AND to roi/landmarkROIExtraction.m's KLT proxy.
%
% WHY THIS FILE EXISTS NOW, AND NOT IN SEGMENT 7 TASK D: Task D's own
% Action 0 (see docs/Segment7_Task_D_Landmark_ROI.md, and
% roi/landmarkROIExtraction.m's header) found NO facial-landmark/face-mesh
% detector anywhere in this MATLAB R2024b installation -- no toolbox, no
% Deep Learning Toolbox Model support package, nothing -- and fell back to
% a KLT-tracked rotation-compensated proxy instead, which REGRESSED
% ABPF's notch confidence (4/5 subjects above the 0.3 bar down to 2/5,
% then 0/5 under a frozen-cadence variant; root cause left genuinely
% unresolved in that doc). The supervisor has now explicitly authorized
% using a real DL mesh model, so this file replaces the "no toolbox
% exists" premise: MATLAB itself still has no built-in face-mesh function,
% but MATLAB R2024b can call out to Python (`py.*`), and Google's
% MediaPipe FaceMesh -- a real, published, DL-based 468-point face-mesh
% model -- is installable from PyPI and IS the standard implementation
% behind landmark indices 67/297/105/334 (that exact numbering only makes
% sense under MediaPipe's specific 468-point topology, which is why this
% project's own docs already referred to "a 468-point face mesh" using
% those numbers before this file existed). Feasibility (in-process Python
% crashes with a DLL conflict against MATLAB's own bundled libraries;
% OutOfProcess mode works, confirmed against a real UBFC frame with real
% landmark coordinates before this file was written) is documented in
% matlab/docs/Segment7_Task_H_FaceMesh_ROI.md.
%
% REQUIRED ONE-TIME SESSION SETUP (caller's responsibility, not done
% silently inside this function -- pyenv's ExecutionMode can only be
% changed while Status is "NotLoaded", i.e. before ANY py.* call has
% happened yet in the current MATLAB session):
%   pyenv('ExecutionMode', 'OutOfProcess');
% before this function (or anything else touching py.*) is called. This
% function checks that condition and errors with a clear, actionable
% message rather than silently proceeding in the wrong mode (in-process
% mode is confirmed to crash on mediapipe's native bindings -- see the
% doc above). The caller's MATLAB Python environment must also have
% mediapipe, opencv-python (cv2, used only for BGR<->RGB -- actually not
% needed since MATLAB frames are already RGB; kept unimported to minimize
% dependencies) -- in practice just `pip install mediapipe` in whatever
% Python `pyenv` is currently pointed at (this project's: Python 3.12) is
% sufficient; no cv2 dependency.
%
% LANDMARK GEOMETRY: MediaPipe FaceMesh landmarks 67 and 105 sit on one
% side of the forehead (67 above 105), 297 and 334 on the other (297
% above 334) -- confirmed against real pixel coordinates on a UBFC frame
% before this file was written (see the doc above). The polygon vertex
% order used below, [67, 297, 334, 105], traces these in a proper
% clockwise loop (upper-side-A -> upper-side-B -> lower-side-B ->
% lower-side-A) -- NOT the thesis's own listed order (67, 297, 105, 334),
% which would self-intersect into a bowtie if fed to poly2mask directly
% (105 and 297 are diagonal from each other, not adjacent). Re-ordering
% the same 4 points into a valid simple polygon is a geometry fix, not a
% deviation from which 4 landmarks are used.
%
% Inputs:
%   frames    - a VideoReader object, as produced by io/loadUBFCVideo.m
%               (same as roi/extractROISignals.m's first argument).
%   frameRate - scalar, frames per second.
%
% Outputs: same shape/convention as roi/extractROISignals.m and
% roi/landmarkROIExtraction.m -- R, G, B (1 x numFrames, raw per-channel,
% NOT pre-combined), roiTimestamps, droppedFrameIdx (frames where
% MediaPipe found no face and the last good polygon was reused),
% debugFrame (struct: image, faceMeshLandmarksPx [4x2, the 4 raw
% landmark pixel coordinates before reordering], roiPolygon [4x2, the
% reordered polygon actually used], frameIndex).

pe = pyenv();
if pe.ExecutionMode ~= "OutOfProcess"
    error('faceMeshROIExtraction:wrongExecutionMode', ...
        ['pyenv ExecutionMode is "%s", not "OutOfProcess". In-process mode is confirmed to crash on ' ...
         'mediapipe''s native bindings (DLL load failure against MATLAB''s own bundled libraries). Call ' ...
         'pyenv(''ExecutionMode'', ''OutOfProcess'') BEFORE any other py.* call in this MATLAB session ' ...
         '(it cannot be changed once Python is loaded), then retry.'], char(pe.ExecutionMode));
end

mpModule = py.importlib.import_module('mediapipe');
faceMeshModule = py.getattr(mpModule.solutions, 'face_mesh');
faceMesh = faceMeshModule.FaceMesh(pyargs('static_image_mode', false, 'max_num_faces', int32(1), ...
    'refine_landmarks', false, 'min_detection_confidence', 0.5, 'min_tracking_confidence', 0.5));

landmarkIdx = [67, 297, 334, 105]; % reordered for a valid simple polygon -- see header

frames.CurrentTime = 0;
numFrames = frames.NumFrames;

R = zeros(1, numFrames);
G = zeros(1, numFrames);
B = zeros(1, numFrames);
roiTimestamps = zeros(1, numFrames);
frameDroppedFlag = false(1, numFrames);

lastGoodPolygon = [];
lastGoodLandmarksPx = [];

debugFrame = struct();
debugFrame.image = [];
debugFrame.faceMeshLandmarksPx = [];
debugFrame.roiPolygon = [];
debugFrame.frameIndex = round(numFrames / 2);

frameIdx = 0;

while hasFrame(frames)
    frameIdx = frameIdx + 1;
    if frameIdx > numFrames
        break
    end

    img = readFrame(frames); % MATLAB uint8 H x W x 3, RGB order already
    [frameHeight, frameWidth, ~] = size(img);

    pyImg = py.numpy.array(img); % explicit numpy conversion (MATLAB handles row/col-major transpose internally)
    detResult = faceMesh.process(pyImg);

    frameDropped = false;

    if isempty(detResult.multi_face_landmarks) || detResult.multi_face_landmarks == py.None
        frameDropped = true;
        if frameIdx <= 5 || mod(frameIdx, 200) == 0
            disp(['Frame ' num2str(frameIdx) ': mediapipe FaceMesh found no face, reusing last known polygon.']);
        end
        currentPolygon = lastGoodPolygon;
        currentLandmarksPx = lastGoodLandmarksPx;
    else
        faceLandmarks = detResult.multi_face_landmarks{1};
        landmarkList = py.getattr(faceLandmarks, 'landmark');

        landmarksPx = zeros(4, 2);
        for k = 1:4
            pt = landmarkList{landmarkIdx(k) + 1}; % Python list, MATLAB {} indexing is 1-based over the py.list
            landmarksPx(k, 1) = double(py.getattr(pt, 'x')) * frameWidth;
            landmarksPx(k, 2) = double(py.getattr(pt, 'y')) * frameHeight;
        end

        currentLandmarksPx = landmarksPx;
        currentPolygon = landmarksPx; % already in the reordered [67,297,334,105] clockwise sequence
        lastGoodPolygon = currentPolygon;
        lastGoodLandmarksPx = currentLandmarksPx;
    end

    if isempty(currentPolygon)
        % No detection has EVER succeeded yet -- centered fallback
        % polygon, same "no history yet" philosophy as
        % roi/extractROISignals.m's centered fallback box.
        frameDropped = true;
        cx = 0.5 * frameWidth;
        cy = 0.3 * frameHeight;
        halfW = 0.15 * frameWidth;
        halfH = 0.08 * frameHeight;
        currentPolygon = [cx - halfW, cy - halfH; cx + halfW, cy - halfH; cx + halfW, cy + halfH; cx - halfW, cy + halfH];
        lastGoodPolygon = currentPolygon;
    end

    roiMask = poly2mask(currentPolygon(:, 1), currentPolygon(:, 2), frameHeight, frameWidth);

    if ~any(roiMask(:))
        frameDropped = true;
        disp(['Frame ' num2str(frameIdx) ': face-mesh polygon produced an empty mask, using centered fallback for this frame only.']);
        cx = 0.5 * frameWidth;
        cy = 0.3 * frameHeight;
        halfW = 0.15 * frameWidth;
        halfH = 0.08 * frameHeight;
        fallbackPolygon = [cx - halfW, cy - halfH; cx + halfW, cy - halfH; cx + halfW, cy + halfH; cx - halfW, cy + halfH];
        roiMask = poly2mask(fallbackPolygon(:, 1), fallbackPolygon(:, 2), frameHeight, frameWidth);
    end

    frameDroppedFlag(frameIdx) = frameDropped;

    redChannel = double(img(:, :, 1));
    greenChannel = double(img(:, :, 2));
    blueChannel = double(img(:, :, 3));

    R(frameIdx) = mean(redChannel(roiMask));
    G(frameIdx) = mean(greenChannel(roiMask));
    B(frameIdx) = mean(blueChannel(roiMask));
    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    if frameIdx == debugFrame.frameIndex
        debugFrame.image = img;
        debugFrame.faceMeshLandmarksPx = currentLandmarksPx;
        debugFrame.roiPolygon = currentPolygon;
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
    debugFrame.faceMeshLandmarksPx = currentLandmarksPx;
    debugFrame.roiPolygon = currentPolygon;
    debugFrame.frameIndex = frameIdx;
end

end
