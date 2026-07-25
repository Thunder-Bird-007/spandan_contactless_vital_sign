function pulseSignal = chromCombine(R, G, B)
% CHROMCOMBINE Combine filtered R/G/B channels into a pulse signal via CHROM.
%
% Pipeline stage: Stage 3 (motion-robust pulse extraction) — implements
% the published CHROM algorithm (de Haan & Jeanne, 2013) as an alternative
% to naive single-channel averaging. Output feeds Stage 4 (FFT -> HR).
%
% Inputs:
%   R, G, B - 1 x N vectors, filtered (detrended + bandpassed) color
%             channel signals from filtering/bandpassClean.m.
%
% Outputs:
%   pulseSignal - 1 x N vector, the combined chrominance-based pulse
%                 signal.

error('Not implemented yet — see docs/');

end
