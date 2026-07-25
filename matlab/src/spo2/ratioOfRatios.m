function R = ratioOfRatios(redSignal, blueSignal)
% RATIOOFRATIOS Compute the AC/DC ratio-of-ratios (R) for SpO2 estimation.
%
% Pipeline stage: Stage 5 (SpO2 estimation) — extracts AC (pulsatile) and
% DC (baseline) components from the Red and Blue channel signals and
% computes the classic ratio-of-ratios R = (AC_red/DC_red) /
% (AC_blue/DC_blue). Camera has no infrared channel, so Blue substitutes
% for Infrared (a published, known approximation). Output feeds
% spo2/calibrateSpO2.m to map R -> SpO2%.
%
% Inputs:
%   redSignal  - 1 x N vector, filtered Red channel signal.
%   blueSignal - 1 x N vector, filtered Blue channel signal (substituting
%                for Infrared).
%
% Outputs:
%   R - scalar, the ratio-of-ratios value for this window/recording.

error('Not implemented yet — see docs/');

end
