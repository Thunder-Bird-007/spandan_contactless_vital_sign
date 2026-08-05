function [frames, frameRate, numFrames] = loadUBFCVideo(videoPath)
% LOADUBFCVIDEO Load a UBFC-rPPG subject video into memory.
%
% Pipeline stage: Stage 1 (input) — reads the raw facial video that all
% later stages (ROI extraction, filtering, pulse extraction, HR/SpO2
% estimation) operate on.
%
% Inputs:
%   videoPath - string/char, full path to a subject's .avi file. Note
%               DATASET_1 and DATASET_2 subjects do not share a fixed
%               filename (see docs/DATA_FORMAT.md) — caller is
%               responsible for locating the file first.
%
% Outputs:
%   frames    - a VideoReader object opened on videoPath. Frames are NOT
%               preloaded into memory here — these are large uncompressed
%               AVIs (over a gigabyte for some DATASET_2 subjects), so
%               loading every frame up front would exhaust RAM. Callers
%               stream frames one at a time with hasFrame()/readFrame(),
%               exactly as roi/extractROISignals.m does.
%   frameRate - scalar, frames per second, read from the file itself
%               (do NOT hardcode 30 fps — see docs/DATA_FORMAT.md, actual
%               UBFC videos run ~28.6-29.8 fps and vary per subject).
%   numFrames - scalar, total number of frames in the video.

if ~isfile(videoPath)
    error('loadUBFCVideo:fileNotFound', 'Video file not found: %s', videoPath);
end

frames = VideoReader(videoPath);
frameRate = frames.FrameRate;
numFrames = frames.NumFrames;

end
