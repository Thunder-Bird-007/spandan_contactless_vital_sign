% RUN_SEGMENT12_TASK2B_GAUSSIAN_ALPHA_SWEEP Segment 12 Task 2, follow-up
% sensitivity check -- Segment 12 Task 2's head-to-head found
% morphology/harmonicSelectiveGaussianFilter.m UNDERPERFORMS the current
% ABPF comb at the paper's own literal alpha=0.5 (sigma=f0/2), with a
% mechanistic explanation (adjacent-harmonic Gaussian overlap, see that
% task's own doc). This script asks the natural next question BEFORE
% concluding the underlying method is unsound: does a TIGHTER Gaussian
% (smaller alpha, less overlap) close the gap, or is alpha=0.5 not the
% real problem?
%
% READ-ONLY WITH RESPECT TO PRODUCTION CODE. Only calls
% harmonicSelectiveGaussianFilter.m (this task's own new, gated file) with
% different alpha values via its existing optional 5th argument -- no
% production file touched.
%
% Outputs:
%   results/metrics/segment12_task2b_gaussian_alpha_sweep.csv
%   results/figures/segment12_task2b_alpha_sweep.png

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
processedRoot = fullfile(projectRoot, 'data', 'processed');

task1CsvPath = fullfile(metricsRoot, 'segment10_waveform_fidelity_per_subject.csv');
task1TableFull = readtable(task1CsvPath);
task1Table = task1TableFull(task1TableFull.success == 1, :);
numSubjects = height(task1Table);
fprintf('Loaded Task 1 100-subject pool: %d successful subjects.\n', numSubjects);

targetFs = 250;
maxLagSec = 5;
confidenceBar = 0.3;
alphaList = [0.10, 0.15, 0.20, 0.30, 0.50];

blank = struct('kind', '', 'id', '', 'alpha', NaN, 'sharedF0Hz', NaN, ...
    'corr', NaN, 'notchConfidence', NaN, 'harmonicConfused', false, ...
    'n', NaN, 'nPass', NaN, 'passRate', NaN, 'medianNotchConf', NaN, 'medianCorr', NaN, 'harmonicConfusedFraction', NaN);
rows = repmat(blank, 0, 1);

for i = 1:numSubjects
    id = char(task1Table.id(i));
    source = char(task1Table.source(i));
    cachePath = fullfile(processedRoot, [id '_rgb_traces.mat']);
    if ~isfile(cachePath)
        continue
    end
    d = load(cachePath);
    R = d.R; G = d.G; B = d.B; fs = d.fs;
    roiTimestamps = (0:numel(R) - 1) / fs;

    try
        [gtPPG, gtTimestamps] = loadGTForSegment12c(id, source, projectRoot);
    catch
        continue
    end

    [Rd, ~] = detrendSignal(R);
    [Gd, ~] = detrendSignal(G);
    [Bd, ~] = detrendSignal(B);

    [Rw, ~, ~] = bandpassMorphology(Rd, fs, 'wide');
    [Gw, ~, ~] = bandpassMorphology(Gd, fs, 'wide');
    [Bw, ~, ~] = bandpassMorphology(Bd, fs, 'wide');
    pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
    sharedF0Hz = fftHeartRate(pulseWide, fs) / 60;

    for ai = 1:numel(alphaList)
        alpha = alphaList(ai);
        r = blank;
        r.kind = 'subject';
        r.id = id; r.alpha = alpha; r.sharedF0Hz = sharedF0Hz;

        try
            [Rh, ~, ~] = harmonicSelectiveGaussianFilter(Rd, fs, 6, sharedF0Hz, alpha);
            [Gh, ~, ~] = harmonicSelectiveGaussianFilter(Gd, fs, 6, sharedF0Hz, alpha);
            [Bh, ~, ~] = harmonicSelectiveGaussianFilter(Bd, fs, 6, sharedF0Hz, alpha);
            pulseHarmonic = chromCombine(Rh, Gh, Bh, R, G, B);

            [sigAligned, gtAligned, ~, ~, ~, ~, ~, ~] = ...
                estimateLagPolarityByGroundTruth(pulseHarmonic, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
            sigZ = zscoreLocal(sigAligned);
            gtZ = zscoreLocal(gtAligned);
            r.corr = pearsonCorrLocal(sigZ, gtZ);

            [protoSig, ~, ~, ~] = ensembleAverageBeats(sigAligned, targetFs);
            hrSigUsed = fftHeartRate(sigAligned, targetFs);
            effFsSig = numel(protoSig.trimmedMean) * (hrSigUsed / 60);
            [~, ~, ~, notchConf, ~] = notchDetectIEM(protoSig.trimmedMean, effFsSig);
            r.notchConfidence = notchConf;

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
                r.harmonicConfused = (nearest ~= 1) && (abs(ratio - nearest) / nearest < 0.08);
            end
        catch
            % leave NaN
        end
        rows(end + 1) = r; %#ok<AGROW>
    end

    if mod(i, 20) == 0 || i == numSubjects
        fprintf('  %d/%d subjects done\n', i, numSubjects);
    end
end

for ai = 1:numel(alphaList)
    alpha = alphaList(ai);
    subset = rows(strcmp({rows.kind}, 'subject') & [rows.alpha] == alpha);
    confVals = [subset.notchConfidence];
    confVals = confVals(~isnan(confVals));
    corrVals = [subset.corr];
    corrVals = corrVals(~isnan(corrVals));
    confusedVals = [subset.harmonicConfused];

    r = blank;
    r.kind = 'summary';
    r.alpha = alpha;
    r.n = numel(subset);
    r.nPass = sum(confVals > confidenceBar);
    r.passRate = r.nPass / max(1, numel(confVals));
    r.medianNotchConf = median(confVals);
    r.medianCorr = median(corrVals);
    r.harmonicConfusedFraction = sum(confusedVals) / max(1, numel(confusedVals));
    rows(end + 1) = r; %#ok<AGROW>
    fprintf('  [alpha=%.2f] n=%d pass=%d/%d (%.0f%%) medianNotchConf=%.3f medianCorr=%.3f harmonicConfused=%.0f%%\n', ...
        alpha, r.n, r.nPass, numel(confVals), 100 * r.passRate, r.medianNotchConf, r.medianCorr, 100 * r.harmonicConfusedFraction);
end

outCsvPath = fullfile(metricsRoot, 'segment12_task2b_gaussian_alpha_sweep.csv');
writetable(struct2table(rows, 'AsArray', true), outCsvPath);
fprintf('\nSaved %s\n', outCsvPath);

% --- ABPF reference lines (Task 2's own fixed values, for the plot only). ---
abpfPassRate = 24; abpfMedianCorr = 0.519; abpfMedianNotchConf = 0.058;

summaryRows = rows(strcmp({rows.kind}, 'summary'));
fig = figure('Visible', 'off', 'Position', [100, 100, 1000, 400]);
subplot(1, 3, 1);
plot([summaryRows.alpha], [summaryRows.passRate] * 100, 'o-', 'LineWidth', 1.5); hold on;
yline(abpfPassRate, 'k--');
xlabel('alpha'); ylabel('% pass (notch conf > 0.3)');
legend({'Gaussian', 'ABPF (fixed ref.)'}, 'Location', 'best');
title('Pass rate vs. alpha'); grid on;

subplot(1, 3, 2);
plot([summaryRows.alpha], [summaryRows.medianCorr], 'o-', 'LineWidth', 1.5); hold on;
yline(abpfMedianCorr, 'k--');
xlabel('alpha'); ylabel('median waveform corr');
title('Waveform correlation vs. alpha'); grid on;

subplot(1, 3, 3);
plot([summaryRows.alpha], [summaryRows.medianNotchConf], 'o-', 'LineWidth', 1.5); hold on;
yline(abpfMedianNotchConf, 'k--');
xlabel('alpha'); ylabel('median notch confidence');
title('Notch confidence vs. alpha'); grid on;

sgtitle('Segment 12 Task 2b: Gaussian filter alpha sensitivity (dashed = current ABPF comb)');
outFig = fullfile(figuresRoot, 'segment12_task2b_alpha_sweep.png');
exportgraphics(fig, outFig, 'Resolution', 150);
close(fig);
fprintf('Saved %s\n', outFig);
fprintf('\nSegment 12 Task 2b complete.\n');


function [gtPPG, gtTimestamps] = loadGTForSegment12c(id, source, projectRoot)
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
        error('loadGTForSegment12c:badSource', 'Unknown source "%s".', source);
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
