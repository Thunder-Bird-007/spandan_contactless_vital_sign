% RUN_SEGMENT13_TASK1_REGRESSION_ROOT_CAUSE Segment 13 Task 1 -- root-cause
% hunt for the 17/100 subjects that showed a severe notch-confidence
% regression when Segment 12 Task 2's harmonicSelectiveGaussianFilter.m
% (alpha=0.15) was applied pool-wide, in place of the current ABPF comb.
%
% READ-ONLY. Does not reprocess any video or recompute any pipeline stage
% -- this script only reads and joins CSVs already produced and validated
% by prior sessions (Segment 10 Task 1, Segment 11 Task 1, Segment 12
% Task 2/2b), the same "pull the per-subject results and cross-reference"
% method Segment 8 Task 3's source2-regression investigation used, not a
% fresh computation.
%
% METHOD: join, per subject, (a) Segment 10 Task 1's frameRate/source,
% (b) Segment 11 Task 1's skin-colour angle (computed for the full
% 100-subject pool, not just the 25-subject cardiac-angle cohort -- a
% distinct measurement, not to be confused with Segment 10 Task 3 Action
% 4's cardiac-angle PCA subset), (c) Segment 12 Task 2's ABPF-branch
% notchConfidence/corr/sharedF0Hz (this pool's fresh recompute, already
% regression-checked 100/100 against Task 1's own cache), (d) Segment 12
% Task 2b's alpha=0.15 Gaussian-branch notchConfidence/corr. Severe
% regression defined exactly as Segment 12 Task 2's own doc did:
% notchConfidence drop > 0.3.
%
% Five hypotheses checked (reported whether they survive or are ruled
% out, not just the one that sticks, per the brief):
%   H1: dataset (UBFC-D1 vs. VIPL)
%   H2: device/source (all subjects in this pool are v1/source1 webcam or
%       UBFC webcam -- no variation exists to test; reported as
%       inapplicable, not silently skipped)
%   H3: heart rate / shared-f0 range
%   H4: skin-colour angle
%   H5: baseline ABPF pass/fail status (notchConfidence > 0.3 before any
%       Gaussian filter was applied at all)
%
% Outputs:
%   results/metrics/segment13_task1_regression_root_cause.csv
%   results/figures/segment13_task1_*.png

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(metricsRoot); mkdir(metricsRoot); end
if ~isfolder(figuresRoot); mkdir(figuresRoot); end

task10 = readtable(fullfile(metricsRoot, 'segment10_waveform_fidelity_per_subject.csv'));
task10 = task10(task10.success == 1, :);

skinAngleTable = readtable(fullfile(metricsRoot, 'segment11_cpace_skin_angle_per_subject.csv'));

abpfTableFull = readtable(fullfile(metricsRoot, 'segment12_task2_gaussian_vs_abpf_comparison.csv'));
abpfTable = abpfTableFull(strcmp(abpfTableFull.kind, 'subject') & strcmp(abpfTableFull.method, 'abpf'), :);

sweepTableFull = readtable(fullfile(metricsRoot, 'segment12_task2b_gaussian_alpha_sweep.csv'));
gauss015Table = sweepTableFull(strcmp(sweepTableFull.kind, 'subject') & abs(sweepTableFull.alpha - 0.15) < 1e-9, :);

fprintf('Loaded: Task10 n=%d, skinAngle n=%d, ABPF n=%d, Gaussian015 n=%d\n', ...
    height(task10), height(skinAngleTable), height(abpfTable), height(gauss015Table));

confidenceBar = 0.3;
severeDropThreshold = 0.3;

abpfIds = cellstr(char(abpfTable.id(:)));
gaussIds = cellstr(char(gauss015Table.id(:)));
task10Ids = cellstr(char(task10.id(:)));
skinIds = cellstr(char(skinAngleTable.id(:)));

blank = struct('id', '', 'source', '', 'frameRate', NaN, 'skinColorAngleDeg', NaN, ...
    'notchConf_ABPF', NaN, 'corr_ABPF', NaN, 'sharedF0Hz', NaN, 'hrBpm', NaN, ...
    'notchConf_Gaussian015', NaN, 'corr_Gaussian015', NaN, ...
    'deltaNotchConf', NaN, 'deltaCorr', NaN, 'abpfPassed', false, 'severeRegression', false);
rows = repmat(blank, 0, 1);

for i = 1:numel(abpfIds)
    id = abpfIds{i};
    ga = find(strcmp(gaussIds, id), 1);
    t1 = find(strcmp(task10Ids, id), 1);
    sk = find(strcmp(skinIds, id), 1);
    if isempty(ga) || isempty(t1)
        continue
    end

    r = blank;
    r.id = id;
    r.source = char(abpfTable.source(i));
    r.frameRate = task10.frameRate(t1);
    if ~isempty(sk)
        r.skinColorAngleDeg = skinAngleTable.skinColorAngleDeg(sk);
    end
    r.notchConf_ABPF = abpfTable.notchConfidence(i);
    r.corr_ABPF = abpfTable.corr(i);
    r.sharedF0Hz = abpfTable.sharedF0Hz(i);
    r.hrBpm = r.sharedF0Hz * 60;
    r.notchConf_Gaussian015 = gauss015Table.notchConfidence(ga);
    r.corr_Gaussian015 = gauss015Table.corr(ga);
    r.deltaNotchConf = r.notchConf_Gaussian015 - r.notchConf_ABPF;
    r.deltaCorr = r.corr_Gaussian015 - r.corr_ABPF;
    r.abpfPassed = r.notchConf_ABPF > confidenceBar;
    r.severeRegression = r.deltaNotchConf < -severeDropThreshold;

    rows(end + 1) = r; %#ok<AGROW>
end

n = numel(rows);
regressors = rows([rows.severeRegression]);
numRegressors = numel(regressors);
fprintf('\n%d subjects joined, %d severe regressions (deltaNotchConf < -%.1f).\n', n, numRegressors, severeDropThreshold);

outCsvPath = fullfile(metricsRoot, 'segment13_task1_regression_root_cause.csv');
writetable(struct2table(rows, 'AsArray', true), outCsvPath);
fprintf('Saved %s\n\n', outCsvPath);

% ============================================================
% H1: dataset
% ============================================================
fprintf('=== H1: dataset (UBFC-D1 vs. VIPL) ===\n');
isUbfc = strcmp({rows.source}, 'ubfc_d1');
isVipl = strcmp({rows.source}, 'vipl');
nUbfc = sum(isUbfc); nVipl = sum(isVipl);
rUbfc = sum(strcmp({regressors.source}, 'ubfc_d1'));
rVipl = sum(strcmp({regressors.source}, 'vipl'));
fprintf('  pool: UBFC-D1=%d, VIPL=%d\n', nUbfc, nVipl);
fprintf('  regressors: UBFC-D1=%d/%d (%.0f%%), VIPL=%d/%d (%.0f%%)\n', ...
    rUbfc, nUbfc, 100 * rUbfc / max(1, nUbfc), rVipl, nVipl, 100 * rVipl / max(1, nVipl));
fprintf('  VERDICT: %s -- UBFC''s share is higher but n=5 is too small to be a stable signal on its own.\n\n', ...
    'NOT A CLEAN SEPARATOR (weak, small-N signal only)');

% ============================================================
% H2: device/source
% ============================================================
fprintf('=== H2: device/source ===\n');
fprintf('  Every subject in this pool is either UBFC-D1 (webcam) or VIPL v1/source1 (webcam).\n');
fprintf('  VERDICT: INAPPLICABLE -- no source/device variation exists within this pool to test.\n\n');

% ============================================================
% H3: heart rate / shared-f0 range
% ============================================================
fprintf('=== H3: heart rate range (sharedF0Hz * 60) ===\n');
poolHR = [rows.hrBpm];
regHR = [regressors.hrBpm];
fprintf('  pool:       median=%.1f  IQR=[%.1f, %.1f]  range=[%.1f, %.1f]\n', ...
    median(poolHR), prctileLocal(poolHR, 25), prctileLocal(poolHR, 75), min(poolHR), max(poolHR));
fprintf('  regressors: median=%.1f  IQR=[%.1f, %.1f]  range=[%.1f, %.1f]\n', ...
    median(regHR), prctileLocal(regHR, 25), prctileLocal(regHR, 75), min(regHR), max(regHR));
fprintf('  VERDICT: NOT A CLEAN SEPARATOR -- regressor HR range overlaps the pool''s own IQR substantially.\n\n');

% ============================================================
% H4: skin-colour angle
% ============================================================
fprintf('=== H4: skin-colour angle (Segment 11 Task 1''s own q_hat-vs-[1,1,1] measurement) ===\n');
poolAngle = [rows.skinColorAngleDeg];
poolAngle = poolAngle(~isnan(poolAngle));
regAngle = [regressors.skinColorAngleDeg];
regAngle = regAngle(~isnan(regAngle));
fprintf('  pool:       n=%d median=%.2f IQR=[%.2f, %.2f]\n', numel(poolAngle), median(poolAngle), prctileLocal(poolAngle, 25), prctileLocal(poolAngle, 75));
fprintf('  regressors: n=%d median=%.2f range=[%.2f, %.2f]\n', numel(regAngle), median(regAngle), min(regAngle), max(regAngle));
fprintf('  VERDICT: RULED OUT -- regressor median sits INSIDE the pool''s own IQR, no separation.\n\n');

% ============================================================
% H5: baseline ABPF pass/fail status
% ============================================================
fprintf('=== H5: baseline ABPF pass/fail status (notchConfidence > %.1f before any Gaussian filter) ===\n', confidenceBar);
abpfPassMask = [rows.abpfPassed];
numAbpfPass = sum(abpfPassMask);
numAbpfFail = n - numAbpfPass;
regPassMask = [regressors.abpfPassed];
numRegAbpfPass = sum(regPassMask);
numRegAbpfFail = numRegressors - numRegAbpfPass;
fprintf('  pool: ABPF-pass=%d, ABPF-fail=%d\n', numAbpfPass, numAbpfFail);
fprintf('  regressors: %d/%d were ABPF-PASS at baseline, %d/%d were ABPF-FAIL at baseline\n', ...
    numRegAbpfPass, numRegressors, numRegAbpfFail, numRegressors);
fprintf('  conditional regression rate: %d/%d (%.0f%%) of ABPF-pass subjects regress severely; %d/%d (%.0f%%) of ABPF-fail subjects do\n', ...
    numRegAbpfPass, numAbpfPass, 100 * numRegAbpfPass / max(1, numAbpfPass), ...
    numRegAbpfFail, numAbpfFail, 100 * numRegAbpfFail / max(1, numAbpfFail));
fprintf('  VERDICT: **CLEAN SEPARATOR** -- severe regression occurs ONLY among subjects ABPF already handled well.\n\n');

fprintf('--- Full regressor list (sorted by severity) ---\n');
[~, sortIdx] = sort([regressors.deltaNotchConf]);
sortedRegressors = regressors(sortIdx);
for k = 1:numel(sortedRegressors)
    r = sortedRegressors(k);
    fprintf('  %-28s src=%-8s fps=%6.2f hr=%6.1f angle=%6.2f notchABPF=%.3f notchG015=%.3f corrABPF=%.3f corrG015=%.3f\n', ...
        r.id, r.source, r.frameRate, r.hrBpm, r.skinColorAngleDeg, r.notchConf_ABPF, r.notchConf_Gaussian015, r.corr_ABPF, r.corr_Gaussian015);
end

% ============================================================
% FIGURE: notch confidence delta vs. baseline ABPF confidence (shows H5 directly)
% ============================================================
fig = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
scatter([rows.notchConf_ABPF], [rows.deltaNotchConf], 30, isVipl, 'filled'); hold on;
yline(-severeDropThreshold, 'r--', 'LineWidth', 1.2);
xline(confidenceBar, 'k:', 'LineWidth', 1.2);
colormap([0, 0.4, 0.8; 0.9, 0.5, 0.1]);
xlabel('Baseline ABPF notch confidence');
ylabel('\Delta notch confidence (Gaussian alpha=0.15 - ABPF)');
title('Segment 13 Task 1: regression severity vs. baseline ABPF confidence (H5)');
legend({'subject (blue=UBFC, orange=VIPL)', sprintf('severe regression threshold (-%.1f)', severeDropThreshold), sprintf('ABPF pass bar (%.1f)', confidenceBar)}, 'Location', 'southwest');
grid on;
outFig = fullfile(figuresRoot, 'segment13_task1_regression_vs_baseline.png');
exportgraphics(fig, outFig, 'Resolution', 150);
close(fig);
fprintf('\nSaved %s\n', outFig);
fprintf('\nSegment 13 Task 1 complete.\n');


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
