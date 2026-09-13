function [sigFiltered, f0Hz, harmonicsUsedHz] = harmonicSelectiveGaussianFilter(sigDetrended, frameRate, numHarmonics, f0HzOverride, alpha)
% HARMONICSELECTIVEGAUSSIANFILTER Harmonic filter with Gaussian-tapered
% (not hard-edged) passbands centered on the cardiac fundamental and its
% harmonics, bandwidth scaled to f0.
%
% Pipeline stage: Segment 12 Task 2 (NEW, additive) -- a GATED,
% OFF-BY-DEFAULT alternative to morphology/adaptiveHarmonicFilter.m's
% hard-edged rectangular comb. Does NOT modify adaptiveHarmonicFilter.m or
% any of its call sites (pipeline/estimateVitalsAndMorphology.m,
% scripts/run_segment10_waveform_fidelity_audit.m, etc.) -- this is a
% parallel, drop-in-signature-compatible function a caller can choose to
% call INSTEAD, never called by any existing production script itself.
%
% Reference: Dominguez-Hernandez, S., Paez, G. & Padilla, M. (2026).
% "Harmonic-Selective Gaussian Filtering for Morphology and Timing
% Preservation in PPG Signals." Sensors 26(12):3710,
% doi:10.3390/s26123710 (PMC13307314). Full text retrieved and read this
% session (2026-09-13) for this implementation -- not from the
% Segment10_Task2_Solution_Literature_Search.md summary alone.
%
% WHY: adaptiveHarmonicFilter.m's rectangular 3-bin mask around each
% harmonic rings in the time domain (a hard frequency-domain edge is a
% textbook cause of Gibbs-phenomenon ringing after the inverse transform)
% -- a candidate explanation for part of Segment 10 Task 1 finding (4)
% (40-47% of subjects show real phase/shape distortion surviving lag
% removal), which this project's own harmonic-comb branch was found to
% suffer from more than the narrow-band branches (Task 1 finding 3: 4-5x
% higher harmonic-confusion rate). A Gaussian-tapered passband has no hard
% edge, so its impulse response decays smoothly instead of ringing.
%
% METHOD (the paper's own Eq. 4/5/7/8, read from the primary source, not
% paraphrased from a secondary summary):
%   Per-harmonic filter (Eq. 4, extended to a full magnitude mask over the
%   FFT's own frequency axis, not just algebraically near +f0):
%     G_h(f) = exp(-(f - h*f0)^2 / sigma^2) + exp(-(f + h*f0)^2 / sigma^2)
%   Composite filter across all requested harmonics (Eq. 5, k ranges over
%   both positive and negative harmonic indices -- the "+h*f0" mirror term
%   above already realizes that symmetric sum for a two-sided FFT axis
%   without a separate manual mirroring step):
%     H(f) = sum_{h=1}^{numHarmonics} G_h(f)
%   Bandwidth (the paper's own stated parameter, Eq. 6): sigma = alpha*f0.
%   THE PAPER'S OWN VALUE: alpha = 1/2 (sigma = f0/2), described by its
%   authors as "a practical compromise" rather than a universal optimum --
%   used here as this function's default, not a value this project
%   invented. The paper's own -3dB cutoff: f_(low,high) = +/- alpha*f0*
%   sqrt(ln(sqrt(2))), stated for reference in this header but not needed
%   by the implementation below (which applies the continuous Gaussian
%   directly to every discrete FFT bin frequency, rather than computing an
%   explicit passband edge).
%   Filtering (Eq. 7): S_filtered(f) = S(f) .* H(f), applied to the FULL
%   (two-sided) FFT of sigDetrended -- H(f) is already symmetric by
%   construction (the +h*f0/-h*f0 mirror terms), so the result is
%   automatically conjugate-symmetric and the inverse FFT is real-valued
%   by construction, the same real-by-construction guarantee
%   adaptiveHarmonicFilter.m's manual bin-mirroring achieves a different
%   way.
%   Reconstruction (Eq. 8): sigFiltered = real(ifft(S_filtered)).
%   NUMBER OF HARMONICS: the paper examined N in {3,4,5} for morphology
%   preservation (up to N=10 with diminishing returns). This function
%   DEFAULTS to 6 instead, matching adaptiveHarmonicFilter.m's own default
%   -- a deliberate choice so a head-to-head comparison (Segment 12 Task 2)
%   isolates the Gaussian-vs-rectangular shape difference alone, without
%   also changing the harmonic count. Callers wanting the paper's own
%   recommended N should pass numHarmonics explicitly.
%
% f0 estimation, override, and the mirrored-negative-frequency handling
% otherwise follow morphology/adaptiveHarmonicFilter.m's own conventions
% exactly (same heartrate/fftHeartRate.m call, same f0HzOverride
% parameter for a caller-forced shared f0 across channels), so the two
% functions are drop-in interchangeable at any existing call site.
%
% Inputs:
%   sigDetrended - 1 x N vector, a detrended signal (same input
%                  morphology/adaptiveHarmonicFilter.m and
%                  morphology/bandpassMorphology.m themselves take).
%   frameRate    - scalar, Hz, sampling rate of sigDetrended.
%   numHarmonics - (optional) scalar, how many harmonics (h=1..numHarmonics)
%                  to include. Defaults to 6 -- see the NUMBER OF HARMONICS
%                  note above for why this differs from the paper's own
%                  examined range.
%   f0HzOverride - (optional) scalar, Hz. If supplied (non-empty), skips
%                  the internal heartrate/fftHeartRate.m estimation and
%                  uses this value as f0 instead -- same purpose as
%                  adaptiveHarmonicFilter.m's own argument of the same
%                  name (force all three R/G/B channels onto one shared f0
%                  estimated once from the combined pulse).
%   alpha        - (optional) scalar, the sigma=alpha*f0 bandwidth
%                  scaling factor. Defaults to 0.5, the paper's own value.
%                  Exposed as a parameter (not hardcoded) since the paper
%                  itself calls its own choice "a practical compromise,"
%                  not a proven optimum -- a future sensitivity sweep over
%                  this parameter is a natural, NOT-yet-attempted next
%                  step, stated explicitly rather than silently implied
%                  the default is the only reasonable value.
%
% Outputs:
%   sigFiltered     - 1 x N vector, real-valued, the Gaussian-harmonic-
%                     filtered signal.
%   f0Hz            - scalar, the estimated (or overridden) cardiac
%                     fundamental (Hz) actually used.
%   harmonicsUsedHz - vector, the h*f0Hz harmonic CENTER frequencies that
%                     fall at or below the Nyquist frequency -- reported
%                     using the same convention
%                     adaptiveHarmonicFilter.m uses for its own
%                     harmonicsUsedHz output, for direct side-by-side
%                     comparison. Unlike the hard comb, a harmonic whose
%                     CENTER lies just above this cutoff can still leak a
%                     small, smoothly-tapered amount of energy into valid
%                     sub-Nyquist bins here (by construction -- the
%                     Gaussian has no hard edge); harmonicsUsedHz reports
%                     only the in-band-center convention, not literal
%                     nonzero-contribution, and this distinction is stated
%                     here rather than left implicit.

if nargin < 3 || isempty(numHarmonics)
    numHarmonics = 6;
end

if nargin < 4
    f0HzOverride = [];
end

if nargin < 5 || isempty(alpha)
    alpha = 0.5; % the paper's own value (sigma = f0/2), see header
end

sigRow = sigDetrended(:)';
N = numel(sigRow);

if isempty(f0HzOverride)
    hrBpm = fftHeartRate(sigRow, frameRate);
    f0Hz = hrBpm / 60;
else
    f0Hz = f0HzOverride;
end

sigma = alpha * f0Hz;
if sigma <= 0
    error('harmonicSelectiveGaussianFilter:badSigma', 'alpha*f0Hz must be positive (got alpha=%.4g, f0Hz=%.4g).', alpha, f0Hz);
end

freqResolution = frameRate / N;
nyquistHz = frameRate / 2;

% Standard FFT bin-to-frequency mapping (1-based indexing): bin 1 = DC,
% bins 2..floor(N/2)+1 are positive frequencies up to (or just past)
% Nyquist, and the remaining bins are the negative-frequency mirror --
% built directly as signed frequencies so the Gaussian mask's "+h*f0"
% mirror term (Eq. 4/5) applies correctly on both sides in one pass.
binIdx = (0:N - 1);
freqAxis = binIdx * freqResolution;
freqAxis(freqAxis > nyquistHz) = freqAxis(freqAxis > nyquistHz) - frameRate; % fold upper half to negative freq

mask = zeros(1, N);
harmonicsUsedHz = [];

for h = 1:numHarmonics
    harmonicFreqHz = h * f0Hz;
    if harmonicFreqHz <= nyquistHz
        harmonicsUsedHz(end + 1) = harmonicFreqHz; %#ok<AGROW>
    end
    mask = mask + exp(-((freqAxis - harmonicFreqHz) .^ 2) / (sigma ^ 2)) ...
                + exp(-((freqAxis + harmonicFreqHz) .^ 2) / (sigma ^ 2));
end

fullFFT = fft(sigRow);
filteredFFT = fullFFT .* mask;
sigFiltered = real(ifft(filteredFFT));

end
