% RUN_TASK1_CPACE_WINDOWED Segment 23 Task 1. Cached raw R/G/B traces only (light, no video decode).
% Verified BEFORE running: production cpaceProjection.m estimates q_hat ONCE over the whole clip
% (meanVec = [mean(R);mean(G);mean(B)]), so Segment 11/15's cPACE used a single global q_hat.
% Arms (CHROM/POS where applicable), on two chains (wavelet OFF = Seg 11/15's own chain, used for the
% regression check; wavelet ON = current production default):
%   production | Stage1 global q (Seg 11) | Stage1 WINDOWED q | Full global bw0.30 | Full WINDOWED bw0.30 | Full WINDOWED bw0.15
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath')); addpath(fullfile(here, '..', 'src'));
outDir = fullfile(here, '..', 'results');
T = s23_pool(true); N = height(T);
chainDefs = {'noWavelet', false; 'wavelet', true};
allRows = {};
mk = T.pool ~= "VIPL_v2_motion";
for ci = 1:2
    HRc = nan(N, 3); HRp = nan(N, 3); HRf = nan(N, 3);
    for i = 1:N
        try
            [R0,G0,B0,fs] = s23_loadRGB(T.subjectID(i), T.pool(i));
            if chainDefs{ci,2}, R=waveletDenoise(R0); G=waveletDenoise(G0); B=waveletDenoise(B0); else, R=R0; G=G0; B=B0; end
            [Rd,~]=detrendSignal(R); [Gd,~]=detrendSignal(G); [Bd,~]=detrendSignal(B);
            [Rf,~]=bandpassClean(Rd,fs); [Gf,~]=bandpassClean(Gd,fs); [Bf,~]=bandpassClean(Bd,fs);
            HRc(i,1) = fftHeartRate(bandpassClean(chromCombine(Rf,Gf,Bf,R,G,B),fs),fs);
            HRp(i,1) = fftHeartRate(bandpassClean(posCombine(Rf,Gf,Bf,fs,R,G,B),fs),fs);
            for v = 1:2
                if v == 1, [Rc,Gc,Bc] = cpaceProjection(R,G,B); else, [Rc,Gc,Bc] = cpaceProjectionWindowed(R,G,B,fs,10,5); end
                [a,~]=detrendSignal(Rc); [b,~]=detrendSignal(Gc); [c,~]=detrendSignal(Bc);
                [a,~]=bandpassClean(a,fs); [b,~]=bandpassClean(b,fs); [c,~]=bandpassClean(c,fs);
                HRc(i,1+v) = fftHeartRate(bandpassClean(chromCombine(a,b,c,R,G,B),fs),fs);
                HRp(i,1+v) = fftHeartRate(bandpassClean(posCombine(a,b,c,fs,R,G,B),fs),fs);
            end
            [Rg,Gg,Bg] = cpaceProjection(R,G,B);
            [Rw1,Gw1,Bw1] = cpaceProjectionWindowed(R,G,B,fs,10,5);
            HRf(i,1) = fftHeartRate(cpaceHomodyneNormalize(cpaceEigenExtract(Rg,Gg,Bg,fs,0.30),fs),fs);
            HRf(i,2) = fftHeartRate(cpaceHomodyneNormalize(cpaceEigenExtract(Rw1,Gw1,Bw1,fs,0.30),fs),fs);
            HRf(i,3) = fftHeartRate(cpaceHomodyneNormalize(cpaceEigenExtract(Rw1,Gw1,Bw1,fs,0.15),fs),fs);
        catch err
            fprintf('%s FAILED (%s): %s\n', T.subjectID(i), chainDefs{ci,1}, err.message);
        end
    end
    per = [T, array2table([HRc HRp HRf], 'VariableNames', {'chrom_prod','chrom_S1global','chrom_S1win','pos_prod','pos_S1global','pos_S1win','full_global030','full_win030','full_win015'})];
    writetable(per, fullfile(outDir, sprintf('task1_per_subject_%s.csv', chainDefs{ci,1})));
    lst = {'CHROM production',HRc(:,1); 'CHROM S1 global q',HRc(:,2); 'CHROM S1 windowed q',HRc(:,3); 'POS production',HRp(:,1); 'POS S1 global q',HRp(:,2); 'POS S1 windowed q',HRp(:,3); 'cPACE Full global q bw0.30',HRf(:,1); 'cPACE Full windowed q bw0.30',HRf(:,2); 'cPACE Full windowed q bw0.15',HRf(:,3)};
    for m = 1:size(lst,1)
        t = s23_poolTable(lst{m,2}, T, lst{m,1}); t.chain = repmat(string(chainDefs{ci,1}), height(t), 1); allRows{end+1} = t; %#ok<AGROW>
    end
    for nm = {'CHROM','POS'}
        if strcmp(nm{1},'CHROM'), M=HRc; else, M=HRp; end
        for ref = 1:2
            d = abs(M(mk,3)-T.gt(mk)) - abs(M(mk,ref)-T.gt(mk)); d = d(isfinite(d));
            fprintf('[%s] %s S1windowed vs arm%d(1=prod,2=S1global) MAIN_112: worse>1 %d better>1 %d severe-worse %d signrank p=%.4f\n', chainDefs{ci,1}, nm{1}, ref, nnz(d>1), nnz(d<-1), nnz(d>10), signrank(d));
        end
    end
    for ref = 1:2
        d = abs(HRf(mk,2)-T.gt(mk)) - abs(HRf(mk,1)-T.gt(mk)); d = d(isfinite(d));
    end
    d = abs(HRf(mk,2)-T.gt(mk)) - abs(HRf(mk,1)-T.gt(mk)); d = d(isfinite(d));
    fprintf('[%s] Full windowed030 vs Full global030 MAIN_112: worse>1 %d better>1 %d severe-worse %d p=%.4f\n', chainDefs{ci,1}, nnz(d>1), nnz(d<-1), nnz(d>10), signrank(d));
    d = abs(HRf(mk,2)-T.gt(mk)) - abs(HRc(mk,1)-T.gt(mk)); d = d(isfinite(d));
    fprintf('[%s] Full windowed030 vs CHROM production MAIN_112: worse>1 %d better>1 %d severe-worse %d p=%.4f\n', chainDefs{ci,1}, nnz(d>1), nnz(d<-1), nnz(d>10), signrank(d));
end
S = vertcat(allRows{:}); writetable(S, fullfile(outDir, 'task1_summary_by_pool.csv'));
s15 = readtable(fullfile(s23_root(),'results','metrics','segment15_cpace_full_per_subject_hr.csv'),'TextType','string');
per = readtable(fullfile(outDir,'task1_per_subject_noWavelet.csv'),'TextType','string');
chk = {'cPACE-Full-bw0.30','full_global030'; 'CHROM','chrom_prod'; 'POS','pos_prod'; 'cPACE-Stage1+CHROM','chrom_S1global'};
for q = 1:size(chk,1)
    r = s15(s15.pipeline==chk{q,1},:); [tf,loc] = ismember(r.id, per.subjectID);
    fprintf('REGRESSION CHECK vs Segment 15 [%s]: n=%d max|diff|=%.4f bpm\n', chk{q,1}, nnz(tf), max(abs(r.predictedHR(tf) - per.(chk{q,2})(loc(tf))), [], 'omitnan'));
end
disp(S(S.pool=="MAIN_112" | S.pool=="VIPL_v2_motion",:));
