% RUN_SEGMENT14_TASK1_UBFC_D2_HELD_OUT_VALIDATION Segment 14 Task 1 --
% before promoting harmonicFilterConfidenceGate.m to production, validate
% it on GENUINELY HELD-OUT data: UBFC DATASET_2 (42 subjects), which has
% never been decoded, cached, tuned on, or evaluated anywhere in Segments
% 10-13's work. This is the one honest gap in the evidence prior to this
% task -- Segment 10 Task 1's 100-subject audit pool (5 UBFC-D1 + 95 VIPL
% v1/source1) is the SAME pool every subsequent Segment 11/12/13 evaluation
% reused, so nothing in this project has yet been checked against data the
% gate's own design (the 0.3 confidence threshold, choosing alpha=0.15 as
% the fallback) could not have been implicitly shaped by.
%
% DATA PROVENANCE (see docs/DATA_FORMAT.md, written 2026-07-26, "recommended
% action... not yet done" until this task): UBFC DATASET_2's canonical
% archive, `H:\EEE 312 project\Contactless Vital Sign\UBFC dataset\ubfc-
% rppg-dataset.zip`, contains all 42 complete subjects (video + ground_
% truth.txt, no SpO2). A prior session's extraction ATTEMPT briefly filled
% H: to 0 bytes and was rolled back (Segment 7 Task K's own changelog entry)
% -- disk space is no longer a blocker (114GB free measured this session,
% vs. the ~1.6GB average per subject this set needs), so this task performs
% the targeted per-entry extraction docs/DATA_FORMAT.md already recommended,
% using the same technique (`System.IO.Compression.ZipFile`, not a full-
% archive unzip) this project already uses for VIPL.
%
% NO VIDEO FROM THE SEGMENT 10 TASK 1 AUDIT POOL IS TOUCHED. This script
% only reads freshly-extracted DATASET_2 video, decodes it via the
% unmodified io/loadUBFCVideo.m -> roi/extractROISignals.m chain (same
% 'forehead' default every other UBFC script uses), and caches each
% subject's raw RGB trace to data/processed/UBFC_D2_<id>_rgb_traces.mat --
% resumable/checkpointed like every other batch script in this project (a
% subject already cached is skipped, not redecoded).
%
% METHOD: for every successfully decoded subject, run the EXACT SAME
% three-way comparison (ABPF alone / Gaussian alpha=0.15 alone / the
% harmonicFilterConfidenceGate.m gate) that Segment 13 Task 2 ran on the
% audit pool -- same functions, same 0.3 confidence bar, same metrics
% (pass rate, median waveform correlation, harmonic confusion rate, severe
% regression count). Nothing about the gate's own logic is re-derived or
% re-tuned here, per the brief.
%
% Outputs:
%   results/metrics/segment14_task1_ubfc_d2_held_out_validation.csv
%   results/figures/segment14_task1_*.png

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
processedRoot = fullfile(projectRoot, 'data', 'processed');
d2Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_2');

if ~isfolder(metricsRoot); mkdir(metricsRoot); end
if ~isfolder(figuresRoot); mkdir(figuresRoot); end

subjectIds = {'subject1', 'subject3', 'subject4', 'subject5', 'subject8', 'subject9', ...
    'subject10', 'subject11', 'subject12', 'subject13', 'subject14', 'subject15', ...
    'subject16', 'subject17', 'subject18', 'subject20', 'subject22', 'subject23', ...
    'subject24', 'subject25', 'subject26', 'subject27', 'subject30', 'subject31', ...
    'subject32', 'subject33', 'subject34', 'subject35', 'subject36', 'subject37', ...
    'subject38', 'subject39', 'subject40', 'subject41', 'subject42', 'subject43', ...
    'subject44', 'subject45', 'subject46', 'subject47', 'subject48', 'subject49'};
fprintf('UBFC DATASET_2 target pool: %d subjects.\n', numel(subjectIds));

targetFs = 250;
maxLagSec = 5;
confidenceBar = 0.3;

blank = struct('kind', '', 'id', '', ...
    'notchConf_ABPF', NaN, 'corr_ABPF', NaN, 'confused_ABPF', false, ...
    'notchConf_G015', NaN, 'corr_G015', NaN, 'confused_G015', false, ...
    'notchConf_SafeGate', NaN, 'corr_SafeGate', NaN, 'confused_SafeGate', false, 'safeGateSubstituted', false, ...
    'n', NaN, 'nPass', NaN, 'passRate', NaN, 'medianNotchConf', NaN, 'medianCorr', NaN, ...
    'harmonicConfusedFraction', NaN, 'severeRegressionCount', NaN);
rows = repmat(blank, 0, 1);

resultsCsvPath = fullfile(metricsRoot, 'segment14_task1_ubfc_d2_held_out_validation.csv');
if isfile(resultsCsvPath)
    existingTable = readtable(resultsCsvPath);
    existingSubject = existingTable(strcmp(existingTable.kind, 'subject'), :);
    doneIds = cellstr(char(existingSubject.id(:)));
    fprintf('Resuming: %d subjects already in %s.\n', numel(doneIds), resultsCsvPath);
    for i = 1:height(existingSubject)
        r = blank;
        fn = fieldnames(blank);
        for k = 1:numel(fn)
            if isnumeric(blank.(fn{k})) || islogical(blank.(fn{k}))
                r.(fn{k}) = existingSubject.(fn{k})(i);
            end
        end
        r.kind = 'subject';
        r.id = char(existingSubject.id(i));
        rows(end + 1) = r; %#ok<AGROW>
    end
else
    doneIds = {};
end

numProcessed = 0;
numFailed = 0;
failedIds = {};

for si = 1:numel(subjectIds)
    id = subjectIds{si};
    if any(strcmp(doneIds, id))
        continue
    end

    cachePath = fullfile(processedRoot, ['UBFC_D2_' id '_rgb_traces.mat']);
    vidPath = fullfile(d2Root, id, 'vid.avi');
    gtPath = fullfile(d2Root, id, 'ground_truth.txt');

    if ~isfile(cachePath)
        if ~isfile(vidPath) || ~isfile(gtPath)
            fprintf('  SKIP %s: raw files not found (extraction incomplete or subject genuinely missing)\n', id);
            numFailed = numFailed + 1;
            failedIds{end + 1} = id; %#ok<AGROW>
            continue
        end
        try
            fprintf('  Decoding %s ...\n', id);
            decodeTic = tic;
            [frames, fs, ~] = loadUBFCVideo(vidPath);
            [R, G, B, ~] = extractROISignals(frames, fs, 'forehead');
            save(cachePath, 'R', 'G', 'B', 'fs', '-v7');
            fprintf('    decoded+cached in %.1fs (fs=%.3f, %d frames)\n', toc(decodeTic), fs, numel(R));
        catch decodeErr
            fprintf('  SKIP %s: decode failed -- %s\n', id, decodeErr.message);
            numFailed = numFailed + 1;
            failedIds{end + 1} = id; %#ok<AGROW>
            continue
        end
    end

    try
        d = load(cachePath);
        R = d.R; G = d.G; B = d.B; fs = d.fs;
        roiTimestamps = (0:numel(R) - 1) / fs;

        gt = loadGroundTruth(gtPath, 'dataset2');
        gtPPG = gt.ppg(:)';
        gtTimestamps = gt.timestamp(:)';

        [Rd, ~] = detrendSignal(R);
        [Gd, ~] = detrendSignal(G);
        [Bd, ~] = detrendSignal(B);

        [Rw, ~, ~] = bandpassMorphology(Rd, fs, 'wide');
        [Gw, ~, ~] = bandpassMorphology(Gd, fs, 'wide');
        [Bw, ~, ~] = bandpassMorphology(Bd, fs, 'wide');
        pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
        sharedF0Hz = fftHeartRate(pulseWide, fs) / 60;

        [Rh, ~, ~] = adaptiveHarmonicFilter(Rd, fs, 6, sharedF0Hz);
        [Gh, ~, ~] = adaptiveHarmonicFilter(Gd, fs, 6, sharedF0Hz);
        [Bh, ~, ~] = adaptiveHarmonicFilter(Bd, fs, 6, sharedF0Hz);
        pulseABPF = chromCombine(Rh, Gh, Bh, R, G, B);
        [sigABPF, notchConfABPF, corrABPF, confusedABPF] = analyzeHarmonicBranch(pulseABPF, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);

        [Rg, ~, ~] = harmonicSelectiveGaussianFilter(Rd, fs, 6, sharedF0Hz, 0.15);
        [Gg, ~, ~] = harmonicSelectiveGaussianFilter(Gd, fs, 6, sharedF0Hz, 0.15);
        [Bg, ~, ~] = harmonicSelectiveGaussianFilter(Bd, fs, 6, sharedF0Hz, 0.15);
        pulseGauss = chromCombine(Rg, Gg, Bg, R, G, B);
        [sigG015, notchConfG015, corrG015, confusedG015] = analyzeHarmonicBranch(pulseGauss, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);

        [~, ~, selConf, wasSub] = harmonicFilterConfidenceGate( ...
            sigABPF, notchConfABPF, 'abpf', {sigG015}, notchConfG015, {'gaussian015'}, confidenceBar);

        r = blank;
        r.kind = 'subject';
        r.id = id;
        r.notchConf_ABPF = notchConfABPF; r.corr_ABPF = corrABPF; r.confused_ABPF = confusedABPF;
        r.notchConf_G015 = notchConfG015; r.corr_G015 = corrG015; r.confused_G015 = confusedG015;
        r.notchConf_SafeGate = selConf; r.safeGateSubstituted = wasSub;
        if wasSub
            r.corr_SafeGate = corrG015; r.confused_SafeGate = confusedG015;
        else
            r.corr_SafeGate = corrABPF; r.confused_SafeGate = confusedABPF;
        end
        rows(end + 1) = r; %#ok<AGROW>
        numProcessed = numProcessed + 1;
        fprintf('  %s: ABPF conf=%.3f corr=%.3f | Gaussian015 conf=%.3f corr=%.3f | gate conf=%.3f (substituted=%d)\n', ...
            id, notchConfABPF, corrABPF, notchConfG015, corrG015, selConf, wasSub);
    catch procErr
        fprintf('  SKIP %s: processing failed -- %s\n', id, procErr.message);
        numFailed = numFailed + 1;
        failedIds{end + 1} = id; %#ok<AGROW>
    end

    % Checkpoint after every subject.
    writetable(struct2table(rows, 'AsArray', true), resultsCsvPath);
end

fprintf('\n%d/%d subjects processed successfully, %d failed/skipped.\n', numel(rows), numel(subjectIds), numFailed);
if ~isempty(failedIds)
    fprintf('Failed/skipped IDs: %s\n', strjoin(failedIds, ', '));
end

if isempty(rows)
    fprintf('\nNo subjects processed -- nothing to summarize.\n');
    return
end

% ============================================================
% SUMMARY
% ============================================================
conditions = {'ABPF', 'Gaussian015', 'SafeGate'};
notchFields = {'notchConf_ABPF', 'notchConf_G015', 'notchConf_SafeGate'};
corrFields = {'corr_ABPF', 'corr_G015', 'corr_SafeGate'};
confusedFields = {'confused_ABPF', 'confused_G015', 'confused_SafeGate'};

fprintf('\n=== UBFC DATASET_2 held-out validation summary (n=%d) ===\n', numel(rows));
summaryRows = repmat(blank, 0, 1);
abpfNotch = [rows.notchConf_ABPF];
for ci = 1:numel(conditions)
    notchVals = [rows.(notchFields{ci})];
    corrVals = [rows.(corrFields{ci})];
    confusedVals = [rows.(confusedFields{ci})];
    validNotch = ~isnan(notchVals);
    validCorr = ~isnan(corrVals);
    severeRegressionCount = sum((notchVals - abpfNotch) < -0.3 & validNotch);

    r = blank;
    r.kind = 'summary';
    r.id = conditions{ci};
    r.n = sum(validNotch);
    r.nPass = sum(notchVals(validNotch) > confidenceBar);
    r.passRate = r.nPass / max(1, r.n);
    r.medianNotchConf = median(notchVals(validNotch));
    r.medianCorr = median(corrVals(validCorr));
    r.harmonicConfusedFraction = sum(confusedVals) / max(1, numel(confusedVals));
    r.severeRegressionCount = severeRegressionCount;
    summaryRows(end + 1) = r; %#ok<AGROW>

    fprintf('  [%-12s] n=%d pass=%d/%d (%.0f%%) medianNotchConf=%.3f medianCorr=%.3f harmonicConfused=%.0f%% severeRegressionsVsABPF=%d\n', ...
        conditions{ci}, r.n, r.nPass, r.n, 100 * r.passRate, r.medianNotchConf, r.medianCorr, 100 * r.harmonicConfusedFraction, r.severeRegressionCount);
end

allRows = [rows(:); summaryRows(:)];
writetable(struct2table(allRows, 'AsArray', true), resultsCsvPath);
fprintf('\nSaved %s\n', resultsCsvPath);

% ============================================================
% FIGURE
% ============================================================
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
subplot(1, 2, 1);
bar([summaryRows.passRate] * 100);
set(gca, 'XTickLabel', conditions);
ylabel('% pass (notch conf > 0.3)');
title(sprintf('Pass rate, held-out UBFC-D2 (n=%d)', numel(rows)));
grid on;

subplot(1, 2, 2);
bar([summaryRows.medianCorr]);
set(gca, 'XTickLabel', conditions);
ylabel('median waveform correlation');
title('Median waveform correlation');
grid on;
sgtitle('Segment 14 Task 1: ABPF vs. Gaussian(0.15) vs. safe gate, held-out UBFC DATASET_2');
outFig = fullfile(figuresRoot, 'segment14_task1_held_out_summary.png');
exportgraphics(fig, outFig, 'Resolution', 150);
close(fig);
fprintf('Saved %s\n', outFig);
fprintf('\nSegment 14 Task 1 complete.\n');


% ============================================================
% LOCAL FUNCTIONS (identical method to Segment 12/13's own scripts)
% ============================================================
function [sigAligned, notchConf, corrVal, harmonicConfused] = analyzeHarmonicBranch(pulseSignal, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec)
notchConf = NaN; corrVal = NaN; harmonicConfused = false;
sigAligned = pulseSignal;
try
    [sigAligned, gtAligned, ~, ~, ~, ~, ~, ~] = ...
        estimateLagPolarityByGroundTruth(pulseSignal, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
    sigZ = zscoreLocal(sigAligned);
    gtZ = zscoreLocal(gtAligned);
    corrVal = pearsonCorrLocal(sigZ, gtZ);

    [protoSig, ~, ~, ~] = ensembleAverageBeats(sigAligned, targetFs);
    hrSigUsed = fftHeartRate(sigAligned, targetFs);
    effFsSig = numel(protoSig.trimmedMean) * (hrSigUsed / 60);
    [~, ~, ~, notchConf, ~] = notchDetectIEM(protoSig.trimmedMean, effFsSig);

    N = numel(sigZ);
    winLen = min(N, round(8 * targetFs));
    winLen = max(winLen, min(N, round(2 * targetFs)));
    winLen = max(winLen, 8);
    noverlap = floor(winLen / 2);
    nfft = 2 ^ nextpow2(max(winLen, 1024));
    [PxxSig, fAxis] = pwelch(sigZ, hamming(winLen), noverlap, nfft, targetFs);
    [PxxGT, ~] = pwelch(gtZ, hamming(winLen), noverlap, nfft, targetFs);
    searchMask = fAxis >= 0.5 & fAxis <= 8;
    freqsInSearch = fAxis(searchMask);
    [~, idxSig] = max(PxxSig(searchMask));
    [~, idxGt] = max(PxxGT(searchMask));
    sigPeakHz = freqsInSearch(idxSig);
    gtPeakHz = freqsInSearch(idxGt);
    if gtPeakHz > 0
        ratio = sigPeakHz / gtPeakHz;
        candidates = [1 / 3, 1 / 2, 1, 2, 3];
        [~, ci] = min(abs(ratio - candidates));
        nearest = candidates(ci);
        harmonicConfused = (nearest ~= 1) && (abs(ratio - nearest) / nearest < 0.08);
    end
catch
    % leave NaN/false
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
x = x(:); y = y(:);
xc = x - mean(x);
yc = y - mean(y);
denom = sqrt(sum(xc .^ 2) * sum(yc .^ 2));
if denom > 0
    r = sum(xc .* yc) / denom;
else
    r = NaN;
end
end
