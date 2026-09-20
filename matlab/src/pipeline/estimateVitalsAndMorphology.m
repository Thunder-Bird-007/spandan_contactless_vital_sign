function result = estimateVitalsAndMorphology(videoInput, groundTruth, calibParams, opts)
% ESTIMATEVITALSANDMORPHOLOGY Single entry point that runs BOTH the
% production HR/SpO2 branch and the morphology (notch) branch off ONE
% ROI extraction, for the Segment 7 Task F demo/report deliverable.
%
% Pipeline stage: Segment 7 Task F (NEW, additive) -- this file, not
% pipeline/estimateVitals.m, is the orchestrator used from this point on.
% pipeline/estimateVitals.m remains an unimplemented stub (`error('Not
% implemented yet')`) and is NEVER called or modified here -- see Segment
% 7 Task E's finding below for why a single shared filter choice was
% rejected in favor of two parallel branches.
%
% =====================================================================
% FIX, 2026-09-19 -- READ BEFORE ASSUMING THIS FUNCTION MATCHES OLDER
% DOCS/REGRESSION DATA BIT-FOR-BIT
% =====================================================================
% SESSION_HANDOFF.md's Segment 8 Action 7 documents DWT wavelet-shrinkage
% denoising (filtering/waveletDenoise.m) as "PROMOTED TO DEFAULT" for
% Branch 1, wired into scripts/run_segment3_filtering_batch.m and
% scripts/run_vipl_integration_batch.m (applied to each raw R/G/B channel
% immediately before filtering/detrendSignal.m, useWaveletDenoise toggle,
% default true) and into Android's RealHeartRateEstimator.kt. That
% promotion was NEVER actually ported into this shared orchestrator --
% the one function scripts/run_spandan_interactive.m and every other
% current call site actually uses -- so every caller of THIS function
% was silently running without wavelet denoising despite it being
% documented project-wide as the production default. This fix closes
% that gap: opts.useWaveletDenoise (default true, matching the batch
% scripts' own default) now applies filtering/waveletDenoise.m to R/G/B
% at the exact same position the validated batch scripts use --
% immediately before the detrendSignal.m call below, upstream of BOTH
% branches (this function only detrends once and both branches consume
% that single result, so wavelet denoising the shared input naturally
% flows into Branch 2 as well as Branch 1; only Branch 1 was ever
% ablated/validated against ground truth, so treat Branch 2's own
% distortion-vs-morphology tradeoff qhen wavelet denoising is active as
% UNVALIDATED, not assumed neutral or beneficial).
%
% SpO2 PIN, 2026-09-20: Branch 1's SpO2 path (ratioOfRatios ->
% calibrateSpO2) does NOT follow opts.useWaveletDenoise. Frozen
% segment5_dataset1_calibration.csv / segment5_vipl_calibration.csv R values
% (all 112 subjects) match the PRE-wavelet chain, and calibrateSpO2's fitted
% A/B were fit on those, so feeding it wavelet-shifted R would be a
% train/serve mismatch. SpO2 is therefore always computed from the
% pre-wavelet chain. Whether wavelet helps or hurts SpO2 is an OPEN,
% deferred question (see matlab/experiments/segment27_*).
%
% HR-GREEN NOTE: HR_green now follows the wavelet-on default. The old frozen
% GREEN column in segment6_hr_pooled_metrics.csv is a Segment 8 splice
% artifact (CHROM/POS spliced in wavelet-on; GREEN left pre-wavelet because
% the ablation never covered it) and is superseded, not because of a new bug.
%
% BEHAVIOR CHANGE A CALLER MUST KNOW ABOUT: exactly like
% scripts/run_vipl_integration_batch.m already does, R/G/B are
% REASSIGNED in place to their wavelet-denoised versions when
% opts.useWaveletDenoise is true (the default). That means
% result.R/result.G/result.B, and the "raw" arguments Branch 1 passes to
% chromCombine/posCombine/ratioOfRatios for DC normalization, are the
% WAVELET-DENOISED signal, not the literal pre-wavelet raw pixel means,
% whenever the default is left on. This exactly matches
% run_vipl_integration_batch.m's own already-validated convention (same
% reassignment, same downstream usage) -- it is not a new, separately
% invented behavior. A caller that specifically needs the literal
% pre-wavelet raw trace (e.g. an on-screen "Raw ROI trace" panel) must
% capture its own copy of R/G/B BEFORE calling this function.
%
% REGRESSION TEST IMPACT, FLAGGED NOT SILENTLY LEFT: this file's own
% header already documents that tests/segment7_task_f_regression_test.m
% requires this function's notch output to match
% results/metrics/segment7_task_b_notch_branch2.csv bit-for-bit, and that
% test already knows to pass opts.useConfidenceGate=false for its Part 3
% bit-exact check. That CSV predates this wavelet fix, so with
% useWaveletDenoise now defaulting to true, that regression test will
% start failing its bit-exact comparison unless it is updated to also
% pass opts.useWaveletDenoise=false (to reproduce pre-fix behavior) OR
% the recorded CSV is regenerated under the new default. This file does
% NOT touch that test or that CSV -- a human should decide which of the
% two is the right fix, same discipline as every other validated-result
% change in this project.
%
% WHY TWO BRANCHES OFF ONE EXTRACTION (Segment 7 Task E's decision):
% the filtering that helps notch morphology (a wide 0.5-8 Hz band plus
% morphology/adaptiveHarmonicFilter.m's harmonic comb) measurably HURTS
% HR accuracy on VIPL -- the harmonic comb locks onto a harmonic of the
% true rate when its f0 estimate is even slightly off (one subject's
% CHROM estimate jumped 69.4 -> 140.8 bpm in that task's comparison), and
% is a wash for SpO2. So the validated production HR/SpO2 path
% (filtering/bandpassClean.m's narrow 0.7-4 Hz band) and the morphology
% path (morphology/bandpassMorphology.m's wide band + the harmonic comb)
% must never be merged into one filter choice -- this function runs both,
% off the SAME raw ROI extraction, and returns both untouched.
%
% roi/extractROISignals.m is called AT MOST ONCE (only when videoInput is
% a video path -- see below) and its R/G/B/roiTimestamps output is reused
% by both branches; it is never called a second time for the morphology
% branch.
%
% Branch 1 (production; UNCHANGED call sequence downstream of the new
% wavelet-denoise step above -- byte-identical to
% scripts/run_segment4_heartrate_batch.m and
% scripts/run_vipl_integration_batch.m's own sequence, both of which
% agree with each other): filtering/detrendSignal.m ->
% filtering/bandpassClean.m -> pulseextraction/chromCombine.m (and
% pulseextraction/posCombine.m) -> heartrate/fftHeartRate.m ->
% HR_chrom/HR_pos/HR_green; spo2/ratioOfRatios.m -> spo2/calibrateSpO2.m
% (only if calibParams is supplied) -> SpO2%. None of these six functions
% is modified by this file.
%
% Branch 2 (morphology, UNCHANGED call sequence -- byte-identical to
% scripts/run_segment7_task_b_branch2_batch.m's "adaptiveHarmonic"
% condition, the same condition scripts/run_segment7_fig7_multicycle_waveform_batch.m
% independently reproduces as this project's own "adopted-best" pipeline):
% filtering/detrendSignal.m -> a SHARED cardiac fundamental f0 is
% estimated ONCE from a wide-band CHROM pulse
% (morphology/bandpassMorphology.m 'wide' on each channel ->
% pulseextraction/chromCombine.m -> heartrate/fftHeartRate.m / 60) ->
% morphology/adaptiveHarmonicFilter.m(channelDetrended, frameRate, 6,
% sharedF0Hz) per channel, all three channels forced onto that SAME
% shared f0 rather than three independently-noisy per-channel estimates
% -> pulseextraction/chromCombine.m -> morphology/fixPolarityByGroundTruth.m
% (groundTruth supplied) or morphology/fixPolarity.m (heuristic fallback,
% no ground truth) -> morphology/resampleUniform.m ->
% morphology/ensembleAverageBeats.m -> morphology/notchDetectIEM.m on
% prototype.trimmedMean, at an effective sample rate derived from a THIRD,
% independent heartrate/fftHeartRate.m call on the final resampled signal
% (fsProto = beatSamples * (hrBpm/60) -- exactly
% run_segment7_task_b_branch2_batch.m's own fsProtoAdaptive formula).
%
% NOTE on the shared f0 (read before changing this): the shared f0 fed to
% morphology/adaptiveHarmonicFilter.m is estimated from Branch 2's OWN
% wide-band CHROM pulse, not read from Branch 1's already-computed
% HR_chrom -- despite Branch 1 having "already computed" an f0 via
% heartrate/fftHeartRate.m, reusing THAT value here was deliberately NOT
% done, because it is not what
% scripts/run_segment7_task_b_branch2_batch.m (or
% scripts/run_segment7_fig7_multicycle_waveform_batch.m, which reproduces
% the identical formula independently) actually computes, and Task F's
% own regression test (tests/segment7_task_f_regression_test.m) requires
% this function's notch output to match results/metrics/segment7_task_b_notch_branch2.csv
% bit-for-bit (see the wavelet-fix note above for the current status of
% that bit-exact match) -- which is only possible by replicating that
% script's own sharedF0Hz computation exactly, band-for-band. Both f0
% estimates come from the SAME function (heartrate/fftHeartRate.m)
% applied once, not independently per channel, which is the property
% that actually matters for Branch 2's cross-channel alignment; they are
% simply computed from two differently-filtered versions of the same
% pulse (Branch 1's narrow 0.7-4 Hz CHROM vs Branch 2's own wide 0.5-8 Hz
% CHROM), and are not guaranteed to be numerically identical.
%
% Inputs:
%   videoInput   - EITHER (a) string/char, full path to a UBFC-style
%                  .avi video -- decoded via io/loadUBFCVideo.m and
%                  passed through roi/extractROISignals.m (called
%                  exactly once, default roiMode unless opts.roiMode
%                  overrides it); OR (b) struct with fields R, G, B
%                  (1 x N raw ROI traces, pre-detrend/pre-filter) and fs
%                  (scalar, Hz) -- e.g. the already-loaded contents of
%                  data/processed/<subjectID>_rgb_traces.mat -- to skip
%                  video decode and ROI extraction entirely because they
%                  were already run upstream. An optional roiTimestamps
%                  field is honored if present; if absent it is
%                  reconstructed as (0:numel(R)-1)/fs, which is
%                  roi/extractROISignals.m's own per-frame timestamp
%                  formula (roiTimestamps(frameIdx) = (frameIdx-1)/
%                  frameRate), so this is an exact reconstruction, not an
%                  approximation.
%   groundTruth  - (optional) struct with fields ppg and timestamp
%                  (io/loadGroundTruth.m's gt.ppg / gt.timestamp for the
%                  same subject), forwarded to Branch 2's polarity-fix
%                  step exactly as morphology/extractMorphologyWaveform.m's
%                  own groundTruth argument: supplied and non-empty ->
%                  morphology/fixPolarityByGroundTruth.m; omitted or [] ->
%                  morphology/fixPolarity.m (heuristic fallback, for
%                  contexts with no contact-PPG reference, e.g. Android).
%   calibParams  - (optional) struct {A, B} from spo2/calibrateSpO2.m,
%                  already fit on subjects OTHER than the one being
%                  processed here (this function never fits a
%                  calibration itself -- see spo2/calibrateSpO2.m's own
%                  header for why that must stay the caller's
%                  responsibility). Omit or pass [] to skip calibrated
%                  SpO2 -- Branch 1's ratio-of-ratios R value is still
%                  computed and returned either way, only spo2Pct is NaN.
%   opts         - (optional) struct, any subset of:
%                    roiMode   - forwarded to roi/extractROISignals.m
%                                when videoInput is a video path. Default
%                                'forehead', matching every existing
%                                production script -- never overridden
%                                elsewhere in this project.
%                    beatOpts  - struct forwarded as-is to
%                                morphology/ensembleAverageBeats.m's own
%                                opts argument. Default struct() (that
%                                function's own defaults), matching
%                                scripts/run_segment7_task_b_branch2_batch.m,
%                                which never overrides them either.
%                    subjectID - string/char, echoed back in
%                                result.subjectID purely for
%                                figure/report labeling. Default ''.
%                    useWaveletDenoise - logical, default true (2026-09-19
%                                fix promoting SESSION_HANDOFF.md's Segment
%                                8 Action 7 default into this shared
%                                orchestrator -- see the FIX note at the
%                                top of this header for the full story).
%                                When true, filtering/waveletDenoise.m
%                                (db4, 3-level, default params) is applied
%                                to R/G/B, in place, immediately before
%                                filtering/detrendSignal.m -- the exact
%                                position scripts/run_vipl_integration_batch.m
%                                uses. Set to false to reproduce this
%                                function's exact pre-2026-09-19 behavior.
%                    useConfidenceGate - logical, default true (Segment 14
%                                Task 2 promotion, 2026-09-13). When true,
%                                Branch 2 additionally computes
%                                morphology/harmonicSelectiveGaussianFilter.m
%                                (alpha=0.15) and uses
%                                morphology/harmonicFilterConfidenceGate.m
%                                to decide between it and
%                                morphology/adaptiveHarmonicFilter.m's ABPF
%                                comb: keep ABPF wherever its OWN notch
%                                confidence already clears this project's
%                                0.3 bar (computed once, cheaply, before
%                                deciding whether the Gaussian candidate is
%                                even needed), substitute the Gaussian
%                                candidate only where ABPF fails. This is
%                                Segment 13's own settled gate logic,
%                                re-derived nowhere in this file -- see
%                                docs/Segment13_Task1_Gaussian_Regression_
%                                Root_Cause_and_Gate.md and
%                                docs/Segment14_Task2_Confidence_Gate_
%                                Production_Promotion.md for the full
%                                evidence (100-subject audit-pool result:
%                                pass rate 24%->47%, median waveform corr
%                                0.519->0.522, harmonic confusion 5%->3%,
%                                zero severe regressions BY CONSTRUCTION,
%                                plus a held-out UBFC DATASET_2 check).
%                                Set to false to reproduce the exact
%                                pre-2026-09-13 ABPF-only behavior (this is
%                                what tests/segment7_task_f_regression_
%                                test.m's own Part 3 does, since it tests
%                                the 'adaptiveHarmonic' condition BY NAME,
%                                independent of whatever the production
%                                default is).
%
% Outputs:
%   result - struct with fields:
%     subjectID, frameRate, roiTimestamps, R, G, B  - the shared inputs
%       both branches were run on (R/G/B are POST-wavelet-denoise when
%       opts.useWaveletDenoise is true -- see the BEHAVIOR CHANGE note
%       above -- and real timestamps).
%     waveletDenoiseUsed - logical, echoes opts.useWaveletDenoise, so a
%       caller/report can tell which convention result.R/G/B follow
%       without re-reading opts itself.
%     hrBpm.chrom / .pos / .green  - Branch 1's three HR estimates (bpm),
%       identical convention to results/metrics/segment4_hr_summary*.csv.
%     spo2Pct   - Branch 1's calibrated SpO2 estimate (%), or NaN if
%       calibParams was not supplied.
%     prototype - Branch 2's ensemble-averaged beat prototype struct
%       (morphology/ensembleAverageBeats.m's own trimmedMean/median
%       fields), for the demo figure's shaded-waveform panel.
%     iqrBand   - Branch 2's per-sample beat-to-beat stability band
%       (morphology/ensembleAverageBeats.m's own q1/q3/width/... fields).
%     notch.detected / .position / .depth / .confidence / .confidenceRaw
%       - Branch 2's morphology/notchDetectIEM.m output on
%       prototype.trimmedMean.
%     branch1 - struct with the full Branch 1 detail: R_filtered,
%       G_filtered, B_filtered, pulseChromFiltered, pulsePosFiltered,
%       HR_chrom, HR_pos, HR_green, Rvalue (ratio-of-ratios), spo2Pct,
%       calibParamsUsed (echoes the input, [] if none supplied).
%     branch2 - struct with the full Branch 2 detail: sharedF0Hz,
%       pulseAdaptive (pre-polarity-fix), pulseAdaptiveFixed,
%       polarityMethod ('groundTruth' or 'heuristic'), wasFlipped,
%       sigUniform, timeUniform, uniformFs, prototype, iqrBand,
%       beatMatrix, beatStats, hrBpmUsed (the third, independent
%       fftHeartRate.m call used only to convert beatSamples -> an
%       effective Hz for notchDetectIEM.m), effectiveFsHz, notchDetected,
%       notchPositionNormalized, notchDepth, notchConfidence,
%       notchConfidenceRaw. When opts.useConfidenceGate is true (default):
%       harmonicMethodUsed ('adaptiveHarmonic' or 'gaussian015' -- which
%       candidate the gate actually kept for this subject),
%       gateSubstituted (logical, true if the Gaussian candidate replaced
%       ABPF), abpfNotchConfidence (ABPF's OWN notch confidence, preserved
%       even when substituted, so a caller can see what was being
%       overridden), gaussianNotchConfidence (NaN if the gate never needed
%       to compute the Gaussian candidate, i.e. ABPF already passed).

if nargin < 2
    groundTruth = [];
end

if nargin < 3
    calibParams = [];
end

if nargin < 4 || isempty(opts)
    opts = struct();
end

if ~isfield(opts, 'roiMode') || isempty(opts.roiMode)
    opts.roiMode = 'forehead';
end

if ~isfield(opts, 'beatOpts') || isempty(opts.beatOpts)
    opts.beatOpts = struct();
end

if ~isfield(opts, 'subjectID')
    opts.subjectID = '';
end

if ~isfield(opts, 'useWaveletDenoise') || isempty(opts.useWaveletDenoise)
    opts.useWaveletDenoise = true; % 2026-09-19 fix -- see header FIX note
end

if ~isfield(opts, 'useConfidenceGate') || isempty(opts.useConfidenceGate)
    opts.useConfidenceGate = true; % Segment 14 Task 2 promotion -- see Branch 2 section below
end

% === Shared input stage: decode + extract ROI at most once. ===
if ischar(videoInput) || isstring(videoInput)
    [frames, frameRate, ~] = loadUBFCVideo(char(videoInput));
    [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate, opts.roiMode);
elseif isstruct(videoInput)
    if ~isfield(videoInput, 'R') || ~isfield(videoInput, 'G') || ~isfield(videoInput, 'B') || ~isfield(videoInput, 'fs')
        error('estimateVitalsAndMorphology:badCachedInput', 'videoInput struct must have fields R, G, B, and fs (e.g. a loaded <subjectID>_rgb_traces.mat).');
    end
    R = videoInput.R;
    G = videoInput.G;
    B = videoInput.B;
    frameRate = videoInput.fs;
    if isfield(videoInput, 'roiTimestamps') && ~isempty(videoInput.roiTimestamps)
        roiTimestamps = videoInput.roiTimestamps;
    else
        roiTimestamps = (0:(numel(R) - 1)) / frameRate; % exact match to roi/extractROISignals.m's own per-frame formula
    end
else
    error('estimateVitalsAndMorphology:badVideoInput', 'videoInput must be a video path (char/string) or a struct with fields R, G, B, fs.');
end

% === 2026-09-19 fix: DWT wavelet-shrinkage denoise, in place, immediately
% before detrendSignal -- same position/params scripts/run_vipl_integration_batch.m
% and scripts/run_segment3_filtering_batch.m already use as their own
% validated default. See header FIX note for why this was missing and
% what it changes for callers. ===
% SpO2 is deliberately PINNED to the pre-wavelet signal (see the SpO2 PIN
% note in the header): capture the untouched R/G/B before the reassignment.
R_preWavelet = R;
G_preWavelet = G;
B_preWavelet = B;

if opts.useWaveletDenoise
    R = waveletDenoise(R);
    G = waveletDenoise(G);
    B = waveletDenoise(B);
end

[R_detrended, ~] = detrendSignal(R);
[G_detrended, ~] = detrendSignal(G);
[B_detrended, ~] = detrendSignal(B);

% === Branch 1: production HR/SpO2, UNCHANGED sequence downstream of the
% wavelet-denoise step above. ===
[R_filtered, ~] = bandpassClean(R_detrended, frameRate);
[G_filtered, ~] = bandpassClean(G_detrended, frameRate);
[B_filtered, ~] = bandpassClean(B_detrended, frameRate);

pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
pulseChromFiltered = bandpassClean(pulseChrom, frameRate);
[HR_chrom, ~, ~] = fftHeartRate(pulseChromFiltered, frameRate);

pulsePos = posCombine(R_filtered, G_filtered, B_filtered, frameRate, R, G, B);
pulsePosFiltered = bandpassClean(pulsePos, frameRate);
[HR_pos, ~, ~] = fftHeartRate(pulsePosFiltered, frameRate);

[HR_green, ~, ~] = fftHeartRate(G_filtered, frameRate);

% SpO2 PIN (2026-09-20): ratioOfRatios consumes BOTH the filtered AC
% channels and the raw DC channels, and spo2/calibrateSpO2.m's coefficients
% were fit on R values from the pre-wavelet chain, so the WHOLE chain is
% rebuilt here from the pre-wavelet signal (detrend -> bandpass), regardless
% of opts.useWaveletDenoise. When wavelet is off this is byte-identical to
% the values already computed above and is simply reused.
if opts.useWaveletDenoise
    [R_spo2Detrended, ~] = detrendSignal(R_preWavelet);
    [G_spo2Detrended, ~] = detrendSignal(G_preWavelet);
    [B_spo2Detrended, ~] = detrendSignal(B_preWavelet);
    [R_spo2Filtered, ~] = bandpassClean(R_spo2Detrended, frameRate);
    [G_spo2Filtered, ~] = bandpassClean(G_spo2Detrended, frameRate);
    [B_spo2Filtered, ~] = bandpassClean(B_spo2Detrended, frameRate);
else
    R_spo2Filtered = R_filtered;
    G_spo2Filtered = G_filtered;
    B_spo2Filtered = B_filtered;
end
Rvalue = ratioOfRatios(R_spo2Filtered, G_spo2Filtered, B_spo2Filtered, R_preWavelet, G_preWavelet, B_preWavelet, frameRate);

if isempty(calibParams)
    spo2Pct = NaN;
else
    [spo2Pct, ~] = calibrateSpO2(Rvalue, [], calibParams);
end

branch1 = struct();
branch1.R_filtered = R_filtered;
branch1.G_filtered = G_filtered;
branch1.B_filtered = B_filtered;
branch1.pulseChromFiltered = pulseChromFiltered;
branch1.pulsePosFiltered = pulsePosFiltered;
branch1.HR_chrom = HR_chrom;
branch1.HR_pos = HR_pos;
branch1.HR_green = HR_green;
branch1.Rvalue = Rvalue;
branch1.spo2Pct = spo2Pct;
branch1.calibParamsUsed = calibParams;

% === Branch 2: morphology (notch). ABPF sequence UNCHANGED -- byte-
% identical to scripts/run_segment7_task_b_branch2_batch.m's
% "adaptiveHarmonic" condition, exactly as before this promotion. When
% opts.useConfidenceGate is true (default), a second candidate
% (morphology/harmonicSelectiveGaussianFilter.m, alpha=0.15) is computed
% ONLY if ABPF's own notch confidence fails the 0.3 bar (cheap: the common
% already-passing case never touches the Gaussian path at all), and
% morphology/harmonicFilterConfidenceGate.m -- Segment 13's own settled
% logic, not re-derived here -- decides whether to substitute it. ===
[R_wide, ~, ~] = bandpassMorphology(R_detrended, frameRate, 'wide');
[G_wide, ~, ~] = bandpassMorphology(G_detrended, frameRate, 'wide');
[B_wide, ~, ~] = bandpassMorphology(B_detrended, frameRate, 'wide');
pulseWide = chromCombine(R_wide, G_wide, B_wide, R, G, B);
sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;

[R_ahf, ~, ~] = adaptiveHarmonicFilter(R_detrended, frameRate, 6, sharedF0Hz);
[G_ahf, ~, ~] = adaptiveHarmonicFilter(G_detrended, frameRate, 6, sharedF0Hz);
[B_ahf, ~, ~] = adaptiveHarmonicFilter(B_detrended, frameRate, 6, sharedF0Hz);
pulseAdaptive = chromCombine(R_ahf, G_ahf, B_ahf, R, G, B);

useGroundTruth = ~isempty(groundTruth);

if useGroundTruth
    [pulseAdaptiveFixed, wasFlipped] = fixPolarityByGroundTruth(pulseAdaptive, roiTimestamps, groundTruth.ppg, groundTruth.timestamp);
    polarityMethod = 'groundTruth';
else
    [pulseAdaptiveFixed, wasFlipped, ~] = fixPolarity(pulseAdaptive, frameRate);
    polarityMethod = 'heuristic';
end

[sigAdaptiveUniform, timeUniform, fsAdaptiveUniform] = resampleUniform(pulseAdaptiveFixed, roiTimestamps);
[prototype, iqrBand, beatMatrix, beatStats] = ensembleAverageBeats(sigAdaptiveUniform, fsAdaptiveUniform, opts.beatOpts);

hrBpmUsed = fftHeartRate(sigAdaptiveUniform, fsAdaptiveUniform);
effectiveFsHz = numel(prototype.trimmedMean) * (hrBpmUsed / 60);
[notchDetected, notchPositionNormalized, notchDepth, notchConfidence, notchConfidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFsHz);

abpfNotchConfidence = notchConfidence; % preserved even if substituted below
harmonicMethodUsed = 'adaptiveHarmonic';
gateSubstituted = false;
gaussianNotchConfidence = NaN;
confidenceGateBar = 0.3; % this project's own standing notch-confidence bar

if opts.useConfidenceGate && abpfNotchConfidence <= confidenceGateBar
    [R_gau, ~, ~] = harmonicSelectiveGaussianFilter(R_detrended, frameRate, 6, sharedF0Hz, 0.15);
    [G_gau, ~, ~] = harmonicSelectiveGaussianFilter(G_detrended, frameRate, 6, sharedF0Hz, 0.15);
    [B_gau, ~, ~] = harmonicSelectiveGaussianFilter(B_detrended, frameRate, 6, sharedF0Hz, 0.15);
    pulseGaussian = chromCombine(R_gau, G_gau, B_gau, R, G, B);

    if useGroundTruth
        [pulseGaussianFixed, wasFlippedGaussian] = fixPolarityByGroundTruth(pulseGaussian, roiTimestamps, groundTruth.ppg, groundTruth.timestamp);
    else
        [pulseGaussianFixed, wasFlippedGaussian, ~] = fixPolarity(pulseGaussian, frameRate);
    end

    [sigGaussianUniform, timeUniformGaussian, fsGaussianUniform] = resampleUniform(pulseGaussianFixed, roiTimestamps);
    [prototypeGaussian, iqrBandGaussian, beatMatrixGaussian, beatStatsGaussian] = ensembleAverageBeats(sigGaussianUniform, fsGaussianUniform, opts.beatOpts);
    hrBpmUsedGaussian = fftHeartRate(sigGaussianUniform, fsGaussianUniform);
    effectiveFsHzGaussian = numel(prototypeGaussian.trimmedMean) * (hrBpmUsedGaussian / 60);
    [notchDetectedGaussian, notchPositionNormalizedGaussian, notchDepthGaussian, notchConfidenceGaussian, notchConfidenceRawGaussian] = ...
        notchDetectIEM(prototypeGaussian.trimmedMean, effectiveFsHzGaussian);
    gaussianNotchConfidence = notchConfidenceGaussian;

    [~, harmonicMethodUsed, ~, gateSubstituted] = harmonicFilterConfidenceGate( ...
        pulseAdaptiveFixed, abpfNotchConfidence, 'adaptiveHarmonic', ...
        {pulseGaussianFixed}, notchConfidenceGaussian, {'gaussian015'}, confidenceGateBar);

    if gateSubstituted
        pulseAdaptive = pulseGaussian;
        pulseAdaptiveFixed = pulseGaussianFixed;
        wasFlipped = wasFlippedGaussian;
        sigAdaptiveUniform = sigGaussianUniform;
        timeUniform = timeUniformGaussian;
        fsAdaptiveUniform = fsGaussianUniform;
        prototype = prototypeGaussian;
        iqrBand = iqrBandGaussian;
        beatMatrix = beatMatrixGaussian;
        beatStats = beatStatsGaussian;
        hrBpmUsed = hrBpmUsedGaussian;
        effectiveFsHz = effectiveFsHzGaussian;
        notchDetected = notchDetectedGaussian;
        notchPositionNormalized = notchPositionNormalizedGaussian;
        notchDepth = notchDepthGaussian;
        notchConfidence = notchConfidenceGaussian;
        notchConfidenceRaw = notchConfidenceRawGaussian;
    end
end

branch2 = struct();
branch2.sharedF0Hz = sharedF0Hz;
branch2.pulseAdaptive = pulseAdaptive;
branch2.pulseAdaptiveFixed = pulseAdaptiveFixed;
branch2.polarityMethod = polarityMethod;
branch2.wasFlipped = wasFlipped;
branch2.sigUniform = sigAdaptiveUniform;
branch2.timeUniform = timeUniform;
branch2.uniformFs = fsAdaptiveUniform;
branch2.prototype = prototype;
branch2.iqrBand = iqrBand;
branch2.beatMatrix = beatMatrix;
branch2.beatStats = beatStats;
branch2.hrBpmUsed = hrBpmUsed;
branch2.effectiveFsHz = effectiveFsHz;
branch2.notchDetected = notchDetected;
branch2.notchPositionNormalized = notchPositionNormalized;
branch2.notchDepth = notchDepth;
branch2.notchConfidence = notchConfidence;
branch2.notchConfidenceRaw = notchConfidenceRaw;
branch2.harmonicMethodUsed = harmonicMethodUsed;
branch2.gateSubstituted = gateSubstituted;
branch2.abpfNotchConfidence = abpfNotchConfidence;
branch2.gaussianNotchConfidence = gaussianNotchConfidence;

% === Combined result struct: shared inputs, both branches' full detail,
% plus flat top-level convenience fields (hrBpm, spo2Pct, prototype,
% iqrBand, notch) for callers that only want the headline numbers. ===
result = struct();
result.subjectID = opts.subjectID;
result.frameRate = frameRate;
result.roiTimestamps = roiTimestamps;
result.R = R;
result.G = G;
result.B = B;
result.waveletDenoiseUsed = opts.useWaveletDenoise;

result.hrBpm = struct('chrom', HR_chrom, 'pos', HR_pos, 'green', HR_green);
result.spo2Pct = spo2Pct;

result.prototype = prototype;
result.iqrBand = iqrBand;

result.notch = struct();
result.notch.detected = notchDetected;
result.notch.position = notchPositionNormalized;
result.notch.depth = notchDepth;
result.notch.confidence = notchConfidence;
result.notch.confidenceRaw = notchConfidenceRaw;
result.notch.methodUsed = harmonicMethodUsed; % 'adaptiveHarmonic' or 'gaussian015' -- see branch2 for the full gate detail

result.branch1 = branch1;
result.branch2 = branch2;

end
