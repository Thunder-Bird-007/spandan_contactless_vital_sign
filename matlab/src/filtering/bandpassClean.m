function signalFiltered = bandpassClean(signalDetrended, frameRate)
% BANDPASSCLEAN Bandpass-filter a detrended signal to the physiological HR band.
%
% Pipeline stage: Stage 2 (detrend + bandpass filter) — runs after
% detrendSignal.m to isolate the 0.7-4 Hz band (42-240 bpm) that contains
% the cardiac pulse, ahead of Stage 3 (CHROM/POS combination).
%
% Inputs:
%   signalDetrended - 1 x N vector, output of filtering/detrendSignal.m.
%   frameRate       - scalar, sampling rate of the signal in Hz (i.e. the
%                     video frame rate — must NOT be hardcoded, see
%                     docs/DATA_FORMAT.md).
%
% Outputs:
%   signalFiltered - 1 x N vector, bandpassed to approximately 0.7-4 Hz.

error('Not implemented yet — see docs/');

end
