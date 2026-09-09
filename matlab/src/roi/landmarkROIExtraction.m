function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = landmarkROIExtraction(frames, frameRate, freezeCadence)
% LANDMARKROIEXTRACTION KLT-tracked, rotation-compensated forehead ROI:
% a drop-in alternative to roi/extractROISignals.m's axis-aligned
% forehead box.
%
% Segment 7 Task D2, Action 1 update: gained an optional 3rd argument,
% freezeCadence (default false -- the ORIGINAL, already-reported Task D
% behaviour is byte-for-byte unchanged when this is omitted; see the
% regression check in docs/Segment7_Task_D_Landmark_ROI.md). This exists
% to test a specific hypothesis about WHY the continuous-update version
% regressed ABPF's notch confidence so badly (see that doc's Task D2
% section): roi/extractROISignals.m only recomputes its ROI box on
% detectEveryN=5 anchor frames and reuses it UNCHANGED on the 4 frames in
% between (currentBBox = lastGoodBBox); the default freezeCadence=false
% mode here instead calls estimateGeometricTransform2D and poly2mask on
% EVERY frame, so even tiny tracking noise flips a ring of boundary
% pixels in and out of the spatial mean every single frame -- a noise
% source the fixed-box baseline structurally cannot have. When
% freezeCadence=true, the tracked polygon is still rotation-compensated
% (this is NOT a reversion to the axis-aligned baseline -- see Step 2'
% below), but that compensation is computed and applied ONLY once per
% detectEveryN=5 cycle, at the anchor frame, and then held FROZEN
% (reused unchanged, no new step()/transform/poly2mask call) for the up
% to 4 frames until the next anchor -- mirroring
% roi/extractROISignals.m's own currentBBox = lastGoodBBox behaviour
% exactly, just applied to a tracked polygon instead of an axis-aligned
% box.
%
% Pipeline stage: Segment 7 Task D, Action 1 (NEW, additive, ROI stage --
% same pipeline position as roi/extractROISignals.m; belongs in roi/,
% not morphology/, per this project's stage-based folder convention).
% Does NOT modify roi/extractROISignals.m in any way -- this is a
% separate front-end for the morphology branch's chain, selected instead
% of extractROISignals.m by the caller (see
% scripts/run_segment7_task_d_landmark_roi_batch.m), never both at once
% for the same condition.
%
% WHY THIS EXISTS (Segment 7 Task D, Action 0): the original plan (per
% the uploaded thesis's Section 3.2.1) was a forehead ROI built from 4
% named landmarks (indices 67, 297, 105, 334 on a 468-point face mesh).
% Action 0 checked this MATLAB R2024b installation for ANY facial-
% landmark / face-mesh detector -- Deep Learning Toolbox Model support
% packages (`matlab.addons.installedAddons`), Computer Vision Toolbox
% functions, and direct `exist()` probes for
% facemark/faceLandmark/facialLandmark/landmarkDetector/mediapipe/
% faceMesh/shapePredictor/faceLandmarkDetector -- and found NONE (only
% the ~113 toolboxes this project already knew about, none of which ship
% a 468-point face-mesh model). `vision.PointTracker`,
% `detectMinEigenFeatures`, `detectHarrisFeatures`, and
% `estimateGeometricTransform2D` ARE all present (confirmed via `exist`),
% so this function instead implements the documented fallback: KLT-based
% rotation compensation of the SAME axis-aligned forehead region
% roi/extractROISignals.m already uses (x:[0.30,0.70] y:[0.10,0.30] of
% the Viola-Jones face box), tracked and re-oriented frame-to-frame
% instead of staying axis-aligned. This does not reproduce the 4-landmark
% geometry the thesis specifies (this MATLAB installation cannot locate
% those 4 named points at all, with or without tracking) -- it targets
% the narrower, adjacent question the thesis section motivates: does
% compensating for head ROTATION (not landmark-precise placement) recover
% any of the dicrotic-notch confidence ABPF alone still misses on this
% project's pool. See docs/Segment7_Task_D_Landmark_ROI.md for the
% full writeup and the comparison this distinction supports.
%
% Algorithm concept (NOT code) adapted from van der Kooij & Naber,
% "A snapshot of the current state of eye tracking" -- actually: van der
% Kooij K, Naber M. "An open-source remote heart rate imaging method with
% practical apparatus and algorithms." Behav Res Methods 51:2106-2119
% (2019), and its reference implementation marnixnaber/rPPG on GitHub.
% That repository is GPL-3.0 licensed and this project is MIT-licensed,
% so ONLY the algorithm's shape was read from its description -- no code
% from that repository was copied, adapted line-by-line, or transliterated
% here; every implementation choice below (which MATLAB functions, which
% parameters, which fallback rules) was made independently against this
% project's own existing conventions (Viola-Jones cadence, forehead
% fractions, largest-bbox rule -- all reused from
% roi/extractROISignals.m, not from the paper or its repository).
%
% Method:
%   1. Detect the face every detectEveryN=5 frames, same convention as
%      roi/extractROISignals.m: vision.CascadeObjectDetector, largest
%      bounding box wins on multiple detections (see
%      roi/extractROISignals.m's own header/fix for why largest-box, not
%      bboxes(1,:), is required), last-known-good bbox reused between
%      detection frames, centered fallback box if no detection has ever
%      succeeded yet.
%   2. On every detection frame (an "anchor" frame), compute the forehead
%      sub-region from that frame's face bbox using the SAME fractions
%      roi/extractROISignals.m's default 'forehead' roiMode uses
%      (x:[0.30,0.70], y:[0.10,0.30]) -- this is the axis-aligned
%      "anchor polygon" that gets rotation-compensated between anchor
%      frames. detectMinEigenFeatures(...,'ROI', foreheadBBox) selects up
%      to maxTrackedPoints trackable corner features restricted to that
%      box (already in full-frame coordinates via the 'ROI' option, no
%      manual offset bookkeeping needed), and (re)initializes a fresh
%      vision.PointTracker on them. Re-anchoring at the SAME detectEveryN
%      cadence roi/extractROISignals.m uses for face redetection is the
%      explicit drift bound the Task D brief calls for -- KLT tracking
%      error does not have a chance to accumulate for more than
%      detectEveryN frames before being reset against a fresh detection.
%   3. On frames between anchors, vision.PointTracker's step() tracks the
%      anchor's own feature points forward. estimateGeometricTransform2D
%      (similarity transform: rotation + uniform scale + translation,
%      MSAC-robust by default) is fit between the ANCHOR frame's own
%      points and the CURRENT frame's tracked points -- not
%      frame-to-frame incrementally -- specifically so estimation noise
%      does not compound across the up-to-4 tracked frames between
%      anchors; each anchor resets the reference, same drift-bounding
%      reasoning as step 2.
%   4. That similarity transform is applied to the anchor polygon's own 4
%      corners (transformPointsForward), producing a ROTATED
%      quadrilateral that follows head rotation instead of staying
%      axis-aligned. Pixels are pooled via poly2mask (Image Processing
%      Toolbox) over this quadrilateral, not a rectangular crop, so a
%      rotated ROI is sampled correctly.
%   5. Fallback / sanity bound (this project's own addition, not from the
%      paper): if fewer than minPointsForTransform=4 tracked points
%      survive vision.PointTracker's own validity flag, OR the fitted
%      transform's resulting polygon area falls outside
%      [0.25x, 4x] of the anchor polygon's own area (a badly-conditioned
%      or degenerate transform), that frame reuses the LAST good polygon
%      unchanged rather than trusting the new estimate -- same
%      last-known-good philosophy roi/extractROISignals.m already uses
%      for face bboxes, applied here to polygons. Frames that hit this
%      fallback (or the face-detection fallback in step 1) are recorded
%      in droppedFrameIdx.
%
%   Step 2' (freezeCadence=true ONLY, Segment 7 Task D2): steps 3-4 above
%      do NOT run on non-anchor frames -- no step()/transform/poly2mask
%      call happens between anchors at all; the polygon computed at the
%      last anchor is reused completely unchanged. Rotation compensation
%      itself still happens, but only ONCE per detectEveryN=5 cycle, at
%      the anchor frame: before that anchor's own fresh face
%      redetection/feature reselection/tracker reinitialization runs (the
%      same re-anchoring step 2 already describes), the EXISTING tracker
%      (still holding the PREVIOUS cycle's anchor points) is stepped
%      forward ONE time to this new anchor frame, and
%      estimateGeometricTransform2D is fit between the previous cycle's
%      anchor points and this frame's tracked points -- the same
%      transform-fitting logic as step 3, just evaluated once per cycle
%      (previous-anchor-to-new-anchor) instead of once per frame
%      (anchor-to-current-frame). That transform is applied to the
%      PREVIOUS cycle's anchor polygon to produce the polygon frozen for
%      the WHOLE upcoming cycle (this anchor frame plus its following up
%      to 4 non-anchor frames). Only after this resolution does the
%      normal re-anchoring (fresh detection, fresh points, fresh
%      axis-aligned reference polygon for measuring the NEXT cycle's
%      rotation) proceed. The very first anchor of a video has no
%      previous cycle to resolve, so its own frame simply uses the fresh
%      axis-aligned box, same as freezeCadence=false's first anchor.
%
% Inputs:
%   frames        - a VideoReader object, as produced by
%                   io/loadUBFCVideo.m (same as
%                   roi/extractROISignals.m's first argument).
%   frameRate     - scalar, frames per second (from io/loadUBFCVideo.m).
%   freezeCadence - (optional) logical scalar. false (default) -- the
%                   ORIGINAL, already-reported Task D behaviour,
%                   unchanged: continuous per-frame transform + rerasterize.
%                   true -- Segment 7 Task D2's frozen-cadence variant
%                   (Step 2' above): rotation-compensated but updated only
%                   once per detectEveryN=5 cycle. See
%                   docs/Segment7_Task_D_Landmark_ROI.md for the
%                   hypothesis this parameter tests and the three-way
%                   comparison result.
%
% Outputs:
%   R, G, B         - 1 x numFrames vectors, the spatial average pixel
%                     intensity of the tracked, rotation-compensated
%                     forehead polygon for each color channel, one value
%                     per frame. Same shape/units as
%                     roi/extractROISignals.m's own R, G, B -- this
%                     function is a drop-in ROI-stage replacement, so its
%                     output feeds filtering/detrendSignal.m ->
%                     morphology/adaptiveHarmonicFilter.m ->
%                     pulseextraction/chromCombine.m exactly as
%                     roi/extractROISignals.m's output does (raw,
%                     per-channel, NOT pre-combined -- see this task's
%                     brief on avoiding Task C1's confound).
%   roiTimestamps   - 1 x numFrames vector, seconds, same convention as
%                     roi/extractROISignals.m.
%   droppedFrameIdx - row vector of frame indices where EITHER the face
%                     detector fallback (step 1) OR the polygon-transform
%                     fallback (step 5) fired. Empty if neither ever
%                     happened.
%   debugFrame      - struct for the Action 4 drift sanity-check figure.
%                     UNLIKE roi/extractROISignals.m's debugFrame (which
%                     carries exactly ONE representative frame), this
%                     carries SEVERAL sample frames spread across the
%                     video -- a single mid-video frame cannot show
%                     whether the tracked polygon actually follows head
%                     rotation over time, which is the entire point of
%                     this comparison. Documented deviation, not an
%                     oversight. Fields:
%                       samples    - 1 x numSamples struct array, each
%                                    entry: image (raw H x W x 3 uint8
%                                    frame), frameIndex, faceBBox (that
%                                    frame's detected/reused face bbox),
%                                    axisAlignedForeheadBBox (the OLD,
%                                    non-tracked forehead box computed
%                                    fresh from faceBBox on THIS frame,
%                                    for direct old-vs-new comparison --
%                                    this is exactly what
%                                    roi/extractROISignals.m would have
%                                    used for this same frame), and
%                                    roiPolygon (the NEW, rotation-
%                                    tracked 4x2 [x y] polygon actually
%                                    used for R/G/B extraction on this
%                                    frame).
%                       frameIndices - the numSamples frame indices
%                                    chosen (same as [samples.frameIndex],
%                                    provided separately for convenience).

if nargin < 3 || isempty(freezeCadence)
    freezeCadence = false;
end

detectEveryN = 5;
maxTrackedPoints = 60;
minPointsForTransform = 4;
areaRatioBounds = [0.25, 4.0];
numDebugSamples = 8;

faceDetector = vision.CascadeObjectDetector();
pointTracker = vision.PointTracker('MaxBidirectionalError', 2);

frames.CurrentTime = 0;
numFrames = frames.NumFrames;

R = zeros(1, numFrames);
G = zeros(1, numFrames);
B = zeros(1, numFrames);
roiTimestamps = zeros(1, numFrames);
frameDroppedFlag = false(1, numFrames);

lastGoodFaceBBox = [];
lastGoodPolygon = [];
anchorPolygon = [];
anchorPoints = [];
trackerInitialized = false;

debugSampleIdx = unique(round(linspace(1, numFrames, min(numDebugSamples, numFrames))));
debugSamples = struct('image', {}, 'frameIndex', {}, 'faceBBox', {}, 'axisAlignedForeheadBBox', {}, 'roiPolygon', {});

frameIdx = 0;

while hasFrame(frames)
    frameIdx = frameIdx + 1;
    if frameIdx > numFrames
        break
    end

    img = readFrame(frames);
    [frameHeight, frameWidth, ~] = size(img);
    imgGray = rgb2gray(img);

    runDetectionThisFrame = mod(frameIdx - 1, detectEveryN) == 0;
    frameDropped = false;

    if freezeCadence
        % === Segment 7 Task D2, Action 1: FROZEN-CADENCE MODE ===
        % See this function's own header (Step 2') and
        % docs/Segment7_Task_D_Landmark_ROI.md for the hypothesis this
        % mode tests. Face detection below is a duplicate of the
        % freezeCadence=false branch's own face-detection logic
        % (unavoidable, kept as a full separate copy rather than
        % factored out, specifically so the freezeCadence=false branch
        % below is left 100% untouched and the Action 4 regression check
        % has nothing to second-guess).
        if runDetectionThisFrame
            bboxes = step(faceDetector, img);
            if isempty(bboxes)
                frameDropped = true;
                disp(['Frame ' num2str(frameIdx) ': face detector found nothing, reusing last known bounding box.']);
                currentFaceBBox = lastGoodFaceBBox;
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
                currentFaceBBox = bestBBox;
                lastGoodFaceBBox = currentFaceBBox;
            end

            if isempty(currentFaceBBox)
                frameDropped = true;
                disp(['Frame ' num2str(frameIdx) ': no bounding box available yet, using centered fallback box.']);
                currentFaceBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
                lastGoodFaceBBox = currentFaceBBox;
            end

            axisAlignedForeheadBBox = foreheadBBoxFromFace(currentFaceBBox, frameWidth, frameHeight);

            % --- Resolve the PREVIOUS cycle's net rotation in ONE
            % measurement (Step 2' in the header): step the EXISTING
            % tracker (still holding the previous cycle's anchor points)
            % forward to this new anchor frame, fit ONE transform from
            % the previous anchor's points to here, and apply it to the
            % previous anchor's polygon. This is the polygon that will
            % be frozen for this whole upcoming cycle. Must happen
            % BEFORE re-anchoring below overwrites anchorPoints/
            % anchorPolygon with fresh values. ---
            if trackerInitialized
                [trackedPoints, validity] = step(pointTracker, imgGray);
                validAnchorPoints = anchorPoints(validity, :);
                validTrackedPoints = trackedPoints(validity, :);

                if size(validTrackedPoints, 1) >= minPointsForTransform
                    [tform, inlierIdx] = estimateGeometricTransform2D(validAnchorPoints, validTrackedPoints, 'similarity');
                    if nnz(inlierIdx) >= minPointsForTransform
                        candidatePolygon = transformPointsForward(tform, anchorPolygon);
                        anchorArea = polyarea(anchorPolygon(:, 1), anchorPolygon(:, 2));
                        candidateArea = polyarea(candidatePolygon(:, 1), candidatePolygon(:, 2));
                        areaRatio = candidateArea / anchorArea;

                        if areaRatio >= areaRatioBounds(1) && areaRatio <= areaRatioBounds(2)
                            currentPolygon = candidatePolygon;
                        else
                            frameDropped = true;
                            disp(['Frame ' num2str(frameIdx) ': [frozen-cadence] transformed polygon area ratio ' num2str(areaRatio, '%.3f') ' outside [' num2str(areaRatioBounds(1)) ', ' num2str(areaRatioBounds(2)) '], reusing last good polygon.']);
                            currentPolygon = lastGoodPolygon;
                        end
                    else
                        frameDropped = true;
                        disp(['Frame ' num2str(frameIdx) ': [frozen-cadence] too few inlier point pairs (' num2str(nnz(inlierIdx)) ' < ' num2str(minPointsForTransform) ') resolving the previous cycle''s rotation, reusing last good polygon.']);
                        currentPolygon = lastGoodPolygon;
                    end
                else
                    frameDropped = true;
                    disp(['Frame ' num2str(frameIdx) ': [frozen-cadence] only ' num2str(size(validTrackedPoints, 1)) ' valid tracked point(s) (< ' num2str(minPointsForTransform) ') resolving the previous cycle''s rotation, reusing last good polygon.']);
                    currentPolygon = lastGoodPolygon;
                end
            else
                % First-ever anchor (or tracking was never successfully
                % re-established): nothing to compensate yet, same as
                % freezeCadence=false's own first-anchor behaviour.
                currentPolygon = bboxToPolygon(axisAlignedForeheadBBox);
            end
            lastGoodPolygon = currentPolygon;

            % --- Re-anchor for the NEXT cycle: fresh feature selection +
            % tracker reinitialization, same convention as
            % freezeCadence=false. ---
            candidatePoints = detectMinEigenFeatures(imgGray, 'ROI', axisAlignedForeheadBBox);
            if candidatePoints.Count > maxTrackedPoints
                candidatePoints = candidatePoints.selectStrongest(maxTrackedPoints);
            end

            if candidatePoints.Count >= minPointsForTransform
                anchorPoints = candidatePoints.Location;
                anchorPolygon = bboxToPolygon(axisAlignedForeheadBBox);

                if trackerInitialized
                    release(pointTracker);
                end
                initialize(pointTracker, anchorPoints, imgGray);
                trackerInitialized = true;
            else
                disp(['Frame ' num2str(frameIdx) ': [frozen-cadence] only ' num2str(candidatePoints.Count) ' trackable feature(s) found (< ' num2str(minPointsForTransform) '), cannot re-anchor tracking for the next cycle -- next cycle will resolve to the axis-aligned box until a later anchor succeeds.']);
                trackerInitialized = false;
            end
        else
            % Non-anchor frame, frozen cadence: reuse the polygon fixed
            % at the last anchor completely UNCHANGED -- no
            % step()/transform/poly2mask call this frame at all,
            % mirroring roi/extractROISignals.m's own
            % currentBBox = lastGoodBBox behaviour exactly.
            currentFaceBBox = lastGoodFaceBBox;
            axisAlignedForeheadBBox = foreheadBBoxFromFace(currentFaceBBox, frameWidth, frameHeight);
            currentPolygon = lastGoodPolygon;
        end
    elseif runDetectionThisFrame
        bboxes = step(faceDetector, img);
        if isempty(bboxes)
            frameDropped = true;
            disp(['Frame ' num2str(frameIdx) ': face detector found nothing, reusing last known bounding box.']);
            currentFaceBBox = lastGoodFaceBBox;
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
            currentFaceBBox = bestBBox;
            lastGoodFaceBBox = currentFaceBBox;
        end

        if isempty(currentFaceBBox)
            frameDropped = true;
            disp(['Frame ' num2str(frameIdx) ': no bounding box available yet, using centered fallback box.']);
            currentFaceBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
            lastGoodFaceBBox = currentFaceBBox;
        end

        axisAlignedForeheadBBox = foreheadBBoxFromFace(currentFaceBBox, frameWidth, frameHeight);

        % --- Re-anchor: fresh feature selection + tracker reinitialization,
        % the explicit drift bound (Task D brief, Action 0's KLT branch). ---
        candidatePoints = detectMinEigenFeatures(imgGray, 'ROI', axisAlignedForeheadBBox);
        if candidatePoints.Count > maxTrackedPoints
            candidatePoints = candidatePoints.selectStrongest(maxTrackedPoints);
        end

        if candidatePoints.Count >= minPointsForTransform
            anchorPoints = candidatePoints.Location;
            anchorPolygon = bboxToPolygon(axisAlignedForeheadBBox);

            if trackerInitialized
                release(pointTracker);
            end
            initialize(pointTracker, anchorPoints, imgGray);
            trackerInitialized = true;

            currentPolygon = anchorPolygon;
            lastGoodPolygon = currentPolygon;
        else
            % Too few trackable corners in this frame's forehead box to
            % re-anchor safely -- fall back to the plain axis-aligned box
            % for this anchor cycle (equivalent to
            % roi/extractROISignals.m's own behaviour) rather than
            % initializing a tracker on an unreliably small point set.
            frameDropped = true;
            disp(['Frame ' num2str(frameIdx) ': only ' num2str(candidatePoints.Count) ' trackable feature(s) found (< ' num2str(minPointsForTransform) '), using axis-aligned forehead box for this frame.']);
            anchorPolygon = bboxToPolygon(axisAlignedForeheadBBox);
            trackerInitialized = false;
            currentPolygon = anchorPolygon;
            lastGoodPolygon = currentPolygon;
        end
    else
        currentFaceBBox = lastGoodFaceBBox;
        axisAlignedForeheadBBox = foreheadBBoxFromFace(currentFaceBBox, frameWidth, frameHeight);

        if trackerInitialized
            [trackedPoints, validity] = step(pointTracker, imgGray);
            validAnchorPoints = anchorPoints(validity, :);
            validTrackedPoints = trackedPoints(validity, :);

            if size(validTrackedPoints, 1) >= minPointsForTransform
                [tform, inlierIdx] = estimateGeometricTransform2D(validAnchorPoints, validTrackedPoints, 'similarity');
                if nnz(inlierIdx) >= minPointsForTransform
                    candidatePolygon = transformPointsForward(tform, anchorPolygon);
                    anchorArea = polyarea(anchorPolygon(:, 1), anchorPolygon(:, 2));
                    candidateArea = polyarea(candidatePolygon(:, 1), candidatePolygon(:, 2));
                    areaRatio = candidateArea / anchorArea;

                    if areaRatio >= areaRatioBounds(1) && areaRatio <= areaRatioBounds(2)
                        currentPolygon = candidatePolygon;
                        lastGoodPolygon = currentPolygon;
                    else
                        frameDropped = true;
                        disp(['Frame ' num2str(frameIdx) ': transformed polygon area ratio ' num2str(areaRatio, '%.3f') ' outside [' num2str(areaRatioBounds(1)) ', ' num2str(areaRatioBounds(2)) '], reusing last good polygon.']);
                        currentPolygon = lastGoodPolygon;
                    end
                else
                    frameDropped = true;
                    disp(['Frame ' num2str(frameIdx) ': too few inlier point pairs (' num2str(nnz(inlierIdx)) ' < ' num2str(minPointsForTransform) ') for a reliable transform, reusing last good polygon.']);
                    currentPolygon = lastGoodPolygon;
                end
            else
                frameDropped = true;
                disp(['Frame ' num2str(frameIdx) ': only ' num2str(size(validTrackedPoints, 1)) ' valid tracked point(s) (< ' num2str(minPointsForTransform) '), reusing last good polygon.']);
                currentPolygon = lastGoodPolygon;
            end
        else
            currentPolygon = lastGoodPolygon;
        end
    end

    if isempty(currentPolygon)
        frameDropped = true;
        currentPolygon = bboxToPolygon([round(0.35 * frameWidth), round(0.15 * frameHeight), round(0.40 * frameWidth), round(0.20 * frameHeight)]);
        lastGoodPolygon = currentPolygon;
    end

    % poly2mask requires double coordinates; detectMinEigenFeatures'/
    % estimateGeometricTransform2D's outputs (and hence a
    % transform-derived currentPolygon) are single-precision, so cast
    % explicitly here rather than propagate single through the rest of
    % the function.
    roiMask = poly2mask(double(currentPolygon(:, 1)), double(currentPolygon(:, 2)), frameHeight, frameWidth);

    if ~any(roiMask(:))
        frameDropped = true;
        disp(['Frame ' num2str(frameIdx) ': tracked polygon produced an empty mask, falling back to the axis-aligned forehead box for this frame only.']);
        fallbackBBox = foreheadBBoxFromFace(currentFaceBBox, frameWidth, frameHeight);
        fallbackPolygon = bboxToPolygon(fallbackBBox);
        roiMask = poly2mask(double(fallbackPolygon(:, 1)), double(fallbackPolygon(:, 2)), frameHeight, frameWidth);
    end

    frameDroppedFlag(frameIdx) = frameDropped;

    redChannel = double(img(:, :, 1));
    greenChannel = double(img(:, :, 2));
    blueChannel = double(img(:, :, 3));

    R(frameIdx) = mean(redChannel(roiMask));
    G(frameIdx) = mean(greenChannel(roiMask));
    B(frameIdx) = mean(blueChannel(roiMask));
    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    if ismember(frameIdx, debugSampleIdx)
        thisSample = struct();
        thisSample.image = img;
        thisSample.frameIndex = frameIdx;
        thisSample.faceBBox = currentFaceBBox;
        thisSample.axisAlignedForeheadBBox = axisAlignedForeheadBBox;
        thisSample.roiPolygon = currentPolygon;
        debugSamples(end + 1) = thisSample; %#ok<AGROW>
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

debugFrame = struct();
debugFrame.samples = debugSamples;
if isempty(debugSamples)
    debugFrame.frameIndices = [];
else
    debugFrame.frameIndices = [debugSamples.frameIndex];
end

end

function foreheadBBox = foreheadBBoxFromFace(faceBBox, frameWidth, frameHeight)
% Duplicates roi/extractROISignals.m's default 'forehead' fractions
% (x:[0.30,0.70], y:[0.10,0.30] of the face bbox) rather than importing
% them -- same reasoning morphology/tiledROIExtraction.m's header already
% gives for its own duplicated face-detection logic: extractROISignals.m
% returns an already spatially-averaged trace, there is no reusable
% intermediate bbox-computation function exposed on the path to call
% instead.

faceX = faceBBox(1);
faceY = faceBBox(2);
faceW = faceBBox(3);
faceH = faceBBox(4);

xFracLo = 0.30;
xFracHi = 0.70;
yFracLo = 0.10;
yFracHi = 0.30;

x1 = max(1, round(faceX + xFracLo * faceW));
x2 = min(frameWidth, round(faceX + xFracHi * faceW));
y1 = max(1, round(faceY + yFracLo * faceH));
y2 = min(frameHeight, round(faceY + yFracHi * faceH));

foreheadBBox = [x1, y1, x2 - x1, y2 - y1];

end

function polygon = bboxToPolygon(bbox)
% [x y width height] -> 4x2 [x y] corners, clockwise from top-left.
x = bbox(1);
y = bbox(2);
w = bbox(3);
h = bbox(4);
polygon = [x, y; x + w, y; x + w, y + h; x, y + h];
end
