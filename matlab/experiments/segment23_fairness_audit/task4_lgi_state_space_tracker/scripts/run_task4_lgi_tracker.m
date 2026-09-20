% RUN_TASK4_LGI_TRACKER Segment 23 Task 4. VERIFIED FIRST: Segment 22 did NOT cache the LGI pulse signal,
% but lgiProjection.m operates on the cached raw ROI-mean R/G/B (verified: seg22cov_*.mat / *_rgb_traces.mat
% hold R,G,B,fs), so the projection is regenerated in milliseconds -- NO video decode -> LIGHT.
% Read-outs on the LGI pulse: (a) whole-clip fftHeartRate (Seg 22's, regression-checked),
% (b) LGI paper's OWN benchmark read-out (256-sample/90% FFT peak-pick, 0.5-2 Hz), (c) state-space tracker.
% Same read-outs applied to production CHROM/POS so any tracker effect is not credited to LGI alone.
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src'));
outDir = fullfile(here, '..', 'results');
T = s23_pool(true); N = height(T);
cols = {'LGI_fft','LGI_paperReadout','LGI_tracker','CHROM_fft','CHROM_paperReadout','CHROM_tracker','POS_fft','POS_paperReadout','POS_tracker'};
HR = nan(N, numel(cols));
for i = 1:N
    try
        [R0,G0,B0,fs] = s23_loadRGB(T.subjectID(i), T.pool(i));
        Rw=waveletDenoise(R0); Gw=waveletDenoise(G0); Bw=waveletDenoise(B0);
        [Ld,~] = detrendSignal(lgiProjection(Rw,Gw,Bw));
        lgiSig = bandpassClean(Ld, fs);                       % Seg 22's exact LGI chain
        ch = s23_chain(R0,G0,B0,fs,true);
        sigs = {lgiSig, ch.chrom, ch.pos};
        for k = 1:3
            HR(i, (k-1)*3+1) = fftHeartRate(sigs{k}, fs);
            HR(i, (k-1)*3+2) = lgiPaperReadout(sigs{k}, fs);
            HR(i, (k-1)*3+3) = lgiStateSpaceTracker(sigs{k}, fs);
        end
    catch err
        fprintf('%s FAILED: %s\n', T.subjectID(i), err.message);
    end
    if mod(i,20)==0, fprintf('%d/%d\n', i, N); end
end
per = [T, array2table(HR, 'VariableNames', cols)]; writetable(per, fullfile(outDir, 'task4_per_subject.csv'));
rows = {}; for k = 1:numel(cols), rows{end+1} = s23_poolTable(HR(:,k), T, cols{k}); end %#ok<AGROW>
S = vertcat(rows{:}); writetable(S, fullfile(outDir, 'task4_summary_by_pool.csv'));
% regression check vs Segment 22 (LGI whole-clip fft and production CHROM/POS)
s22 = readtable(fullfile(root,'results','metrics','segment22_per_subject.csv'),'TextType','string');
[tf,loc] = ismember(s22.subjectID, T.subjectID);
fprintf('REGRESSION vs Seg22: LGI_fft max|diff|=%.4f, CHROM max|diff|=%.4f, POS max|diff|=%.4f bpm (n=%d)\n', ...
    max(abs(s22.HR_lgi(tf) - HR(loc(tf),1))), max(abs(s22.HR_chrom(tf) - HR(loc(tf),4))), max(abs(s22.HR_pos(tf) - HR(loc(tf),7))), nnz(tf));
mk = T.pool ~= "VIPL_v2_motion";
for pr = {[3 1],'LGI tracker vs LGI fft'; [3 4],'LGI tracker vs CHROM fft'; [3 7],'LGI tracker vs POS fft'; [2 1],'LGI paperReadout vs LGI fft'; [2 4],'LGI paperReadout vs CHROM fft'}'
    for scope = {'MAIN_112', mk; 'V2', T.pool=="VIPL_v2_motion"}'
        d = abs(HR(scope{2}, pr{1}(1)) - T.gt(scope{2})) - abs(HR(scope{2}, pr{1}(2)) - T.gt(scope{2})); d = d(isfinite(d));
        fprintf('%s [%s]: better>1 %d worse>1 %d severe-worse %d signrank p=%.4f\n', pr{2}, scope{1}, nnz(d<-1), nnz(d>1), nnz(d>10), signrank(d));
    end
end
disp(S(S.pool=="MAIN_112" | S.pool=="VIPL_v2_motion",:));
