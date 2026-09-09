function [sigFiltered, f0Hz, harmonicsUsedHz] = adaptiveHarmonicFilter(sigDetrended, frameRate, numHarmonics, f0HzOverride)
% ADAPTIVEHARMONICFILTER Harmonic-comb filter: keep only narrow bins
% around the cardiac fundamental and its harmonics, zero everything else,
% IFFT back.
%
% Pipeline stage: Segment 7 Task B, Action 5 branch-2 (NEW, additive --
% implemented ONLY because the branch-2 condition fired: ground truth
% showed a reliable notch on this project's UBFC pool but our rPPG did
% not, per docs/Segment7_Task_B_Notch_Quantification.md's decision-gate
% section). Does not modify morphology/bandpassMorphology.m or
% morphology/ensembleAverageBeats.m, per the handoff's explicit
% instruction.
%
% Reference: Moco AV, Stuijk S, de Haan G. "Motion robust PPG-imaging
% through color channel mapping." (See also their broader harmonic-comb
% filtering work published as Sci Rep 8:8501, 2018.) A flat Butterworth
% bandpass (morphology/bandpassMorphology.m's approach) passes ALL
% energy between its two cutoffs, including inter-harmonic noise that
% carries no cardiac information; a harmonic comb instead keeps ONLY
% narrow windows around the fundamental f0 and each of its harmonics
% (2*f0, 3*f0, ...), rejecting inter-harmonic noise without attenuating
% any harmonic content the way a wide flat passband's rolloff eventually
% would.
%
% Method: f0 is estimated by reusing heartrate/fftHeartRate.m
% (unmodified) on sigDetrended -- i.e. the SAME robust, already-validated
% band-restricted FFT peak-pick this project's whole HR path relies on,
% rather than a second, independent f0 estimator. The full (two-sided)
% FFT of sigDetrended is then masked to keep only the 3 bins (+/- 1 bin
% around the nearest bin) surrounding each harmonic h*f0 for
% h = 1..numHarmonics, mirrored onto the conjugate-symmetric negative-
% frequency side so the inverse FFT is real-valued by construction (not
% via ifft's 'symmetric' rounding option, which only cleans up numerical
% noise -- it does not mirror an incomplete one-sided mask into a valid
% two-sided spectrum). Harmonics above the Nyquist frequency are simply
% skipped (there is nothing to keep).
%
% Inputs:
%   sigDetrended - 1 x N vector, a detrended signal (e.g.
%                  filtering/detrendSignal.m's output on a single R/G/B
%                  channel, the same input morphology/bandpassMorphology.m
%                  itself takes).
%   frameRate    - scalar, Hz, sampling rate of sigDetrended.
%   numHarmonics - (optional) scalar, how many harmonics (including the
%                  fundamental, h=1) to keep. Defaults to 6 (f0 through
%                  6*f0), matching the Segment 7 Task B handoff's
%                  explicit instruction.
%   f0HzOverride - (optional) scalar, Hz. If supplied (non-empty), skips
%                  the internal heartrate/fftHeartRate.m estimation and
%                  uses this value as f0 instead. Added so a caller
%                  filtering R/G/B independently (e.g.
%                  scripts/run_segment7_task_b_branch2_batch.m) can force
%                  all three channels onto the SAME shared f0 (estimated
%                  once, from the combined CHROM pulse) rather than let
%                  each channel's own noise shift its own f0 estimate
%                  slightly, which would re-introduce a cross-channel
%                  misalignment this whole task is trying to remove.
%
% Outputs:
%   sigFiltered     - 1 x N vector, real-valued, the harmonic-comb-
%                     filtered signal.
%   f0Hz            - scalar, the estimated cardiac fundamental (Hz),
%                     from heartrate/fftHeartRate.m's bpm output / 60.
%   harmonicsUsedHz - vector, the h*f0Hz harmonic frequencies that
%                     actually fell within the Nyquist limit and were
%                     kept (shorter than numHarmonics if some harmonics
%                     exceeded Nyquist).

if nargin < 3 || isempty(numHarmonics)
    numHarmonics = 6;
end

if nargin < 4
    f0HzOverride = [];
end

sigRow = sigDetrended(:)';
N = numel(sigRow);

if isempty(f0HzOverride)
    hrBpm = fftHeartRate(sigRow, frameRate);
    f0Hz = hrBpm / 60;
else
    f0Hz = f0HzOverride;
end

freqResolution = frameRate / N;
nyquistBinIdx = floor(N / 2) + 1; % 1-based index of the Nyquist (or highest positive-freq) bin

fullFFT = fft(sigRow);
mask = zeros(1, N);
harmonicsUsedHz = [];

for h = 1:numHarmonics
    harmonicFreqHz = h * f0Hz;
    centerBinIdx = round(harmonicFreqHz / freqResolution) + 1; % +1 for 1-based indexing, bin 1 = DC

    if centerBinIdx > nyquistBinIdx
        continue % this harmonic and all higher ones are above Nyquist
    end

    harmonicsUsedHz(end + 1) = harmonicFreqHz; %#ok<AGROW>

    for offset = -1:1
        binIdx = centerBinIdx + offset;
        if binIdx < 2 || binIdx > nyquistBinIdx
            continue % skip DC (bin 1) and anything past Nyquist
        end
        mask(binIdx) = 1;
        mirrorBinIdx = N - binIdx + 2;
        if mirrorBinIdx >= 1 && mirrorBinIdx <= N
            mask(mirrorBinIdx) = 1;
        end
    end
end

filteredFFT = fullFFT .* mask;
sigFiltered = real(ifft(filteredFFT));

end
