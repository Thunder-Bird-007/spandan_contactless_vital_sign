function [sigFiltered, filterOrder, bandUsed] = bandpassMorphology(sigDetrended, frameRate, bandMode)
% BANDPASSMORPHOLOGY Wider bandpass filter for rPPG WAVEFORM MORPHOLOGY,
% as opposed to filtering/bandpassClean.m which is tuned for HR detection.
%
% Pipeline stage: Segment 7 Task A, Action 1 (NEW, additive) — this is a
% brand new file, not a modification to filtering/bandpassClean.m.
% bandpassClean.m stays byte-for-byte untouched and every existing HR
% script that calls it is unaffected. See
% docs/Segment7_Task_A_Morphology_Pipeline.md for the full diagnosis this
% was written for.
%
% WHY THIS FILE EXISTS: filtering/bandpassClean.m uses a 0.7-4.0 Hz
% passband. That band is correct for HR detection (the fundamental
% cardiac frequency H1 always falls inside it, which is all
% heartrate/fftHeartRate.m needs), but the dicrotic notch is carried by
% the 3rd-5th cardiac harmonics, not H1. At 100 bpm (f0 = 1.67 Hz), a
% 4.0 Hz cutoff keeps ONLY H1 (1.67 Hz) and H2 (3.33 Hz) — by definition
% a near-sinusoid, with no notch. Most UBFC subjects sit at 90-115 bpm,
% so this is the majority case, not an edge case. filtfilt gives zero
% PHASE distortion, not zero AMPLITUDE distortion: energy in the
% stopband above 4 Hz is attenuated and effectively gone, not just
% delayed, so this is not something a later processing stage can undo.
%
% Inputs:
%   sigDetrended - 1 x N vector, output of filtering/detrendSignal.m
%                  (same input filtering/bandpassClean.m itself takes).
%   frameRate    - scalar, sampling rate of the signal in Hz (the video
%                  frame rate — must NOT be hardcoded, see
%                  docs/DATA_FORMAT.md).
%   bandMode     - (optional) string/char, one of:
%                    'wide'   - 0.5-8.0 Hz. DEFAULT. Retains H2 and H3
%                               across the full 60-180 bpm physiological
%                               range (f0 up to 3.0 Hz, so H3 = 9.0 Hz
%                               at the very top of that range is already
%                               starting to roll off at an 8 Hz cutoff —
%                               deliberately biased toward "keep enough
%                               harmonic content for the notch" over
%                               "keep every harmonic at every possible
%                               HR", since UBFC subjects in this project
%                               are observed to sit at 90-115 bpm, not
%                               180 bpm). See arXiv:2606.03802 for the
%                               harmonic-retention justification.
%                    'mid'    - 0.6-6.0 Hz. Less aggressive than 'wide';
%                               the setting used on real patients by
%                               Klibus et al. Try this if 'wide' turns
%                               out too noisy on a given subject/dataset.
%                    'legacy' - 0.7-4.0 Hz, i.e. exactly
%                               filtering/bandpassClean.m's band,
%                               reproduced here ONLY so
%                               scripts/run_segment7_morphology_batch.m's
%                               ablation (Action 6) can include the
%                               current HR-path behaviour as one of the
%                               four compared conditions. This is NOT
%                               the default and is not meant to be used
%                               as a substitute for bandpassClean.m
%                               anywhere in the HR path.
%                  Defaults to 'wide'.
%
% Outputs:
%   sigFiltered - 1 x N vector, bandpassed signal.
%   filterOrder - scalar, the Butterworth order passed to butter() for
%                 all three bandMode values (3, per the Segment 7 Task A
%                 brief — one order higher than bandpassClean.m's order
%                 2, for a sharper rolloff at whichever band edge is
%                 chosen).
%   bandUsed    - 1 x 2 vector, [lowCutoffHz, highCutoffHz] actually
%                 used, returned so callers such as
%                 scripts/run_segment7_morphology_batch.m can label
%                 plots/metrics without hardcoding the band values a
%                 second time.

if nargin < 3 || isempty(bandMode)
    bandMode = 'wide';
end

switch bandMode
    case 'wide'
        lowCutoffHz = 0.5;
        highCutoffHz = 8.0;
    case 'mid'
        lowCutoffHz = 0.6;
        highCutoffHz = 6.0;
    case 'legacy'
        lowCutoffHz = 0.7;
        highCutoffHz = 4.0;
    otherwise
        error('bandpassMorphology:badBandMode', 'bandMode must be one of ''wide'', ''mid'', ''legacy'' (got %s).', bandMode);
end

filterOrder = 3;
nyquistHz = frameRate / 2;

if highCutoffHz >= nyquistHz
    error('bandpassMorphology:cutoffAboveNyquist', 'highCutoffHz (%.2f Hz) for bandMode ''%s'' is at or above the Nyquist frequency (%.2f Hz) for frameRate %.2f Hz.', highCutoffHz, bandMode, nyquistHz, frameRate);
end

lowCutoffNormalized = lowCutoffHz / nyquistHz;
highCutoffNormalized = highCutoffHz / nyquistHz;

[filterCoeffB, filterCoeffA] = butter(filterOrder, [lowCutoffNormalized, highCutoffNormalized], 'bandpass');
sigFiltered = filtfilt(filterCoeffB, filterCoeffA, sigDetrended);

bandUsed = [lowCutoffHz, highCutoffHz];

end
