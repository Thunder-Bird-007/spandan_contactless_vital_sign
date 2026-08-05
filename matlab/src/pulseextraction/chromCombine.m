function pulseSignal = chromCombine(R, G, B, RRaw, GRaw, BRaw)
% CHROMCOMBINE Combine filtered R/G/B channels into a pulse signal via CHROM.
%
% Pipeline stage: Stage 3 (motion-robust pulse extraction) — implements
% the published CHROM algorithm (de Haan & Jeanne, 2013) as an alternative
% to naive single-channel averaging. Output feeds Stage 4 (FFT -> HR).
%
% Inputs:
%   R, G, B         - 1 x N vectors, filtered (detrended + bandpassed)
%                      color channel signals from filtering/bandpassClean.m.
%   RRaw, GRaw, BRaw - 1 x N vectors, the RAW (pre-detrend, pre-filter)
%                      color channel signals for the same subject, i.e.
%                      data/processed/<subjectID>_rgb_traces.mat's R, G, B.
%                      These are used only to compute each channel's own
%                      DC brightness level (its temporal mean) for the
%                      CHROM normalization step below. See
%                      segment4_heartrate/Segment4_LineByLine_Explanation.md
%                      for why this extra input was added on top of the
%                      original 3-argument stub — in short, R/G/B here are
%                      already bandpass-filtered and so have a mean very
%                      close to zero, which is unusable as a normalization
%                      denominator.
%
% Outputs:
%   pulseSignal - 1 x N vector, the combined chrominance-based pulse
%                 signal.

meanRRaw = mean(RRaw);
meanGRaw = mean(GRaw);
meanBRaw = mean(BRaw);

Rn = R / meanRRaw;
Gn = G / meanGRaw;
Bn = B / meanBRaw;

Xs = 3*Rn - 2*Gn;
Ys = 1.5*Rn + Gn - 1.5*Bn;

alpha = std(Xs) / std(Ys);

pulseSignal = Xs - alpha*Ys;

end
