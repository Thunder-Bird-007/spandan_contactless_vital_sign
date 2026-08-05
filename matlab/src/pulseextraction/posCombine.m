function pulseSignal = posCombine(R, G, B, frameRate, RRaw, GRaw, BRaw)
% POSCOMBINE Combine filtered R/G/B channels into a pulse signal via POS.
%
% Pipeline stage: Stage 3 (motion-robust pulse extraction) — implements
% the published POS algorithm (Wang et al., 2017, "Algorithmic Principles
% of Remote PPG") as an alternative to naive single-channel averaging and
% to CHROM (pulseextraction/chromCombine.m). Output feeds Stage 4
% (FFT -> HR).
%
% Inputs:
%   R, G, B         - 1 x N vectors, filtered (detrended + bandpassed)
%                      color channel signals from filtering/bandpassClean.m.
%   frameRate       - scalar, sampling rate in Hz. The published POS
%                      algorithm runs this combination over a short
%                      sliding window sized from frameRate. This
%                      project's Segment 4 brief specifies the simpler
%                      whole-signal formula below (matching CHROM's
%                      whole-signal approach) instead, so frameRate is
%                      accepted here for signature consistency and
%                      possible future windowed extension but is not
%                      used by the current formula — see
%                      segment4_heartrate/Segment4_LineByLine_Explanation.md.
%   RRaw, GRaw, BRaw - 1 x N vectors, the RAW (pre-detrend, pre-filter)
%                      color channel signals for the same subject. Used
%                      only for the CHROM/POS normalization mean — same
%                      reasoning as chromCombine.m.
%
% Outputs:
%   pulseSignal - 1 x N vector, the combined POS-based pulse signal.

meanRRaw = mean(RRaw);
meanGRaw = mean(GRaw);
meanBRaw = mean(BRaw);

Rn = R / meanRRaw;
Gn = G / meanGRaw;
Bn = B / meanBRaw;

S1 = Gn - Bn;
S2 = Gn + Bn - 2*Rn;

pulseSignal = S1 + (std(S1)/std(S2))*S2;

end
