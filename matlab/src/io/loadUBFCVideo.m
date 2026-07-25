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
%   frames    - the loaded video frames (format/shape TBD: e.g. H x W x 3
%               x numFrames uint8 array, or a VideoReader handle for
%               frame-by-frame streaming — decide based on memory limits).
%   frameRate - scalar, frames per second, read from the file itself
%               (do NOT hardcode 30 fps — see docs/DATA_FORMAT.md, actual
%               UBFC videos run ~28.6-29.8 fps and vary per subject).
%   numFrames - scalar, total number of frames in the video.

error('Not implemented yet — see docs/');

end
