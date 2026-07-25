function pulseSignal = posCombine(R, G, B, frameRate)
% POSCOMBINE Combine filtered R/G/B channels into a pulse signal via POS.
%
% Pipeline stage: Stage 3 (motion-robust pulse extraction) — implements
% the published POS algorithm (Wang et al., 2017, "Algorithmic Principles
% of Remote PPG") as an alternative to naive single-channel averaging and
% to CHROM (pulseextraction/chromCombine.m). Output feeds Stage 4
% (FFT -> HR).
%
% Inputs:
%   R, G, B   - 1 x N vectors, filtered (detrended + bandpassed) color
%               channel signals from filtering/bandpassClean.m.
%   frameRate - scalar, sampling rate in Hz (POS operates on a sliding
%               window sized in samples, derived from frame rate).
%
% Outputs:
%   pulseSignal - 1 x N vector, the combined POS-based pulse signal.

error('Not implemented yet — see docs/');

end
