function [sigAligned, gtAligned, timeAligned, lagSec, lagSamples, wasFlipped, maxAbsCorr, targetFsUsed] = estimateLagPolarityByGroundTruth(sig, sigTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec)
% ESTIMATELAGPOLARITYBYGROUNDTRUTH Extend morphology/fixPolarityByGroundTruth.m's
% cross-correlation approach to solve for the best time LAG between an
% rPPG pulse signal and its ground-truth contact-PPG, not just the
% polarity (sign) that function already handles.
%
% Pipeline stage: Segment 10 Task 1 (NEW, additive) -- does NOT modify
% morphology/fixPolarityByGroundTruth.m, which stays the production
% polarity-only fix used everywhere else in this project
% (pipeline/estimateVitalsAndMorphology.m, Task K's batch script, etc.).
% This function exists only for this task's read-only waveform-fidelity
% audit, which needs the actual estimated lag reported per subject (not
% just silently corrected for), per the task brief.
%
% METHOD: both sig and gtPPG are first resampled (morphology/resampleUniform.m,
% unmodified, 'pchip') onto their OWN uniform grids at targetFs, using each
% signal's own real timestamps -- same discipline as
% morphology/resampleUniform.m's own header. Both uniform grids are then
% re-interpolated onto ONE common time axis spanning their overlap (pchip
% again, since the two grids are not guaranteed to share a phase origin),
% zero-meaned, and cross-correlated (xcorr) over +/- maxLagSec. Unlike
% fixPolarityByGroundTruth.m (which only compares xcorr(sig,gt) against
% xcorr(-sig,gt) at their own respective peak lags and keeps whichever
% sign scores higher), this function finds the single (lag, sign) pair
% that maximizes |xcorr| jointly across the full searched lag range --
% i.e. it solves for both unknowns at once, of which polarity-only is a
% special case (lag fixed at the xcorr peak's own natural lag=0
% neighborhood).
%
% SIGN CONVENTION (verified empirically against a synthetic delayed sine
% before writing this function -- see the Segment 10 audit doc's Method
% section): if x(n) = y(n - d) for d > 0 (x is a delayed copy of y), then
% argmax(xcorr(x, y, maxlag)) occurs at lag = +d. So a positive lagSec
% here means sig is DELAYED relative to gtPPG (sig's features appear
% lagSec seconds later than the matching gtPPG feature). To align, sig is
% shifted EARLIER by lagSec (equivalently: sig's future samples are
% pulled back to line up with gt's current samples).
%
% ALIGNMENT: because sigCommon/gtCommon share one uniform grid at
% targetFs, an integer-sample lag can be applied by exact index shift (no
% further interpolation, hence no additional smoothing/blurring of the
% comparison) -- lagSamples = round(lagSec*targetFs) samples are trimmed
% from the appropriate end of each signal so the two returned vectors are
% already time-registered, equal length, and polarity-corrected.
%
% Inputs:
%   sig           - 1 x N vector, a pulse signal (e.g. a CHROM/POS/
%                   harmonic-comb combiner's output).
%   sigTimestamps - 1 x N vector, seconds, sig's own real per-sample
%                   acquisition times (roi/extractROISignals.m's
%                   roiTimestamps convention).
%   gtPPG         - vector, ground-truth contact-PPG waveform (io/loadGroundTruth.m's
%                   gt.ppg, or io/loadVIPLGroundTruth.m's gt.ppg).
%   gtTimestamps  - vector, seconds, matching gtPPG (real per-sample
%                   timestamps for UBFC; an assumed-uniform axis at the
%                   sensor's nominal rate for VIPL, same convention Task K
%                   used -- see this task's own doc for why that does not
%                   bias the shape/lag comparison).
%   targetFs      - (optional) scalar, Hz, the common uniform grid rate.
%                   Default 250, matching morphology/resampleUniform.m's
%                   own default.
%   maxLagSec     - (optional) scalar, seconds, search range +/- this much.
%                   Default 5 -- generous enough to surface a genuinely
%                   large misalignment (multiple cardiac cycles) rather
%                   than silently clip the search to "only ever look
%                   plausible", at the cost of a real risk of periodic
%                   aliasing onto the wrong cycle for a strongly
%                   quasi-periodic signal -- stated explicitly here and in
%                   the audit doc, not hidden. This is exactly why the
%                   calling script flags (never silently drops) any
%                   |lagSec| that exceeds roughly one cardiac cycle at the
%                   subject's own f0.
%
% Outputs:
%   sigAligned   - 1 x M vector, sig polarity-corrected and lag-shifted
%                  onto the common targetFs grid, trimmed to the aligned
%                  overlap with gtAligned.
%   gtAligned    - 1 x M vector, gtPPG resampled onto the same common
%                  targetFs grid, trimmed to the same aligned overlap.
%   timeAligned  - 1 x M vector, seconds, the common time axis for both
%                  outputs above.
%   lagSec       - scalar, seconds, the estimated lag (see sign convention
%                  above). Positive = sig lags gtPPG.
%   lagSamples   - scalar, round(lagSec*targetFs) -- the integer sample
%                  shift actually applied.
%   wasFlipped   - logical scalar, true if sig was negated to match
%                  gtPPG's polarity.
%   maxAbsCorr   - scalar, the peak |xcorr| value achieved at
%                  (lagSamples, wasFlipped) -- returned so callers can
%                  sanity-check how sharply-defined the chosen lag is
%                  relative to its neighbors (a very flat xcorr surface
%                  around the peak is its own kind of caveat, e.g. for a
%                  near-sinusoidal signal with little harmonic content).
%   targetFsUsed - scalar, Hz, echoes targetFs (or its default).

if nargin < 5 || isempty(targetFs)
    targetFs = 250;
end

if nargin < 6 || isempty(maxLagSec)
    maxLagSec = 5;
end

sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';
gtPPGRow = gtPPG(:)';
gtTimestampsRow = gtTimestamps(:)';

[sigUniform, sigTimeUniform, ~] = resampleUniform(sigRow, sigTimestampsRow, targetFs);
[gtUniform, gtTimeUniform, ~] = resampleUniform(gtPPGRow, gtTimestampsRow, targetFs);

overlapLowSec = max(sigTimeUniform(1), gtTimeUniform(1));
overlapHighSec = min(sigTimeUniform(end), gtTimeUniform(end));

if overlapHighSec <= overlapLowSec
    error('estimateLagPolarityByGroundTruth:noOverlap', 'sigTimestamps and gtTimestamps do not overlap in time -- cannot align rPPG and ground-truth PPG.');
end

commonTime = overlapLowSec:(1 / targetFs):overlapHighSec;

sigCommon = interp1(sigTimeUniform, sigUniform, commonTime, 'pchip');
gtCommon = interp1(gtTimeUniform, gtUniform, commonTime, 'pchip');

sigZeroMean = sigCommon - mean(sigCommon);
gtZeroMean = gtCommon - mean(gtCommon);

maxLagSamplesSearch = round(maxLagSec * targetFs);
maxLagSamplesSearch = min(maxLagSamplesSearch, numel(commonTime) - 1);

crossCorr = xcorr(sigZeroMean, gtZeroMean, maxLagSamplesSearch);
lagsSearched = -maxLagSamplesSearch:maxLagSamplesSearch;

[maxAbsCorr, bestIdx] = max(abs(crossCorr));
lagSamples = lagsSearched(bestIdx);
wasFlipped = crossCorr(bestIdx) < 0;
lagSec = lagSamples / targetFs;

if lagSamples >= 0
    sigShifted = sigCommon(1 + lagSamples:end);
    gtShifted = gtCommon(1:end - lagSamples);
    timeAligned = commonTime(1:end - lagSamples);
else
    sigShifted = sigCommon(1:end + lagSamples);
    gtShifted = gtCommon(1 - lagSamples:end);
    timeAligned = commonTime(1:end + lagSamples);
end

if wasFlipped
    sigAligned = -sigShifted;
else
    sigAligned = sigShifted;
end

gtAligned = gtShifted;
targetFsUsed = targetFs;

end
