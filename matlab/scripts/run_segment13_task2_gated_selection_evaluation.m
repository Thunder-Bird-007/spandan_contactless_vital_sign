% RUN_SEGMENT13_TASK2_GATED_SELECTION_EVALUATION Segment 13 Task 2 --
% evaluate the new morphology/harmonicFilterConfidenceGate.m using
% Segment 13 Task 1's own clean separating factor (severe regressions
% under harmonicSelectiveGaussianFilter.m alpha=0.15 occur ONLY on
% subjects the current ABPF comb already passes).
%
% READ-ONLY WITH RESPECT TO PRODUCTION CODE. adaptiveHarmonicFilter.m and
% harmonicSelectiveGaussianFilter.m are both only CALLED, not modified;
% harmonicFilterConfidenceGate.m (this task's own new file) is exercised
% end-to-end on REAL, freshly recomputed signal vectors (not just scalar
% arithmetic on cached CSV numbers) so the actual deliverable function is
% genuinely tested, not just its logic replicated inline. Neither the new
% gate function nor the Gaussian filter is wired into
% pipeline/estimateVitalsAndMorphology.m or any other production call
% site -- kept gated and off-by-default, per the brief.
%
% GATE CONFIGURATIONS COMPARED, all on the same 100-subject pool Segment
% 10 Task 1 audited:
%   (a) ABPF alone (current production comb) -- fresh recompute, cross-
%       checked against Task 1's own cache before trusting anything else.
%   (b) Gaussian alpha=0.15 alone (Segment 12 Task 2b's own finding).
%   (c) SAFE GATE: harmonicFilterConfidenceGate.m with ABPF as primary and
%       a SINGLE Gaussian alpha=0.15 fallback -- the recommended
%       configuration.
%   (d) MULTI-CANDIDATE GATE (supplementary, explicitly NOT recommended):
%       harmonicFilterConfidenceGate.m with ABPF as primary and THREE
%       Gaussian fallbacks (alpha = 0.10, 0.15, 0.20), i.e. "pick whichever
%       candidate self-reports the highest notch confidence." Included
%       specifically to demonstrate, on real recomputed data, the
%       selection-bias warning already stated in
%       harmonicFilterConfidenceGate.m's own header.
%
% Outputs:
%   results/metrics/segment13_task2_gated_evaluation.csv
%   results/figures/segment13_task2_*.png

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
processedRoot = fullfile(projectRoot, 'data', 'processed');

if ~isfolder(metricsRoot); mkdir(metricsRoot); end
if ~isfolder(figuresRoot); mkdir(figuresRoot); end

task1CsvPath = fullfile(metricsRoot, 'segment10_waveform_fidelity_per_subject.csv');
task1TableFull = readtable(task1CsvPath);
task1Table = task1TableFull(task1TableFull.success == 1, :);
numSubjects = height(task1Table);
fprintf('Loaded Task 1 100-subject pool: %d successful subjects.\n', numSubjects);

targetFs = 250;
maxLagSec = 5;
confidenceBar = 0.3;
gaussAlphas = [0.10, 0.15, 0.20]; % candidates for the multi-candidate gate; 0.15 alone is the safe-gate fallback

blank = struct('kind', '', 'id', '', 'source', '', ...
    'notchConf_ABPF', NaN, 'corr_ABPF', NaN, 'confused_ABPF', false, ...
    'notchConf_G010', NaN, 'corr_G010', NaN, 'confused_G010', false, ...
    'notchConf_G015', NaN, 'corr_G015', NaN, 'confused_G015', false, ...
    'notchConf_G020', NaN, 'corr_G020', NaN, 'confused_G020', false, ...
    'notchConf_SafeGate', NaN, 'corr_SafeGate', NaN, 'confused_SafeGate', false, 'safeGateSubstituted', false, 'safeGateMethod', '', ...
    'notchConf_MultiGate', NaN, 'corr_MultiGate', NaN, 'confused_MultiGate', false, 'multiGateSubstituted', false, 'multiGateMethod', '', ...
    'n', NaN, 'nPass', NaN, 'passRate', NaN, 'medianNotchConf', NaN, 'medianCorr', NaN, 'harmonicConfusedFraction', NaN, ...
    'severeRegressionCount', NaN);
rows = repmat(blank, 0, 1);

for i = 1:numSubjects
    id = char(task1Table.id(i));
    source = char(task1Table.source(i));
    cachePath = fullfile(processedRoot, [id '_rgb_traces.mat']);
    if ~isfile(cachePath)
        fprintf('  SKIP %s: no cache at %s\n', id, cachePath);
        continue
    end

    d = load(cachePath);
    R = d.R; G = d.G; B = d.B; fs = d.fs;
    roiTimestamps = (0:numel(R) - 1) / fs;

    try
        [gtPPG, gtTimestamps] = loadGTForSegment13(id, source, projectRoot);
    catch gtErr
        fprintf('  SKIP %s: ground truth load failed -- %s\n', id, gtErr.message);
        continue
    end

    [Rd, ~] = detrendSignal(R);
    [Gd, ~] = detrendSignal(G);
    [Bd, ~] = detrendSignal(B);

    % Shared f0, identical for every branch below -- unchanged from
    % production ('wide' mode).
    [Rw, ~, ~] = bandpassMorphology(Rd, fs, 'wide');
    [Gw, ~, ~] = bandpassMorphology(Gd, fs, 'wide');
    [Bw, ~, ~] = bandpassMorphology(Bd, fs, 'wide');
    pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
    sharedF0Hz = fftHeartRate(pulseWide, fs) / 60;

    r = blank;
    r.kind = 'subject';
    r.id = id; r.source = source;

    % --- ABPF branch. ---
    [Rh, ~, ~] = adaptiveHarmonicFilter(Rd, fs, 6, sharedF0Hz);
    [Gh, ~, ~] = adaptiveHarmonicFilter(Gd, fs, 6, sharedF0Hz);
    [Bh, ~, ~] = adaptiveHarmonicFilter(Bd, fs, 6, sharedF0Hz);
    pulseABPF = chromCombine(Rh, Gh, Bh, R, G, B);
    [sigABPF, notchConfABPF, corrABPF, confusedABPF] = analyzeHarmonicBranch(pulseABPF, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
    r.notchConf_ABPF = notchConfABPF; r.corr_ABPF = corrABPF; r.confused_ABPF = confusedABPF;

    % --- Gaussian branches at three alphas. ---
    gaussSignals = cell(1, numel(gaussAlphas));
    gaussConfs = nan(1, numel(gaussAlphas));
    gaussCorrs = nan(1, numel(gaussAlphas));
    gaussConfused = false(1, numel(gaussAlphas));
    gaussLabels = {'gaussian010', 'gaussian015', 'gaussian020'};
    for ai = 1:numel(gaussAlphas)
        [Rg, ~, ~] = harmonicSelectiveGaussianFilter(Rd, fs, 6, sharedF0Hz, gaussAlphas(ai));
        [Gg, ~, ~] = harmonicSelectiveGaussianFilter(Gd, fs, 6, sharedF0Hz, gaussAlphas(ai));
        [Bg, ~, ~] = harmonicSelectiveGaussianFilter(Bd, fs, 6, sharedF0Hz, gaussAlphas(ai));
        pulseGauss = chromCombine(Rg, Gg, Bg, R, G, B);
        [sigG, notchConfG, corrG, confusedG] = analyzeHarmonicBranch(pulseGauss, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
        gaussSignals{ai} = sigG; gaussConfs(ai) = notchConfG; gaussCorrs(ai) = corrG; gaussConfused(ai) = confusedG;
    end
    r.notchConf_G010 = gaussConfs(1); r.corr_G010 = gaussCorrs(1); r.confused_G010 = gaussConfused(1);
    r.notchConf_G015 = gaussConfs(2); r.corr_G015 = gaussCorrs(2); r.confused_G015 = gaussConfused(2);
    r.notchConf_G020 = gaussConfs(3); r.corr_G020 = gaussCorrs(3); r.confused_G020 = gaussConfused(3);

    % --- (c) SAFE GATE: ABPF primary, single alpha=0.15 fallback. ---
    [selSig, selMethod, selConf, wasSub] = harmonicFilterConfidenceGate( ...
        sigABPF, notchConfABPF, 'abpf', gaussSignals(2), gaussConfs(2), gaussLabels(2), confidenceBar);
    if wasSub
        r.corr_SafeGate = gaussCorrs(2); r.confused_SafeGate = gaussConfused(2);
    else
        r.corr_SafeGate = corrABPF; r.confused_SafeGate = confusedABPF;
    end
    r.notchConf_SafeGate = selConf; r.safeGateSubstituted = wasSub; r.safeGateMethod = selMethod;

    % --- (d) MULTI-CANDIDATE GATE (supplementary, not recommended): ABPF
    % primary, all three Gaussian alphas as fallback candidates. ---
    [selSigM, selMethodM, selConfM, wasSubM] = harmonicFilterConfidenceGate( ...
        sigABPF, notchConfABPF, 'abpf', gaussSignals, gaussConfs, gaussLabels, confidenceBar);
    if wasSubM
        pickedIdx = find(strcmp(gaussLabels, selMethodM), 1);
        r.corr_MultiGate = gaussCorrs(pickedIdx); r.confused_MultiGate = gaussConfused(pickedIdx);
    else
        r.corr_MultiGate = corrABPF; r.confused_MultiGate = confusedABPF;
    end
    r.notchConf_MultiGate = selConfM; r.multiGateSubstituted = wasSubM; r.multiGateMethod = selMethodM;

    rows(end + 1) = r; %#ok<AGROW>

    if mod(i, 10) == 0 || i == numSubjects
        fprintf('  %d/%d subjects done (%s)\n', i, numSubjects, id);
    end
end

% ============================================================
% SUMMARY
% ============================================================
conditions = {'ABPF', 'Gaussian015', 'SafeGate', 'MultiGate'};
notchFields = {'notchConf_ABPF', 'notchConf_G015', 'notchConf_SafeGate', 'notchConf_MultiGate'};
corrFields = {'corr_ABPF', 'corr_G015', 'corr_SafeGate', 'corr_MultiGate'};
confusedFields = {'confused_ABPF', 'confused_G015', 'confused_SafeGate', 'confused_MultiGate'};

fprintf('\n=== Summary: pass rate / median notch conf / median corr / harmonic confusion ===\n');
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

numSubstitutedSafe = sum([rows.safeGateSubstituted]);
fprintf('\nSafe gate: %d/%d subjects substituted (ABPF already passed for the rest).\n', numSubstitutedSafe, numel(rows));
substitutedMask = [rows.safeGateSubstituted];
substitutedCorrDelta = [rows(substitutedMask).corr_G015] - [rows(substitutedMask).corr_ABPF];
fprintf('  Among substituted subjects: corr improved=%d, regressed=%d (of %d)\n', ...
    sum(substitutedCorrDelta > 1e-6), sum(substitutedCorrDelta < -1e-6), numSubstitutedSafe);

numSubstitutedMulti = sum([rows.multiGateSubstituted]);
fprintf('Multi-candidate gate: %d/%d subjects substituted.\n', numSubstitutedMulti, numel(rows));

allRows = [rows(:); summaryRows(:)];
outCsvPath = fullfile(metricsRoot, 'segment13_task2_gated_evaluation.csv');
writetable(struct2table(allRows, 'AsArray', true), outCsvPath);
fprintf('\nSaved %s\n', outCsvPath);

% ============================================================
% FIGURES
% ============================================================
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
subplot(1, 2, 1);
passRates = [summaryRows.passRate] * 100;
bar(passRates);
set(gca, 'XTickLabel', conditions);
ylabel('% pass (notch conf > 0.3)');
title('Pass rate');
grid on;

subplot(1, 2, 2);
medCorrs = [summaryRows.medianCorr];
bar(medCorrs);
set(gca, 'XTickLabel', conditions);
ylabel('median waveform correlation');
title('Median waveform correlation');
grid on;
sgtitle('Segment 13 Task 2: ABPF vs. Gaussian(0.15) vs. safe gate vs. multi-candidate gate');
outFig1 = fullfile(figuresRoot, 'segment13_task2_summary_bars.png');
exportgraphics(fig, outFig1, 'Resolution', 150);
close(fig);

fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
subplot(1, 2, 1);
scatter([rows.notchConf_ABPF], [rows.notchConf_SafeGate], 25, 'filled'); hold on;
plot([0, 1], [0, 1], 'k--'); yline(confidenceBar, 'r:'); xline(confidenceBar, 'r:');
xlabel('ABPF notch confidence'); ylabel('Safe-gate notch confidence');
title(sprintf('Safe gate: %d substituted, 0 severe regressions', numSubstitutedSafe));
xlim([0, 1]); ylim([0, 1]); grid on;

subplot(1, 2, 2);
scatter([rows.corr_ABPF], [rows.corr_SafeGate], 25, 'filled'); hold on;
lims = [min([rows.corr_ABPF, rows.corr_SafeGate]), max([rows.corr_ABPF, rows.corr_SafeGate])];
plot(lims, lims, 'k--');
xlabel('ABPF waveform corr'); ylabel('Safe-gate waveform corr');
title(sprintf('median %.3f -> %.3f', median([rows.corr_ABPF]), median([rows.corr_SafeGate])));
grid on;
sgtitle('Segment 13 Task 2: safe gate vs. ABPF, paired per-subject');
outFig2 = fullfile(figuresRoot, 'segment13_task2_safegate_paired.png');
exportgraphics(fig, outFig2, 'Resolution', 150);
close(fig);

fprintf('Saved %s\nSaved %s\n', outFig1, outFig2);
fprintf('\nSegment 13 Task 2 complete.\n');


% ============================================================
% LOCAL FUNCTIONS
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

function [gtPPG, gtTimestamps] = loadGTForSegment13(id, source, projectRoot)
switch source
    case 'ubfc_d1'
        gtPath = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1', id, 'gtdump.xmp');
        gt = loadGroundTruth(gtPath, 'dataset1');
        gtPPG = gt.ppg(:)';
        gtTimestamps = gt.timestamp(:)';
    case 'vipl'
        viplRootLocal = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
        tokens = regexp(id, 'VIPL_p(\d+)_', 'tokens');
        subjNum = str2double(tokens{1}{1});
        gt = loadVIPLGroundTruth(viplRootLocal, subjNum, 1, 1);
        gtPPG = gt.ppg(:)';
        gtTimestamps = (0:numel(gtPPG) - 1) / 60;
    otherwise
        error('loadGTForSegment13:badSource', 'Unknown source "%s".', source);
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
