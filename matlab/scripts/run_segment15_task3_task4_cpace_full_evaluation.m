% RUN_SEGMENT15_TASK3_TASK4_CPACE_FULL_EVALUATION Segment 15 Tasks 3 and 4
% -- (a) sweep cpaceEigenExtract.m's eigen-window half-width bw over
% {0.15, 0.30, 0.50} Hz (Table S2's own flagged sensitive parameter) on
% Spandan's real 100-subject pool, per-subject, and (b) evaluate the full
% Stage1+2+3 cPACE pipeline (cpaceProjection -> cpaceEigenExtract ->
% cpaceHomodyneNormalize) against (i) current production POS/CHROM (no
% cPACE) and (ii) Stage-1-only cPACE (Segment 11 Task 1), on HR MAE and
% cross-ROI PLV, per-subject, not just pooled.
%
% NOTE ON SEGMENT NUMBERING: this work was originally briefed as "Segment
% 14", but `docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md` and
% `docs/Segment14_Task2_Confidence_Gate_Production_Promotion.md` (both
% dated 2026-09-13, both with real output artifacts already on disk) show
% Segment 14 is already taken by a completed, different body of work
% (held-out UBFC-D2 validation and promoting harmonicFilterConfidenceGate.m
% to Branch 2's production default) that was never logged in
% SESSION_HANDOFF.md's changelog. This script and its docs use Segment 15
% instead, to avoid colliding with that existing, real work. See
% SESSION_HANDOFF.md's changelog for a backfilled Segment 14 entry and the
% new Segment 15 entry.
%
% READ-ONLY WITH RESPECT TO PRODUCTION CODE. Only ever CALLS:
% pulseextraction/cpaceProjection.m, cpaceEigenExtract.m (NEW, this
% segment), cpaceHomodyneNormalize.m (NEW, this segment), chromCombine.m,
% posCombine.m, heartrate/fftHeartRate.m, filtering/detrendSignal.m,
% bandpassClean.m, validation/computeCrossROIPLV.m, computeMetrics.m,
% morphology/estimateLagPolarityByGroundTruth.m. Does not modify any of
% them.
%
% SUBJECT POOLS: identical to Segment 11 Task 1's own script --
% (a) the 100-subject HR/waveform pool from
%     results/metrics/segment10_waveform_fidelity_per_subject.csv
%     (success == 1 rows only), read directly, no video reprocessed;
% (b) the 20 VIPL v1/source1 subjects (p1, p3, p4, p6-p22) with all four
%     Task N regions (forehead/glabella/malar/cheek) cached, for cross-ROI
%     PLV.
%
% PIPELINES COMPARED (7 total, per subject):
%   'POS', 'CHROM'                       - current production, cPACE off.
%   'cPACE-Stage1+POS', 'cPACE-Stage1+CHROM'
%                                         - Segment 11 Task 1's Stage-1-only
%                                           cPACE ahead of unmodified
%                                           CHROM/POS.
%   'cPACE-Full-bw0.15', 'cPACE-Full-bw0.30', 'cPACE-Full-bw0.50'
%                                         - this segment's full
%                                           Stage1+2+3 pipeline, swept over
%                                           bw (Task 3). bw=0.30 is Table
%                                           S2's own default; 0.15/0.50
%                                           bracket the paper's own swept
%                                           range.
%
% Outputs:
%   results/metrics/segment15_cpace_full_per_subject_hr.csv
%   results/metrics/segment15_cpace_full_summary_hr.csv
%   results/metrics/segment15_cpace_full_per_subject_plv.csv
%   results/metrics/segment15_cpace_full_summary_plv.csv
%   results/metrics/segment15_task3_bw_sweep_per_subject_regressions.csv
%   results/metrics/segment15_task4_vs_production_per_subject_regressions.csv
%   results/figures/segment15_hr_mae_by_pipeline.png
%   results/figures/segment15_bw_sweep_per_subject.png
%   results/figures/segment15_plv_by_pipeline.png

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
processedRoot = fullfile(projectRoot, 'data', 'processed');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');

if ~isfolder(metricsRoot); mkdir(metricsRoot); end
if ~isfolder(figuresRoot); mkdir(figuresRoot); end

task1CsvPath = fullfile(metricsRoot, 'segment10_waveform_fidelity_per_subject.csv');
task1TableFull = readtable(task1CsvPath);
task1Table = task1TableFull(task1TableFull.success == 1, :);
numSubjects = height(task1Table);
fprintf('Loaded 100-subject pool: %d successful subjects.\n', numSubjects);

targetFs = 250;
maxLagSec = 5;
bwSweep = [0.15, 0.30, 0.50];
pipelineNames = {'POS', 'CHROM', 'cPACE-Stage1+POS', 'cPACE-Stage1+CHROM', ...
    'cPACE-Full-bw0.15', 'cPACE-Full-bw0.30', 'cPACE-Full-bw0.50'};
numPipelines = numel(pipelineNames);

blank = struct('id', '', 'source', '', 'pipeline', '', ...
    'predictedHR', NaN, 'gtHR', NaN, 'absErr', NaN, ...
    'waveformCorr', NaN, 'lagSec', NaN, 'wasFlipped', false, ...
    'eigRatio', NaN, 'seedHz', NaN, 'harmonicConfusion', false);
rows = repmat(blank, 0, 1);

% ============================================================
% PART A: HR + waveform correlation, 7 pipelines, 100-subject pool.
% ============================================================
fprintf('\n=== Part A: HR + waveform correlation, %d pipelines, n=%d ===\n', numPipelines, numSubjects);

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
        [gtPPG, gtTimestamps, gtHRVal] = loadGTForSegment15(id, source, projectRoot);
    catch gtErr
        fprintf('  SKIP %s: ground truth load failed -- %s\n', id, gtErr.message);
        continue
    end

    % --- Production POS/CHROM (cPACE off). ---
    [Rd, ~] = detrendSignal(R); [Gd, ~] = detrendSignal(G); [Bd, ~] = detrendSignal(B);
    [Rf, ~] = bandpassClean(Rd, fs); [Gf, ~] = bandpassClean(Gd, fs); [Bf, ~] = bandpassClean(Bd, fs);
    pulseChrom = bandpassClean(chromCombine(Rf, Gf, Bf, R, G, B), fs);
    pulsePos = bandpassClean(posCombine(Rf, Gf, Bf, fs, R, G, B), fs);

    % --- cPACE Stage 1 only, ahead of CHROM/POS (Segment 11 wiring). ---
    [Rc, Gc, Bc, ~, ~] = cpaceProjection(R, G, B);
    [Rcd, ~] = detrendSignal(Rc); [Gcd, ~] = detrendSignal(Gc); [Bcd, ~] = detrendSignal(Bc);
    [Rcf, ~] = bandpassClean(Rcd, fs); [Gcf, ~] = bandpassClean(Gcd, fs); [Bcf, ~] = bandpassClean(Bcd, fs);
    pulseStage1Chrom = bandpassClean(chromCombine(Rcf, Gcf, Bcf, R, G, B), fs);
    pulseStage1Pos = bandpassClean(posCombine(Rcf, Gcf, Bcf, fs, R, G, B), fs);

    pulseByPipeline = containers.Map();
    pulseByPipeline('POS') = pulsePos;
    pulseByPipeline('CHROM') = pulseChrom;
    pulseByPipeline('cPACE-Stage1+POS') = pulseStage1Pos;
    pulseByPipeline('cPACE-Stage1+CHROM') = pulseStage1Chrom;

    eigRatioByPipeline = containers.Map();
    seedHzByPipeline = containers.Map();

    % --- Full Stage1+2+3 cPACE, swept over bw. Rc/Gc/Bc are the SAME
    % Stage-1 (q_hat) projection computed above -- cpaceEigenExtract.m
    % takes the raw projected trace, not the detrended/bandpassed one. ---
    for bwi = 1:numel(bwSweep)
        bw = bwSweep(bwi);
        pname = sprintf('cPACE-Full-bw%.2f', bw);
        try
            [s2, seedHz, ~, eigRatio, ~] = cpaceEigenExtract(Rc, Gc, Bc, fs, bw);
            s3 = cpaceHomodyneNormalize(s2, fs);
            pulseByPipeline(pname) = s3;
            eigRatioByPipeline(pname) = eigRatio;
            seedHzByPipeline(pname) = seedHz;
        catch cpaceErr
            fprintf('  %s: cPACE-Full bw=%.2f failed -- %s\n', id, bw, cpaceErr.message);
            pulseByPipeline(pname) = nan(1, numel(R));
            eigRatioByPipeline(pname) = NaN;
            seedHzByPipeline(pname) = NaN;
        end
    end

    for pi = 1:numPipelines
        pname = pipelineNames{pi};
        pulseFinal = pulseByPipeline(pname);

        predictedHR = NaN;
        if all(isfinite(pulseFinal))
            predictedHR = fftHeartRate(pulseFinal, fs);
        end

        waveformCorr = NaN;
        lagSec = NaN;
        wasFlipped = false;
        if all(isfinite(pulseFinal))
            try
                [sigAligned, gtAligned, ~, lagSec, ~, wasFlipped, ~, ~] = ...
                    estimateLagPolarityByGroundTruth(pulseFinal, roiTimestamps, gtPPG, gtTimestamps, targetFs, maxLagSec);
                sigZ = zscoreLocal(sigAligned);
                gtZ = zscoreLocal(gtAligned);
                waveformCorr = pearsonCorrLocal(sigZ, gtZ);
            catch
                % leave NaN -- same graceful-degradation convention Segment 11 used
            end
        end

        r = blank;
        r.id = id; r.source = source; r.pipeline = pname;
        r.predictedHR = predictedHR; r.gtHR = gtHRVal;
        r.absErr = abs(predictedHR - gtHRVal);
        r.waveformCorr = waveformCorr; r.lagSec = lagSec; r.wasFlipped = wasFlipped;
        if isKey(eigRatioByPipeline, pname)
            r.eigRatio = eigRatioByPipeline(pname);
            r.seedHz = seedHzByPipeline(pname);
        end
        r.harmonicConfusion = isHarmonicConfusionLocal(predictedHR, gtHRVal);
        rows(end + 1) = r; %#ok<AGROW>
    end

    if mod(i, 10) == 0 || i == numSubjects
        fprintf('  %d/%d subjects done (%s)\n', i, numSubjects, id);
    end
end

perSubjectHRTable = struct2table(rows, 'AsArray', true);
perSubjectHRPath = fullfile(metricsRoot, 'segment15_cpace_full_per_subject_hr.csv');
writetable(perSubjectHRTable, perSubjectHRPath);
fprintf('\nSaved %s\n', perSubjectHRPath);

% ============================================================
% PART A SUMMARY
% ============================================================
summaryBlank = struct('pipeline', '', 'hrMAE', NaN, 'hrRMSE', NaN, 'hrPearsonR', NaN, 'n', NaN, ...
    'waveformCorrMedian', NaN, 'harmonicConfusionRate', NaN, 'meanEigRatio', NaN);
summaryRows = repmat(summaryBlank, 0, 1);

fprintf('\n=== Part A summary (pooled, for orientation only -- see per-subject CSVs for the real comparison) ===\n');
for pi = 1:numPipelines
    pname = pipelineNames{pi};
    mask = strcmp({rows.pipeline}, pname);
    subset = rows(mask);
    predVec = [subset.predictedHR];
    gtVec = [subset.gtHR];
    validMask = ~isnan(predVec) & ~isnan(gtVec);
    m = computeMetrics(predVec(validMask), gtVec(validMask));

    corrVec = [subset.waveformCorr];
    corrVec = corrVec(~isnan(corrVec));

    confVec = [subset.harmonicConfusion];

    eigRatioVec = [subset.eigRatio];
    eigRatioVec = eigRatioVec(isfinite(eigRatioVec));

    sr = summaryBlank;
    sr.pipeline = pname;
    sr.hrMAE = m.mae; sr.hrRMSE = m.rmse; sr.hrPearsonR = m.pearsonR; sr.n = m.n;
    sr.waveformCorrMedian = median(corrVec);
    sr.harmonicConfusionRate = mean(confVec);
    if ~isempty(eigRatioVec)
        sr.meanEigRatio = mean(eigRatioVec);
    end
    summaryRows(end + 1) = sr; %#ok<AGROW>
    fprintf('  %-22s MAE=%6.2f RMSE=%6.2f r=%.3f medianCorr=%.3f harmConf=%.1f%% (n=%d)\n', ...
        pname, sr.hrMAE, sr.hrRMSE, sr.hrPearsonR, sr.waveformCorrMedian, 100 * sr.harmonicConfusionRate, sr.n);
end
summaryHRPath = fullfile(metricsRoot, 'segment15_cpace_full_summary_hr.csv');
writetable(struct2table(summaryRows, 'AsArray', true), summaryHRPath);
fprintf('Saved %s\n', summaryHRPath);

% ============================================================
% TASK 3: bw sweep, PER-SUBJECT regression report (0.30 as reference).
% ============================================================
fprintf('\n=== Task 3: bw sweep, per-subject regressions vs. bw=0.30 ===\n');
ids030 = {rows(strcmp({rows.pipeline}, 'cPACE-Full-bw0.30')).id};
err030 = [rows(strcmp({rows.pipeline}, 'cPACE-Full-bw0.30')).absErr];

sweepBlank = struct('id', '', 'source', '', 'absErr_bw015', NaN, 'absErr_bw030', NaN, 'absErr_bw050', NaN, ...
    'delta_015_vs_030', NaN, 'delta_050_vs_030', NaN, 'regressesAt015', false, 'regressesAt050', false);
sweepRows = repmat(sweepBlank, 0, 1);

ids015rows = rows(strcmp({rows.pipeline}, 'cPACE-Full-bw0.15'));
ids050rows = rows(strcmp({rows.pipeline}, 'cPACE-Full-bw0.50'));
ids030rows = rows(strcmp({rows.pipeline}, 'cPACE-Full-bw0.30'));

for k = 1:numel(ids030rows)
    id = ids030rows(k).id;
    row015 = ids015rows(strcmp({ids015rows.id}, id));
    row050 = ids050rows(strcmp({ids050rows.id}, id));
    if isempty(row015) || isempty(row050)
        continue
    end
    sr = sweepBlank;
    sr.id = id; sr.source = ids030rows(k).source;
    sr.absErr_bw015 = row015(1).absErr;
    sr.absErr_bw030 = ids030rows(k).absErr;
    sr.absErr_bw050 = row050(1).absErr;
    sr.delta_015_vs_030 = sr.absErr_bw015 - sr.absErr_bw030;
    sr.delta_050_vs_030 = sr.absErr_bw050 - sr.absErr_bw030;
    sr.regressesAt015 = sr.delta_015_vs_030 > 1.0; % >1 BPM worse
    sr.regressesAt050 = sr.delta_050_vs_030 > 1.0;
    sweepRows(end + 1) = sr; %#ok<AGROW>
end

numReg015 = sum([sweepRows.regressesAt015]);
numReg050 = sum([sweepRows.regressesAt050]);
fprintf('  bw=0.15 vs 0.30: %d/%d subjects regress by >1 BPM\n', numReg015, numel(sweepRows));
fprintf('  bw=0.50 vs 0.30: %d/%d subjects regress by >1 BPM\n', numReg050, numel(sweepRows));

sweepCsvPath = fullfile(metricsRoot, 'segment15_task3_bw_sweep_per_subject_regressions.csv');
writetable(struct2table(sweepRows, 'AsArray', true), sweepCsvPath);
fprintf('Saved %s\n', sweepCsvPath);

% ============================================================
% TASK 4: full cPACE (bw=0.30) vs. production POS/CHROM and Stage-1-only,
% PER-SUBJECT regression report.
% ============================================================
fprintf('\n=== Task 4: cPACE-Full-bw0.30 vs. production/Stage-1-only, per-subject ===\n');
compareBlank = struct('id', '', 'source', '', ...
    'absErr_POS', NaN, 'absErr_CHROM', NaN, 'absErr_Stage1POS', NaN, 'absErr_Stage1CHROM', NaN, ...
    'absErr_FullbW030', NaN, ...
    'regressesVsPOS', false, 'regressesVsCHROM', false, ...
    'regressesVsStage1POS', false, 'regressesVsStage1CHROM', false);
compareRows = repmat(compareBlank, 0, 1);

posRows = rows(strcmp({rows.pipeline}, 'POS'));
chromRows = rows(strcmp({rows.pipeline}, 'CHROM'));
s1posRows = rows(strcmp({rows.pipeline}, 'cPACE-Stage1+POS'));
s1chromRows = rows(strcmp({rows.pipeline}, 'cPACE-Stage1+CHROM'));

for k = 1:numel(ids030rows)
    id = ids030rows(k).id;
    rPos = posRows(strcmp({posRows.id}, id));
    rChrom = chromRows(strcmp({chromRows.id}, id));
    rS1Pos = s1posRows(strcmp({s1posRows.id}, id));
    rS1Chrom = s1chromRows(strcmp({s1chromRows.id}, id));
    if isempty(rPos) || isempty(rChrom) || isempty(rS1Pos) || isempty(rS1Chrom)
        continue
    end
    cr = compareBlank;
    cr.id = id; cr.source = ids030rows(k).source;
    cr.absErr_POS = rPos(1).absErr;
    cr.absErr_CHROM = rChrom(1).absErr;
    cr.absErr_Stage1POS = rS1Pos(1).absErr;
    cr.absErr_Stage1CHROM = rS1Chrom(1).absErr;
    cr.absErr_FullbW030 = ids030rows(k).absErr;
    cr.regressesVsPOS = cr.absErr_FullbW030 > cr.absErr_POS + 1.0;
    cr.regressesVsCHROM = cr.absErr_FullbW030 > cr.absErr_CHROM + 1.0;
    cr.regressesVsStage1POS = cr.absErr_FullbW030 > cr.absErr_Stage1POS + 1.0;
    cr.regressesVsStage1CHROM = cr.absErr_FullbW030 > cr.absErr_Stage1CHROM + 1.0;
    compareRows(end + 1) = cr; %#ok<AGROW>
end

fprintf('  Full-bw0.30 regresses (>1 BPM worse) vs. POS: %d/%d subjects\n', sum([compareRows.regressesVsPOS]), numel(compareRows));
fprintf('  Full-bw0.30 regresses (>1 BPM worse) vs. CHROM: %d/%d subjects\n', sum([compareRows.regressesVsCHROM]), numel(compareRows));
fprintf('  Full-bw0.30 regresses (>1 BPM worse) vs. Stage1+POS: %d/%d subjects\n', sum([compareRows.regressesVsStage1POS]), numel(compareRows));
fprintf('  Full-bw0.30 regresses (>1 BPM worse) vs. Stage1+CHROM: %d/%d subjects\n', sum([compareRows.regressesVsStage1CHROM]), numel(compareRows));

compareCsvPath = fullfile(metricsRoot, 'segment15_task4_vs_production_per_subject_regressions.csv');
writetable(struct2table(compareRows, 'AsArray', true), compareCsvPath);
fprintf('Saved %s\n', compareCsvPath);

% ============================================================
% PART B: cross-ROI PLV, 7 pipelines, 20-subject VIPL multi-region pool.
% ============================================================
regionNames = {'forehead', 'glabella', 'malar', 'cheek'};
plvSubjNums = [1, 3, 4, 6:22];
fprintf('\n=== Part B: cross-ROI PLV, %d pipelines, n=%d (VIPL v1/source1) ===\n', numPipelines, numel(plvSubjNums));

plvBlank = struct('id', '', 'pipeline', '', 'plvMean', NaN);
plvRows = repmat(plvBlank, 0, 1);

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

    for pi = 1:numPipelines
        pname = pipelineNames{pi};
        regionSignals = cell(1, numel(regionNames));
        okRegion = true;
        for ri = 1:numel(regionNames)
            rd = regionData.(regionNames{ri});
            regionPulse = computeRegionPulseForPipelineLocal(pname, rd, bwSweep);
            if isempty(regionPulse) || ~all(isfinite(regionPulse))
                okRegion = false;
                break
            end
            regionSignals{ri} = regionPulse;
        end
        if ~okRegion
            fprintf('  %s / %s: pipeline failed on at least one region, skipping PLV\n', subjId, pname);
            continue
        end

        plvMeanVal = computeCrossROIPLV(regionSignals, regionNames);
        pr = plvBlank;
        pr.id = subjId; pr.pipeline = pname; pr.plvMean = plvMeanVal;
        plvRows(end + 1) = pr; %#ok<AGROW>
    end
    fprintf('  PLV %s done\n', subjId);
end

plvTable = struct2table(plvRows, 'AsArray', true);
plvCsvPath = fullfile(metricsRoot, 'segment15_cpace_full_per_subject_plv.csv');
writetable(plvTable, plvCsvPath);
fprintf('Saved %s\n', plvCsvPath);

plvSummaryBlank = struct('pipeline', '', 'plvMeanAcrossSubjects', NaN, 'plvMedian', NaN, 'n', NaN);
plvSummaryRows = repmat(plvSummaryBlank, 0, 1);
fprintf('\n=== Part B summary ===\n');
for pi = 1:numPipelines
    pname = pipelineNames{pi};
    vals = [plvRows(strcmp({plvRows.pipeline}, pname)).plvMean];
    vals = vals(~isnan(vals));
    psr = plvSummaryBlank;
    psr.pipeline = pname;
    psr.plvMeanAcrossSubjects = mean(vals);
    psr.plvMedian = median(vals);
    psr.n = numel(vals);
    plvSummaryRows(end + 1) = psr; %#ok<AGROW>
    fprintf('  %-22s mean=%.3f median=%.3f (n=%d)\n', pname, psr.plvMeanAcrossSubjects, psr.plvMedian, psr.n);
end
plvSummaryCsvPath = fullfile(metricsRoot, 'segment15_cpace_full_summary_plv.csv');
writetable(struct2table(plvSummaryRows, 'AsArray', true), plvSummaryCsvPath);
fprintf('Saved %s\n', plvSummaryCsvPath);

% ============================================================
% FIGURES
% ============================================================
fprintf('\n=== Generating figures ===\n');

% --- HR MAE by pipeline (bar chart, pooled -- for orientation; the real
% claim lives in the per-subject CSVs). ---
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 500]);
maeVals = [summaryRows.hrMAE];
bar(maeVals);
set(gca, 'XTick', 1:numPipelines, 'XTickLabel', pipelineNames, 'XTickLabelRotation', 30);
ylabel('HR MAE (bpm)');
title(sprintf('Segment 15: HR MAE by pipeline, pooled (n=%d) -- see per-subject CSVs for regressions', numSubjects), 'Interpreter', 'none');
grid on;
outFig1 = fullfile(figuresRoot, 'segment15_hr_mae_by_pipeline.png');
exportgraphics(fig, outFig1, 'Resolution', 150);
close(fig);

% --- bw sweep, per-subject absolute error (paired lines). ---
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 500]);
hold on;
for k = 1:numel(sweepRows)
    plot([0.15, 0.30, 0.50], [sweepRows(k).absErr_bw015, sweepRows(k).absErr_bw030, sweepRows(k).absErr_bw050], ...
        '-o', 'Color', [0.6, 0.6, 0.6, 0.4], 'MarkerSize', 3);
end
medVals = [median([sweepRows.absErr_bw015]), median([sweepRows.absErr_bw030]), median([sweepRows.absErr_bw050])];
plot([0.15, 0.30, 0.50], medVals, '-o', 'Color', 'r', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'r');
xlabel('Eigen-window half-width bw (Hz)'); ylabel('HR abs. error (bpm)');
title(sprintf('Task 3: per-subject bw sweep (n=%d), red = median', numel(sweepRows)));
xlim([0.10, 0.55]);
grid on;
outFig2 = fullfile(figuresRoot, 'segment15_bw_sweep_per_subject.png');
exportgraphics(fig, outFig2, 'Resolution', 150);
close(fig);

% --- PLV by pipeline (bar chart). ---
fig = figure('Visible', 'off', 'Position', [100, 100, 900, 500]);
plvVals = [plvSummaryRows.plvMeanAcrossSubjects];
bar(plvVals);
set(gca, 'XTick', 1:numPipelines, 'XTickLabel', pipelineNames, 'XTickLabelRotation', 30);
ylabel('Mean cross-ROI PLV');
title(sprintf('Segment 15: cross-ROI PLV by pipeline (n=%d VIPL v1/source1)', numel(plvSubjNums)), 'Interpreter', 'none');
grid on;
outFig3 = fullfile(figuresRoot, 'segment15_plv_by_pipeline.png');
exportgraphics(fig, outFig3, 'Resolution', 150);
close(fig);

fprintf('Saved %s\nSaved %s\nSaved %s\n', outFig1, outFig2, outFig3);
fprintf('\nSegment 15 Tasks 3-4 complete.\n');


% ============================================================
% LOCAL FUNCTIONS
% ============================================================
function pulse = computeRegionPulseForPipelineLocal(pname, rd, bwSweep)
% Computes one region's scalar pulse signal for the named pipeline, using
% that region's own R/G/B/fs (each region gets its own q_hat, per
% Segment 11's own established convention -- the skin's mean reflectance
% direction is a per-ROI-patch quantity).
R = rd.R; G = rd.G; B = rd.B; fs = rd.fs;

switch pname
    case {'POS', 'CHROM'}
        [Rd_, ~] = detrendSignal(R); [Gd_, ~] = detrendSignal(G); [Bd_, ~] = detrendSignal(B);
        [Rf_, ~] = bandpassClean(Rd_, fs); [Gf_, ~] = bandpassClean(Gd_, fs); [Bf_, ~] = bandpassClean(Bd_, fs);
        if strcmp(pname, 'CHROM')
            pulse = bandpassClean(chromCombine(Rf_, Gf_, Bf_, R, G, B), fs);
        else
            pulse = bandpassClean(posCombine(Rf_, Gf_, Bf_, fs, R, G, B), fs);
        end
    case {'cPACE-Stage1+POS', 'cPACE-Stage1+CHROM'}
        [Rin, Gin, Bin, ~, ~] = cpaceProjection(R, G, B);
        [Rd_, ~] = detrendSignal(Rin); [Gd_, ~] = detrendSignal(Gin); [Bd_, ~] = detrendSignal(Bin);
        [Rf_, ~] = bandpassClean(Rd_, fs); [Gf_, ~] = bandpassClean(Gd_, fs); [Bf_, ~] = bandpassClean(Bd_, fs);
        if strcmp(pname, 'cPACE-Stage1+CHROM')
            pulse = bandpassClean(chromCombine(Rf_, Gf_, Bf_, R, G, B), fs);
        else
            pulse = bandpassClean(posCombine(Rf_, Gf_, Bf_, fs, R, G, B), fs);
        end
    otherwise
        % 'cPACE-Full-bw0.XX'
        tokens = regexp(pname, 'cPACE-Full-bw([\d.]+)', 'tokens');
        bw = str2double(tokens{1}{1});
        if ~any(abs(bwSweep - bw) < 1e-9)
            error('computeRegionPulseForPipelineLocal:unknownPipeline', 'Unrecognized pipeline "%s".', pname);
        end
        [Rin, Gin, Bin, ~, ~] = cpaceProjection(R, G, B);
        s2 = cpaceEigenExtract(Rin, Gin, Bin, fs, bw);
        pulse = cpaceHomodyneNormalize(s2, fs);
end
end

function tf = isHarmonicConfusionLocal(predictedHR, gtHR)
% Flags a predicted HR that landed on the 2nd harmonic or the sub-harmonic
% of the ground-truth rate instead of the fundamental (+/- 5 BPM
% tolerance) -- this project's Branch 1 analogue of the harmonic-confusion
% metric Segments 10-12 use for Branch 2's waveform/notch path.
if isnan(predictedHR) || isnan(gtHR) || gtHR <= 0
    tf = false;
    return
end
tf = (abs(predictedHR - 2 * gtHR) < 5) || (abs(predictedHR - gtHR / 2) < 5);
end

function [gtPPG, gtTimestamps, gtHRVal] = loadGTForSegment15(id, source, projectRoot)
% Mirrors Segment 11 Task 1's own loadGTForSegment11 local function
% exactly (same sources, same conventions) -- duplicated here rather than
% shared, consistent with this project's existing per-script local-helper
% convention (e.g. Segment 11's own script duplicates zscoreLocal/
% pearsonCorrLocal rather than factoring them out).
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
        gtTimestamps = (0:numel(gtPPG) - 1) / 60; % same nominal CMS60C convention as Segment 10/11
        gtHRVal = mean(gt.hr);
    otherwise
        error('loadGTForSegment15:badSource', 'Unknown source "%s".', source);
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
