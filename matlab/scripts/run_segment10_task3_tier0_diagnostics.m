% RUN_SEGMENT10_TASK3_TIER0_DIAGNOSTICS Segment 10 Task 3 -- four cheap,
% additive, read-only diagnostics that decide whether Segment 10 Task 2's
% Tier 1 candidate fixes are worth starting. All four use data already on
% disk (Task 1's own per-subject CSV, Task N's cached multi-region traces,
% and a brand-new synthetic waveform); NONE reprocess a video and NONE
% modify any of: pulseextraction/chromCombine.m, pulseextraction/
% posCombine.m, heartrate/fftHeartRate.m, morphology/adaptiveHarmonicFilter.m,
% filtering/waveletDenoise.m, filtering/bandpassClean.m, roi/
% extractROISignals.m -- every one of those is only ever CALLED, never
% edited, exactly the same discipline Task 1's own script
% (run_segment10_waveform_fidelity_audit.m) already used.
%
% Full brief and citations: matlab/docs/Segment10_Task2_Solution_Literature_
% Search.md section 8 ("Tier 0 -- costs almost nothing, decides what else is
% worth doing"). Full method/results writeup:
% matlab/docs/Segment10_Task3_Tier0_Diagnostics.md
%
% ACTION 1 -- Ceiling test. Tests arXiv:2606.03802's claim that the
% dicrotic notch spans only 1-3 samples at 30fps (i.e. at/below the
% measurement's resolution floor), by correlating Task 1's own per-subject
% notch confidence (on the rPPG SIGNAL, which the claim is about) against
% each subject's own TRUE effective fps. The "true fps" here is simply
% Task 1's own cached `frameRate` column: independently re-verified this
% session against p20/v1/source1's raw time.txt (see the doc's Method
% section for the exact numbers) to confirm it already reflects
% docs/VIPL_DATA_FORMAT.md section 4's documented time.txt correction, not
% VIPL's re-encoded 25fps container label -- so no fresh per-subject
% time.txt parsing was needed here, but the claim that the column already
% IS that corrected value was checked, not assumed. A GT-signal control
% (notchConfidenceGT_*, from a fixed-rate contact sensor the camera's fps
% cannot possibly affect) is reported alongside as a falsification check:
% if it correlates with camera fps just as strongly, the mechanism isn't
% camera sampling.
%
% ACTION 2 -- Cross-ROI phase-locking value, a fidelity metric that needs
% NO ground truth (Kaur, Lakshminarayanan & Saini, Biomed. Opt. Express
% 17(7):3832, 2026). Computed on Task N's already-cached four-region
% (forehead/glabella/malar/cheek) v1/source1 traces for the 20 subjects
% Task N validated, for CHROM and POS, then correlated against Task 1's own
% GT-referenced correlation for the same 20 subjects.
%
% ACTION 3 -- Synthetic-notch filter-distortion isolation test. A
% closed-form two-Gaussian single-cycle PPG model (documented parameters
% below) with an exactly known notch location/depth and systolic-peak
% location is sampled at 30/25/16 fps and pushed through
% filtering/bandpassClean.m, morphology/bandpassMorphology.m ('wide'), and
% three NEW (script-local only) order-2 variants at 8/10/12 Hz ceilings, to
% isolate how much of Task 1 finding (4) is filter-induced rather than
% physiological/methodological. Configurations whose upper cutoff meets or
% exceeds that fps's own Nyquist frequency are caught and reported as
% invalid, not silently skipped or crashed past.
%
% ACTION 4 -- POS cardiac-angle / sigma-ratio check (pure measurement; per
% the brief, posCombine.m is NOT modified regardless of what this finds).
% Reuses exactly two lines of posCombine.m's own math (S1 = Gn-Bn, S2 =
% Gn+Bn-2Rn) computed here standalone so the two projections can be
% inspected separately instead of already being combined, then finds the
% dominant direction of cardiac-band variation in that 2-D (S1,S2) plane
% via PCA and reports its angle relative to the S1 axis (POS's own e1),
% against POS's built-in ~57 degree assumption. Subject pool: the same 5
% UBFC-D1 + 20 VIPL v1/source1 subjects Action 2 already loads (reusing
% Task N's validated 20-subject cache -- see that action's own note for why
% these 20).
%
% Outputs:
%   results/metrics/segment10_task3_tier0_action1_ceiling.csv
%   results/metrics/segment10_task3_tier0_action2_plv.csv
%   results/metrics/segment10_task3_tier0_action3_synthetic_notch.csv
%   results/metrics/segment10_task3_tier0_action4_cardiac_angle.csv
%   results/figures/segment10_task3_action1_ceiling_scatter.png
%   results/figures/segment10_task3_action2_plv_scatter.png
%   results/figures/segment10_task3_action3_synthetic_notch.png
%   results/figures/segment10_task3_action4_cardiac_angle_hist.png

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
fprintf('Loaded Task 1 per-subject CSV: %d successful subjects (of %d total).\n', ...
    height(task1Table), height(task1TableFull));

fprintf('\n=== ACTION 1: Ceiling test (notch confidence vs. true effective fps) ===\n');
action1CeilingTest(task1Table, metricsRoot, figuresRoot);

fprintf('\n=== ACTION 2: Cross-ROI phase-locking value ===\n');
action2CrossRoiPLV(task1Table, processedRoot, metricsRoot, figuresRoot);

fprintf('\n=== ACTION 3: Synthetic-notch filter distortion test ===\n');
action3SyntheticNotch(metricsRoot, figuresRoot);

fprintf('\n=== ACTION 4: POS cardiac-angle / sigma-ratio check ===\n');
action4CardiacAngle(processedRoot, metricsRoot, figuresRoot);

fprintf('\nSegment 10 Task 3 Tier 0 diagnostics complete.\n');


% ============================================================
% ACTION 1
% ============================================================
function action1CeilingTest(task1Table, metricsRoot, figuresRoot)
branchNames = {'chrom', 'pos', 'harmonic'};
outCsvPath = fullfile(metricsRoot, 'segment10_task3_tier0_action1_ceiling.csv');

n = height(task1Table);
blank = struct('kind', '', 'group', '', 'branch', '', 'target', '', ...
    'r_pearson', NaN, 'r_spearman', NaN, 'n', NaN, ...
    'id', '', 'source', '', 'frameRate', NaN, ...
    'notchConfidence_chrom', NaN, 'notchConfidence_pos', NaN, 'notchConfidence_harmonic', NaN, ...
    'notchConfidenceGT_chrom', NaN, 'notchConfidenceGT_pos', NaN, 'notchConfidenceGT_harmonic', NaN);
rows = repmat(blank, 0, 1);

for i = 1:n
    r = blank;
    r.kind = 'subject';
    r.id = char(task1Table.id(i));
    r.source = char(task1Table.source(i));
    r.frameRate = task1Table.frameRate(i);
    r.notchConfidence_chrom = task1Table.notchConfidence_chrom(i);
    r.notchConfidence_pos = task1Table.notchConfidence_pos(i);
    r.notchConfidence_harmonic = task1Table.notchConfidence_harmonic(i);
    r.notchConfidenceGT_chrom = task1Table.notchConfidenceGT_chrom(i);
    r.notchConfidenceGT_pos = task1Table.notchConfidenceGT_pos(i);
    r.notchConfidenceGT_harmonic = task1Table.notchConfidenceGT_harmonic(i);
    rows(end + 1) = r; %#ok<AGROW>
end

sourceCol = cellstr(char(task1Table.source(:)));
groupDefs = {'all', true(n, 1); ...
             'ubfc_d1', strcmp(sourceCol, 'ubfc_d1'); ...
             'vipl', strcmp(sourceCol, 'vipl')};
targets = {'notchConfidence', 'notchConfidenceGT'};

for gi = 1:size(groupDefs, 1)
    gName = groupDefs{gi, 1};
    gMask = groupDefs{gi, 2};
    fr = task1Table.frameRate(gMask);
    for bi = 1:numel(branchNames)
        bn = branchNames{bi};
        for ti = 1:numel(targets)
            tgt = targets{ti};
            fieldName = [tgt '_' bn];
            vals = task1Table.(fieldName)(gMask);
            validMask = ~isnan(fr) & ~isnan(vals);
            frV = fr(validMask);
            valV = vals(validMask);
            r = blank;
            r.kind = 'correlation';
            r.group = gName;
            r.branch = bn;
            r.target = tgt;
            r.n = numel(frV);
            if numel(frV) >= 3
                r.r_pearson = pearsonCorrLocal(frV, valV);
                r.r_spearman = spearmanCorrLocal(frV, valV);
            end
            rows(end + 1) = r; %#ok<AGROW>
            fprintf('  [%s] %s vs %s: r_pearson=%.3f r_spearman=%.3f (n=%d)\n', ...
                gName, tgt, bn, r.r_pearson, r.r_spearman, r.n);
        end
    end
end

writetable(struct2table(rows, 'AsArray', true), outCsvPath);

isUbfc = strcmp(sourceCol, 'ubfc_d1');
isVipl = strcmp(sourceCol, 'vipl');

fig = figure('Visible', 'off', 'Position', [100, 100, 1400, 800]);
targetsForFig = {'notchConfidence', 'notchConfidenceGT'};
for ti = 1:2
    for bi = 1:3
        subplot(2, 3, (ti - 1) * 3 + bi);
        fieldName = [targetsForFig{ti} '_' branchNames{bi}];
        vals = task1Table.(fieldName);
        scatter(task1Table.frameRate(isUbfc), vals(isUbfc), 30, 'b', 'filled'); hold on;
        scatter(task1Table.frameRate(isVipl), vals(isVipl), 20, [0.9, 0.5, 0.1], 'filled');
        xlabel('True effective fps'); ylabel(strrep(fieldName, '_', ' '), 'Interpreter', 'none');
        title(sprintf('%s (%s)', targetsForFig{ti}, branchNames{bi}), 'Interpreter', 'none');
        if ti == 1 && bi == 1
            legend('UBFC-D1', 'VIPL', 'Location', 'best');
        end
        ylim([0, 1]);
        grid on;
    end
end
sgtitle('Action 1: notch confidence vs. true effective fps (top=rPPG signal, bottom=GT control)');
outFig = fullfile(figuresRoot, 'segment10_task3_action1_ceiling_scatter.png');
exportgraphics(fig, outFig, 'Resolution', 150);
close(fig);

fprintf('Action 1 saved: %s, %s\n', outCsvPath, outFig);
end


% ============================================================
% ACTION 2
% ============================================================
function action2CrossRoiPLV(task1Table, processedRoot, metricsRoot, figuresRoot)
regionNames = {'forehead', 'glabella', 'malar', 'cheek'};
subjNums = [1, 3, 4, 6:22]; % Task N's validated 20-subject v1/source1 cache -- all 20 confirmed present in Task 1's own pool this session
outCsvPath = fullfile(metricsRoot, 'segment10_task3_tier0_action2_plv.csv');

blank = struct('kind', '', 'id', '', 'regionPairA', '', 'regionPairB', '', ...
    'plv_chrom', NaN, 'plv_pos', NaN, 'corr_chrom', NaN, 'corr_pos', NaN, ...
    'branch', '', 'r_pearson', NaN, 'r_spearman', NaN, 'n', NaN);
rows = repmat(blank, 0, 1);

pairIdx = nchoosek(1:4, 2);

subjPlvChrom = nan(numel(subjNums), 1);
subjPlvPos = nan(numel(subjNums), 1);
subjCorrChrom = nan(numel(subjNums), 1);
subjCorrPos = nan(numel(subjNums), 1);

taskIds = cellstr(char(task1Table.id(:)));

for si = 1:numel(subjNums)
    pNum = subjNums(si);
    subjId = sprintf('VIPL_p%d_v1_source1', pNum);

    regionChrom = struct();
    regionPos = struct();
    okAll = true;
    fsAll = NaN;
    nAll = NaN;
    for ri = 1:4
        regionFile = fullfile(processedRoot, sprintf('VIPL_p%d_v1_source1_%s_rgb_traces.mat', pNum, regionNames{ri}));
        if ~isfile(regionFile)
            fprintf('  SKIP %s: missing region file %s\n', subjId, regionNames{ri});
            okAll = false;
            break
        end
        d = load(regionFile);
        if isnan(fsAll)
            fsAll = d.fs;
            nAll = numel(d.R);
        elseif abs(d.fs - fsAll) > 1e-6 || numel(d.R) ~= nAll
            fprintf('  SKIP %s: region %s fs/N mismatch vs. other regions\n', subjId, regionNames{ri});
            okAll = false;
            break
        end

        [Rd, ~] = detrendSignal(d.R);
        [Gd, ~] = detrendSignal(d.G);
        [Bd, ~] = detrendSignal(d.B);
        [Rf, ~] = bandpassClean(Rd, d.fs);
        [Gf, ~] = bandpassClean(Gd, d.fs);
        [Bf, ~] = bandpassClean(Bd, d.fs);

        pulseChrom = chromCombine(Rf, Gf, Bf, d.R, d.G, d.B);
        pulsePos = posCombine(Rf, Gf, Bf, d.fs, d.R, d.G, d.B);

        regionChrom.(regionNames{ri}) = bandpassClean(pulseChrom, d.fs);
        regionPos.(regionNames{ri}) = bandpassClean(pulsePos, d.fs);
    end
    if ~okAll
        continue
    end

    plvChromPairs = nan(size(pairIdx, 1), 1);
    plvPosPairs = nan(size(pairIdx, 1), 1);
    for pi = 1:size(pairIdx, 1)
        rA = regionNames{pairIdx(pi, 1)};
        rB = regionNames{pairIdx(pi, 2)};

        phaseAC = angle(hilbert(regionChrom.(rA)));
        phaseBC = angle(hilbert(regionChrom.(rB)));
        plvChromPairs(pi) = abs(mean(exp(1i * (phaseAC(:) - phaseBC(:)))));

        phaseAP = angle(hilbert(regionPos.(rA)));
        phaseBP = angle(hilbert(regionPos.(rB)));
        plvPosPairs(pi) = abs(mean(exp(1i * (phaseAP(:) - phaseBP(:)))));

        r = blank;
        r.kind = 'pairwise';
        r.id = subjId;
        r.regionPairA = rA;
        r.regionPairB = rB;
        r.plv_chrom = plvChromPairs(pi);
        r.plv_pos = plvPosPairs(pi);
        rows(end + 1) = r; %#ok<AGROW>
    end

    subjPlvChrom(si) = mean(plvChromPairs);
    subjPlvPos(si) = mean(plvPosPairs);

    task1Idx = find(strcmp(taskIds, subjId), 1);
    if ~isempty(task1Idx)
        subjCorrChrom(si) = task1Table.corr_chrom(task1Idx);
        subjCorrPos(si) = task1Table.corr_pos(task1Idx);
    end

    r = blank;
    r.kind = 'subject';
    r.id = subjId;
    r.plv_chrom = subjPlvChrom(si);
    r.plv_pos = subjPlvPos(si);
    r.corr_chrom = subjCorrChrom(si);
    r.corr_pos = subjCorrPos(si);
    rows(end + 1) = r; %#ok<AGROW>

    fprintf('  %s: PLV chrom=%.3f pos=%.3f | Task1 corr chrom=%.3f pos=%.3f\n', ...
        subjId, subjPlvChrom(si), subjPlvPos(si), subjCorrChrom(si), subjCorrPos(si));
end

branchList = {'chrom', 'pos'};
for bi = 1:2
    bn = branchList{bi};
    if bi == 1
        plvVals = subjPlvChrom; corrVals = subjCorrChrom;
    else
        plvVals = subjPlvPos; corrVals = subjCorrPos;
    end
    validMask = ~isnan(plvVals) & ~isnan(corrVals);
    r = blank;
    r.kind = 'correlation';
    r.branch = bn;
    r.n = sum(validMask);
    if sum(validMask) >= 3
        r.r_pearson = pearsonCorrLocal(plvVals(validMask), corrVals(validMask));
        r.r_spearman = spearmanCorrLocal(plvVals(validMask), corrVals(validMask));
    end
    rows(end + 1) = r; %#ok<AGROW>
    fprintf('  [correlation] PLV vs Task1 corr (%s): r_pearson=%.3f r_spearman=%.3f (n=%d)\n', ...
        bn, r.r_pearson, r.r_spearman, r.n);
end

writetable(struct2table(rows, 'AsArray', true), outCsvPath);

validChrom = ~isnan(subjPlvChrom) & ~isnan(subjCorrChrom);
validPos = ~isnan(subjPlvPos) & ~isnan(subjCorrPos);

fig = figure('Visible', 'off', 'Position', [100, 100, 900, 450]);
subplot(1, 2, 1);
scatter(subjPlvChrom(validChrom), subjCorrChrom(validChrom), 35, 'filled');
xlabel('Mean cross-ROI PLV (CHROM)'); ylabel('Task 1 GT-referenced corr (CHROM)');
title(sprintf('CHROM: r=%.3f (n=%d)', pearsonCorrLocal(subjPlvChrom(validChrom), subjCorrChrom(validChrom)), sum(validChrom)));
grid on;
subplot(1, 2, 2);
scatter(subjPlvPos(validPos), subjCorrPos(validPos), 35, 'filled');
xlabel('Mean cross-ROI PLV (POS)'); ylabel('Task 1 GT-referenced corr (POS)');
title(sprintf('POS: r=%.3f (n=%d)', pearsonCorrLocal(subjPlvPos(validPos), subjCorrPos(validPos)), sum(validPos)));
grid on;
outFig = fullfile(figuresRoot, 'segment10_task3_action2_plv_scatter.png');
exportgraphics(fig, outFig, 'Resolution', 150);
close(fig);

fprintf('Action 2 saved: %s, %s\n', outCsvPath, outFig);
end


% ============================================================
% ACTION 3
% ============================================================
function action3SyntheticNotch(metricsRoot, figuresRoot)
% Two-Gaussian single-cycle PPG model, parameters chosen (documented here,
% not tuned from any real data) so that: (a) both Gaussians decay to
% negligible amplitude at the cycle boundary (tau=0 and tau=T), so tiling
% this single-cycle function periodically produces no boundary
% discontinuity; (b) the systolic-peak-to-notch gap exceeds
% morphology/notchDetectIEM.m's own hard-coded 0.1s minimum gap
% requirement with a safety margin, so the notch is genuinely detectable
% by the same detector Task 1 used, not a borderline case; (c) the
% resulting notch depth and diastolic-peak-to-systolic-peak ratio are
% within the range of physiologically plausible PPG morphology.
f0Hz = 1.2; % 72 bpm, a representative mid-range HR
T = 1 / f0Hz;
mu1 = 0.20; sigma1 = 0.06; A1 = 1.0;    % systolic peak
mu2 = 0.42; sigma2 = 0.095; A2 = 0.72;  % diastolic/dicrotic peak
ppgCycleFn = @(tau) A1 * exp(-0.5 * ((mod(tau, T) - mu1) / sigma1) .^ 2) + ...
                     A2 * exp(-0.5 * ((mod(tau, T) - mu2) / sigma2) .^ 2);

numCycles = 36;
analysisCycleIdx = 18; % middle cycle -- far from filtfilt's edge transients at either end
beatSamples = 256;

% --- Ground truth, from a dense analytic grid, run through the SAME
% detector (notchDetectIEM.m) Task 1 used, for apples-to-apples units. ---
tauFine = linspace(0, T, 200000);
pFine = ppgCycleFn(tauFine);
protoTrue = interp1(tauFine, pFine, linspace(0, T, beatSamples), 'pchip');
effFsTrue = beatSamples * f0Hz; % same fs=beatSamples*(hrBpm/60) convention Task 1's script used

[notchDetTrue, notchPosTrue, notchDepthTrue, ~, ~] = notchDetectIEM(protoTrue, effFsTrue);
[~, peakIdxTrue] = max(protoTrue);
peakFracTrue = (peakIdxTrue - 1) / (beatSamples - 1);

fprintf('  Ground truth (analytic, %.0f bpm, gap-to-notch known >0.1s by construction):\n', f0Hz * 60);
fprintf('    notchDetected=%d notchPosNorm=%.4f notchDepth=%.4f peakFrac=%.4f\n', ...
    notchDetTrue, notchPosTrue, notchDepthTrue, peakFracTrue);
if ~notchDetTrue
    error('action3SyntheticNotch:noGroundTruthNotch', ...
        'Ground-truth synthetic waveform has no detectable notch -- fix the model parameters before trusting any distortion number below.');
end

configs = struct('name', {}, 'lowHz', {}, 'highHz', {}, 'order', {}, 'fn', {});
configs(1) = struct('name', 'bandpassClean (Bw2, 0.7-4Hz)', 'lowHz', 0.7, 'highHz', 4.0, 'order', 2, 'fn', 'bandpassClean');
configs(2) = struct('name', 'bandpassMorphology wide (Bw3, 0.5-8Hz)', 'lowHz', 0.5, 'highHz', 8.0, 'order', 3, 'fn', 'bandpassMorphologyWide');
configs(3) = struct('name', 'order2 custom 0.7-8Hz', 'lowHz', 0.7, 'highHz', 8.0, 'order', 2, 'fn', 'custom');
configs(4) = struct('name', 'order2 custom 0.7-10Hz', 'lowHz', 0.7, 'highHz', 10.0, 'order', 2, 'fn', 'custom');
configs(5) = struct('name', 'order2 custom 0.7-12Hz', 'lowHz', 0.7, 'highHz', 12.0, 'order', 2, 'fn', 'custom');

fpsList = [30, 25, 16];

blank = struct('configName', '', 'lowHz', NaN, 'highHz', NaN, 'order', NaN, 'fps', NaN, ...
    'nyquistHz', NaN, 'valid', false, 'notchDetectedFiltered', false, ...
    'notchPosNormFiltered', NaN, 'notchDepthFiltered', NaN, 'peakFracFiltered', NaN, ...
    'notchPositionErrorMs', NaN, 'notchDepthRatio', NaN, 'systolicPeakTimingShiftMs', NaN, 'note', '');
rows = repmat(blank, 0, 1);

for ci = 1:numel(configs)
    cfg = configs(ci);
    for fi = 1:numel(fpsList)
        fps = fpsList(fi);
        r = blank;
        r.configName = cfg.name;
        r.lowHz = cfg.lowHz;
        r.highHz = cfg.highHz;
        r.order = cfg.order;
        r.fps = fps;
        r.nyquistHz = fps / 2;

        try
            if cfg.highHz >= r.nyquistHz
                error('action3:nyquist', 'high cutoff %.1fHz >= Nyquist %.1fHz at %dfps', cfg.highHz, r.nyquistHz, fps);
            end

            totalSamples = round(numCycles * T * fps);
            tSamples = (0:totalSamples - 1) / fps;
            sigRaw = ppgCycleFn(tSamples);
            sigZeroMean = sigRaw - mean(sigRaw);

            switch cfg.fn
                case 'bandpassClean'
                    sigF = bandpassClean(sigZeroMean, fps);
                case 'bandpassMorphologyWide'
                    [sigF, ~, ~] = bandpassMorphology(sigZeroMean, fps, 'wide');
                case 'custom'
                    sigF = bandpassOrder2Custom(sigZeroMean, fps, cfg.lowHz, cfg.highHz);
            end

            cycleStartT = analysisCycleIdx * T;
            padSec = 3 / fps;
            wideMask = tSamples >= (cycleStartT - padSec) & tSamples <= (cycleStartT + T + padSec);
            if sum(wideMask) < 4
                error('action3:tooFewSamples', 'fewer than 4 samples available around the analysis cycle at %d fps', fps);
            end
            cycleTWide = tSamples(wideMask) - cycleStartT;
            cycleValsWide = sigF(wideMask);

            proto = interp1(cycleTWide, cycleValsWide, linspace(0, T, beatSamples), 'pchip');
            effFs = beatSamples * f0Hz;

            [notchDetF, notchPosF, notchDepthF, ~, ~] = notchDetectIEM(proto, effFs);
            [~, peakIdxF] = max(proto);
            peakFracF = (peakIdxF - 1) / (beatSamples - 1);

            r.valid = true;
            r.notchDetectedFiltered = notchDetF;
            r.notchPosNormFiltered = notchPosF;
            r.notchDepthFiltered = notchDepthF;
            r.peakFracFiltered = peakFracF;
            r.systolicPeakTimingShiftMs = (peakFracF - peakFracTrue) * T * 1000;

            if notchDetF
                r.notchPositionErrorMs = (notchPosF - notchPosTrue) * T * 1000;
                r.notchDepthRatio = notchDepthF / notchDepthTrue;
            else
                r.note = 'notch not detected post-filter (flattened below IEM threshold)';
            end
        catch cErr
            r.valid = false;
            r.note = cErr.message;
        end

        rows(end + 1) = r; %#ok<AGROW>
        fprintf('  %-38s @ %2dfps (Nyq=%5.1fHz): valid=%d notchErr=%7.2fms depthRatio=%.3f peakShift=%7.2fms %s\n', ...
            cfg.name, fps, r.nyquistHz, r.valid, r.notchPositionErrorMs, r.notchDepthRatio, r.systolicPeakTimingShiftMs, r.note);
    end
end

outCsvPath = fullfile(metricsRoot, 'segment10_task3_tier0_action3_synthetic_notch.csv');
writetable(struct2table(rows, 'AsArray', true), outCsvPath);

configNamesShort = {'BwClean(0.7-4)', 'Morph-wide(0.5-8)', 'ord2(0.7-8)', 'ord2(0.7-10)', 'ord2(0.7-12)'};
metricsToPlot = {'notchPositionErrorMs', 'notchDepthRatio', 'systolicPeakTimingShiftMs'};
metricLabels = {'Notch position error (ms)', 'Notch depth ratio (filtered/true)', 'Systolic peak timing shift (ms)'};
barColors = lines(numel(configNamesShort));

fig = figure('Visible', 'off', 'Position', [100, 100, 1200, 950]);
rowConfigNames = {rows.configName};
rowFps = [rows.fps];
for mi = 1:3
    subplot(3, 1, mi);
    dataMat = nan(numel(fpsList), numel(configs));
    for ci = 1:numel(configs)
        for fi = 1:numel(fpsList)
            idx = find(strcmp(rowConfigNames, configs(ci).name) & rowFps == fpsList(fi), 1);
            if ~isempty(idx) && rows(idx).valid
                dataMat(fi, ci) = rows(idx).(metricsToPlot{mi});
            end
        end
    end
    b = bar(dataMat);
    for ci = 1:numel(b)
        b(ci).FaceColor = barColors(ci, :);
    end
    set(gca, 'XTickLabel', arrayfun(@(x) sprintf('%dfps', x), fpsList, 'UniformOutput', false));
    ylabel(metricLabels{mi});
    if mi == 1
        legend(configNamesShort, 'Location', 'eastoutside', 'Interpreter', 'none');
    end
    if mi == 2
        yline(1, 'k--');
    end
    grid on;
end
sgtitle('Action 3: synthetic-notch filter distortion (blank bars = invalid config or notch not detected post-filter)');
outFig = fullfile(figuresRoot, 'segment10_task3_action3_synthetic_notch.png');
exportgraphics(fig, outFig, 'Resolution', 150);
close(fig);

fprintf('Action 3 saved: %s, %s\n', outCsvPath, outFig);
end

function sigF = bandpassOrder2Custom(sigDetrended, frameRate, lowHz, highHz)
% Script-local, additive-only order-2 Butterworth bandpass with a
% caller-specified upper cutoff -- NOT a modification of
% filtering/bandpassClean.m (which hardcodes 4.0Hz) or
% morphology/bandpassMorphology.m (which hardcodes order 3). Same
% butter()+filtfilt() construction as both of those, parameterized only
% for this diagnostic's own Action 3(c).
filterOrder = 2;
nyquistHz = frameRate / 2;
if highHz >= nyquistHz
    error('bandpassOrder2Custom:nyquist', 'highHz (%.2f) >= Nyquist (%.2f) for frameRate %.2f', highHz, nyquistHz, frameRate);
end
lowNorm = lowHz / nyquistHz;
highNorm = highHz / nyquistHz;
[b, a] = butter(filterOrder, [lowNorm, highNorm], 'bandpass');
sigF = filtfilt(b, a, sigDetrended);
end


% ============================================================
% ACTION 4
% ============================================================
function action4CardiacAngle(processedRoot, metricsRoot, figuresRoot)
d1List = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
viplNums = [1, 3, 4, 6:22]; % same 20-subject cache Action 2 uses -- reuses the already-loaded pool rather than opening a third data path

subjects = struct('id', {}, 'source', {}, 'cachePath', {});
for k = 1:numel(d1List)
    subjects(end + 1) = struct('id', d1List{k}, 'source', 'ubfc_d1', ...
        'cachePath', fullfile(processedRoot, [d1List{k} '_rgb_traces.mat'])); %#ok<AGROW>
end
for k = 1:numel(viplNums)
    id = sprintf('VIPL_p%d_v1_source1', viplNums(k));
    subjects(end + 1) = struct('id', id, 'source', 'vipl', ...
        'cachePath', fullfile(processedRoot, [id '_rgb_traces.mat'])); %#ok<AGROW>
end

blank = struct('kind', '', 'id', '', 'source', '', 'cardiacAngleDeg', NaN, ...
    'group', '', 'median', NaN, 'iqr25', NaN, 'iqr75', NaN, 'n', NaN, 'fractionAbove90Deg', NaN);
rows = repmat(blank, 0, 1);

angles = nan(numel(subjects), 1);
sources = cell(numel(subjects), 1);

for i = 1:numel(subjects)
    s = subjects(i);
    if ~isfile(s.cachePath)
        fprintf('  SKIP %s: no cache at %s\n', s.id, s.cachePath);
        continue
    end
    d = load(s.cachePath);
    [Rd, ~] = detrendSignal(d.R);
    [Gd, ~] = detrendSignal(d.G);
    [Bd, ~] = detrendSignal(d.B);
    [Rf, ~] = bandpassClean(Rd, d.fs);
    [Gf, ~] = bandpassClean(Gd, d.fs);
    [Bf, ~] = bandpassClean(Bd, d.fs);

    meanR = mean(d.R);
    meanG = mean(d.G);
    meanB = mean(d.B);
    Rn = Rf / meanR;
    Gn = Gf / meanG;
    Bn = Bf / meanB;

    % Exactly posCombine.m's own S1/S2 lines (lines 39-40 of that file),
    % reproduced standalone here so the two projections can be inspected
    % SEPARATELY instead of already combined by posCombine.m's std-ratio
    % step -- posCombine.m itself is not called or modified.
    S1 = Gn - Bn;
    S2 = Gn + Bn - 2 * Rn;

    C = cov(S1(:), S2(:));
    [V, D] = eig(C);
    [~, maxIdx] = max(diag(D));
    v = V(:, maxIdx);

    angleDeg = atan2d(v(2), v(1));
    if angleDeg < 0
        angleDeg = angleDeg + 180;
    end

    angles(i) = angleDeg;
    sources{i} = s.source;

    r = blank;
    r.kind = 'subject';
    r.id = s.id;
    r.source = s.source;
    r.cardiacAngleDeg = angleDeg;
    rows(end + 1) = r; %#ok<AGROW>

    fprintf('  %s (%s): cardiac angle = %.1f deg\n', s.id, s.source, angleDeg);
end

groupDefs = {'all', true(numel(subjects), 1); ...
             'ubfc_d1', strcmp(sources, 'ubfc_d1'); ...
             'vipl', strcmp(sources, 'vipl')};
for gi = 1:size(groupDefs, 1)
    gName = groupDefs{gi, 1};
    gMask = groupDefs{gi, 2};
    vals = angles(gMask);
    vals = vals(~isnan(vals));
    if isempty(vals)
        continue
    end
    r = blank;
    r.kind = 'summary';
    r.group = gName;
    r.median = median(vals);
    r.iqr25 = prctileLocal(vals, 25);
    r.iqr75 = prctileLocal(vals, 75);
    r.n = numel(vals);
    r.fractionAbove90Deg = sum(vals > 90) / numel(vals);
    rows(end + 1) = r; %#ok<AGROW>
    fprintf('  [summary] %s: median=%.1f deg (IQR %.1f-%.1f), n=%d, %.0f%% above 90deg\n', ...
        gName, r.median, r.iqr25, r.iqr75, r.n, 100 * r.fractionAbove90Deg);
end

outCsvPath = fullfile(metricsRoot, 'segment10_task3_tier0_action4_cardiac_angle.csv');
writetable(struct2table(rows, 'AsArray', true), outCsvPath);

fig = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
histogram(angles(~isnan(angles)), 12);
hold on;
xline(57, 'r--', 'LineWidth', 1.5);
xline(90, 'k--', 'LineWidth', 1.5);
text(57, max(ylim) * 0.95, ' POS assumed (57°)', 'Color', 'r');
text(90, max(ylim) * 0.85, ' destructive threshold (90°)', 'Color', 'k');
xlabel('Measured cardiac angle relative to POS e1 (degrees)');
ylabel('Subject count');
title(sprintf('Action 4: cardiac angle distribution (n=%d, UBFC-D1 5 + VIPL v1/source1 20)', sum(~isnan(angles))));
grid on;
outFig = fullfile(figuresRoot, 'segment10_task3_action4_cardiac_angle_hist.png');
exportgraphics(fig, outFig, 'Resolution', 150);
close(fig);

fprintf('Action 4 saved: %s, %s\n', outCsvPath, outFig);
end


% ============================================================
% SHARED LOCAL HELPERS
% ============================================================
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

function rho = spearmanCorrLocal(x, y)
rho = pearsonCorrLocal(rankLocal(x), rankLocal(y));
end

function ranks = rankLocal(x)
x = x(:);
[sortedX, sortIdx] = sort(x);
n = numel(x);
ranks = zeros(n, 1);
i = 1;
while i <= n
    j = i;
    while j < n && sortedX(j + 1) == sortedX(i)
        j = j + 1;
    end
    avgRank = (i + j) / 2;
    ranks(sortIdx(i:j)) = avgRank;
    i = j + 1;
end
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
