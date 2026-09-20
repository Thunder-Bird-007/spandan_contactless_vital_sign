% RUN_TASK7_RAKF_NATIVE Segment 23 Task 7. Fixes ONE documented bug (Eq.12 exponent vs division).
% No video, no ROI extraction: cached raw traces -> production chain -> windowedHeartRate -> RAKF.
% ------------------------------------------------------------------------------------------
% PRE-REGISTERED CONSTANTS (declared before any result was seen):
BETA_PRIMARY = 1.0;              % paper gives NO numeric beta ("beta>0 sensitivity parameter";
                                 % sensitivity Fig.7 says <0.3 bpm effect). beta=1 = unit exponent,
                                 % R=R0*(1+|innov|) in bpm units. Exponent-form beta is NOT
                                 % interchangeable with the division-form's data-derived beta=std(z).
BETA_SENSITIVITY = [0.5 1.0 1.5 2.0];   % declared sensitivity ONLY, reported in full, not tuned on
R0_PAPER = 25;                   % bpm^2, paper (fixed across datasets)
Q_PAPER_PER_FRAME = 2e-4;        % paper, per video frame
Q_SCALED = Q_PAPER_PER_FRAME * 150;   % = 0.03, Segment 9 Task 2's derivation (150 frames = 5 s hop @30fps)
% ------------------------------------------------------------------------------------------
addpath(fullfile(fileparts(mfilename('fullpath')),'..','..','common')); root = s23_setup(); here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'src'));
outDir = fullfile(here, '..', 'results');
T = s23_pool(true); N = height(T);
chains = {'prewavelet', false; 'wavelet', true};   % prewavelet = Segment 6/9's historical chain; wavelet = current production
combs = {'chrom', 'pos'};
nb = numel(BETA_SENSITIVITY);
rows = {};
for ci = 1:2
  for ki = 1:2
    H = struct('whole', nan(N,1), 'naive', nan(N,1), 'rakfOrig', nan(N,1), 'rakfDivPaper', nan(N,1), 'rakfNat', nan(N,nb));
    for i = 1:N
        try
            [R,G,B,fs] = s23_loadRGB(T.subjectID(i), T.pool(i));
            ch = s23_chain(R,G,B,fs,chains{ci,2});
            pulse = ch.(combs{ki});
            H.whole(i) = fftHeartRate(pulse, fs);
            [hn, wr] = windowedHeartRate(pulse, fs);
            H.naive(i) = hn;
            z = wr.candidateBpm(:,1); q = wr.qualityScore;
            H.rakfOrig(i) = residualAdaptiveKalmanHR(z, q);                       % PRODUCTION function, defaults (the Seg 6 result)
            H.rakfDivPaper(i) = residualAdaptiveKalmanHR_exp(z, q, struct('form','division','R0',R0_PAPER,'Q',Q_SCALED)); % paper R0/Q, division formula
            for b = 1:nb
                H.rakfNat(i,b) = residualAdaptiveKalmanHR_exp(z, q, struct('form','exponent','R0',R0_PAPER,'Q',Q_SCALED,'beta',BETA_SENSITIVITY(b)));
            end
        catch err
            fprintf('%s FAILED: %s\n', T.subjectID(i), err.message);
        end
    end
    tag = sprintf('%s/%s', chains{ci,1}, combs{ki});
    perSub = table(T.subjectID, T.pool, T.gt, H.whole, H.naive, H.rakfOrig, H.rakfDivPaper, H.rakfNat, ...
        'VariableNames', {'subjectID','pool','gt','whole','naive','rakfOrigDivision','rakfDivisionPaperR0Q','rakfNative_b'});
    writetable(perSub, fullfile(outDir, sprintf('task7_per_subject_%s_%s.csv', chains{ci,1}, combs{ki})));
    meths = {'whole-clip fft', H.whole; 'naive windowed', H.naive; 'RAKF original (division, data-derived)', H.rakfOrig; 'RAKF division + paper R0/Q', H.rakfDivPaper};
    for b = 1:nb
        nm = sprintf('RAKF NATIVE exponent beta=%.1f', BETA_SENSITIVITY(b));
        if BETA_SENSITIVITY(b) == BETA_PRIMARY, nm = [nm ' [PRIMARY]']; end %#ok<AGROW>
        meths(end+1,:) = {nm, H.rakfNat(:,b)}; %#ok<AGROW>
    end
    for m = 1:size(meths,1)
        t = s23_poolTable(meths{m,2}, T, meths{m,1}); t.chain = repmat(string(chains{ci,1}), height(t), 1); t.combiner = repmat(string(combs{ki}), height(t), 1);
        rows{end+1} = t; %#ok<AGROW>
    end
    fprintf('done %s\n', tag);
  end
end
S = vertcat(rows{:});
writetable(S, fullfile(outDir, 'task7_summary_by_pool.csv'));
disp(S(S.pool=="VIPL_v1" & S.chain=="prewavelet" & S.combiner=="chrom", :));
disp(S(S.pool=="MAIN_112" & S.chain=="wavelet", :));
