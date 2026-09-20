% S24_RUN_READOUTS Segment 24 ONE-SHOT run (see PREREGISTRATION.md; nothing here may be changed after it is committed).
% For every video in every set: cached R/G/B -> production Branch-1 chain (s23_chain, wavelet default, unmodified) ->
% CHROM and POS pulse -> five read-outs: a) fftHeartRate  bW) lgiPaperReadout default [0.5 2.0]  cW) same, [0.7 4.0]
%   bT) lgiStateSpaceTracker default grid 0.7-3.0  cT) same, fHi=4.0.
% Writes results/s24_hr_per_video.csv (all sets) and results/s24_set_manifest.csv (cache paths/GT, for reuse).
here = fileparts(mfilename('fullpath')); root = fileparts(fileparts(fileparts(fileparts(here))));
addpath(genpath(fullfile(root, 'matlab', 'src'))); addpath(fullfile(here, '..', 'src'));
addpath(fullfile(root, 'matlab', 'experiments', 'segment23_fairness_audit', 'common'));
proc = fullfile(root, 'data', 'processed'); mr = fullfile(root, 'results', 'metrics'); resDir = fullfile(here, '..', 'results');
BAND_A = [0.7 4.0];  % fftHeartRate.m lowBandHz/highBandHz (verified by grep in PREREGISTRATION.md)
% ---------------- manifest ----------------
M = table(); add = @(M, id, set, stratum, subj, gt, file) [M; table(string(id), string(set), string(stratum), string(subj), gt, string(file), 'VariableNames', {'id','set','stratum','subject','gt','traceFile'})];
v7 = readtable(fullfile(mr, 'segment4_hr_summary_v7.csv'), 'TextType', 'string');
for i = 1:height(v7)
    id = v7.subjectID(i); src = extractAfter(id, '_v7_');
    st = "V7_source1"; set = "PRIMARY"; if src ~= "source1", st = "V7_source2_phone"; set = "EXPLORATORY_PHONE"; end
    M = add(M, id, set, st, extractBetween(id, 'VIPL_', '_v7'), v7.HR_groundtruth(i), fullfile(proc, id + "_rgb_traces.mat"));
end
nv = readtable(fullfile(resDir, 's24_new_vipl_manifest.csv'), 'TextType', 'string');
for i = 1:height(nv)
    M = add(M, nv.subjectID(i), "PRIMARY", "V" + nv.scenario(i) + "_source1", "p" + nv.subject(i), nv.HR_groundtruth(i), fullfile(proc, nv.subjectID(i) + "_rgb_traces.mat"));
end
T23 = s23_pool(false); mainIds = T23.subjectID(T23.pool == "VIPL_v1");   % MAIN_112's VIPL rows (v1 source1 or, for 12, v1 source2)
ph = readtable(fullfile(mr, 'segment4_hr_summary_vipl_phone_v8v9.csv'), 'TextType', 'string');
for i = 1:height(ph), M = add(M, ph.subjectID(i), "EXPLORATORY_PHONE", upper(ph.scenario(i)) + "_source2_phone", extractBetween(ph.subjectID(i), 'VIPL_', '_v'), ph.HR_groundtruth(i), fullfile(proc, ph.subjectID(i) + "_rgb_traces.mat")); end
p1 = readtable(fullfile(mr, 'segment4_hr_summary_vipl_phone_v1.csv'), 'TextType', 'string');
for i = 1:height(p1)
    if any(mainIds == p1.subjectID(i)), continue, end   % already inside MAIN_112 -> excluded
    M = add(M, p1.subjectID(i), "EXPLORATORY_PHONE", "V1_source2_phone_notinMAIN", extractBetween(p1.subjectID(i), 'VIPL_', '_v'), p1.HR_groundtruth(i), fullfile(proc, p1.subjectID(i) + "_rgb_traces.mat"));
end
d2 = dir(fullfile(root, 'data', 'raw', 'UBFC-rPPG', 'DATASET_2', 'subject*'));
s14 = readtable(fullfile(mr, 'segment14_task1_ubfc_d2_held_out_validation.csv'), 'TextType', 'string'); s14 = s14(s14.kind == "subject", :);
for i = 1:numel(d2)
    sid = string(d2(i).name); g = loadGroundTruth(fullfile(d2(i).folder, d2(i).name, 'ground_truth.txt'), 'dataset2');
    h = g.hr(:); h = h(isfinite(h) & h > 0 & h < 255); gtHR = mean(h);
    valid14 = any(s14.id == sid & isfinite(s14.corr_ABPF));
    M = add(M, "UBFC_D2_" + sid, "SECONDARY_D2", ternary(valid14, "D2_seg14valid33", "D2_seg14excluded9"), sid, gtHR, fullfile(proc, "UBFC_D2_" + sid + "_rgb_traces.mat"));
end
writetable(M, fullfile(resDir, 's24_set_manifest.csv'));
fprintf('manifest: %d videos\n', height(M)); disp(groupsummary(M, {'set','stratum'}));
% ---------------- parity regression check on MAIN_112 (must match Segment 8 / Segment 23 exactly) ----------------
w8 = readtable(fullfile(mr, 'segment8_task4_wavelet_ablation.csv'), 'TextType', 'string'); maxd = 0;
for id = ["VIPL_p1_v1_source1", "VIPL_p2_v1_source1", "VIPL_p3_v1_source1", "5-gt", "6-gt"]
    d = load(fullfile(proc, id + "_rgb_traces.mat"), 'R', 'G', 'B', 'fs'); c = s23_chain(d.R(:)', d.G(:)', d.B(:)', d.fs, true);
    r = w8(w8.subjectID == id, :); maxd = max([maxd, abs(fftHeartRate(c.chrom, d.fs) - r.HR_chrom_wavelet), abs(fftHeartRate(c.pos, d.fs) - r.HR_pos_wavelet)]);
end
fprintf('PARITY max |diff| vs Segment 8 wavelet numbers = %.6f bpm\n', maxd); assert(maxd < 1e-3, 'parity check failed');
% ---------------- run ----------------
N = height(M); rows = {}; fails = strings(0, 1);
for i = 1:N
    id = char(M.id(i));
    try
        d = load(char(M.traceFile(i)), 'R', 'G', 'B', 'fs');
        c = s23_chain(d.R(:)', d.G(:)', d.B(:)', d.fs, true); fs = d.fs;
        for comb = ["CHROM", "POS"]
            if comb == "CHROM", p = c.chrom; else, p = c.pos; end
            e = nan(1, 5);
            e(1) = fftHeartRate(p, fs);
            e(2) = lgiPaperReadout(p, fs);                 % (b) windowed, as tested, 0.5-2.0 Hz
            e(3) = lgiPaperReadout(p, fs, BAND_A);         % (c) windowed, band-matched
            e(4) = lgiStateSpaceTracker(p, fs);            % (b) tracker, as tested, grid 0.7-3.0 Hz
            e(5) = lgiStateSpaceTracker(p, fs, struct('fHi', BAND_A(2)));  % (c) tracker, band-matched (grid 0.7-4.0 Hz)
            rows(end+1, :) = {M.id(i), M.set(i), M.stratum(i), M.subject(i), comb, M.gt(i), fs, e(1), e(2), e(3), e(4), e(5)}; %#ok<AGROW>
        end
    catch err
        fails(end+1) = string(id) + ": " + err.message; fprintf('%s FAILED: %s\n', id, err.message); %#ok<AGROW>
    end
    if mod(i, 25) == 0, fprintf('%d/%d\n', i, N); end
end
H = cell2table(rows, 'VariableNames', {'id','set','stratum','subject','combiner','gt','fs','HR_a','HR_bW','HR_cW','HR_bT','HR_cT'});
writetable(H, fullfile(resDir, 's24_hr_per_video.csv')); writelines(["failures: " + numel(fails); fails], fullfile(resDir, 's24_failures.txt'));
fprintf('DONE: %d rows, %d failures\n', height(H), numel(fails));
function o = ternary(c, a, b), if c, o = a; else, o = b; end, end
