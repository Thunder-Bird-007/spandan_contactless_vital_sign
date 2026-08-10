function R = ratioOfRatios(R_filtered, G_filtered, B_filtered, R_raw, G_raw, B_raw, fs)
% RATIOOFRATIOS Compute the AC/DC ratio-of-ratios (R) for SpO2 estimation.
%
% Pipeline stage: Stage 5 (SpO2 estimation) — extracts AC (pulsatile) and
% DC (baseline) components from the Red and Blue channel signals and
% computes the classic ratio-of-ratios R = (AC_red/DC_red) /
% (AC_blue/DC_blue). Camera has no infrared channel, so Blue substitutes
% for Infrared (a published, known approximation). Output feeds
% spo2/calibrateSpO2.m to map R -> SpO2%.
%
% Unlike the original 2-argument stub (redSignal, blueSignal), this needs
% BOTH the raw and the filtered trace for each channel: DC is the
% steady-state brightness level, which only the raw (pre-filter) trace
% still carries — a bandpass filter's whole point is to remove the 0 Hz
% component, so mean(filtered) is not a usable DC value. See
% segment5_spo2/Segment5_LineByLine_Explanation.md for the full reasoning
% (same judgment call already documented for chromCombine.m/posCombine.m
% in Segment 4).
%
% Inputs:
%   R_filtered, G_filtered, B_filtered - 1 x N vectors, bandpass-filtered
%                     color channel traces (filtering/bandpassClean.m
%                     output, i.e. data/processed/<subjectID>_filtered_
%                     traces.mat). Used for AC (pulsatile amplitude).
%   R_raw, G_raw, B_raw - 1 x N vectors, RAW (pre-detrend, pre-filter)
%                     color channel traces (roi/extractROISignals.m
%                     output, i.e. data/processed/<subjectID>_rgb_
%                     traces.mat). Used for DC (steady background level).
%   fs                - scalar, sampling rate in Hz. This function
%                     computes a single whole-clip AC/DC ratio (see the
%                     explanation doc for why that is the right
%                     granularity here), so fs is not used by the current
%                     formula — accepted only for signature consistency
%                     with the rest of this segment's data-loading
%                     pattern and a possible future sliding-window
%                     version, same reasoning as posCombine.m's frameRate
%                     argument in Segment 4.
%
% Outputs:
%   R - scalar, the ratio-of-ratios value for this subject's whole clip.

DC_R = mean(R_raw);
DC_B = mean(B_raw);

AC_R = std(R_filtered);
AC_B = std(B_filtered);

R = (AC_R / DC_R) / (AC_B / DC_B);

end
