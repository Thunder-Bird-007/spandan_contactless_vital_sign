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
%                 output), or a single filtered color channel.
%   frameRate   - scalar, sampling rate in Hz.
%
% Outputs:
%   hrBpm         - scalar, estimated heart rate in beats per minute.
%   freqSpectrum  - vector, frequency axis (Hz) of the FULL positive-half
%                   spectrum, 0 to Nyquist (not restricted to the 0.7-4 Hz
%                   search band), so callers can plot a wider view for
%                   sanity-checking.
%   powerSpectrum - vector, FFT MAGNITUDE (not squared power) at each
%                   frequency in freqSpectrum, for plotting/debugging.

signalLength = length(pulseSignal);
fftResult = fft(pulseSignal);

numPositiveBins = floor(signalLength / 2) + 1;
fftPositive = fftResult(1:numPositiveBins);

freqResolution = frameRate / signalLength;
freqSpectrum = (0:numPositiveBins - 1) * freqResolution;
powerSpectrum = abs(fftPositive);

lowBandHz = 0.7;
highBandHz = 4.0;
bandMask = freqSpectrum >= lowBandHz & freqSpectrum <= highBandHz;

freqInBand = freqSpectrum(bandMask);
powerInBand = powerSpectrum(bandMask);

if isempty(freqInBand)
    error('fftHeartRate:emptyBand', 'No FFT bins fall inside the 0.7-4 Hz band — signal too short for the given frameRate.');
end

peakPower = max(powerInBand);
peakIndex = find(powerInBand == peakPower, 1);
peakFreqHz = freqInBand(peakIndex);

hrBpm = peakFreqHz * 60;

end
