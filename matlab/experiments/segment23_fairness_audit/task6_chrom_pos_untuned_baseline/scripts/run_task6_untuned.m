% RUN_TASK6_UNTUNED Segment 23 Task 6: strip CHROM/POS of accumulated tuning, run the papers' native
% generic forms. SAME fixed forehead-box ROI (cached raw traces), SAME whole-clip fftHeartRate
% read-out for every rung (read-out is not "tuning" here; Task 5 swaps read-outs separately).
% Ladder (each rung removes/replaces one more tuned element; all reported, none hidden):
%  L0 production (wavelet ON, cubic detrend, 0.7-4Hz bandpass pre+post, whole-clip combiner)
%  L1 - wavelet OFF                      (= Segment 6's pre-wavelet chain)
%  L2 - wavelet OFF, detrend OFF         (bandpass pre+post only)
%  L3 - all filtering OFF, whole-clip combiner on raw normalised traces
%  L4 NATIVE: paper's windowed overlap-add forms (POS: Alg.1 exactly; CHROM: 1.6s Hann/50%, own bandpass)
%  L4b CHROM native with iphys literal band 0.7-2.5 Hz (sensitivity)
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src'));
outDir = fullfile(here, '..', 'results');
T = s23_pool(true); N = height(T);
names = {'L0 production','L1 no wavelet','L2 no wavelet+no detrend','L3 no filtering (whole-clip)','L4 native windowed','L4b native CHROM band0.7-2.5','L4c native + post-bandpass 0.7-2.5','L4d native + post-bandpass 40-240bpm','L5 production w/ 0.7-2.5Hz band'};
HRc = nan(N, numel(names)); HRp = nan(N, numel(names));
for i = 1:N
    try
        [R,G,B,fs] = s23_loadRGB(T.subjectID(i), T.pool(i));
        c0 = s23_chain(R,G,B,fs,true);  HRc(i,1) = fftHeartRate(c0.chrom, fs); HRp(i,1) = fftHeartRate(c0.pos, fs);
        c1 = s23_chain(R,G,B,fs,false); HRc(i,2) = fftHeartRate(c1.chrom, fs); HRp(i,2) = fftHeartRate(c1.pos, fs);
        % L2: no wavelet, no detrend, bandpass pre+post
        [Rf,~]=bandpassClean(R,fs); [Gf,~]=bandpassClean(G,fs); [Bf,~]=bandpassClean(B,fs);
        HRc(i,3) = fftHeartRate(bandpassClean(chromCombine(Rf,Gf,Bf,R,G,B),fs), fs);
        HRp(i,3) = fftHeartRate(bandpassClean(posCombine(Rf,Gf,Bf,fs,R,G,B),fs), fs);
        % L3: nothing filtered; combiners on raw traces (mean removed so DC does not leak)
        cc = chromCombine(R,G,B,R,G,B); pp = posCombine(R,G,B,fs,R,G,B);
        HRc(i,4) = fftHeartRate(cc - mean(cc), fs); HRp(i,4) = fftHeartRate(pp - mean(pp), fs);
        % L4 native
        HRp(i,5) = fftHeartRate(posNative(R,G,B,fs), fs);
        HRc(i,5) = fftHeartRate(chromNative(R,G,B,fs), fs);
        HRc(i,6) = fftHeartRate(chromNative(R,G,B,fs,[0.7 2.5]), fs);
        HRp(i,6) = NaN;
        % DIAGNOSTIC ATTRIBUTION (declared, not selection): is the band edge the lever?
        [b25,a25] = butter(3, [0.7 2.5]/(fs/2)); [b240,a240] = butter(3, [40/60 4]/(fs/2));
        pn = posNative(R,G,B,fs);
        HRp(i,7) = fftHeartRate(filtfilt(b25,a25,pn), fs); HRc(i,7) = fftHeartRate(filtfilt(b25,a25,chromNative(R,G,B,fs,[40 240]/60)), fs);
        HRp(i,8) = fftHeartRate(filtfilt(b240,a240,pn), fs); HRc(i,8) = fftHeartRate(chromNative(R,G,B,fs,[40 240]/60), fs);
        [b2,a2] = butter(2, [0.7 2.5]/(fs/2)); Rw=waveletDenoise(R); Gw=waveletDenoise(G); Bw=waveletDenoise(B);
        Rf=filtfilt(b2,a2,detrend(Rw,3)); Gf=filtfilt(b2,a2,detrend(Gw,3)); Bf=filtfilt(b2,a2,detrend(Bw,3));
        HRc(i,9) = fftHeartRate(filtfilt(b2,a2,chromCombine(Rf,Gf,Bf,Rw,Gw,Bw)), fs);
        HRp(i,9) = fftHeartRate(filtfilt(b2,a2,posCombine(Rf,Gf,Bf,fs,Rw,Gw,Bw)), fs);
    catch err
        fprintf('%s FAILED: %s\n', T.subjectID(i), err.message);
    end
end
per = [T, array2table(HRc, 'VariableNames', matlab.lang.makeValidName(strcat('chrom_', names))), array2table(HRp, 'VariableNames', matlab.lang.makeValidName(strcat('pos_', names)))];
writetable(per, fullfile(outDir, 'task6_per_subject.csv'));
rows = {};
for k = 1:numel(names)
    rows{end+1} = s23_poolTable(HRc(:,k), T, ['CHROM ' names{k}]); %#ok<AGROW>
    if k ~= 6, rows{end+1} = s23_poolTable(HRp(:,k), T, ['POS ' names{k}]); end %#ok<AGROW>
end
S = vertcat(rows{:}); writetable(S, fullfile(outDir, 'task6_summary_by_pool.csv'));
% paired per-subject comparison native(L4) vs production(L0) on MAIN_112
mk = T.pool ~= "VIPL_v2_motion";
for comb = {'CHROM', 'POS'}
    if strcmp(comb{1}, 'CHROM'), M = HRc; else, M = HRp; end
    d = abs(M(mk,5) - T.gt(mk)) - abs(M(mk,1) - T.gt(mk));
    fprintf('%s native vs production (MAIN_112): worse>1bpm %d, better>1bpm %d, severe worse>10 %d, signrank p=%.4f\n', comb{1}, nnz(d>1), nnz(d<-1), nnz(d>10), signrank(d(isfinite(d))));
end
disp(S(S.pool=="MAIN_112",:)); disp(S(S.pool=="VIPL_v2_motion",:));
