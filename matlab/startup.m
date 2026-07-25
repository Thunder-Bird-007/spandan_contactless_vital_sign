% STARTUP Add all Spandan src/ subfolders to the MATLAB path.
%
% Run this once per MATLAB session before using anything under src/, or
% add it to MATLAB's own startup.m so it runs automatically. This file
% only manages the path — it does not call any pipeline code.

thisFileDir = fileparts(mfilename('fullpath'));
srcRoot = fullfile(thisFileDir, 'src');

addpath(genpath(srcRoot));

fprintf('Spandan: added %s (and subfolders) to the MATLAB path.\n', srcRoot);
