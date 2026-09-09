% RUN_SEGMENT7_TASK_A_SATURATION_CHECK Segment 7 Task A, Action 0
% (diagnostic, run FIRST). For each subject's raw video, decodes the
% forehead ROI per frame (same geometry as roi/extractROISignals.m's
% default 'forehead' roiMode: x:[0.30,0.70], y:[0.10,0.30] of the
% detected face box) and reports, per color channel:
%   - the fraction of individual PIXELS (pooled across every frame) with
%     an 8-bit value >= 250
%   - the fraction of FRAMES whose ROI channel mean is >= 245
%
% WHY THIS RUNS BEFORE ANYTHING ELSE: if the forehead ROI is genuinely
% saturating (sensor clipping), that is a SEPARATE, real cause of defect
% (b) ("cut off / flattened at the top") that no amount of filtering,
% polarity-fixing, or ensemble averaging can undo -- clipped samples are
% gone, not attenuated. This script's job is only to measure and report
% those two fractions; it does not modify the ROI extraction pipeline,
% and it duplicates (does not import) roi/extractROISignals.m's forehead
% geometry constants and face-detection convention (detectEveryN = 5,
% largest-bounding-box selection, last-known-good fallback) because that
% function returns only PER-FRAME MEANS, not the per-pixel/per-frame
% saturation counts this diagnostic needs -- there was nothing to reuse
% by calling it directly.
%
% Outputs:
%   results/metrics/segment7_task_a_saturation_check.csv - one row per
%     (subjectID, channel): fracPixelsSaturated, fracFramesMeanSaturated,
%     numFramesProcessed, numPixelsPerFrame.
%
% See docs/Segment7_Task_A_Morphology_Pipeline.md for the numbers this
% produced and what they mean for the rest of Segment 7 Task A.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

pixelSaturationThreshold = 250;
frameMeanSaturationThreshold = 245;

% Same fractions as roi/extractROISignals.m's 'forehead' region (the
% default roiMode, and the ROI this project's whole rPPG pipeline runs
% on) -- duplicated here, not imported, per this file's header note.
foreheadXFracLo = 0.30;
foreheadXFracHi = 0.70;
foreheadYFracLo = 0.10;
foreheadYFracHi = 0.30;
detectEveryN = 5;

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_task_a_saturation_check.csv');
headerLine = "subjectID,channel,fracPixelsSaturated,fracFramesMeanSaturated,numFramesProcessed,numPixelsPerFrameApprox";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};
anyNonTrivialSaturation = false;

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Saturation check: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        if ~isfolder(subjectDir)
            error('run_segment7_task_a_saturation_check:missingSubject', 'Subject folder not found: %s', subjectDir);
        end

        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_task_a_saturation_check:missingVideo', 'No .avi file found under: %s', subjectDir);
        end

        videoPath = fullfile(subjectDir, aviFiles(1).name);

        [frames, frameRate, ~] = loadUBFCVideo(videoPath);
        frames.CurrentTime = 0;
        numFrames = frames.NumFrames;

        pixelsSaturatedCount = [0, 0, 0];
        pixelsTotalCount = [0, 0, 0];
        framesMeanSaturatedCount = [0, 0, 0];

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
                if frameIdx == 1
                    faceDetector = vision.CascadeObjectDetector();
                end
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

            x1 = max(1, round(faceX + foreheadXFracLo * faceW));
            x2 = min(frameWidth, round(faceX + foreheadXFracHi * faceW));
            y1 = max(1, round(faceY + foreheadYFracLo * faceH));
            y2 = min(frameHeight, round(faceY + foreheadYFracHi * faceH));

            roiPatch = img(y1:y2, x1:x2, :);

            for ch = 1:3
                channelPixels = double(reshape(roiPatch(:, :, ch), [], 1));
                pixelsSaturatedCount(ch) = pixelsSaturatedCount(ch) + sum(channelPixels >= pixelSaturationThreshold);
                pixelsTotalCount(ch) = pixelsTotalCount(ch) + numel(channelPixels);
                if mean(channelPixels) >= frameMeanSaturationThreshold
                    framesMeanSaturatedCount(ch) = framesMeanSaturatedCount(ch) + 1;
                end
            end
        end

        actualNumFrames = frameIdx;
        channelNames = {'R', 'G', 'B'};

        for ch = 1:3
            fracPixelsSaturated = pixelsSaturatedCount(ch) / pixelsTotalCount(ch);
            fracFramesMeanSaturated = framesMeanSaturatedCount(ch) / actualNumFrames;
            numPixelsPerFrameApprox = round(pixelsTotalCount(ch) / actualNumFrames);

            disp(['Subject ' subjectID ', channel ' channelNames{ch} ': fracPixelsSaturated = ' num2str(fracPixelsSaturated, '%.6f') ', fracFramesMeanSaturated = ' num2str(fracFramesMeanSaturated, '%.6f')]);

            if fracPixelsSaturated > 0.01 || fracFramesMeanSaturated > 0.05
                anyNonTrivialSaturation = true;
                disp(['  *** NON-TRIVIAL SATURATION on subject ' subjectID ', channel ' channelNames{ch} ' -- real sensor clipping, must be reported before proceeding. ***']);
            end

            rowParts = {subjectID, channelNames{ch}, num2str(fracPixelsSaturated, '%.6f'), num2str(fracFramesMeanSaturated, '%.6f'), num2str(actualNumFrames), num2str(numPixelsPerFrameApprox)};
            writelines(strjoin(rowParts, ','), csvPath, 'WriteMode', 'append');
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Saturation check complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

if anyNonTrivialSaturation
    disp('=== RESULT: non-trivial saturation detected on at least one subject/channel -- see table above and segment7_task_a_saturation_check.csv. Report this before proceeding to Actions 1-8. ===');
else
    disp('=== RESULT: no non-trivial saturation detected on any subject/channel -- safe to proceed. ===');
end

disp(['Saved ' csvPath]);
