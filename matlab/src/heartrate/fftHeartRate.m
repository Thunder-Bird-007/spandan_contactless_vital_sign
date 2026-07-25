function [hrBpm, freqSpectrum, powerSpectrum] = fftHeartRate(pulseSignal, frameRate)
% FFTHEARTRATE Estimate heart rate from a pulse signal via FFT peak-picking.
%
% Pipeline stage: Stage 4 (FFT -> dominant frequency -> HR in bpm) — takes
% the combined pulse signal from Stage 3 (pulseextraction/chromCombine.m
% or posCombine.m) and finds the dominant frequency within the
% physiological band to report HR.
%
% Inputs:
%   pulseSignal - 1 x N vector, combined pulse signal (CHROM or POS
%                 output).
%   frameRate   - scalar, sampling rate in Hz.
%
% Outputs:
%   hrBpm         - scalar, estimated heart rate in beats per minute.
%   freqSpectrum  - vector, frequency axis (Hz) of the computed spectrum.
%   powerSpectrum - vector, power at each frequency in freqSpectrum (for
%                   plotting/debugging).

error('Not implemented yet — see docs/');

end
