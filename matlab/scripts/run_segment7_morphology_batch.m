% RUN_SEGMENT7_MORPHOLOGY_BATCH Segment 7 Task A, Action 6. Runs the new
% morphology pipeline (morphology/extractMorphologyWaveform.m and its
% component functions) on real UBFC-rPPG DATASET_1 subjects, produces the
% ablation and result figures, and writes a per-subject metrics table.
%
% Only the 5 DATASET_1 subjects with locally-extracted video are used
% (see docs/DATA_FORMAT.md / the data/raw/UBFC-rPPG/DATASET_1 junctions):
% 5-gt, 6-gt, 7-gt, 12-gt, after-exercise. This matches every other
% batch script in this project's Segment 2-6 history that runs against
% real video rather than a cached CSV.
%
% One subject ('5-gt', fixed for reproducibility -- see FIG_SUBJECT_ID
% below) gets the full 4-condition band/polarity ablation (FIG 1-5); the
% remaining subjects only run the single default condition ('wide' band
% + polarity fix) needed for the metrics table.
%
% Outputs (results/figures/):
%   segment7_fig1_bandmode_ablation_<subject>.png  - legacy vs mid vs
%     wide vs wide+polarity-fixed ensemble prototypes, one axis.
%   segment7_fig2_ensemble_iqr_<subject>.png        - prototype with IQR
%     band shaded, notch region annotated.
%   segment7_fig3_polarity_before_after_<subject>.png - before/after
%     polarity fix, same subject.
%   segment7_fig4_prototype_vs_groundtruth_<subject>.png - our prototype
%     vs UBFC ground-truth contact-PPG's own ensemble prototype, both
%     amplitude (z-score) normalized.
%   segment7_fig5_beatcount_vs_snr_<subject>.png    - empirical vs
%     theoretical sqrt(N) coherent-averaging gain curve.
%
% Outputs (results/metrics/):
%   segment7_morphology_metrics.csv - one row per subject: waveform
%     Pearson r vs ground truth, SNR gain (dB), beats found/rejected/
%     averaged, polarity flipped (heuristic), skewness value, polarity
%     flipped (ground-truth-anchored), and whether the two rules agree.
%
% See docs/Segment7_Task_A_Morphology_Pipeline.md for the numbers this
% produced and the honest reading of them.

subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
FIG_SUBJECT_ID = '5-gt';

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end
if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment7_morphology_metrics.csv');
headerLine = "subjectID,waveformPearsonR_vs_GT,snrGainDb,beatsFound,beatsRejectedByDuration,beatsRejectedByQuality,beatsAveraged,heuristicWasFlipped,heuristicSkewValue,gtAnchoredWasFlipped,heuristicAgreesWithGT";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};
agreementCount = 0;
agreementTotal = 0;

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 7 morphology batch: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('run_segment7_morphology_batch:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('run_segment7_morphology_batch:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        isFigSubject = strcmp(subjectID, FIG_SUBJECT_ID);

        if isFigSubject
            % --- Decode once, reuse R/G/B/detrended across all 4 FIG 1
            % conditions plus this subject's main metrics-table result.
            [frames, frameRate, ~] = loadUBFCVideo(videoPath);
            [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate);

            [R_detrended, ~] = detrendSignal(R);
            [G_detrended, ~] = detrendSignal(G);
            [B_detrended, ~] = detrendSignal(B);

            bandConditions = {'legacy', 'mid', 'wide'};
            conditionPrototypes = struct();
            conditionLabels = {'legacy (0.7-4 Hz)', 'mid (0.6-6 Hz)', 'wide (0.5-8 Hz)', 'wide+polarity-fixed'};

            wideResult = struct();

            for condIdx = 1:numel(bandConditions)
                bandMode = bandConditions{condIdx};

                [R_f, ~, ~] = bandpassMorphology(R_detrended, frameRate, bandMode);
                [G_f, ~, ~] = bandpassMorphology(G_detrended, frameRate, bandMode);
                [B_f, ~, ~] = bandpassMorphology(B_detrended, frameRate, bandMode);

                pulse = chromCombine(R_f, G_f, B_f, R, G, B);
                [sigU, ~, fsU] = resampleUniform(pulse, roiTimestamps);
                [proto, iqrB, beatMat, beatStats] = ensembleAverageBeats(sigU, fsU);

                conditionPrototypes.(bandMode) = proto.trimmedMean;

                if strcmp(bandMode, 'wide')
                    wideResult.pulseNoFix = pulse;
                    wideResult.sigUniformNoFix = sigU;
                    wideResult.fsU = fsU;
                    wideResult.protoNoFix = proto;
                    wideResult.iqrBandNoFix = iqrB;
                    wideResult.beatMatrixNoFix = beatMat;
                    wideResult.beatStatsNoFix = beatStats;
                end
            end

            % --- 4th FIG 1 condition: wide + polarity fix. This is ALSO
            % this subject's main result for the metrics table below.
            [pulseFixed, heuristicWasFlipped, heuristicSkewValue] = fixPolarity(wideResult.pulseNoFix, frameRate);
            [sigUniformFixed, timeUniformFixed, uniformFs] = resampleUniform(pulseFixed, roiTimestamps);
            [prototype, iqrBand, beatMatrix, beatStats] = ensembleAverageBeats(sigUniformFixed, uniformFs);

            conditionPrototypes.wideFixed = prototype.trimmedMean;

            % === FIG 1: 4-condition band/polarity ablation ===
            cycleFrac = linspace(0, 1, numel(conditionPrototypes.legacy));
            figHandle = figure('Visible', 'off');
            hold on;
            plot(cycleFrac, conditionPrototypes.legacy, 'LineWidth', 1.2);
            plot(cycleFrac, conditionPrototypes.mid, 'LineWidth', 1.2);
            plot(cycleFrac, conditionPrototypes.wide, 'LineWidth', 1.2);
            plot(cycleFrac, conditionPrototypes.wideFixed, 'LineWidth', 1.8);
            hold off;
            legend(conditionLabels, 'Location', 'best');
            xlabel('Cycle fraction (systolic peak anchored at 0.25)');
            ylabel('Pulse amplitude (a.u.)');
            title(['Subject ' subjectID ' -- Segment 7 FIG 1: bandwidth/polarity ablation']);
            fig1Path = fullfile(figuresRoot, ['segment7_fig1_bandmode_ablation_' subjectID '.png']);
            exportgraphics(figHandle, fig1Path);
            close(figHandle);
            disp(['Saved ' fig1Path]);

            % === FIG 3: before/after polarity fix, same subject ===
            beforeFixProto = wideResult.protoNoFix.trimmedMean;
            afterFixProto = prototype.trimmedMean;

            figHandle = figure('Visible', 'off');
            subplot(2, 1, 1);
            plot(cycleFrac, beforeFixProto, 'LineWidth', 1.5, 'Color', [0.6 0.2 0.2]);
            title(['Before polarity fix (skewness = ' num2str(heuristicSkewValue, '%.3f') ')']);
            xlabel('Cycle fraction'); ylabel('Amplitude (a.u.)');

            subplot(2, 1, 2);
            plot(cycleFrac, afterFixProto, 'LineWidth', 1.5, 'Color', [0.2 0.4 0.6]);
            titleAfter = 'After polarity fix';
            if heuristicWasFlipped
                titleAfter = [titleAfter ' (FLIPPED)'];
            else
                titleAfter = [titleAfter ' (not flipped)'];
            end
            title(titleAfter);
            xlabel('Cycle fraction'); ylabel('Amplitude (a.u.)');

            sgtitle(['Subject ' subjectID ' -- Segment 7 FIG 3: polarity fix before/after']);
            fig3Path = fullfile(figuresRoot, ['segment7_fig3_polarity_before_after_' subjectID '.png']);
            exportgraphics(figHandle, fig3Path);
            close(figHandle);
            disp(['Saved ' fig3Path]);

            % === FIG 2: ensemble prototype with IQR band shaded ===
            figHandle = figure('Visible', 'off');
            hold on;
            fillX = [cycleFrac, fliplr(cycleFrac)];
            fillY = [iqrBand.q3, fliplr(iqrBand.q1)];
            fill(fillX, fillY, [0.7 0.85 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
            plot(cycleFrac, prototype.trimmedMean, 'LineWidth', 2, 'Color', [0.1 0.2 0.6]);
            xregion(0.30, 0.45); % approximate dicrotic-notch region just after the 0.25-anchored systolic peak
            hold off;
            legend({'IQR band (Q1-Q3)', 'Trimmed-mean prototype', 'Notch region (annotated)'}, 'Location', 'best');
            xlabel('Cycle fraction (systolic peak anchored at 0.25)');
            ylabel('Pulse amplitude (a.u.)');
            title(['Subject ' subjectID ' -- Segment 7 FIG 2: ensemble prototype + beat-to-beat IQR (mean width = ' num2str(iqrBand.meanWidthNormalized, '%.4f') ' normalized)']);
            fig2Path = fullfile(figuresRoot, ['segment7_fig2_ensemble_iqr_' subjectID '.png']);
            exportgraphics(figHandle, fig2Path);
            close(figHandle);
            disp(['Saved ' fig2Path]);

            % === Ground-truth ensemble prototype (for FIG 4 + metrics) ===
            [gtPrototype, ~, ~, ~] = buildGroundTruthPrototype(gt, uniformFs);

            % === FIG 4: our prototype vs GT prototype, both amplitude
            % (z-score) normalized ===
            ourNorm = zscoreNormalize(prototype.trimmedMean);
            gtNorm = zscoreNormalize(gtPrototype.trimmedMean);

            figHandle = figure('Visible', 'off');
            plot(cycleFrac, ourNorm, 'LineWidth', 1.8);
            hold on;
            plot(cycleFrac, gtNorm, 'LineWidth', 1.8, 'LineStyle', '--');
            hold off;
            legend({'Our prototype (rPPG, CHROM+wide+polarity-fixed)', 'UBFC ground-truth contact PPG (own ensemble)'}, 'Location', 'best');
            xlabel('Cycle fraction (systolic peak anchored at 0.25)');
            ylabel('Amplitude (z-score normalized)');
            title(['Subject ' subjectID ' -- Segment 7 FIG 4: prototype vs ground truth']);
            fig4Path = fullfile(figuresRoot, ['segment7_fig4_prototype_vs_groundtruth_' subjectID '.png']);
            exportgraphics(figHandle, fig4Path);
            close(figHandle);
            disp(['Saved ' fig4Path]);

            % === FIG 5: beat-count vs SNR curve (empirical vs sqrt(N)) ===
            [empiricalGain, theoreticalGain, kAxis] = beatCountSnrCurve(beatMatrix, prototype.trimmedMean);

            figHandle = figure('Visible', 'off');
            plot(kAxis, empiricalGain, 'o-', 'LineWidth', 1.5);
            hold on;
            plot(kAxis, theoreticalGain, '--', 'LineWidth', 1.5);
            hold off;
            legend({'Empirical gain (relative to 1 beat)', 'Theoretical sqrt(N)'}, 'Location', 'best');
            xlabel('Number of beats averaged (N)');
            ylabel('SNR gain factor (relative to N=1)');
            title(['Subject ' subjectID ' -- Segment 7 FIG 5: coherent-averaging SNR gain']);
            fig5Path = fullfile(figuresRoot, ['segment7_fig5_beatcount_vs_snr_' subjectID '.png']);
            exportgraphics(figHandle, fig5Path);
            close(figHandle);
            disp(['Saved ' fig5Path]);

            waveformR = computeMetrics(prototype.trimmedMean, gtPrototype.trimmedMean).pearsonR;
            snrGainDb = 10 * log10(beatStats.beatsAveraged);

            [~, gtAnchoredWasFlipped] = fixPolarityByGroundTruth(wideResult.pulseNoFix, roiTimestamps, gt.ppg, gt.timestamp);
            heuristicAgreesWithGT = heuristicWasFlipped == gtAnchoredWasFlipped;

            disp(['Subject ' subjectID ': waveformR=' num2str(waveformR) ', snrGainDb=' num2str(snrGainDb) ', beatsAveraged=' num2str(beatStats.beatsAveraged) ', wasFlipped=' num2str(heuristicWasFlipped) ', gtAnchoredWasFlipped=' num2str(gtAnchoredWasFlipped) ', agree=' num2str(heuristicAgreesWithGT)]);

            rowParts = {subjectID, num2str(waveformR, '%.4f'), num2str(snrGainDb, '%.4f'), num2str(beatStats.beatsFound), num2str(beatStats.beatsRejectedByDuration), num2str(beatStats.beatsRejectedByQuality), num2str(beatStats.beatsAveraged), num2str(heuristicWasFlipped), num2str(heuristicSkewValue, '%.4f'), num2str(gtAnchoredWasFlipped), num2str(heuristicAgreesWithGT)};
            writelines(strjoin(rowParts, ','), csvPath, 'WriteMode', 'append');

            agreementTotal = agreementTotal + 1;
            if heuristicAgreesWithGT
                agreementCount = agreementCount + 1;
            end
        else
            % --- Non-FIG subjects: single default run via the Action 5
            % orchestrator (morphology/extractMorphologyWaveform.m).
            result = extractMorphologyWaveform(videoPath, 'wide');

            [gtPrototype, ~, ~, ~] = buildGroundTruthPrototype(gt, result.uniformFs);

            waveformR = computeMetrics(result.prototype.trimmedMean, gtPrototype.trimmedMean).pearsonR;
            snrGainDb = 10 * log10(result.beatStats.beatsAveraged);

            [~, gtAnchoredWasFlipped] = fixPolarityByGroundTruth(result.pulseChrom, result.roiTimestamps, gt.ppg, gt.timestamp);
            heuristicAgreesWithGT = result.wasFlipped == gtAnchoredWasFlipped;

            disp(['Subject ' subjectID ': waveformR=' num2str(waveformR) ', snrGainDb=' num2str(snrGainDb) ', beatsAveraged=' num2str(result.beatStats.beatsAveraged) ', wasFlipped=' num2str(result.wasFlipped) ', gtAnchoredWasFlipped=' num2str(gtAnchoredWasFlipped) ', agree=' num2str(heuristicAgreesWithGT)]);

            rowParts = {subjectID, num2str(waveformR, '%.4f'), num2str(snrGainDb, '%.4f'), num2str(result.beatStats.beatsFound), num2str(result.beatStats.beatsRejectedByDuration), num2str(result.beatStats.beatsRejectedByQuality), num2str(result.beatStats.beatsAveraged), num2str(result.wasFlipped), num2str(result.skewValue, '%.4f'), num2str(gtAnchoredWasFlipped), num2str(heuristicAgreesWithGT)};
            writelines(strjoin(rowParts, ','), csvPath, 'WriteMode', 'append');

            agreementTotal = agreementTotal + 1;
            if heuristicAgreesWithGT
                agreementCount = agreementCount + 1;
            end
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 7 morphology batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

if agreementTotal > 0
    agreementRate = agreementCount / agreementTotal;
    disp(['Skewness-heuristic vs ground-truth-anchored polarity agreement: ' num2str(agreementCount) '/' num2str(agreementTotal) ' = ' num2str(agreementRate, '%.4f')]);
end

disp(['Saved ' csvPath]);

function normalized = zscoreNormalize(vec)
normalized = (vec - mean(vec)) / std(vec);
end

function [gtPrototype, gtIqrBand, gtBeatMatrix, gtBeatStats] = buildGroundTruthPrototype(gt, targetFs)
% Runs the SAME morphology chain (resample -> detrend -> wide bandpass ->
% polarity fix -> ensemble average) on the UBFC ground-truth contact-PPG
% trace, so "our prototype vs ground truth" (FIG 4, waveformPearsonR) is
% an apples-to-apples comparison: both sides are single-cycle ensemble
% averages built the same way, not a raw multi-cycle trace compared
% against a single template.
[gtUniform, ~, gtUniformFs] = resampleUniform(gt.ppg, gt.timestamp, targetFs);
[gtDetrended, ~] = detrendSignal(gtUniform);
[gtFiltered, ~, ~] = bandpassMorphology(gtDetrended, gtUniformFs, 'wide');
[gtFixed, ~, ~] = fixPolarity(gtFiltered, gtUniformFs);
[gtPrototype, gtIqrBand, gtBeatMatrix, gtBeatStats] = ensembleAverageBeats(gtFixed, gtUniformFs);
end

function [empiricalGain, theoreticalGain, kAxis] = beatCountSnrCurve(beatMatrix, referenceProto)
% Empirically demonstrates the sqrt(N) coherent-averaging law: for
% N = 1..numBeats, repeatedly averages N randomly-drawn beats and
% measures the RMS deviation from the full-set trimmed-mean reference;
% the gain factor is the N=1 noise level divided by the N=k noise level,
% which theory predicts should track sqrt(k).
numBeats = size(beatMatrix, 1);
numTrials = 30;
kAxis = 1:numBeats;
noiseRms = zeros(1, numBeats);

for k = kAxis
    trialErrors = zeros(1, numTrials);
    for trialIdx = 1:numTrials
        idx = randperm(numBeats, k);
        avgK = mean(beatMatrix(idx, :), 1);
        trialErrors(trialIdx) = sqrt(mean((avgK - referenceProto).^2));
    end
    noiseRms(k) = mean(trialErrors);
end

epsilonFloor = 1e-9;
noiseRms = max(noiseRms, epsilonFloor);

empiricalGain = noiseRms(1) ./ noiseRms;
theoreticalGain = sqrt(kAxis);

end
