% RUN_SEGMENT12_TASK1_MID_BAND_EVALUATION Segment 12 Task 1 -- evaluate
% morphology/bandpassMorphology.m's existing but unused 'mid' mode
% (0.6-6.0Hz) as a fix for the Nyquist-margin problem Segment 10 Task 3
% Action 3 found for VIPL subjects running at a true ~16fps.
%
% READ-ONLY WITH RESPECT TO PRODUCTION CODE. bandpassMorphology.m already
% ships 'mid' -- this script only CALLS it with a different bandMode
% argument, exactly the way it already supports being called; nothing in
% morphology/bandpassMorphology.m, morphology/adaptiveHarmonicFilter.m, or
% any other do-not-touch file is modified.
%
% STEP 0 (per the brief's explicit instruction: "check first, don't
% assume"): before comparing anything, this script establishes what the
% CURRENT ('wide') mode actually does today for the affected subjects --
% see Section 0 below and the doc's own Method section. Short answer,
% verified not assumed: it does NOT error (every real VIPL subject's true
% fps is a few hundredths to a few tenths of a Hz above the exact 16.0fps
% that would trip bandpassMorphology.m's own Nyquist guard), but it runs
% with an extremely thin transition band (as little as ~0.03 Hz of margin
% between the 8 Hz passband edge and Nyquist).
%
% NOTE ON A CORRECTED FIGURE: Segment 10 Task 3's own doc stated "20 of 95
% VIPL subjects (21%)" run at this true ~16fps. Re-deriving that count
% directly from the same CSV this script also uses found 44 of 95 (46%) --
% the original count was a genuine error (see
% docs/Segment10_Task3_Tier0_Diagnostics.md's own corrected Finding D,
% 2026-09-13), not a different definition. This script uses the corrected
% 44-subject figure throughout, established fresh from frameRate directly.
%
% METHOD: for all 100 of Segment 10 Task 1's subjects (5 UBFC-D1 + 95 VIPL
% v1/source1), Branch 2's harmonic pipeline (morphology/bandpassMorphology.m
% -> pulseextraction/chromCombine.m -> heartrate/fftHeartRate.m -> shared
% f0 -> morphology/adaptiveHarmonicFilter.m -> pulseextraction/chromCombine.m
% -> morphology/estimateLagPolarityByGroundTruth.m -> morphology/
% ensembleAverageBeats.m -> morphology/notchDetectIEM.m, i.e. Task 1's own
% exact "harmonic" branch sequence) is run TWICE per subject, identical in
% every respect EXCEPT the bandMode passed to bandpassMorphology.m for the
% shared-f0 estimation step: 'wide' (today's default) and 'mid' (this
% task's candidate). Both are freshly recomputed (not just read from Task
% 1's CSV) so the 'wide' condition can be cross-checked against Task 1's
% own already-published notchConfidence_harmonic numbers as a regression/
% sanity check before trusting the 'mid' numbers built the same way.
%
% Group split (established from Task 1's own frameRate column, no new
% data): "affected" = frameRate < 17 Hz (44 VIPL subjects, the true ~16fps
% cluster with a large clean gap to the next subject at 18.09fps); "safe"
% = frameRate >= 17 Hz (51 VIPL + 5 UBFC-D1 = 56 subjects, comfortably
% inside 'wide''s own Nyquist margin).
%
% Outputs:
%   results/metrics/segment12_task1_mid_band_comparison.csv
%   results/figures/segment12_task1_*.png

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
bandModes = {'wide', 'mid'};

blank = struct('kind', '', 'id', '', 'source', '', 'group', '', 'frameRate', NaN, ...
    'nyquistHz', NaN, 'bandMode', '', 'bandHighHz', NaN, 'nyquistMarginHz', NaN, ...
    'sharedF0Hz', NaN, 'corr', NaN, 'lagSec', NaN, 'notchDetected', false, ...
    'notchPosNorm', NaN, 'notchDepth', NaN, 'notchConfidence', NaN, ...
    'notchConfidence_task1CSV', NaN, 'notchConfMatchesTask1', false, ...
    'notchConfDelta_midMinusWide', NaN, 'corrDelta_midMinusWide', NaN, ...
    'wideAbovePass', false, 'midAbovePass', false, ...
    'n', NaN, 'nPass', NaN, 'passRate', NaN, 'medianNotchConf', NaN, 'medianCorr', NaN);
rows = repmat(blank, 0, 1);

confidenceBar = 0.3;

for i = 1:numSubjects
    id = char(task1Table.id(i));
    source = char(task1Table.source(i));
    frameRateTask1 = task1Table.frameRate(i);
    cachePath = fullfile(processedRoot, [id '_rgb_traces.mat']);
    if ~isfile(cachePath)
        fprintf('  SKIP %s: no cache at %s\n', id, cachePath);
        continue
    end

    d = load(cachePath);
    R = d.R; G = d.G; B = d.B; fs = d.fs;
    roiTimestamps = (0:numel(R) - 1) / fs;
    nyquistHz = fs / 2;
    groupName = 'safe';
    if fs < 17
        groupName = 'affected';
    end

    try
        [gtPPG, gtTimestamps] = loadGTForSegment12(id, source, projectRoot);
    catch gtErr
        fprintf('  SKIP %s: ground truth load failed -- %s\n', id, gtErr.message);
        continue
    end

    [Rd, ~] = detrendSignal(R);
    [Gd, ~] = detrendSignal(G);
    [Bd, ~] = detrendSignal(B);

    for bi = 1:numel(bandModes)
        bandMode = bandModes{bi};

        r = blank;
        r.kind = 'subject';
        r.id = id; r.source = source; r.group = groupName;
        r.frameRate = fs; r.nyquistHz = nyquistHz; r.bandMode = bandMode;

        try
            [Rw, ~, bandUsed] = bandpassMorphology(Rd, fs, bandMode);
            [Gw, ~, ~] = bandpassMorphology(Gd, fs, bandMode);
            [Bw, ~, ~] = bandpassMorphology(Bd, fs, bandMode);
            r.bandHighHz = bandUsed(2);
            r.nyquistMarginHz = nyquistHz - bandUsed(2);

            pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
            sharedF0Hz = fftHeartRate(pulseWide, fs) / 60;
            r.sharedF0Hz = sharedF0Hz;

            [Rahf, ~, ~] = adaptiveHarmonicFilter(Rd, fs, 6, sharedF0Hz);
            [Gahf, ~, ~] = adaptiveHarmonicFilter(Gd, fs, 6, sharedF0Hz);
            [Bahf, ~, ~] = adaptiveHarmonicFilter(Bd, fs, 6, sharedF0Hz);
            pulseAdaptive = chromCombine(Rahf, Gahf, Bahf, R, G, B);

            [sigAligned, gtAligned, ~, lagSec, ~, ~, ~, ~] = ...
                estimateLagPolarityByGroundTruth(pulseAdaptive, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
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
        catch procErr
            fprintf('  %s [%s]: FAILED -- %s\n', id, bandMode, procErr.message);
        end

        if strcmp(bandMode, 'wide')
            r.notchConfidence_task1CSV = task1Table.notchConfidence_harmonic(i);
            if ~isnan(r.notchConfidence) && ~isnan(r.notchConfidence_task1CSV)
                r.notchConfMatchesTask1 = abs(r.notchConfidence - r.notchConfidence_task1CSV) < 1e-6;
            end
        end

        rows(end + 1) = r; %#ok<AGROW>
    end

    if mod(i, 10) == 0 || i == numSubjects
        fprintf('  %d/%d subjects done (%s)\n', i, numSubjects, id);
    end
end

% --- Regression check: freshly recomputed 'wide' vs Task 1's own cached numbers. ---
wideRows = rows(strcmp({rows.kind}, 'subject') & strcmp({rows.bandMode}, 'wide'));
validCompare = ~isnan([wideRows.notchConfidence]) & ~isnan([wideRows.notchConfidence_task1CSV]);
numMatched = sum([wideRows(validCompare).notchConfMatchesTask1]);
fprintf('\n=== Regression check: fresh ''wide'' recompute vs. Task 1''s own CSV ===\n');
fprintf('  %d/%d subjects match Task 1''s cached notchConfidence_harmonic to 1e-6.\n', numMatched, sum(validCompare));
if numMatched < sum(validCompare)
    mismatchIdx = find(validCompare);
    mismatchIdx = mismatchIdx(~[wideRows(mismatchIdx).notchConfMatchesTask1]);
    for k = mismatchIdx(:)'
        fprintf('    MISMATCH %s: fresh=%.6f task1CSV=%.6f\n', wideRows(k).id, wideRows(k).notchConfidence, wideRows(k).notchConfidence_task1CSV);
    end
end

% --- Group-wise Nyquist margin summary (Section 0 -- what does today's code actually do). ---
affectedWide = wideRows(strcmp({wideRows.group}, 'affected'));
fprintf('\n=== Section 0: today''s ''wide'' Nyquist margin for the affected (frameRate<17Hz) group, n=%d ===\n', numel(affectedWide));
margins = [affectedWide.nyquistMarginHz];
fprintf('  margin (Nyquist - 8.0Hz): min=%.3f max=%.3f mean=%.3f Hz -- all positive means NO error today, confirmed empirically (not assumed).\n', ...
    min(margins), max(margins), mean(margins));

% --- Per-subject mid-vs-wide deltas. ---
midRows = rows(strcmp({rows.kind}, 'subject') & strcmp({rows.bandMode}, 'mid'));
idsWide = {wideRows.id};
notchConfDeltas = nan(numel(midRows), 1);
corrDeltas = nan(numel(midRows), 1);
groupOfDelta = cell(numel(midRows), 1);
for k = 1:numel(midRows)
    wideIdx = find(strcmp(idsWide, midRows(k).id), 1);
    if isempty(wideIdx); continue; end
    groupOfDelta{k} = midRows(k).group;
    if ~isnan(midRows(k).notchConfidence) && ~isnan(wideRows(wideIdx).notchConfidence)
        notchConfDeltas(k) = midRows(k).notchConfidence - wideRows(wideIdx).notchConfidence;
    end
    if ~isnan(midRows(k).corr) && ~isnan(wideRows(wideIdx).corr)
        corrDeltas(k) = midRows(k).corr - wideRows(wideIdx).corr;
    end
end

% --- Summary rows: per group, per bandMode, pass-rate + medians. ---
groupDefs = {'affected', 'safe', 'all'};
for gi = 1:numel(groupDefs)
    gName = groupDefs{gi};
    for bi = 1:numel(bandModes)
        bandMode = bandModes{bi};
        if strcmp(gName, 'all')
            subset = rows(strcmp({rows.kind}, 'subject') & strcmp({rows.bandMode}, bandMode));
        else
            subset = rows(strcmp({rows.kind}, 'subject') & strcmp({rows.bandMode}, bandMode) & strcmp({rows.group}, gName));
        end
        confVals = [subset.notchConfidence];
        confVals = confVals(~isnan(confVals));
        corrVals = [subset.corr];
        corrVals = corrVals(~isnan(corrVals));

        r = blank;
        r.kind = 'summary';
        r.group = gName; r.bandMode = bandMode;
        r.n = numel(subset);
        r.nPass = sum(confVals > confidenceBar);
        r.passRate = r.nPass / max(1, numel(confVals));
        r.medianNotchConf = median(confVals);
        r.medianCorr = median(corrVals);
        rows(end + 1) = r; %#ok<AGROW>
        fprintf('  [summary %s/%s] n=%d pass(>%.1f)=%d/%d (%.0f%%) medianNotchConf=%.3f medianCorr=%.3f\n', ...
            gName, bandMode, r.n, confidenceBar, r.nPass, numel(confVals), 100 * r.passRate, r.medianNotchConf, r.medianCorr);
    end
end

% --- Per-subject delta summary rows. ---
for gi = 1:numel(groupDefs)
    gName = groupDefs{gi};
    if strcmp(gName, 'all')
        mask = true(numel(midRows), 1);
    else
        mask = strcmp(groupOfDelta, gName);
    end
    deltasHere = notchConfDeltas(mask);
    deltasHere = deltasHere(~isnan(deltasHere));
    r = blank;
    r.kind = 'delta_summary';
    r.group = gName;
    r.n = numel(deltasHere);
    r.notchConfDelta_midMinusWide = median(deltasHere);
    corrDeltasHere = corrDeltas(mask);
    corrDeltasHere = corrDeltasHere(~isnan(corrDeltasHere));
    r.corrDelta_midMinusWide = median(corrDeltasHere);
    rows(end + 1) = r; %#ok<AGROW>
    fprintf('  [delta %s] n=%d median(mid-wide) notchConf=%.4f corr=%.4f\n', gName, r.n, r.notchConfDelta_midMinusWide, r.corrDelta_midMinusWide);
end

outCsvPath = fullfile(metricsRoot, 'segment12_task1_mid_band_comparison.csv');
writetable(struct2table(rows, 'AsArray', true), outCsvPath);
fprintf('\nSaved %s\n', outCsvPath);


% ============================================================
% FIGURES
% ============================================================

% --- Paired notch confidence scatter, split by group. ---
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
groupsToPlot = {'affected', 'safe'};
for gi = 1:2
    subplot(1, 2, gi);
    gName = groupsToPlot{gi};
    wSub = wideRows(strcmp({wideRows.group}, gName));
    mSub = midRows(strcmp({midRows.group}, gName));
    wIds = {wSub.id}; mIds = {mSub.id};
    [commonIds, wIdx, mIdx] = intersect(wIds, mIds);
    wConf = [wSub(wIdx).notchConfidence];
    mConf = [mSub(mIdx).notchConfidence];
    validMask = ~isnan(wConf) & ~isnan(mConf);
    scatter(wConf(validMask), mConf(validMask), 25, 'filled'); hold on;
    plot([0, 1], [0, 1], 'k--');
    yline(confidenceBar, 'r:');
    xline(confidenceBar, 'r:');
    xlabel('Notch confidence, ''wide'' (today)'); ylabel('Notch confidence, ''mid''');
    title(sprintf('%s (n=%d): median wide=%.3f mid=%.3f', gName, sum(validMask), median(wConf(validMask)), median(mConf(validMask))));
    xlim([0, 1]); ylim([0, 1]);
    grid on;
end
sgtitle('Segment 12 Task 1: notch confidence, ''mid'' vs. ''wide'' bandMode');
outFig1 = fullfile(figuresRoot, 'segment12_task1_notch_confidence_scatter.png');
exportgraphics(fig, outFig1, 'Resolution', 150);
close(fig);

% --- Nyquist margin bar, wide vs mid, affected group. ---
fig = figure('Visible', 'off', 'Position', [100, 100, 700, 450]);
wAff = wideRows(strcmp({wideRows.group}, 'affected'));
mAff = midRows(strcmp({midRows.group}, 'affected'));
histogram([wAff.nyquistMarginHz], 'BinWidth', 0.05, 'FaceAlpha', 0.6); hold on;
histogram([mAff.nyquistMarginHz], 'BinWidth', 0.2, 'FaceAlpha', 0.6);
legend({'wide (0.5-8Hz)', 'mid (0.6-6Hz)'}, 'Location', 'best');
xlabel('Nyquist margin (Nyquist Hz - band high cutoff Hz)');
ylabel('Subject count');
title(sprintf('Affected group (frameRate<17Hz, n=%d): filter design margin, wide vs. mid', numel(wAff)));
grid on;
outFig2 = fullfile(figuresRoot, 'segment12_task1_nyquist_margin.png');
exportgraphics(fig, outFig2, 'Resolution', 150);
close(fig);

% --- Pass-rate bar chart, both groups, both modes. ---
fig = figure('Visible', 'off', 'Position', [100, 100, 700, 450]);
passMat = nan(2, 2); % rows=group(affected,safe), cols=bandMode(wide,mid)
for gi = 1:2
    for bi = 1:2
        subset = rows(strcmp({rows.kind}, 'summary') & strcmp({rows.group}, groupsToPlot{gi}) & strcmp({rows.bandMode}, bandModes{bi}));
        passMat(gi, bi) = subset.passRate * 100;
    end
end
bar(passMat);
set(gca, 'XTickLabel', {'affected (<17fps)', 'safe (>=17fps)'});
legend({'wide', 'mid'}, 'Location', 'best');
ylabel('% subjects above 0.3 notch-confidence bar');
title('Segment 12 Task 1: pass-rate, ''mid'' vs. ''wide''');
grid on;
outFig3 = fullfile(figuresRoot, 'segment12_task1_pass_rate.png');
exportgraphics(fig, outFig3, 'Resolution', 150);
close(fig);

fprintf('Saved %s\nSaved %s\nSaved %s\n', outFig1, outFig2, outFig3);
fprintf('\nSegment 12 Task 1 complete.\n');


% ============================================================
% LOCAL FUNCTIONS
% ============================================================
function [gtPPG, gtTimestamps] = loadGTForSegment12(id, source, projectRoot)
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
        error('loadGTForSegment12:badSource', 'Unknown source "%s".', source);
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
