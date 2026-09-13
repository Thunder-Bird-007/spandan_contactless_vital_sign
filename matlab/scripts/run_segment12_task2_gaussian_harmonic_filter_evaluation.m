% RUN_SEGMENT12_TASK2_GAUSSIAN_HARMONIC_FILTER_EVALUATION Segment 12 Task 2
% -- head-to-head evaluation of morphology/harmonicSelectiveGaussianFilter.m
% (NEW, gated, off-by-default) against morphology/adaptiveHarmonicFilter.m's
% existing hard-edged ABPF comb, on the same 100-subject pool Segment 10
% Task 1 audited.
%
% READ-ONLY WITH RESPECT TO PRODUCTION CODE. adaptiveHarmonicFilter.m is
% called, never modified; harmonicSelectiveGaussianFilter.m (Segment 12
% Task 2's own new file) is likewise only called here, never wired into
% pipeline/estimateVitalsAndMorphology.m or any other production call
% site. Both branches are computed in this ONE script, side by side, so
% the comparison is apples-to-apples under identical code/environment
% (not "Gaussian numbers from this session vs. ABPF numbers cached from a
% different session's script") -- and the freshly-recomputed ABPF branch
% is cross-checked against Task 1's own already-published CSV as a
% regression/sanity check before trusting anything built the same way.
%
% ISOLATION: the ONLY difference between the two branches below is the
% harmonic-filter call itself (adaptiveHarmonicFilter.m vs.
% harmonicSelectiveGaussianFilter.m). The shared-f0 estimation step
% (morphology/bandpassMorphology.m 'wide') is IDENTICAL in both branches,
% unchanged from production -- Segment 12 Task 1's 'mid'-mode question is
% a separate, independent change and is NOT combined with this one, so
% this comparison isolates the harmonic-filter SHAPE question alone.
%
% METRICS (per the brief): notch confidence (the 0.3 bar, this project's
% own house threshold), waveform correlation vs. ground truth (Task 1's
% headline metric), and the harmonic-confusion rate (Task 1 finding 3's
% own detector, reproduced exactly: nearest-integer/fractional-multiple
% check on each signal's own dominant in-band PSD peak vs. GT's).
%
% Outputs:
%   results/metrics/segment12_task2_gaussian_vs_abpf_comparison.csv
%   results/figures/segment12_task2_*.png

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
methods = {'abpf', 'gaussian'};
confidenceBar = 0.3;

blank = struct('kind', '', 'id', '', 'source', '', 'method', '', ...
    'sharedF0Hz', NaN, 'corr', NaN, 'lagSec', NaN, ...
    'notchDetected', false, 'notchPosNorm', NaN, 'notchDepth', NaN, 'notchConfidence', NaN, ...
    'notchConfidence_task1CSV', NaN, 'notchConfMatchesTask1', false, ...
    'corr_task1CSV', NaN, 'corrMatchesTask1', false, ...
    'sigPeakHz', NaN, 'gtPeakHz', NaN, 'peakRatio', NaN, 'nearestHarmonicMultiple', NaN, 'harmonicConfused', false, ...
    'harmonicConfused_task1CSV', NaN, ...
    'n', NaN, 'nPass', NaN, 'passRate', NaN, 'medianNotchConf', NaN, 'medianCorr', NaN, ...
    'harmonicConfusedCount', NaN, 'harmonicConfusedFraction', NaN);
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
        [gtPPG, gtTimestamps] = loadGTForSegment12b(id, source, projectRoot);
    catch gtErr
        fprintf('  SKIP %s: ground truth load failed -- %s\n', id, gtErr.message);
        continue
    end

    [Rd, ~] = detrendSignal(R);
    [Gd, ~] = detrendSignal(G);
    [Bd, ~] = detrendSignal(B);

    % Shared f0, IDENTICAL for both branches, unchanged from production
    % ('wide' mode -- Task 1's own baseline, NOT Task 12 Task 1's 'mid'
    % question, which is a separate, independent change).
    [Rw, ~, ~] = bandpassMorphology(Rd, fs, 'wide');
    [Gw, ~, ~] = bandpassMorphology(Gd, fs, 'wide');
    [Bw, ~, ~] = bandpassMorphology(Bd, fs, 'wide');
    pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
    sharedF0Hz = fftHeartRate(pulseWide, fs) / 60;

    for mi = 1:numel(methods)
        method = methods{mi};

        r = blank;
        r.kind = 'subject';
        r.id = id; r.source = source; r.method = method; r.sharedF0Hz = sharedF0Hz;

        try
            if strcmp(method, 'abpf')
                [Rh, ~, ~] = adaptiveHarmonicFilter(Rd, fs, 6, sharedF0Hz);
                [Gh, ~, ~] = adaptiveHarmonicFilter(Gd, fs, 6, sharedF0Hz);
                [Bh, ~, ~] = adaptiveHarmonicFilter(Bd, fs, 6, sharedF0Hz);
            else
                [Rh, ~, ~] = harmonicSelectiveGaussianFilter(Rd, fs, 6, sharedF0Hz);
                [Gh, ~, ~] = harmonicSelectiveGaussianFilter(Gd, fs, 6, sharedF0Hz);
                [Bh, ~, ~] = harmonicSelectiveGaussianFilter(Bd, fs, 6, sharedF0Hz);
            end
            pulseHarmonic = chromCombine(Rh, Gh, Bh, R, G, B);

            [sigAligned, gtAligned, ~, lagSec, ~, ~, ~, ~] = ...
                estimateLagPolarityByGroundTruth(pulseHarmonic, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
            r.lagSec = lagSec;

            sigZ = zscoreLocal(sigAligned);
            gtZ = zscoreLocal(gtAligned);
            r.corr = pearsonCorrLocal(sigZ, gtZ);

            [protoSig, ~, ~, ~] = ensembleAverageBeats(sigAligned, targetFs);
            hrSigUsed = fftHeartRate(sigAligned, targetFs);
            effFsSig = numel(protoSig.trimmedMean) * (hrSigUsed / 60);
            [notchDet, notchPos, notchDepth, notchConf, ~] = notchDetectIEM(protoSig.trimmedMean, effFsSig);
            r.notchDetected = notchDet;
            r.notchPosNorm = notchPos;
            r.notchDepth = notchDepth;
            r.notchConfidence = notchConf;

            % --- Harmonic-confusion detector, reproduced exactly from
            % run_segment10_waveform_fidelity_audit.m's own Step 4. ---
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
            r.sigPeakHz = sigPeakHz;
            r.gtPeakHz = gtPeakHz;
            if gtPeakHz > 0
                ratio = sigPeakHz / gtPeakHz;
                candidates = [1 / 3, 1 / 2, 1, 2, 3];
                [~, ci] = min(abs(ratio - candidates));
                nearest = candidates(ci);
                r.peakRatio = ratio;
                r.nearestHarmonicMultiple = nearest;
                r.harmonicConfused = (nearest ~= 1) && (abs(ratio - nearest) / nearest < 0.08);
            end
        catch procErr
            fprintf('  %s [%s]: FAILED -- %s\n', id, method, procErr.message);
        end

        if strcmp(method, 'abpf')
            r.notchConfidence_task1CSV = task1Table.notchConfidence_harmonic(i);
            r.corr_task1CSV = task1Table.corr_harmonic(i);
            r.harmonicConfused_task1CSV = task1Table.harmonicConfused_harmonic(i);
            if ~isnan(r.notchConfidence) && ~isnan(r.notchConfidence_task1CSV)
                r.notchConfMatchesTask1 = abs(r.notchConfidence - r.notchConfidence_task1CSV) < 1e-6;
            end
            if ~isnan(r.corr) && ~isnan(r.corr_task1CSV)
                r.corrMatchesTask1 = abs(r.corr - r.corr_task1CSV) < 1e-6;
            end
        end

        rows(end + 1) = r; %#ok<AGROW>
    end

    if mod(i, 10) == 0 || i == numSubjects
        fprintf('  %d/%d subjects done (%s)\n', i, numSubjects, id);
    end
end

% --- Regression check: freshly recomputed ABPF vs Task 1's own CSV. ---
abpfRows = rows(strcmp({rows.kind}, 'subject') & strcmp({rows.method}, 'abpf'));
gaussRows = rows(strcmp({rows.kind}, 'subject') & strcmp({rows.method}, 'gaussian'));

validConf = ~isnan([abpfRows.notchConfidence]) & ~isnan([abpfRows.notchConfidence_task1CSV]);
numMatchedConf = sum([abpfRows(validConf).notchConfMatchesTask1]);
validCorr = ~isnan([abpfRows.corr]) & ~isnan([abpfRows.corr_task1CSV]);
numMatchedCorr = sum([abpfRows(validCorr).corrMatchesTask1]);
fprintf('\n=== Regression check: fresh ABPF recompute vs. Task 1''s own CSV ===\n');
fprintf('  notchConfidence: %d/%d match to 1e-6.\n', numMatchedConf, sum(validConf));
fprintf('  waveform corr:   %d/%d match to 1e-6.\n', numMatchedCorr, sum(validCorr));

% --- Summary rows. ---
for mi = 1:numel(methods)
    method = methods{mi};
    subset = rows(strcmp({rows.kind}, 'subject') & strcmp({rows.method}, method));
    confVals = [subset.notchConfidence];
    confVals = confVals(~isnan(confVals));
    corrVals = [subset.corr];
    corrVals = corrVals(~isnan(corrVals));
    confusedVals = [subset.harmonicConfused];

    r = blank;
    r.kind = 'summary';
    r.method = method;
    r.n = numel(subset);
    r.nPass = sum(confVals > confidenceBar);
    r.passRate = r.nPass / max(1, numel(confVals));
    r.medianNotchConf = median(confVals);
    r.medianCorr = median(corrVals);
    r.harmonicConfusedCount = sum(confusedVals);
    r.harmonicConfusedFraction = sum(confusedVals) / max(1, numel(confusedVals));
    rows(end + 1) = r; %#ok<AGROW>
    fprintf('  [summary %s] n=%d pass(>%.1f)=%d/%d (%.0f%%) medianNotchConf=%.3f medianCorr=%.3f harmonicConfused=%d/%d (%.0f%%)\n', ...
        method, r.n, confidenceBar, r.nPass, numel(confVals), 100 * r.passRate, r.medianNotchConf, r.medianCorr, ...
        r.harmonicConfusedCount, numel(confusedVals), 100 * r.harmonicConfusedFraction);
end

% --- Per-subject delta summary (paired by id). ---
idsAbpf = {abpfRows.id};
idsGauss = {gaussRows.id};
[commonIds, ia, ig] = intersect(idsAbpf, idsGauss);
notchDeltas = [gaussRows(ig).notchConfidence] - [abpfRows(ia).notchConfidence];
corrDeltas = [gaussRows(ig).corr] - [abpfRows(ia).corr];
validNotch = ~isnan(notchDeltas);
validCorrD = ~isnan(corrDeltas);

r = blank;
r.kind = 'delta_summary';
r.n = numel(commonIds);
r.notchConfidence = median(notchDeltas(validNotch)); % reused field: median(gaussian-abpf) notch delta
r.corr = median(corrDeltas(validCorrD));              % reused field: median(gaussian-abpf) corr delta
rows(end + 1) = r; %#ok<AGROW>
fprintf('  [delta gaussian-abpf] n=%d median notchConfDelta=%.4f median corrDelta=%.4f\n', r.n, r.notchConfidence, r.corr);

numImprovedNotch = sum(notchDeltas(validNotch) > 1e-6);
numRegressedNotch = sum(notchDeltas(validNotch) < -1e-6);
numImprovedCorr = sum(corrDeltas(validCorrD) > 1e-6);
numRegressedCorr = sum(corrDeltas(validCorrD) < -1e-6);
fprintf('  notchConfidence: %d improved, %d regressed, %d unchanged (of %d)\n', ...
    numImprovedNotch, numRegressedNotch, sum(validNotch) - numImprovedNotch - numRegressedNotch, sum(validNotch));
fprintf('  waveform corr:   %d improved, %d regressed, %d unchanged (of %d)\n', ...
    numImprovedCorr, numRegressedCorr, sum(validCorrD) - numImprovedCorr - numRegressedCorr, sum(validCorrD));

outCsvPath = fullfile(metricsRoot, 'segment12_task2_gaussian_vs_abpf_comparison.csv');
writetable(struct2table(rows, 'AsArray', true), outCsvPath);
fprintf('\nSaved %s\n', outCsvPath);


% ============================================================
% FIGURES
% ============================================================

% --- Paired notch confidence scatter. ---
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
subplot(1, 2, 1);
abpfConf = [abpfRows(ia).notchConfidence];
gaussConf = [gaussRows(ig).notchConfidence];
validMask = ~isnan(abpfConf) & ~isnan(gaussConf);
scatter(abpfConf(validMask), gaussConf(validMask), 25, 'filled'); hold on;
plot([0, 1], [0, 1], 'k--');
yline(confidenceBar, 'r:'); xline(confidenceBar, 'r:');
xlabel('Notch confidence, ABPF comb (current)'); ylabel('Notch confidence, Gaussian (new)');
title(sprintf('n=%d: median ABPF=%.3f Gaussian=%.3f', sum(validMask), median(abpfConf(validMask)), median(gaussConf(validMask))));
xlim([0, 1]); ylim([0, 1]);
grid on;

subplot(1, 2, 2);
abpfCorr = [abpfRows(ia).corr];
gaussCorr = [gaussRows(ig).corr];
validMaskC = ~isnan(abpfCorr) & ~isnan(gaussCorr);
scatter(abpfCorr(validMaskC), gaussCorr(validMaskC), 25, 'filled'); hold on;
lims = [min([abpfCorr(validMaskC), gaussCorr(validMaskC)]), max([abpfCorr(validMaskC), gaussCorr(validMaskC)])];
plot(lims, lims, 'k--');
xlabel('Waveform corr, ABPF comb (current)'); ylabel('Waveform corr, Gaussian (new)');
title(sprintf('n=%d: median ABPF=%.3f Gaussian=%.3f', sum(validMaskC), median(abpfCorr(validMaskC)), median(gaussCorr(validMaskC))));
grid on;
sgtitle('Segment 12 Task 2: Gaussian harmonic filter vs. ABPF comb, paired per-subject');
outFig1 = fullfile(figuresRoot, 'segment12_task2_paired_scatter.png');
exportgraphics(fig, outFig1, 'Resolution', 150);
close(fig);

% --- Summary bar: pass-rate and harmonic-confusion rate. ---
fig = figure('Visible', 'off', 'Position', [100, 100, 800, 450]);
summaryRows = rows(strcmp({rows.kind}, 'summary'));
passRates = [summaryRows.passRate] * 100;   % order: [abpf, gaussian]
confusedRates = [summaryRows.harmonicConfusedFraction] * 100; % order: [abpf, gaussian]
barData = [passRates; confusedRates]; % rows = metric (x-groups), columns = method (abpf, gaussian) -- NOT transposed, see bar()'s own row=group/col=series convention
b = bar(barData);
set(gca, 'XTickLabel', {'notch confidence >0.3', 'harmonic confusion rate'});
legend({'ABPF (current)', 'Gaussian (new)'}, 'Location', 'best');
ylabel('% of 100 subjects');
title('Segment 12 Task 2: pass-rate and harmonic-confusion rate, ABPF vs. Gaussian');
grid on;
outFig2 = fullfile(figuresRoot, 'segment12_task2_summary_bars.png');
exportgraphics(fig, outFig2, 'Resolution', 150);
close(fig);

% --- Supplementary: visualize the actual composite frequency-domain mask
% for a representative f0 (this pool's own median sharedF0Hz, ~1.2Hz),
% ABPF's rectangular comb vs. the Gaussian filter's composite H(f) -- to
% show WHY the Gaussian filter underperforms (see the doc's own
% mechanistic explanation): with the paper's own alpha=0.5, sigma=f0/2, so
% each harmonic's Gaussian full-width (~2.355*sigma = ~1.18*f0) already
% exceeds the harmonic spacing (f0) itself, causing heavy overlap between
% adjacent harmonics rather than the intended narrow, selective comb.
f0Example = median([abpfRows.sharedF0Hz]);
fsExample = 30;
NExample = 900;
freqAxisPlot = (0:NExample - 1) * (fsExample / NExample);
freqAxisPlot(freqAxisPlot > fsExample / 2) = freqAxisPlot(freqAxisPlot > fsExample / 2) - fsExample;

rectMask = zeros(1, NExample);
freqResolutionExample = fsExample / NExample;
nyquistBinIdxExample = floor(NExample / 2) + 1;
for h = 1:6
    centerBinIdx = round((h * f0Example) / freqResolutionExample) + 1;
    if centerBinIdx > nyquistBinIdxExample; continue; end
    for offset = -1:1
        binIdx = centerBinIdx + offset;
        if binIdx < 2 || binIdx > nyquistBinIdxExample; continue; end
        rectMask(binIdx) = 1;
        mirrorBinIdx = NExample - binIdx + 2;
        if mirrorBinIdx >= 1 && mirrorBinIdx <= NExample; rectMask(mirrorBinIdx) = 1; end
    end
end

sigmaExample = 0.5 * f0Example;
gaussMask = zeros(1, NExample);
for h = 1:6
    harmonicFreqHz = h * f0Example;
    gaussMask = gaussMask + exp(-((freqAxisPlot - harmonicFreqHz) .^ 2) / (sigmaExample ^ 2)) ...
                          + exp(-((freqAxisPlot + harmonicFreqHz) .^ 2) / (sigmaExample ^ 2));
end

[sortedFreq, sortIdx] = sort(freqAxisPlot);
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
plot(sortedFreq, rectMask(sortIdx), 'b-', 'LineWidth', 1.2); hold on;
plot(sortedFreq, gaussMask(sortIdx), 'r-', 'LineWidth', 1.2);
xlim([-1, 9]);
xlabel('Frequency (Hz)'); ylabel('Filter magnitude mask H(f)');
legend({'ABPF rectangular comb', sprintf('Gaussian comb (alpha=0.5, f0=%.2fHz)', f0Example)}, 'Location', 'best');
title(sprintf('Composite harmonic-filter mask, f0=%.2fHz (this pool''s own median): adjacent Gaussians visibly overlap', f0Example));
grid on;
outFig3 = fullfile(figuresRoot, 'segment12_task2_mask_comparison.png');
exportgraphics(fig, outFig3, 'Resolution', 150);
close(fig);
fprintf('Saved %s\n', outFig3);

fprintf('Saved %s\nSaved %s\n', outFig1, outFig2);
fprintf('\nSegment 12 Task 2 complete.\n');


% ============================================================
% LOCAL FUNCTIONS
% ============================================================
function [gtPPG, gtTimestamps] = loadGTForSegment12b(id, source, projectRoot)
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
        error('loadGTForSegment12b:badSource', 'Unknown source "%s".', source);
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
