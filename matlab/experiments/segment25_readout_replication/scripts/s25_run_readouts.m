% S25_RUN_READOUTS Segment 25 ONE-SHOT run (PREREGISTRATION.md, commit aef3beb). Candidate = lgiPaperReadout(p, fs, [0.7 4.0]);
% baseline = production fftHeartRate. Sets: A MAIN_112 | B VIPL v3+v5 source1 | C VIPL v1 source3. Combiners CHROM, POS.
here = fileparts(mfilename('fullpath')); root = fileparts(fileparts(fileparts(fileparts(here))));
addpath(genpath(fullfile(root, 'matlab', 'src'))); addpath(fullfile(here, '..', 'src'));
addpath(fullfile(root, 'matlab', 'experiments', 'segment23_fairness_audit', 'common'));
proc = fullfile(root, 'data', 'processed'); mr = fullfile(root, 'results', 'metrics'); resDir = fullfile(here, '..', 'results');
BAND = [0.7 4.0];
% ---- parity gate ----
w8 = readtable(fullfile(mr, 'segment8_task4_wavelet_ablation.csv'), 'TextType', 'string'); maxd = 0;
for id = ["VIPL_p1_v1_source1", "VIPL_p2_v1_source1", "VIPL_p3_v1_source1", "5-gt", "6-gt"]
    d = load(fullfile(proc, id + "_rgb_traces.mat"), 'R', 'G', 'B', 'fs'); c = s23_chain(d.R(:)', d.G(:)', d.B(:)', d.fs, true);
    r = w8(w8.subjectID == id, :); maxd = max([maxd, abs(fftHeartRate(c.chrom, d.fs) - r.HR_chrom_wavelet), abs(fftHeartRate(c.pos, d.fs) - r.HR_pos_wavelet)]);
end
fprintf('PARITY max |diff| = %.6f bpm\n', maxd); assert(maxd < 1e-3, 'parity failed');
% ---- manifest ----
T = s23_pool(false);
M = table(string(T.subjectID), repmat("A_MAIN112", height(T), 1), string(T.pool), string(T.subjectID), T.gt, strings(height(T), 1), string(T.pool), ...
    'VariableNames', {'id','set','stratum','person','gt','file','fromPool'});
nv = readtable(fullfile(resDir, 's25_new_vipl_manifest.csv'), 'TextType', 'string');
for i = 1:height(nv)
    if nv.source(i) == 1 && (nv.scenario(i) == 3 || nv.scenario(i) == 5), st = "B_v" + nv.scenario(i); set = "B_SCENARIO";
    elseif nv.source(i) == 3 && nv.scenario(i) == 1, st = "C_v1_source3"; set = "C_DEVICE"; else, continue, end
    M = [M; table(nv.subjectID(i), set, st, "p" + nv.subject(i), nv.HR_groundtruth(i), fullfile(proc, nv.subjectID(i) + "_rgb_traces.mat"), "", 'VariableNames', M.Properties.VariableNames)]; %#ok<AGROW>
end
writetable(M, fullfile(resDir, 's25_set_manifest.csv')); disp(groupsummary(M, {'set','stratum'}));
% ---- run ----
rows = {}; fails = strings(0, 1);
for i = 1:height(M)
    try
        if M.set(i) == "A_MAIN112"
            [R, G, B, fs] = s23_loadRGB(M.id(i), M.fromPool(i));
        else
            d = load(char(M.file(i)), 'R', 'G', 'B', 'fs'); R = d.R(:)'; G = d.G(:)'; B = d.B(:)'; fs = d.fs;
        end
        c = s23_chain(R, G, B, fs, true);
        for comb = ["CHROM", "POS"]
            if comb == "CHROM", p = c.chrom; else, p = c.pos; end
            rows(end+1, :) = {M.id(i), M.set(i), M.stratum(i), M.person(i), comb, M.gt(i), fs, fftHeartRate(p, fs), lgiPaperReadout(p, fs, BAND)}; %#ok<AGROW>
        end
    catch err
        fails(end+1) = M.id(i) + ": " + err.message; fprintf('%s FAILED: %s\n', M.id(i), err.message); %#ok<AGROW>
    end
end
H = cell2table(rows, 'VariableNames', {'id','set','stratum','person','combiner','gt','fs','HR_a','HR_c'});
writetable(H, fullfile(resDir, 's25_hr_per_video.csv')); writelines(["failures: " + numel(fails); fails], fullfile(resDir, 's25_failures.txt'));
fprintf('DONE: %d rows, %d failures\n', height(H), numel(fails));
