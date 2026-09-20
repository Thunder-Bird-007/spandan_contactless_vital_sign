% S26_RUN Segment 26 ONE-SHOT compute (PREREGISTRATION_addendum.md, commit 1bb7d0c). No video decode: cached traces only.
% Per clip x combiner: baseline fftHeartRate, median read-out lgiPaperReadout(.., [0.7 4.0]), mean variant lgiPaperReadoutMean(.., [0.7 4.0]),
% plus the cached quality proxies (fs, dropped-frame fraction, mean raw ROI green). Parity-gated against stored Segment 24/25 results.
here = fileparts(mfilename('fullpath')); root = fileparts(fileparts(fileparts(fileparts(here))));
addpath(genpath(fullfile(root, 'matlab', 'src'))); addpath(fullfile(here, '..', 'src'));
addpath(fullfile(root, 'matlab', 'experiments', 'segment23_fairness_audit', 'common'));
proc = fullfile(root, 'data', 'processed'); resDir = fullfile(here, '..', 'results'); BAND = [0.7 4.0];
e24 = fullfile(root, 'matlab', 'experiments', 'segment24_readout_heldout_validation', 'results');
e25 = fullfile(root, 'matlab', 'experiments', 'segment25_readout_replication', 'results');
% ---- clip list + stored values for the parity gate ----
h25 = readtable(fullfile(e25, 's25_hr_per_video.csv'), 'TextType', 'string'); m25 = readtable(fullfile(e25, 's25_set_manifest.csv'), 'TextType', 'string');
h24 = readtable(fullfile(e24, 's24_hr_per_video.csv'), 'TextType', 'string'); m24 = readtable(fullfile(e24, 's24_set_manifest.csv'), 'TextType', 'string');
h24 = h24(h24.set == "PRIMARY" | h24.set == "SECONDARY_D2", :);
C = table(); % id, set5, stratum, file, fromPool
for i = 1:height(m25), C = [C; table(m25.id(i), "S25_" + extractBefore(m25.set(i), '_'), m25.stratum(i), m25.file(i), m25.fromPool(i), 'VariableNames', {'id','set5','stratum','file','fromPool'})]; end %#ok<AGROW>
u24 = unique(h24.id, 'stable');
for i = 1:numel(u24)
    k = find(m24.id == u24(i), 1); C = [C; table(u24(i), "S24_" + m24.set(k), m24.stratum(k), m24.traceFile(k), "", 'VariableNames', C.Properties.VariableNames)]; end %#ok<AGROW>
fprintf('%d clips\n', height(C));
rows = {}; maxPar = 0; fails = strings(0, 1);
for i = 1:height(C)
    id = char(C.id(i));
    try
        if C.set5(i) == "S25_A"
            [R, G, B, fs] = s23_loadRGB(C.id(i), C.fromPool(i)); f = fullfile(proc, id + "_rgb_traces.mat");
        else
            f = char(C.file(i)); d = load(f, 'R', 'G', 'B', 'fs'); R = d.R(:)'; G = d.G(:)'; B = d.B(:)'; fs = d.fs;
        end
        nd = NaN; if isfile(f) && any(strcmp(who('-file', f), 'numDroppedFrames')), q = load(f, 'numDroppedFrames'); nd = q.numDroppedFrames / numel(R); end
        c = s23_chain(R, G, B, fs, true);
        for comb = ["CHROM", "POS"]
            if comb == "CHROM", p = c.chrom; else, p = c.pos; end
            a = fftHeartRate(p, fs); md = lgiPaperReadout(p, fs, BAND); mn = lgiPaperReadoutMean(p, fs, BAND);
            % parity vs stored
            if startsWith(C.set5(i), "S25")
                s = h25(h25.id == C.id(i) & h25.combiner == comb, :); gt = s.gt(1); st = [s.HR_a(1) s.HR_c(1)];
            else
                s = h24(h24.id == C.id(i) & h24.combiner == comb, :); gt = s.gt(1); st = [s.HR_a(1) s.HR_cW(1)];
            end
            maxPar = max(maxPar, max(abs([a md] - st)));
            rows(end+1, :) = {C.id(i), C.set5(i), C.stratum(i), comb, gt, fs, nd, mean(G), a, md, mn}; %#ok<AGROW>
        end
    catch err, fails(end+1) = string(id) + ": " + err.message; fprintf('%s FAILED: %s\n', id, err.message); end %#ok<AGROW>
end
fprintf('PARITY max |diff| vs stored Segment 24/25 = %.3g bpm\n', maxPar); assert(maxPar < 1e-4, 'parity gate failed');
H = cell2table(rows, 'VariableNames', {'id','set5','stratum','combiner','gt','fs','dropFrac','meanG','HR_a','HR_med','HR_mean'});
writetable(H, fullfile(resDir, 's26_per_clip.csv')); writelines(["failures: " + numel(fails); fails], fullfile(resDir, 's26_failures.txt'));
fprintf('DONE: %d rows, %d failures\n', height(H), numel(fails));
