% RUN_SEGMENT10_WAVEFORM_FIDELITY_AUDIT Segment 10 Task 1 -- full
% rPPG-vs-ground-truth-PPG waveform and frequency fidelity audit.
%
% READ-ONLY DIAGNOSTIC. Does not modify, and never calls in a way that
% would change, any of: pulseextraction/chromCombine.m,
% pulseextraction/posCombine.m, heartrate/fftHeartRate.m,
% morphology/adaptiveHarmonicFilter.m, filtering/waveletDenoise.m,
% roi/extractROISignals.m. Reuses all of them exactly as
% pipeline/estimateVitalsAndMorphology.m documents its own Branch 1/Branch
% 2 call sequence (this script inlines that same sequence, the same way
% scripts/run_segment7_task_k_template_collapse_batch.m inlines it,
% rather than calling the orchestrator, because this script also needs
% Branch 1's pre-anything-else pulseChromFiltered/pulsePosFiltered and
% Branch 2's pre-polarity-fix pulseAdaptive, which
% estimateVitalsAndMorphology.m does not return standalone).
%
% NEW additive function this task adds:
% morphology/estimateLagPolarityByGroundTruth.m -- extends
% morphology/fixPolarityByGroundTruth.m's cross-correlation approach to
% solve for the best LAG (not just polarity sign). See that file's own
% header for the method and sign convention.
%
% SUBJECT POOL: the exact 100-subject pool Segment 7 Task K established
% and cached (docs/Segment7_Task_K_Template_Collapse_Diagnostic.md) --
% UBFC DATASET_1 (5) + VIPL-HR v1/source1 (95) -- the only subjects in
% this project with a real ground-truth contact-PPG WAVEFORM, not just a
% scalar HR/SpO2 label. Reuses data/processed/*_rgb_traces.mat (raw R/G/B
% + fs) directly -- NO video is decoded or reprocessed by this script.
%
% Per subject, per branch (CHROM, POS, harmonic-comb):
%   1. Lag+polarity alignment against the subject's own GT PPG
%      (morphology/estimateLagPolarityByGroundTruth.m), lag reported
%      explicitly, flagged (not dropped) if |lag| exceeds one GT cardiac
%      cycle.
%   2. Time domain: Pearson correlation, RMSE/NRMSE (both signals
%      z-scored first -- see Method section below for why), DTW alignment
%      cost (downsampled to 25 Hz, Sakoe-Chiba band +/-1s, since the rigid
%      lag is already removed and DTW here is only meant to catch
%      residual local timing warp).
%   3. Beat-shape: morphology/ensembleAverageBeats.m +
%      morphology/resampleUniform.m (unmodified) on the aligned overlap,
%      for both the rPPG branch signal and GT; morphology/notchDetectIEM.m
%      on both prototypes; a NEW pre-warp systolic-peak-fraction helper
%      (local function below) since ensembleAverageBeats.m's own
%      two-anchor time warp forces the POST-warp peak to a constant
%      cycle-fraction by construction, which would make a post-warp
%      peak-timing comparison trivially uninformative -- stated plainly
%      rather than silently worked around.
%   4. Frequency domain: Welch PSD (pwelch) of both signals (z-scored),
%      magnitude-squared coherence (mscohere), a per-band mismatch-energy
%      breakdown weighted by GT PSD, a harmonic-confusion detector
%      (nearest-integer-multiple/submultiple check on each signal's own
%      dominant in-band peak), and a phase-spectrum (cpsd) comparison in
%      the fundamental band to separate pure delay from genuine
%      distortion.
%
% CHECKPOINTED / RESUMABLE, same discipline as every other batch script in
% this project: each subject's outcome is appended to `results` and both
% the .mat cache and the per-subject CSV are rewritten after every
% subject, so an interrupted run leaves usable partial output and a rerun
% skips subjects already in the cache.
%
% Outputs:
%   results/metrics/segment10_waveform_fidelity_per_subject.csv
%   results/metrics/segment10_waveform_fidelity_pooled_summary.csv
%   results/figures/segment10_*.png
%   data/processed/segment10_task1_audit_cache.mat (resumable cache)

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
ubfcD1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
processedRoot = fullfile(projectRoot, 'data', 'processed');

if ~isfolder(metricsRoot); mkdir(metricsRoot); end
if ~isfolder(figuresRoot); mkdir(figuresRoot); end
if ~isfolder(processedRoot); mkdir(processedRoot); end

perSubjectCsvPath = fullfile(metricsRoot, 'segment10_waveform_fidelity_per_subject.csv');
pooledCsvPath = fullfile(metricsRoot, 'segment10_waveform_fidelity_pooled_summary.csv');
matPath = fullfile(processedRoot, 'segment10_task1_audit_cache.mat');

branchNames = {'chrom', 'pos', 'harmonic'};
targetFs = 250;
maxLagSec = 5;

% --- Build the 100-subject list, restricted to subjects with an already-
% cached raw rgb_traces.mat (per the task brief: reuse cache, never
% reprocess video). ---
subjects = struct('source', {}, 'id', {}, 'cachePath', {}, 'gtPath', {}, 'subjectNum', {});

d1List = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
for k = 1:numel(d1List)
    cachePath = fullfile(processedRoot, [d1List{k} '_rgb_traces.mat']);
    gtPath = fullfile(ubfcD1Root, d1List{k}, 'gtdump.xmp');
    if ~isfile(cachePath) || ~isfile(gtPath)
        fprintf('SKIP (no cache/GT): ubfc_d1 %s\n', d1List{k});
        continue
    end
    entry.source = 'ubfc_d1';
    entry.id = d1List{k};
    entry.cachePath = cachePath;
    entry.gtPath = gtPath;
    entry.subjectNum = NaN;
    subjects(end + 1) = entry; %#ok<AGROW>
end

viplSubjectDirs = dir(fullfile(viplRoot, 'p*'));
viplSubjectDirs = viplSubjectDirs([viplSubjectDirs.isdir]);
for k = 1:numel(viplSubjectDirs)
    subjName = viplSubjectDirs(k).name;
    subjNum = str2double(subjName(2:end));
    if isnan(subjNum); continue; end
    wavePath = fullfile(viplRoot, subjName, 'v1', 'source1', 'wave.csv');
    compositeId = ['VIPL_' subjName '_v1_source1'];
    cachePath = fullfile(processedRoot, [compositeId '_rgb_traces.mat']);
    if ~isfile(wavePath) || ~isfile(cachePath)
        continue
    end
    entry.source = 'vipl';
    entry.id = compositeId;
    entry.cachePath = cachePath;
    entry.gtPath = '';
    entry.subjectNum = subjNum;
    subjects(end + 1) = entry; %#ok<AGROW>
end

% Optional smoke-test limit (SPANDAN_TEST_LIMIT env var) -- for
% development/verification only, unset for the real full-pool run.
testLimitStr = getenv('SPANDAN_TEST_LIMIT');
if ~isempty(testLimitStr)
    testLimit = str2double(testLimitStr);
    if ~isnan(testLimit)
        idxUbfc = find(strcmp({subjects.source}, 'ubfc_d1'));
        idxVipl = find(strcmp({subjects.source}, 'vipl'));
        keepUbfc = idxUbfc(1:min(testLimit, numel(idxUbfc)));
        keepVipl = idxVipl(1:min(testLimit, numel(idxVipl)));
        subjects = subjects([keepUbfc, keepVipl]);
        fprintf('SPANDAN_TEST_LIMIT=%d active: restricted to %d subjects for a smoke test.\n', testLimit, numel(subjects));
    end
end

numSubjects = numel(subjects);
fprintf('Segment 10 Task 1: %d subjects total (UBFC-D1 %d, VIPL-v1s1 %d).\n', ...
    numSubjects, numel(d1List), numel(viplSubjectDirs));

% --- Fixed full-field row template, built ONCE, used for every subject
% (success or failure) so struct2table's field set never depends on
% which subject happened to be processed first -- a subject that fails
% still contributes a row with every branch field present (NaN/false/''),
% not a truncated one. ---
rowTemplate = struct();
rowTemplate.source = '';
rowTemplate.id = '';
rowTemplate.success = false;
rowTemplate.failReason = '';
rowTemplate.frameRate = NaN;
rowTemplate.durationSec = NaN;
rowTemplate.f0GTHz = NaN;
rowTemplate.device = '';
rowTemplate.scenario = '';
for b = 1:numel(branchNames)
    rowTemplate = mergeBranchFields(rowTemplate, branchNames{b}, defaultBranchResult());
end
rowTemplate.elapsedSec = NaN;

% --- Resume support. ---
if isfile(matPath)
    loaded = load(matPath);
    results = loaded.results;
    doneIds = {results.id};
    fprintf('Resuming: %d subjects already in cache.\n', numel(doneIds));
else
    results = struct([]);
    doneIds = {};
end

for subjPos = 1:numSubjects
    s = subjects(subjPos);

    if any(strcmp(doneIds, s.id))
        continue
    end

    fprintf('--- Task 1 subject %d/%d: %s (%s) ---\n', subjPos, numSubjects, s.id, s.source);
    subjTic = tic;

    try
        cached = load(s.cachePath);
        R = cached.R; G = cached.G; B = cached.B; frameRate = cached.fs;
        roiTimestamps = (0:numel(R) - 1) / frameRate;

        [gtPPG, gtTimestamps] = loadGTWaveformForAudit(s, projectRoot);

        [Rd, ~] = detrendSignal(R);
        [Gd, ~] = detrendSignal(G);
        [Bd, ~] = detrendSignal(B);

        % --- Branch 1: CHROM/POS, narrow 0.7-4 Hz, byte-identical
        % sequence to pipeline/estimateVitalsAndMorphology.m's Branch 1. ---
        [Rf, ~] = bandpassClean(Rd, frameRate);
        [Gf, ~] = bandpassClean(Gd, frameRate);
        [Bf, ~] = bandpassClean(Bd, frameRate);

        pulseChrom = chromCombine(Rf, Gf, Bf, R, G, B);
        pulseChromFiltered = bandpassClean(pulseChrom, frameRate);

        pulsePos = posCombine(Rf, Gf, Bf, frameRate, R, G, B);
        pulsePosFiltered = bandpassClean(pulsePos, frameRate);

        % --- Branch 2: harmonic-comb, wide 0.5-8 Hz, byte-identical
        % sequence to pipeline/estimateVitalsAndMorphology.m's Branch 2,
        % up to (not including) its own fixPolarityByGroundTruth call --
        % this script supersedes that step with
        % estimateLagPolarityByGroundTruth.m below. ---
        [Rw, ~, ~] = bandpassMorphology(Rd, frameRate, 'wide');
        [Gw, ~, ~] = bandpassMorphology(Gd, frameRate, 'wide');
        [Bw, ~, ~] = bandpassMorphology(Bd, frameRate, 'wide');
        pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
        sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;

        [Rahf, ~, ~] = adaptiveHarmonicFilter(Rd, frameRate, 6, sharedF0Hz);
        [Gahf, ~, ~] = adaptiveHarmonicFilter(Gd, frameRate, 6, sharedF0Hz);
        [Bahf, ~, ~] = adaptiveHarmonicFilter(Bd, frameRate, 6, sharedF0Hz);
        pulseAdaptive = chromCombine(Rahf, Gahf, Bahf, R, G, B);

        branchSignals = {pulseChromFiltered, pulsePosFiltered, pulseAdaptive};

        % --- Ground-truth's own dominant cardiac frequency, used as
        % "each subject's own f0" for the per-band mismatch-energy split
        % below (a GT-anchored basis so bands reflect where the TRUE
        % physiological energy is, shared across both branches for a
        % consistent basis of comparison). ---
        if strcmp(s.source, 'ubfc_d1')
            gtFsForFFT = 1 / median(diff(gtTimestamps));
        else
            gtFsForFFT = 60;
        end
        f0GTHz = fftHeartRate(gtPPG(:)' - mean(gtPPG), gtFsForFFT) / 60;

        row = rowTemplate;
        row.source = s.source;
        row.id = s.id;
        row.success = true;
        row.failReason = '';
        row.frameRate = frameRate;
        row.durationSec = numel(R) / frameRate;
        row.f0GTHz = f0GTHz;
        row.device = 'webcam'; % pool restricted to UBFC (webcam) + VIPL v1/source1 (Logitech C310 webcam) -- see doc caveat
        row.scenario = 'baseline_v1_or_ubfc'; % VIPL restricted to v1 (stable); UBFC has no scenario tag -- see doc caveat

        for b = 1:numel(branchNames)
            bn = branchNames{b};
            branchResult = analyzeOneBranch(branchSignals{b}, roiTimestamps, gtPPG, gtTimestamps, ...
                targetFs, maxLagSec, f0GTHz);
            row = mergeBranchFields(row, bn, branchResult);
        end

        elapsedSec = toc(subjTic);
        row.elapsedSec = elapsedSec;
        fprintf('  %s done (%.1fs): corr chrom/pos/harm = %.3f / %.3f / %.3f, lag = %.3f / %.3f / %.3f s\n', ...
            s.id, elapsedSec, row.corr_chrom, row.corr_pos, row.corr_harmonic, ...
            row.lagSec_chrom, row.lagSec_pos, row.lagSec_harmonic);

        if isempty(results)
            results = row;
        else
            results(end + 1) = row; %#ok<AGROW>
        end
    catch causeErr
        elapsedSec = toc(subjTic);
        disp(['Subject ' s.id ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        row = rowTemplate;
        row.source = s.source;
        row.id = s.id;
        row.success = false;
        row.failReason = causeErr.message;
        row.elapsedSec = elapsedSec;
        if isempty(results)
            results = row;
        else
            results(end + 1) = row; %#ok<AGROW>
        end
    end

    save(matPath, 'results', '-v7');
    writetable(struct2table(results, 'AsArray', true), perSubjectCsvPath);
end

numSucceeded = sum([results.success]);
fprintf('--- Segment 10 Task 1 batch complete: %d/%d subjects succeeded ---\n', numSucceeded, numel(results));

% ============================================================
% POOLED SUMMARY
% ============================================================
buildPooledSummary(results, branchNames, pooledCsvPath);

% ============================================================
% EXAMPLE FIGURES: one clear good / one clear bad case, both branches
% ============================================================
generateExampleFigures(results, branchNames, figuresRoot, processedRoot);

fprintf('Saved %s, %s, and example figures under %s\n', perSubjectCsvPath, pooledCsvPath, figuresRoot);


% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function [gtPPG, gtTimestamps] = loadGTWaveformForAudit(s, projectRoot)
switch s.source
    case 'ubfc_d1'
        gt = loadGroundTruth(s.gtPath, 'dataset1');
        gtPPG = gt.ppg;
        gtTimestamps = gt.timestamp;
    case 'vipl'
        viplRootLocal = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
        gt = loadVIPLGroundTruth(viplRootLocal, s.subjectNum, 1, 1);
        gtPPG = gt.ppg;
        gtTimestamps = (0:numel(gtPPG) - 1) / 60; % nominal CMS60C rate, no per-sample timestamp array -- same convention Task K used
    otherwise
        error('run_segment10_waveform_fidelity_audit:badSource', 'Unknown source "%s".', s.source);
end
gtPPG = gtPPG(:)';
gtTimestamps = gtTimestamps(:)';
end

function out = analyzeOneBranch(sig, sigTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec, f0GTHz)
% Runs the full alignment + time-domain + beat-shape + frequency-domain
% comparison for ONE branch signal against GT. Returns a flat struct;
% every field NaN/false by default so a sub-step's failure (e.g. too few
% beats for ensembleAverageBeats.m on a short/noisy clip) degrades
% gracefully to NaN for that piece only, without failing the subject.

out = defaultBranchResult();

% --- Step 1: lag + polarity alignment. ---
[sigAligned, gtAligned, ~, lagSec, ~, wasFlipped, maxAbsCorr, ~] = ...
    estimateLagPolarityByGroundTruth(sig, sigTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);

out.lagSec = lagSec;
out.wasFlipped = wasFlipped;
out.maxAbsCorr = maxAbsCorr;
onePeriodSec = 1 / f0GTHz;
out.lagFlaggedImplausible = abs(lagSec) > onePeriodSec;

% --- Step 2: time-domain, both z-scored (arbitrary/incomparable native
% amplitude units between an rPPG chrominance signal and a raw contact-PPG
% sensor trace otherwise make RMSE meaningless -- stated explicitly, see
% doc Method section). ---
sigZ = zscoreLocal(sigAligned);
gtZ = zscoreLocal(gtAligned);

out.corr = pearsonCorrLocal(sigZ, gtZ);
out.rmseZ = sqrt(mean((sigZ - gtZ) .^ 2));
gtRange = max(gtZ) - min(gtZ);
if gtRange > 0
    out.nrmseZ = out.rmseZ / gtRange;
end

try
    dsFactor = max(1, round(targetFs / 25));
    sigDS = sigZ(1:dsFactor:end);
    gtDS = gtZ(1:dsFactor:end);
    fsDS = targetFs / dsFactor;
    dtwWindow = max(1, round(1 * fsDS));
    [dtwDist, ix, ~] = dtw(sigDS, gtDS, dtwWindow);
    out.dtwCostNorm = dtwDist / max(1, numel(ix));
catch
    % leave NaN
end

% --- Step 3: beat-shape comparison on the aligned overlap. ---
try
    [protoSig, iqrSig, ~, ~] = ensembleAverageBeats(sigAligned, targetFs);
    hrSigUsed = fftHeartRate(sigAligned, targetFs);
    effFsSig = numel(protoSig.trimmedMean) * (hrSigUsed / 60);
    [notchDetSig, notchPosSig, notchDepthSig, notchConfSig, ~] = notchDetectIEM(protoSig.trimmedMean, effFsSig);
    out.notchDetected = notchDetSig;
    out.notchPosNorm = notchPosSig;
    out.notchDepth = notchDepthSig;
    out.notchConfidence = notchConfSig;
    out.iqrNormalized = iqrSig.meanWidthNormalized;
catch
    % leave NaN
end

try
    [protoGT, iqrGT, ~, ~] = ensembleAverageBeats(gtAligned, targetFs);
    hrGTUsed = fftHeartRate(gtAligned, targetFs);
    effFsGT = numel(protoGT.trimmedMean) * (hrGTUsed / 60);
    [notchDetGT, notchPosGT, notchDepthGT, notchConfGT, ~] = notchDetectIEM(protoGT.trimmedMean, effFsGT);
    out.notchDetectedGT = notchDetGT;
    out.notchPosNormGT = notchPosGT;
    out.notchDepthGT = notchDepthGT;
    out.notchConfidenceGT = notchConfGT;
    out.iqrNormalizedGT = iqrGT.meanWidthNormalized;

    if notchDetGT && out.notchDetected
        out.notchPosDiff = out.notchPosNorm - notchPosGT;
        out.notchDepthDiff = out.notchDepth - notchDepthGT;
    end
catch
    % leave NaN
end

try
    [peakFracMeanSig, ~, ~] = rawPeakFractionStats(sigAligned, targetFs);
    [peakFracMeanGT, ~, ~] = rawPeakFractionStats(gtAligned, targetFs);
    out.peakFracMean = peakFracMeanSig;
    out.peakFracMeanGT = peakFracMeanGT;
    out.peakFracDiff = peakFracMeanSig - peakFracMeanGT;
catch
    % leave NaN
end

% --- Step 4: frequency domain. ---
try
    N = numel(sigZ);
    winLen = min(N, round(8 * targetFs));
    winLen = max(winLen, min(N, round(2 * targetFs)));
    winLen = max(winLen, 8); % pwelch's hard floor
    noverlap = floor(winLen / 2);
    nfft = 2 ^ nextpow2(max(winLen, 1024));

    [PxxSig, fAxis] = pwelch(sigZ, hamming(winLen), noverlap, nfft, targetFs);
    [PxxGT, ~] = pwelch(gtZ, hamming(winLen), noverlap, nfft, targetFs);
    [Cxy, ~] = mscohere(sigZ, gtZ, hamming(winLen), noverlap, nfft, targetFs);
    [Pxy, ~] = cpsd(sigZ, gtZ, hamming(winLen), noverlap, nfft, targetFs);

    % Harmonic-confusion detector.
    searchMask = fAxis >= 0.5 & fAxis <= 8;
    freqsInSearch = fAxis(searchMask);
    [~, idxSig] = max(PxxSig(searchMask));
    [~, idxGt] = max(PxxGT(searchMask));
    sigPeakHz = freqsInSearch(idxSig);
    gtPeakHz = freqsInSearch(idxGt);
    out.sigPeakHz = sigPeakHz;
    out.gtPeakHz = gtPeakHz;
    if gtPeakHz > 0
        ratio = sigPeakHz / gtPeakHz;
        candidates = [1/3, 1/2, 1, 2, 3];
        [~, ci] = min(abs(ratio - candidates));
        nearest = candidates(ci);
        out.peakRatio = ratio;
        out.nearestHarmonicMultiple = nearest;
        out.harmonicConfused = (nearest ~= 1) && (abs(ratio - nearest) / nearest < 0.08);
    end

    % Per-band mismatch-energy breakdown, bands anchored on f0GTHz.
    df = fAxis(2) - fAxis(1);
    mismatch = (1 - Cxy) .* PxxGT;
    totalMismatch = sum(mismatch) * df;
    out.totalMismatchEnergy = totalMismatch;

    noiseLowerHz = min(6.5 * f0GTHz, 8);
    out.noiseLowerHz = noiseLowerHz;
    edges = [0, 0.7, ...
        min(1.5 * f0GTHz, noiseLowerHz), min(2.5 * f0GTHz, noiseLowerHz), ...
        min(3.5 * f0GTHz, noiseLowerHz), min(4.5 * f0GTHz, noiseLowerHz), ...
        min(5.5 * f0GTHz, noiseLowerHz), noiseLowerHz, fAxis(end) + df];
    bandFieldNames = {'band_subCardiac', 'band_h1', 'band_h2', 'band_h3', 'band_h4', 'band_h5', 'band_h6', 'band_noise'};

    if totalMismatch > 0
        for bi = 1:numel(bandFieldNames)
            bandMask = fAxis >= edges(bi) & fAxis < edges(bi + 1);
            out.(bandFieldNames{bi}) = sum(mismatch(bandMask)) * df / totalMismatch;
        end
    end

    % Phase-spectrum comparison (post-lag-alignment) in the fundamental
    % band and each harmonic band up to the 6th, to separate pure delay
    % (near-zero, near-flat phase residual after the rigid lag was
    % already removed) from genuine shape distortion (large/non-flat
    % residual).
    phaseFields = {'phaseResidualDeg_h1', 'phaseResidualDeg_h2', 'phaseResidualDeg_h3', ...
        'phaseResidualDeg_h4', 'phaseResidualDeg_h5', 'phaseResidualDeg_h6'};
    for h = 1:6
        if h == 1
            loEdge = 0.7; % matches band_h1's own lower edge above exactly
        else
            loEdge = (h - 0.5) * f0GTHz;
        end
        hiEdge = min((h + 0.5) * f0GTHz, noiseLowerHz);
        if hiEdge <= loEdge
            continue
        end
        bandMask = fAxis >= loEdge & fAxis < hiEdge;
        if ~any(bandMask)
            continue
        end
        phaseVals = angle(Pxy(bandMask));
        out.(phaseFields{h}) = rad2deg(circMeanLocal(phaseVals));
    end

    if ~isnan(out.phaseResidualDeg_h1)
        out.phaseClass = classifyPhase(out.phaseResidualDeg_h1);
    end
catch
    % leave NaN
end

out.mismatchScore = 1 - out.corr;

end

function out = defaultBranchResult()
fieldsNumeric = {'lagSec', 'maxAbsCorr', 'corr', 'rmseZ', 'nrmseZ', 'dtwCostNorm', ...
    'notchPosNorm', 'notchDepth', 'notchConfidence', 'iqrNormalized', ...
    'notchPosNormGT', 'notchDepthGT', 'notchConfidenceGT', 'iqrNormalizedGT', ...
    'notchPosDiff', 'notchDepthDiff', 'peakFracMean', 'peakFracMeanGT', 'peakFracDiff', ...
    'sigPeakHz', 'gtPeakHz', 'peakRatio', 'nearestHarmonicMultiple', ...
    'band_subCardiac', 'band_h1', 'band_h2', 'band_h3', 'band_h4', 'band_h5', 'band_h6', 'band_noise', ...
    'noiseLowerHz', 'totalMismatchEnergy', ...
    'phaseResidualDeg_h1', 'phaseResidualDeg_h2', 'phaseResidualDeg_h3', ...
    'phaseResidualDeg_h4', 'phaseResidualDeg_h5', 'phaseResidualDeg_h6', 'mismatchScore'};
out = struct();
for i = 1:numel(fieldsNumeric)
    out.(fieldsNumeric{i}) = NaN;
end
out.wasFlipped = false;
out.lagFlaggedImplausible = false;
out.notchDetected = false;
out.notchDetectedGT = false;
out.harmonicConfused = false;
out.phaseClass = 'indeterminate';
end

function rowOut = mergeBranchFields(rowIn, branchName, branchResult)
rowOut = rowIn;
fn = fieldnames(branchResult);
for i = 1:numel(fn)
    rowOut.([fn{i} '_' branchName]) = branchResult.(fn{i});
end
end

function z = zscoreLocal(x)
sigma = std(x);
if sigma > 0
    z = (x - mean(x)) / sigma;
else
    z = x - mean(x);
end
end

function r = pearsonCorrLocal(x, y)
xc = x - mean(x);
yc = y - mean(y);
denom = sqrt(sum(xc .^ 2) * sum(yc .^ 2));
if denom > 0
    r = sum(xc .* yc) / denom;
else
    r = NaN;
end
end

function m = circMeanLocal(theta)
m = angle(mean(exp(1i * theta(:))));
end

function classification = classifyPhase(phaseResidualDegH1)
% A phase residual near 0 in the fundamental band, AFTER the rigid
% broadband lag has already been removed, means the remaining
% relationship is well explained by that single delay -- "just delayed".
% A large residual means the fundamental-band content is out of step with
% the rest of the signal in a way one global lag cannot capture --
% "distorted". 20 degrees is this task's own chosen cutoff (roughly
% 1/18th of a cycle), stated explicitly as a convention, not a threshold
% discovered from this data.
phaseDelayThresholdDeg = 20;
if abs(phaseResidualDegH1) <= phaseDelayThresholdDeg
    classification = 'delayOnly';
else
    classification = 'distorted';
end
end

function [peakFracMean, peakFracStd, numBeats] = rawPeakFractionStats(sig, fs)
% Replicates ensembleAverageBeats.m's Steps 1-3 (negative-zero-crossing
% beat segmentation + per-beat pchip resample to a fixed-length cycle)
% WITHOUT Step 4's two-anchor time warp, so the systolic peak's cycle
% fraction is measured as it actually falls, not forced to a constant
% anchor fraction (ensembleAverageBeats.m's own 0.25 default) the way
% ensembleAverageBeats.m's OWN prototype output would trivially show.
% This is a diagnostic-only duplication of that segmentation logic (not a
% modification of morphology/ensembleAverageBeats.m itself), needed
% specifically because this task asks for a real systolic-peak-timing
% comparison, which the production function's own warp step makes
% impossible to read off its output.
beatSamples = 256;
sigRow = sig(:)';
N = numel(sigRow);
timeAxis = (0:N - 1) / fs;
sigZeroMean = sigRow - mean(sigRow);

crossingTimes = [];
for i = 1:(N - 1)
    if sigZeroMean(i) >= 0 && sigZeroMean(i + 1) < 0
        frac = sigZeroMean(i) / (sigZeroMean(i) - sigZeroMean(i + 1));
        crossingTimes(end + 1) = timeAxis(i) + frac * (timeAxis(i + 1) - timeAxis(i)); %#ok<AGROW>
    end
end

numBeatsFound = numel(crossingTimes) - 1;
if numBeatsFound < 1
    error('rawPeakFractionStats:tooFewBeats', 'No beats found.');
end

peakFracs = zeros(1, numBeatsFound);
for k = 1:numBeatsFound
    t0 = crossingTimes(k);
    t1 = crossingTimes(k + 1);
    queryTimes = linspace(t0, t1, beatSamples);
    beatValues = interp1(timeAxis, sigRow, queryTimes, 'pchip');
    [~, peakIdx] = max(beatValues);
    peakFracs(k) = (peakIdx - 1) / (beatSamples - 1);
end

peakFracMean = mean(peakFracs);
peakFracStd = std(peakFracs);
numBeats = numBeatsFound;
end

function buildPooledSummary(results, branchNames, pooledCsvPath)
successMask = [results.success];
successResults = results(successMask);
sources = {successResults.source};

metricNames = {'corr', 'rmseZ', 'nrmseZ', 'dtwCostNorm', 'lagSec', 'mismatchScore', ...
    'iqrNormalized', 'iqrNormalizedGT', 'notchPosDiff', 'notchDepthDiff', 'peakFracDiff', ...
    'totalMismatchEnergy', 'notchConfidenceGT', 'notchConfidence', ...
    'band_subCardiac', 'band_h1', 'band_h2', 'band_h3', 'band_h4', 'band_h5', 'band_h6', 'band_noise', ...
    'phaseResidualDeg_h1', 'phaseResidualDeg_h2', 'phaseResidualDeg_h3'};

groupDefs = {'all', true(1, numel(successResults)); ...
             'ubfc_d1', strcmp(sources, 'ubfc_d1'); ...
             'vipl', strcmp(sources, 'vipl')};

poolRows = struct('kind', {}, 'group', {}, 'branch', {}, 'metric', {}, 'median', {}, 'iqr25', {}, 'iqr75', {}, 'n', {}, ...
    'rank', {}, 'subjectID', {}, 'source', {}, 'mismatchScore', {}, ...
    'corr_chrom', {}, 'corr_pos', {}, 'corr_harmonic', {}, ...
    'lagSec_chrom', {}, 'lagSec_pos', {}, 'lagSec_harmonic', {}, ...
    'harmonicConfusedCount', {}, 'harmonicConfusedTotal', {}, 'harmonicConfusedFraction', {});

blankRow = struct('kind', '', 'group', '', 'branch', '', 'metric', '', 'median', NaN, 'iqr25', NaN, 'iqr75', NaN, 'n', NaN, ...
    'rank', NaN, 'subjectID', '', 'source', '', 'mismatchScore', NaN, ...
    'corr_chrom', NaN, 'corr_pos', NaN, 'corr_harmonic', NaN, ...
    'lagSec_chrom', NaN, 'lagSec_pos', NaN, 'lagSec_harmonic', NaN, ...
    'harmonicConfusedCount', NaN, 'harmonicConfusedTotal', NaN, 'harmonicConfusedFraction', NaN);

for gi = 1:size(groupDefs, 1)
    groupName = groupDefs{gi, 1};
    groupMask = groupDefs{gi, 2};
    groupSubset = successResults(groupMask);
    if isempty(groupSubset)
        continue
    end
    for bi = 1:numel(branchNames)
        bn = branchNames{bi};
        for mi = 1:numel(metricNames)
            mn = metricNames{mi};
            fieldName = [mn '_' bn];
            if ~isfield(groupSubset, fieldName)
                continue
            end
            vals = [groupSubset.(fieldName)];
            vals = vals(~isnan(vals));
            if isempty(vals)
                continue
            end
            r = blankRow;
            r.kind = 'distribution';
            r.group = groupName;
            r.branch = bn;
            r.metric = mn;
            r.median = median(vals);
            r.iqr25 = prctileLocal(vals, 25);
            r.iqr75 = prctileLocal(vals, 75);
            r.n = numel(vals);
            poolRows(end + 1) = r; %#ok<AGROW>
        end

        confField = ['harmonicConfused_' bn];
        if isfield(groupSubset, confField)
            confVals = [groupSubset.(confField)];
            r = blankRow;
            r.kind = 'harmonic_confusion';
            r.group = groupName;
            r.branch = bn;
            r.harmonicConfusedCount = sum(confVals);
            r.harmonicConfusedTotal = numel(confVals);
            r.harmonicConfusedFraction = sum(confVals) / max(1, numel(confVals));
            poolRows(end + 1) = r; %#ok<AGROW>
        end

        flagField = ['lagFlaggedImplausible_' bn];
        if isfield(groupSubset, flagField)
            flagVals = [groupSubset.(flagField)];
            r = blankRow;
            r.kind = 'lag_flagged';
            r.group = groupName;
            r.branch = bn;
            r.harmonicConfusedCount = sum(flagVals); % reused generic count/total/fraction columns
            r.harmonicConfusedTotal = numel(flagVals);
            r.harmonicConfusedFraction = sum(flagVals) / max(1, numel(flagVals));
            poolRows(end + 1) = r; %#ok<AGROW>
        end

        phaseField = ['phaseClass_' bn];
        if isfield(groupSubset, phaseField)
            phaseVals = {groupSubset.(phaseField)};
            delayCount = sum(strcmp(phaseVals, 'delayOnly'));
            distortedCount = sum(strcmp(phaseVals, 'distorted'));
            classifiedTotal = delayCount + distortedCount;
            r = blankRow;
            r.kind = 'phase_class';
            r.group = groupName;
            r.branch = bn;
            r.harmonicConfusedCount = delayCount; % 'delayOnly' count, reusing generic columns
            r.harmonicConfusedTotal = classifiedTotal;
            r.harmonicConfusedFraction = delayCount / max(1, classifiedTotal);
            poolRows(end + 1) = r; %#ok<AGROW>
        end
    end
end

% --- Worst/best 5 by pooled mismatch score (mean of 1-corr across the
% three branches). ---
pooledScore = nan(1, numel(successResults));
for i = 1:numel(successResults)
    vals = [successResults(i).mismatchScore_chrom, successResults(i).mismatchScore_pos, successResults(i).mismatchScore_harmonic];
    pooledScore(i) = mean(vals(~isnan(vals)));
end

[sortedScore, sortIdx] = sort(pooledScore, 'ascend'); %#ok<ASGLU>
validIdx = sortIdx(~isnan(pooledScore(sortIdx)));

numBest = min(5, numel(validIdx));
numWorst = min(5, numel(validIdx));

for rankI = 1:numBest
    idx = validIdx(rankI);
    r = blankRow;
    r.kind = 'best5';
    r.rank = rankI;
    r.subjectID = successResults(idx).id;
    r.source = successResults(idx).source;
    r.mismatchScore = pooledScore(idx);
    r.corr_chrom = successResults(idx).corr_chrom;
    r.corr_pos = successResults(idx).corr_pos;
    r.corr_harmonic = successResults(idx).corr_harmonic;
    r.lagSec_chrom = successResults(idx).lagSec_chrom;
    r.lagSec_pos = successResults(idx).lagSec_pos;
    r.lagSec_harmonic = successResults(idx).lagSec_harmonic;
    poolRows(end + 1) = r; %#ok<AGROW>
end

for rankI = 1:numWorst
    idx = validIdx(end - rankI + 1);
    r = blankRow;
    r.kind = 'worst5';
    r.rank = rankI;
    r.subjectID = successResults(idx).id;
    r.source = successResults(idx).source;
    r.mismatchScore = pooledScore(idx);
    r.corr_chrom = successResults(idx).corr_chrom;
    r.corr_pos = successResults(idx).corr_pos;
    r.corr_harmonic = successResults(idx).corr_harmonic;
    r.lagSec_chrom = successResults(idx).lagSec_chrom;
    r.lagSec_pos = successResults(idx).lagSec_pos;
    r.lagSec_harmonic = successResults(idx).lagSec_harmonic;
    poolRows(end + 1) = r; %#ok<AGROW>
end

writetable(struct2table(poolRows, 'AsArray', true), pooledCsvPath);
end

function p = prctileLocal(data, percentile)
sortedData = sort(data(:));
n = numel(sortedData);
if n == 1
    p = sortedData(1);
    return
end
position = 1 + (percentile / 100) * (n - 1);
lowerIdx = floor(position);
upperIdx = ceil(position);
weight = position - lowerIdx;
p = sortedData(lowerIdx) * (1 - weight) + sortedData(upperIdx) * weight;
end

function generateExampleFigures(results, branchNames, figuresRoot, processedRoot)
successMask = [results.success];
successResults = results(successMask);
if isempty(successResults)
    return
end

exampleBranches = {'chrom', 'harmonic'}; % one Branch 1 representative, one Branch 2 representative

for bi = 1:numel(exampleBranches)
    bn = exampleBranches{bi};
    scoreField = ['mismatchScore_' bn];
    if ~isfield(successResults, scoreField)
        continue
    end
    scores = [successResults.(scoreField)];
    validMask = ~isnan(scores);
    if ~any(validMask)
        continue
    end
    validIdx = find(validMask);
    [~, bestLocal] = min(scores(validIdx));
    [~, worstLocal] = max(scores(validIdx));
    bestIdx = validIdx(bestLocal);
    worstIdx = validIdx(worstLocal);

    makeExampleFigure(successResults(bestIdx), bn, 'good', figuresRoot, processedRoot);
    makeExampleFigure(successResults(worstIdx), bn, 'bad', figuresRoot, processedRoot);
end
end

function makeExampleFigure(subjectRow, branchName, label, figuresRoot, processedRoot)
try
    cachePath = fullfile(processedRoot, [subjectRow.id '_rgb_traces.mat']);
    if ~isfile(cachePath)
        return
    end
    cached = load(cachePath);
    R = cached.R; G = cached.G; B = cached.B; frameRate = cached.fs;
    roiTimestamps = (0:numel(R) - 1) / frameRate;

    if strcmp(subjectRow.source, 'ubfc_d1')
        thisFileDir = fileparts(mfilename('fullpath'));
        projectRoot = fileparts(fileparts(thisFileDir));
        gtPath = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1', subjectRow.id, 'gtdump.xmp');
        gt = loadGroundTruth(gtPath, 'dataset1');
        gtPPG = gt.ppg(:)';
        gtTimestamps = gt.timestamp(:)';
    else
        thisFileDir = fileparts(mfilename('fullpath'));
        projectRoot = fileparts(fileparts(thisFileDir));
        viplRootLocal = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
        subjNumStr = regexp(subjectRow.id, 'VIPL_p(\d+)_', 'tokens');
        subjNum = str2double(subjNumStr{1}{1});
        gt = loadVIPLGroundTruth(viplRootLocal, subjNum, 1, 1);
        gtPPG = gt.ppg(:)';
        gtTimestamps = (0:numel(gtPPG) - 1) / 60;
    end

    [Rd, ~] = detrendSignal(R);
    [Gd, ~] = detrendSignal(G);
    [Bd, ~] = detrendSignal(B);

    switch branchName
        case 'chrom'
            [Rf, ~] = bandpassClean(Rd, frameRate);
            [Gf, ~] = bandpassClean(Gd, frameRate);
            [Bf, ~] = bandpassClean(Bd, frameRate);
            pulseChrom = chromCombine(Rf, Gf, Bf, R, G, B);
            sig = bandpassClean(pulseChrom, frameRate);
        case 'harmonic'
            [Rw, ~, ~] = bandpassMorphology(Rd, frameRate, 'wide');
            [Gw, ~, ~] = bandpassMorphology(Gd, frameRate, 'wide');
            [Bw, ~, ~] = bandpassMorphology(Bd, frameRate, 'wide');
            pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
            sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;
            [Rahf, ~, ~] = adaptiveHarmonicFilter(Rd, frameRate, 6, sharedF0Hz);
            [Gahf, ~, ~] = adaptiveHarmonicFilter(Gd, frameRate, 6, sharedF0Hz);
            [Bahf, ~, ~] = adaptiveHarmonicFilter(Bd, frameRate, 6, sharedF0Hz);
            sig = chromCombine(Rahf, Gahf, Bahf, R, G, B);
        otherwise
            return
    end

    targetFs = 250;
    [sigAligned, gtAligned, timeAligned, lagSec, ~, ~, ~, ~] = ...
        estimateLagPolarityByGroundTruth(sig, roiTimestamps, gtPPG, gtTimestamps, targetFs, 5);

    sigZ = zscoreLocal(sigAligned);
    gtZ = zscoreLocal(gtAligned);

    N = numel(sigZ);
    winLen = min(N, round(8 * targetFs));
    winLen = max(winLen, min(N, round(2 * targetFs)));
    noverlap = floor(winLen / 2);
    nfft = 2 ^ nextpow2(max(winLen, 1024));
    [PxxSig, fAxis] = pwelch(sigZ, hamming(winLen), noverlap, nfft, targetFs);
    [PxxGT, ~] = pwelch(gtZ, hamming(winLen), noverlap, nfft, targetFs);
    [Cxy, fCoh] = mscohere(sigZ, gtZ, hamming(winLen), noverlap, nfft, targetFs);

    fig = figure('Visible', 'off', 'Position', [100, 100, 900, 900]);

    plotWindowSec = min(15, timeAligned(end) - timeAligned(1));
    plotMask = timeAligned <= (timeAligned(1) + plotWindowSec);

    subplot(3, 1, 1);
    plot(timeAligned(plotMask), sigZ(plotMask), 'b-', 'LineWidth', 1.1); hold on;
    plot(timeAligned(plotMask), gtZ(plotMask), 'r-', 'LineWidth', 1.1);
    legend('rPPG (aligned, z-scored)', 'Ground-truth PPG (z-scored)', 'Location', 'best');
    xlabel('Time (s)'); ylabel('z-score');
    title(sprintf('%s -- %s branch (%s case), lag=%.3fs', subjectRow.id, branchName, label, lagSec), 'Interpreter', 'none');
    grid on;

    subplot(3, 1, 2);
    freqMask = fAxis <= 10;
    plot(fAxis(freqMask), 10 * log10(PxxSig(freqMask) + eps), 'b-'); hold on;
    plot(fAxis(freqMask), 10 * log10(PxxGT(freqMask) + eps), 'r-');
    legend('rPPG PSD', 'GT PSD', 'Location', 'best');
    xlabel('Frequency (Hz)'); ylabel('PSD (dB, z-scored units)');
    title('Welch PSD');
    grid on;

    subplot(3, 1, 3);
    freqMaskCoh = fCoh <= 10;
    plot(fCoh(freqMaskCoh), Cxy(freqMaskCoh), 'k-');
    xlabel('Frequency (Hz)'); ylabel('Magnitude-squared coherence');
    title('Coherence');
    ylim([0, 1]);
    grid on;

    outPath = fullfile(figuresRoot, sprintf('segment10_%s_%s_%s.png', label, branchName, subjectRow.id));
    exportgraphics(fig, outPath, 'Resolution', 150);
    close(fig);
catch figErr
    disp(['Figure generation failed for ' subjectRow.id ' (' branchName ', ' label '): ' figErr.message]);
end
end
