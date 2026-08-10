function [frames, frameRate, numFrames, videoPath] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum)
% LOADVIPLVIDEO Load a VIPL-HR subject/scenario/source video into memory.
%
% Pipeline stage: Stage 1 (input) — reads the raw facial video that all
% later stages (ROI extraction, filtering, pulse extraction, HR/SpO2
% estimation) operate on. This is the VIPL-HR counterpart of
% io/loadUBFCVideo.m, adapted to VIPL-HR's real on-disk layout — see
% docs/VIPL_DATA_FORMAT.md for exactly how that layout was confirmed.
%
% VIPL-HR has no single addressable "subject video" the way UBFC does.
% Each subject pXXX has up to nine scenario folders (v1-v9) and each
% scenario folder has up to four device folders (source1-source4), and
% every (subject, scenario, source) triple is its own independent video
% with its own ground truth files. This function therefore takes all
% three identifiers explicitly rather than a single subject ID — see
% docs/VIPL_DATA_FORMAT.md Section 1 for why a two-part
% (subjectID, sourceID) scheme, as originally suggested, is not
% sufficient on its own.
%
% Only RGB sources are supported here (source1, source2, source3).
% source4 is VIPL-HR's NIR (near-infrared) camera — a different sensing
% modality the rest of this pipeline (extractROISignals.m onward) was
% never designed for, so it is explicitly rejected rather than silently
% loaded. See docs/VIPL_DATA_FORMAT.md Section 3 for source4 details.
%
% Inputs:
%   viplRoot    - string/char, path to the extracted VIPL-HR root folder,
%                 i.e. the folder directly containing pXXX subject
%                 folders (this project's copy: data/raw/VIPL-HR — see
%                 docs/VIPL_DATA_FORMAT.md Section 0 for why only a
%                 validation subset is extracted there rather than the
%                 full 107-subject archive).
%   subjectNum  - scalar, subject number (e.g. 1 for "p1").
%   scenarioNum - scalar, scenario number 1-9 (e.g. 1 for "v1", the
%                 stable scenario — see docs/VIPL_DATA_FORMAT.md
%                 Section 2 for what each of v1-v9 means).
%   sourceNum   - scalar, 1, 2, or 3 (source4 is NIR and rejected).
%
% Outputs:
%   frames    - a VideoReader object opened on the video file. Frames
%               are NOT preloaded into memory here, same discipline as
%               loadUBFCVideo.m — callers stream with
%               hasFrame()/readFrame(), exactly as roi/extractROISignals.m
%               does.
%   frameRate - scalar, frames per second. IMPORTANT — this is NOT simply
%               VideoReader.FrameRate. VIPL-HR's own ReadMe.pdf states
%               that source1/source3/source4 videos are re-encoded for
%               storage and their container frame rate does not reflect
%               real acquisition timing ("the videos are only used for
%               compression and the time steps for the frames are
%               recorded in the time.txt"). This was confirmed for real:
%               p1/v1/source3's container claims 25 fps (41.64 s) while
%               its own time.txt shows the same 1041 frames actually
%               span 34.72 s (~30.0 fps) — see docs/VIPL_DATA_FORMAT.md
%               Section 4 for the full measurement table. When a
%               time.txt file exists next to video.avi (source1,
%               source3, source4), frameRate is computed from time.txt's
%               own frame-acquisition timestamps instead of trusting
%               VideoReader.FrameRate, and a disp() warning is printed
%               if the two disagree by more than 5%. source2 (the phone
%               camera) has no time.txt at all, so VideoReader.FrameRate
%               is the only available estimate for it and is used as-is
%               — this is a real, documented accuracy limitation for
%               source2, not an oversight.
%   numFrames - scalar, total number of frames in the video.
%   videoPath - string, the full path that was opened, returned so
%               callers/loggers can record exactly which file was used
%               without reconstructing the path themselves.

if sourceNum == 4
    error('loadVIPLVideo:nirNotSupported', 'source4 is the VIPL-HR NIR camera, not RGB. This pipeline (extractROISignals.m onward) is RGB-only -- see docs/VIPL_DATA_FORMAT.md Section 3.');
end

if sourceNum ~= 1 && sourceNum ~= 2 && sourceNum ~= 3
    error('loadVIPLVideo:badSource', 'sourceNum must be 1, 2, or 3 (got %s). VIPL-HR only defines source1-source4, and source4 is NIR (rejected above).', num2str(sourceNum));
end

subjectFolder = ['p' num2str(subjectNum)];
scenarioFolder = ['v' num2str(scenarioNum)];
sourceFolder = ['source' num2str(sourceNum)];

videoPath = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder, 'video.avi');

if ~isfile(videoPath)
    error('loadVIPLVideo:fileNotFound', 'Video file not found: %s', videoPath);
end

frames = VideoReader(videoPath);
containerFrameRate = frames.FrameRate;
numFrames = frames.NumFrames;

timePath = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder, 'time.txt');

if isfile(timePath)
    frameTimestampsMs = readmatrix(timePath, 'FileType', 'text');
    numTimestamps = numel(frameTimestampsMs);

    if numTimestamps >= 2
        elapsedSec = (frameTimestampsMs(numTimestamps) - frameTimestampsMs(1)) / 1000;
        timestampFrameRate = (numTimestamps - 1) / elapsedSec;

        relativeDiff = abs(timestampFrameRate - containerFrameRate) / containerFrameRate;

        if relativeDiff > 0.05
            disp(['loadVIPLVideo: WARNING -- container FrameRate (' num2str(containerFrameRate) ' fps) disagrees with time.txt-derived FrameRate (' num2str(timestampFrameRate) ' fps) by ' num2str(100 * relativeDiff) '% for ' videoPath '. Using the time.txt-derived value -- see docs/VIPL_DATA_FORMAT.md Section 4.']);
        end

        frameRate = timestampFrameRate;
    else
        disp(['loadVIPLVideo: time.txt found but has fewer than 2 timestamps, falling back to container FrameRate for ' videoPath]);
        frameRate = containerFrameRate;
    end
else
    disp(['loadVIPLVideo: no time.txt for source' num2str(sourceNum) ' (' videoPath '), using container FrameRate = ' num2str(containerFrameRate) ' fps -- see docs/VIPL_DATA_FORMAT.md Section 4 for why this is a known accuracy limitation for source2.']);
    frameRate = containerFrameRate;
end

end
