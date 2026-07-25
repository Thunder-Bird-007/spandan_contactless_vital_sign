function [R, G, B, roiTimestamps] = extractROISignals(frames, frameRate)
% EXTRACTROISIGNALS Detect face, crop forehead/cheek ROI, average per-frame.
%
% Pipeline stage: Stage 1 (face detection + ROI signal extraction) — turns
% a raw video into three 1-D raw color-channel traces R(t), G(t), B(t).
% These feed Stage 2 (filtering/detrending) and then Stage 3 (CHROM/POS
% combination).
%
% Inputs:
%   frames    - loaded video frames, as produced by io/loadUBFCVideo.m.
%   frameRate - scalar, frames per second (from loadUBFCVideo.m — needed
%               to build roiTimestamps).
%
% Outputs:
%   R, G, B       - 1 x numFrames vectors, the spatial average pixel
%                   intensity of the chosen ROI (forehead/cheek skin
%                   patch) for each color channel, one value per frame.
%   roiTimestamps - 1 x numFrames vector, seconds, frame acquisition time
%                   (used later to align against ground-truth timestamps).

error('Not implemented yet — see docs/');

end
