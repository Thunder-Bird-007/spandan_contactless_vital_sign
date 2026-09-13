% RUN_SEGMENT11_TASK1_CPACE_AND_PLV Segment 11 Task 1 -- the two
% highest-value, best-supported next steps identified by Segment 10 Task
% 3's Tier 0 diagnostics: (1) implement and evaluate cPACE Stage 1
% (Kaur, Lakshminarayanan & Saini, Biomed. Opt. Express 17(7):3832, 2026)
% as a new, gated, OFF-by-default pre-step ahead of CHROM/POS, and (2)
% promote the cross-ROI PLV computation from a Task 3 one-off into a
% standing, reusable, ground-truth-free validation metric.
%
% READ-ONLY WITH RESPECT TO PRODUCTION CODE. Does not modify, and only ever
% CALLS: pulseextraction/chromCombine.m, posCombine.m, heartrate/
% fftHeartRate.m, morphology/adaptiveHarmonicFilter.m, bandpassMorphology.m,
% filtering/waveletDenoise.m, bandpassClean.m, roi/extractROISignals.m.
% cPACE itself lives in a brand-new file (pulseextraction/cpaceProjection.m)
% that is only ever an OPTIONAL pre-step this script calls before
% chromCombine.m/posCombine.m -- it is never wired into those files
% themselves. Branch 2 (harmonic-comb) is out of scope for this task (the
% brief asks for CHROM/POS only).
%
% SUBJECT POOL (Action 1, HR + waveform correlation): the same 100-subject
% pool Segment 10 Task 1 established (5 UBFC DATASET_1 + 95 VIPL
% v1/source1), read directly from Task 1's own per-subject CSV
% (results/metrics/segment10_waveform_fidelity_per_subject.csv) rather than
% re-deriving it from Segment 7 Task K's raw prototypes/correlation-matrix
% cache -- Task 1's own script header states it reused exactly that Task K
% pool and reprocessed everything from data/processed/*_rgb_traces.mat
% directly (never from Task K's prototypes.mat/correlation_matrices.mat),
% so this script does the same rather than adding a second, redundant path
% to the same 100 IDs. No video is decoded or reprocessed here either.
%
% SUBJECT POOL (Action 1's cross-ROI PLV cross-check, and Action 2's own
% validation): the same 20 VIPL v1/source1 subjects Segment 10 Task 3
% Action 2 used (p1, p3, p4, p6-p22) -- the only subjects with all four
% Task N regions (forehead/glabella/malar/cheek) cached. This is a smaller
% subset of the 100 above, stated explicitly rather than silently mixed in.
%
% cPACE WIRING (see pulseextraction/cpaceProjection.m's own header for the
% full explanation): when the cPACE condition is ON, the RAW R/G/B trace is
% first projected (cpaceProjection.m), then that PROJECTED trace goes
% through the unchanged detrendSignal.m -> bandpassClean.m sequence before
% chromCombine.m/posCombine.m -- but chromCombine.m/posCombine.m's own
% RRaw/GRaw/BRaw normalization argument is ALWAYS the ORIGINAL,
% unprojected raw trace, both conditions, because cPACE's projection
% deliberately zeroes the projected trace's own per-channel mean by
% construction (using it for normalization would divide by zero). When the
% condition is OFF, every step is byte-identical to the existing pipeline.
%
% Outputs:
%   results/metrics/segment11_cpace_before_after.csv
%   results/metrics/segment11_cpace_skin_angle_per_subject.csv
%   results/figures/segment11_hr_scatter.png
%   results/figures/segment11_waveform_corr_before_after.png
%   results/figures/segment11_plv_before_after.png
%   results/figures/segment11_skin_angle_hist.png

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
processedRoot = fullfile(projectRoot, 'data', 'processed');
ubfcD1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');

if ~isfolder(metricsRoot); mkdir(metricsRoot); end
if ~isfolder(figuresRoot); mkdir(figuresRoot); end

task1CsvPath = fullfile(metricsRoot, 'segment10_waveform_fidelity_per_subject.csv');
task1TableFull = readtable(task1CsvPath);
task1Table = task1TableFull(task1TableFull.success == 1, :);
numSubjects = height(task1Table);
fprintf('Loaded Task 1 100-subject pool: %d successful subjects.\n', numSubjects);

targetFs = 250;
maxLagSec = 5;
conditions = {'off', 'on'};
branchNames = {'chrom', 'pos'};

blank = struct('kind', '', 'id', '', 'source', '', 'condition', '', 'branch', '', ...
    'predictedHR', NaN, 'gtHR', NaN, 'waveformCorr', NaN, 'lagSec', NaN, 'wasFlipped', false, ...
    'plvMean', NaN, ...
    'hrMAE', NaN, 'hrRMSE', NaN, 'hrPearsonR', NaN, 'n', NaN, ...
    'waveformCorrMedian', NaN, 'waveformCorrIQR25', NaN, 'waveformCorrIQR75', NaN, ...
    'plvMeanAcrossSubjects', NaN, 'plvMedian', NaN);
rows = repmat(blank, 0, 1);

skinBlank = struct('id', '', 'source', '', 'skinColorAngleDeg', NaN);
skinRows = repmat(skinBlank, 0, 1);


% ============================================================
% ACTION 1a: HR accuracy + waveform correlation, with vs without cPACE,
% on the full 100-subject pool.
% ============================================================
fprintf('\n=== Action 1a: HR + waveform correlation, cPACE on/off, n=%d ===\n', numSubjects);

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
        [gtPPG, gtTimestamps, gtHRVal] = loadGTForSegment11(id, source, projectRoot);
    catch gtErr
        fprintf('  SKIP %s: ground truth load failed -- %s\n', id, gtErr.message);
        continue
    end

    [Rc, Gc, Bc, ~, skinAngleDeg] = cpaceProjection(R, G, B);
    sr = skinBlank;
    sr.id = id; sr.source = source; sr.skinColorAngleDeg = skinAngleDeg;
    skinRows(end + 1) = sr; %#ok<AGROW>

    for ci = 1:numel(conditions)
        cond = conditions{ci};
        if strcmp(cond, 'off')
            Rin = R; Gin = G; Bin = B;
        else
            Rin = Rc; Gin = Gc; Bin = Bc;
        end

        [Rd, ~] = detrendSignal(Rin);
        [Gd, ~] = detrendSignal(Gin);
        [Bd, ~] = detrendSignal(Bin);
        [Rf, ~] = bandpassClean(Rd, fs);
        [Gf, ~] = bandpassClean(Gd, fs);
        [Bf, ~] = bandpassClean(Bd, fs);

        for bi = 1:numel(branchNames)
            bn = branchNames{bi};
            if strcmp(bn, 'chrom')
                % ALWAYS the ORIGINAL raw R/G/B for normalization -- see
                % cpaceProjection.m's own header for why.
                pulse = chromCombine(Rf, Gf, Bf, R, G, B);
            else
                pulse = posCombine(Rf, Gf, Bf, fs, R, G, B);
            end
            pulseFinal = bandpassClean(pulse, fs);

            predictedHR = fftHeartRate(pulseFinal, fs);

            waveformCorr = NaN;
            lagSec = NaN;
            wasFlipped = false;
            try
                [sigAligned, gtAligned, ~, lagSec, ~, wasFlipped, ~, ~] = ...
                    estimateLagPolarityByGroundTruth(pulseFinal, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
                sigZ = zscoreLocal(sigAligned);
                gtZ = zscoreLocal(gtAligned);
                waveformCorr = pearsonCorrLocal(sigZ, gtZ);
            catch
                % leave NaN -- same graceful-degradation convention Task 1's own script used
            end

            r = blank;
            r.kind = 'subject_hr_wave';
            r.id = id; r.source = source; r.condition = cond; r.branch = bn;
            r.predictedHR = predictedHR; r.gtHR = gtHRVal;
            r.waveformCorr = waveformCorr; r.lagSec = lagSec; r.wasFlipped = wasFlipped;
            rows(end + 1) = r; %#ok<AGROW>
        end
    end

    if mod(i, 10) == 0 || i == numSubjects
        fprintf('  %d/%d subjects done (%s)\n', i, numSubjects, id);
    end
end


% ============================================================
% ACTION 1b / ACTION 2 validation: cross-ROI PLV, with vs without cPACE,
% on Task 3's 20-subject four-region pool.
% ============================================================
regionNames = {'forehead', 'glabella', 'malar', 'cheek'};
plvSubjNums = [1, 3, 4, 6:22];
fprintf('\n=== Action 1b: cross-ROI PLV, cPACE on/off, n=%d (VIPL v1/source1) ===\n', numel(plvSubjNums));

for si = 1:numel(plvSubjNums)
    pNum = plvSubjNums(si);
    subjId = sprintf('VIPL_p%d_v1_source1', pNum);

    regionData = struct();
    okAll = true;
    for ri = 1:numel(regionNames)
        regionFile = fullfile(processedRoot, sprintf('VIPL_p%d_v1_source1_%s_rgb_traces.mat', pNum, regionNames{ri}));
        if ~isfile(regionFile)
            fprintf('  SKIP %s: missing region %s\n', subjId, regionNames{ri});
            okAll = false;
            break
        end
        regionData.(regionNames{ri}) = load(regionFile);
    end
    if ~okAll
        continue
    end

    for ci = 1:numel(conditions)
        cond = conditions{ci};
        for bi = 1:numel(branchNames)
            bn = branchNames{bi};
            regionSignals = cell(1, numel(regionNames));
            for ri = 1:numel(regionNames)
                rd = regionData.(regionNames{ri});
                if strcmp(cond, 'off')
                    Rin = rd.R; Gin = rd.G; Bin = rd.B;
                else
                    % Each region gets its OWN q_hat -- the skin's mean
                    % reflectance direction is a per-ROI-patch quantity,
                    % not necessarily identical across regions of the same
                    % face (different average lighting/geometry per patch).
                    [Rin, Gin, Bin, ~, ~] = cpaceProjection(rd.R, rd.G, rd.B);
                end
                [Rd_, ~] = detrendSignal(Rin);
                [Gd_, ~] = detrendSignal(Gin);
                [Bd_, ~] = detrendSignal(Bin);
                [Rf_, ~] = bandpassClean(Rd_, rd.fs);
                [Gf_, ~] = bandpassClean(Gd_, rd.fs);
                [Bf_, ~] = bandpassClean(Bd_, rd.fs);

                if strcmp(bn, 'chrom')
                    pulse = chromCombine(Rf_, Gf_, Bf_, rd.R, rd.G, rd.B);
                else
                    pulse = posCombine(Rf_, Gf_, Bf_, rd.fs, rd.R, rd.G, rd.B);
                end
                regionSignals{ri} = bandpassClean(pulse, rd.fs);
            end

            plvMeanVal = computeCrossROIPLV(regionSignals, regionNames);

            r = blank;
            r.kind = 'subject_plv';
            r.id = subjId; r.condition = cond; r.branch = bn; r.plvMean = plvMeanVal;
            rows(end + 1) = r; %#ok<AGROW>
        end
    end
    fprintf('  PLV %s done\n', subjId);
end


% ============================================================
% SUMMARY AGGREGATION
% ============================================================
fprintf('\n=== Aggregating summary tables ===\n');

subjectHW = rows(strcmp({rows.kind}, 'subject_hr_wave'));
for ci = 1:numel(conditions)
    cond = conditions{ci};
    for bi = 1:numel(branchNames)
        bn = branchNames{bi};
        mask = strcmp({subjectHW.condition}, cond) & strcmp({subjectHW.branch}, bn);
        subset = subjectHW(mask);

        predVec = [subset.predictedHR];
        gtVec = [subset.gtHR];
        validMask = ~isnan(predVec) & ~isnan(gtVec);
        m = computeMetrics(predVec(validMask), gtVec(validMask));

        r = blank;
        r.kind = 'summary_hr';
        r.condition = cond; r.branch = bn;
        r.hrMAE = m.mae; r.hrRMSE = m.rmse; r.hrPearsonR = m.pearsonR; r.n = m.n;
        rows(end + 1) = r; %#ok<AGROW>
        fprintf('  [HR summary] %s/%s: MAE=%.2f RMSE=%.2f r=%.3f (n=%d)\n', cond, bn, m.mae, m.rmse, m.pearsonR, m.n);

        corrVec = [subset.waveformCorr];
        corrVec = corrVec(~isnan(corrVec));
        r = blank;
        r.kind = 'summary_waveform';
        r.condition = cond; r.branch = bn;
        r.waveformCorrMedian = median(corrVec);
        r.waveformCorrIQR25 = prctileLocal(corrVec, 25);
        r.waveformCorrIQR75 = prctileLocal(corrVec, 75);
        r.n = numel(corrVec);
        rows(end + 1) = r; %#ok<AGROW>
        fprintf('  [waveform summary] %s/%s: median r=%.3f (IQR %.3f-%.3f, n=%d)\n', ...
            cond, bn, r.waveformCorrMedian, r.waveformCorrIQR25, r.waveformCorrIQR75, r.n);
    end
end

subjectPLV = rows(strcmp({rows.kind}, 'subject_plv'));
for ci = 1:numel(conditions)
    cond = conditions{ci};
    for bi = 1:numel(branchNames)
        bn = branchNames{bi};
        mask = strcmp({subjectPLV.condition}, cond) & strcmp({subjectPLV.branch}, bn);
        vals = [subjectPLV(mask).plvMean];
        vals = vals(~isnan(vals));
        r = blank;
        r.kind = 'summary_plv';
        r.condition = cond; r.branch = bn;
        r.plvMeanAcrossSubjects = mean(vals);
        r.plvMedian = median(vals);
        r.n = numel(vals);
        rows(end + 1) = r; %#ok<AGROW>
        fprintf('  [PLV summary] %s/%s: mean=%.3f median=%.3f (n=%d)\n', cond, bn, r.plvMeanAcrossSubjects, r.plvMedian, r.n);
    end
end

outCsvPath = fullfile(metricsRoot, 'segment11_cpace_before_after.csv');
writetable(struct2table(rows, 'AsArray', true), outCsvPath);

skinCsvPath = fullfile(metricsRoot, 'segment11_cpace_skin_angle_per_subject.csv');
writetable(struct2table(skinRows, 'AsArray', true), skinCsvPath);

fprintf('\nSaved %s\nSaved %s\n', outCsvPath, skinCsvPath);


% ============================================================
% FIGURES
% ============================================================
fprintf('\n=== Generating figures ===\n');

% --- HR scatter: rows=branch, cols=condition ---
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 900]);
for bi = 1:numel(branchNames)
    bn = branchNames{bi};
    for ci = 1:numel(conditions)
        cond = conditions{ci};
        subplot(2, 2, (bi - 1) * 2 + ci);
        mask = strcmp({subjectHW.condition}, cond) & strcmp({subjectHW.branch}, bn);
        subset = subjectHW(mask);
        predVec = [subset.predictedHR];
        gtVec = [subset.gtHR];
        validMask = ~isnan(predVec) & ~isnan(gtVec);
        scatter(gtVec(validMask), predVec(validMask), 20, 'filled'); hold on;
        lims = [min([gtVec(validMask), predVec(validMask)]), max([gtVec(validMask), predVec(validMask)])];
        plot(lims, lims, 'k--');
        xlabel('Ground-truth HR (bpm)'); ylabel('Predicted HR (bpm)');
        m = computeMetrics(predVec(validMask), gtVec(validMask));
        title(sprintf('%s, cPACE %s: MAE=%.2f r=%.2f', upper(bn), cond, m.mae, m.pearsonR), 'Interpreter', 'none');
        grid on;
    end
end
sgtitle('Action 1: HR accuracy, cPACE on vs. off (100-subject pool)');
outFig1 = fullfile(figuresRoot, 'segment11_hr_scatter.png');
exportgraphics(fig, outFig1, 'Resolution', 150);
close(fig);

% --- Waveform correlation before/after (paired per-subject, boxplot-style via scatter+bar) ---
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
for bi = 1:numel(branchNames)
    bn = branchNames{bi};
    subplot(1, 2, bi);
    offMask = strcmp({subjectHW.condition}, 'off') & strcmp({subjectHW.branch}, bn);
    onMask = strcmp({subjectHW.condition}, 'on') & strcmp({subjectHW.branch}, bn);
    offIds = {subjectHW(offMask).id}; onIds = {subjectHW(onMask).id};
    offCorr = [subjectHW(offMask).waveformCorr]; onCorr = [subjectHW(onMask).waveformCorr];
    % align by id so the paired scatter is genuinely paired
    [commonIds, offIdx, onIdx] = intersect(offIds, onIds);
    pairedOff = offCorr(offIdx); pairedOn = onCorr(onIdx);
    validPair = ~isnan(pairedOff) & ~isnan(pairedOn);
    scatter(pairedOff(validPair), pairedOn(validPair), 18, 'filled'); hold on;
    lims = [min([pairedOff(validPair), pairedOn(validPair)]), max([pairedOff(validPair), pairedOn(validPair)])];
    plot(lims, lims, 'k--');
    xlabel('Waveform corr, cPACE OFF'); ylabel('Waveform corr, cPACE ON');
    title(sprintf('%s: median off=%.3f on=%.3f (n=%d paired)', upper(bn), median(pairedOff(validPair)), median(pairedOn(validPair)), sum(validPair)), 'Interpreter', 'none');
    grid on;
end
sgtitle('Action 1: per-subject waveform correlation, cPACE on vs. off (paired)');
outFig2 = fullfile(figuresRoot, 'segment11_waveform_corr_before_after.png');
exportgraphics(fig, outFig2, 'Resolution', 150);
close(fig);

% --- PLV before/after bar chart ---
fig = figure('Visible', 'off', 'Position', [100, 100, 700, 450]);
plvMat = nan(numel(branchNames), numel(conditions));
for bi = 1:numel(branchNames)
    for ci = 1:numel(conditions)
        mask = strcmp({subjectPLV.condition}, conditions{ci}) & strcmp({subjectPLV.branch}, branchNames{bi});
        vals = [subjectPLV(mask).plvMean];
        plvMat(bi, ci) = mean(vals(~isnan(vals)));
    end
end
bar(plvMat);
set(gca, 'XTickLabel', upper(branchNames));
legend({'cPACE off', 'cPACE on'}, 'Location', 'best');
ylabel('Mean cross-ROI PLV');
title(sprintf('Action 1b: cross-ROI PLV, cPACE on vs. off (n=%d VIPL v1/source1)', numel(plvSubjNums)));
grid on;
outFig3 = fullfile(figuresRoot, 'segment11_plv_before_after.png');
exportgraphics(fig, outFig3, 'Resolution', 150);
close(fig);

% --- Skin-colour angle histogram ---
fig = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
angleVals = [skinRows.skinColorAngleDeg];
histogram(angleVals, 15);
hold on;
xline(7.5, 'g--', 'LineWidth', 1.5);
xline(40, 'r--', 'LineWidth', 1.5);
text(7.5, max(ylim) * 0.95, ' light skin (~5-10°)', 'Color', [0, 0.6, 0]);
text(40, max(ylim) * 0.85, 'dark skin (~30-50°) ', 'Color', 'r', 'HorizontalAlignment', 'right');
xlim([0, 45]);
xlabel('Skin-colour angle to [1,1,1] (degrees)');
ylabel('Subject count');
title(sprintf('Action 1: skin-colour angle distribution (n=%d, UBFC-D1 + VIPL v1/source1)', numel(angleVals)));
grid on;
outFig4 = fullfile(figuresRoot, 'segment11_skin_angle_hist.png');
exportgraphics(fig, outFig4, 'Resolution', 150);
close(fig);

fprintf('Saved %s\nSaved %s\nSaved %s\nSaved %s\n', outFig1, outFig2, outFig3, outFig4);
fprintf('\nSegment 11 Task 1 complete.\n');


% ============================================================
% LOCAL FUNCTIONS
% ============================================================
function [gtPPG, gtTimestamps, gtHRVal] = loadGTForSegment11(id, source, projectRoot)
% Mirrors run_segment10_waveform_fidelity_audit.m's own
% loadGTWaveformForAudit local function, extended to also return the
% mean ground-truth HR (bpm) this task needs -- same
% HR_groundtruth = mean(gt.hr) convention already used throughout this
% project (e.g. scripts/run_vipl_integration_batch.m).
switch source
    case 'ubfc_d1'
        gtPath = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1', id, 'gtdump.xmp');
        gt = loadGroundTruth(gtPath, 'dataset1');
        gtPPG = gt.ppg(:)';
        gtTimestamps = gt.timestamp(:)';
        gtHRVal = mean(gt.hr);
    case 'vipl'
        viplRootLocal = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
        tokens = regexp(id, 'VIPL_p(\d+)_', 'tokens');
        subjNum = str2double(tokens{1}{1});
        gt = loadVIPLGroundTruth(viplRootLocal, subjNum, 1, 1);
        gtPPG = gt.ppg(:)';
        gtTimestamps = (0:numel(gtPPG) - 1) / 60; % same nominal CMS60C convention Task K/Task 1 used
        gtHRVal = mean(gt.hr);
    otherwise
        error('loadGTForSegment11:badSource', 'Unknown source "%s".', source);
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

function p = prctileLocal(data, percentile)
sortedData = sort(data(:));
n = numel(sortedData);
if n == 0
    p = NaN;
    return
end
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
