function [R, G, B, fs] = s23_loadRGB(id, pool)
% S23_LOADRGB cached raw forehead-box ROI-mean traces (no video decode).
% main pool: data/processed/<id>_rgb_traces.mat ; v2 motion: seg22cov_<id>.mat (Segment 22
% verified R/G/B parity vs the production cache).
proc = fullfile(s23_root(), 'data', 'processed');
if string(pool) == "VIPL_v2_motion"
    d = load(fullfile(proc, ['seg22cov_' char(id) '.mat']), 'R', 'G', 'B', 'fs');
else
    d = load(fullfile(proc, [char(id) '_rgb_traces.mat']), 'R', 'G', 'B', 'fs');
end
R = d.R(:)'; G = d.G(:)'; B = d.B(:)'; fs = d.fs;
end
