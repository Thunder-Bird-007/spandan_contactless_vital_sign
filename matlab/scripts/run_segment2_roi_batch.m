% RUN_SEGMENT2_ROI_BATCH Batch driver for Segment 2 (face detection + ROI
% extraction) across a configurable list of UBFC-rPPG subjects.
%
% Each of the 4 team members edits the SUBJECT LIST section below to their
% own assigned subset of the shared 42-subject DATASET_2 pool (or whatever
% subjects they have locally), then runs this script. Every subject's
% output filename is tagged with that subject's own ID, so everyone's
% .mat/.png outputs can be copied into one shared folder afterwards
% without collisions.
%
% For each subject this script:
%   1. Locates the subject's video file under data/raw/UBFC-rPPG/.
%   2. Calls io/loadUBFCVideo.m to open it.
%   3. Calls roi/extractROISignals.m to get R(t), G(t), B(t).
%   4. Saves data/processed/<subjectID>_rgb_traces.mat.
%   5. Draws the detected face box and the ROI box on one representative
%      frame and saves it as results/figures/<subjectID>_roi_sanity.png.
%   6. Prints progress and dropped-frame counts to the console.
%
% If a subject fails (missing file, corrupt video, detector error), this
% script logs the error and moves on to the next subject rather than
% halting the whole batch. A summary of any failures is printed at the
% end.

datasetName = 'DATASET_1';
subjectList = {'5-gt', '6-gt', '7-gt'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
rawDataRoot = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', datasetName);
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(processedDataRoot)
    mkdir(processedDataRoot);
end

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};

    disp(['--- Processing subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        subjectFolder = fullfile(rawDataRoot, subjectID);
        videoList = dir(fullfile(subjectFolder, '*.avi'));

        if isempty(videoList)
            error('run_segment2_roi_batch:noVideo', 'No .avi file found in %s', subjectFolder);
        end

        videoPath = fullfile(videoList(1).folder, videoList(1).name);

        [videoReaderObj, fs, numFrames] = loadUBFCVideo(videoPath);

        disp(['Subject ' subjectID ': fs = ' num2str(fs) ' fps, numFrames = ' num2str(numFrames)]);

        [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(videoReaderObj, fs);

        numDroppedFrames = numel(droppedFrameIdx);

        disp(['Subject ' subjectID ': dropped/reused-bbox frames = ' num2str(numDroppedFrames)]);

        matOutPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);
        save(matOutPath, 'R', 'G', 'B', 'fs', 'subjectID', 'numDroppedFrames');

        disp(['Subject ' subjectID ': saved ' matOutPath]);

        annotatedImg = insertObjectAnnotation(debugFrame.image, 'rectangle', debugFrame.faceBBox, 'Detected Face', 'Color', 'yellow', 'LineWidth', 3);
        annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrame.roiBBox, 'ROI (forehead)', 'Color', 'green', 'LineWidth', 3);

        pngOutPath = fullfile(figuresRoot, [subjectID '_roi_sanity.png']);
        imwrite(annotatedImg, pngOutPath);

        disp(['Subject ' subjectID ': saved ' pngOutPath]);
    catch causeErr
        disp(['Subject ' subjectID ': FAILED — ' causeErr.message]);
        failedSubjects{end + 1} = subjectID;
        failedReasons{end + 1} = causeErr.message;
    end
end

disp('--- Batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end
