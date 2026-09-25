% S27_BRANCH2_WAVELET Segment 27 Item A (PREREGISTRATION.md). A copy of
% scripts/run_segment7_task_b_branch2_batch.m with exactly one logic
% change: R/G/B are wavelet-denoised (filtering/waveletDenoise.m, db4,
% 3-level, in place) immediately before the three detrendSignal calls,
% gated by USE_WAVELET_DENOISE below -- the same position/params
% pipeline/estimateVitalsAndMorphology.m uses for Branch 2.
%
% Everything else (subject list, conditions, notch detection, CSV schema)
% is byte-identical to the original script. Two path differences, not
% logic differences: (1) output goes under this experiment folder, never
% under results/metrics/ or the frozen CSV's name; (2) the FIG 1v2 figure
% block is omitted -- Item A's decision rule only needs the CSV, and
% generating figures here would write into results/figures/, outside this
% experiment folder's guardrail.
%
% Parity gate (run this first): with USE_WAVELET_DENOISE = false, this
% script must reproduce results/metrics/segment7_task_b_notch_branch2.csv
% row for row, at the CSV's own num2str precision. Invoke via:
%   matlab -batch "startup; USE_WAVELET_DENOISE=false; run('experiments/segment27_branch2_wavelet_evaluation/scripts/s27_branch2_wavelet.m')"
% Then the real Item A run:
%   matlab -batch "startup; USE_WAVELET_DENOISE=true; run('experiments/segment27_branch2_wavelet_evaluation/scripts/s27_branch2_wavelet.m')"

if ~exist('USE_WAVELET_DENOISE', 'var') || isempty(USE_WAVELET_DENOISE)
    USE_WAVELET_DENOISE = true; %#ok<NASGU>
end

FIG_SUBJECT_ID = '5-gt'; %#ok<NASGU> % kept for parity with the original script's header; no figure is produced here
subjectList = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(fileparts(fileparts(thisFileDir))));
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
outRoot = fullfile(fileparts(thisFileDir), 'results');

if ~isfolder(outRoot)
    mkdir(outRoot);
end

if USE_WAVELET_DENOISE
    csvPath = fullfile(outRoot, 's27_branch2_wavelet.csv');
else
    csvPath = fullfile(outRoot, 's27_branch2_parity_check.csv');
end

headerLine = "subjectID,method,notchDetected,notchPositionNormalized,notchDepth,confidence,effectiveFsHz,hrBpmUsed,beatsAveraged,harmonicMethodUsed,gateSubstituted";
writelines(headerLine, csvPath);

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

adaptiveDetectedCount = 0;
adaptiveConfidentCount = 0;
tiledDetectedCount = 0;
tiledConfidentCount = 0;
gateDetectedCount = 0;
gatePassCount = 0;
gateSubstitutedCount = 0;

confidenceThreshold = 1.0;
confidenceGateBar = 0.3;

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};
    subjectDir = fullfile(dataset1Root, subjectID);

    disp(['--- Segment 27 Item A: subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) '), USE_WAVELET_DENOISE=' num2str(USE_WAVELET_DENOISE) ' ---']);

    try
        aviFiles = dir(fullfile(subjectDir, '*.avi'));
        if isempty(aviFiles)
            error('s27_branch2_wavelet:missingVideo', 'No .avi file found under: %s', subjectDir);
        end
        videoPath = fullfile(subjectDir, aviFiles(1).name);

        gtPath = fullfile(subjectDir, 'gtdump.xmp');
        if ~isfile(gtPath)
            error('s27_branch2_wavelet:missingGT', 'No gtdump.xmp found under: %s', subjectDir);
        end
        gt = loadGroundTruth(gtPath, 'dataset1');

        [frames, frameRate, ~] = loadUBFCVideo(videoPath);
        [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate);

        % === The one logic change from the original script: wavelet
        % denoise R/G/B in place, upstream of everything below, exactly
        % the position/params estimateVitalsAndMorphology.m uses. ===
        if USE_WAVELET_DENOISE
            R = waveletDenoise(R);
            G = waveletDenoise(G);
            B = waveletDenoise(B);
        end

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        [R_wide, ~, ~] = bandpassMorphology(R_detrended, frameRate, 'wide');
        [G_wide, ~, ~] = bandpassMorphology(G_detrended, frameRate, 'wide');
        [B_wide, ~, ~] = bandpassMorphology(B_detrended, frameRate, 'wide');
        pulseWide = chromCombine(R_wide, G_wide, B_wide, R, G, B);
        sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;

        % === Adaptive harmonic filter condition ===
        [R_ahf, ~, ~] = adaptiveHarmonicFilter(R_detrended, frameRate, 6, sharedF0Hz);
        [G_ahf, ~, ~] = adaptiveHarmonicFilter(G_detrended, frameRate, 6, sharedF0Hz);
        [B_ahf, ~, ~] = adaptiveHarmonicFilter(B_detrended, frameRate, 6, sharedF0Hz);
        pulseAdaptive = chromCombine(R_ahf, G_ahf, B_ahf, R, G, B);

        [pulseAdaptiveFixed, ~] = fixPolarityByGroundTruth(pulseAdaptive, roiTimestamps, gt.ppg, gt.timestamp);
        [sigAdaptiveUniform, ~, fsAdaptiveUniform] = resampleUniform(pulseAdaptiveFixed, roiTimestamps);
        [protoAdaptive, ~, ~, statsAdaptive] = ensembleAverageBeats(sigAdaptiveUniform, fsAdaptiveUniform);

        hrAdaptive = fftHeartRate(sigAdaptiveUniform, fsAdaptiveUniform);
        fsProtoAdaptive = numel(protoAdaptive.trimmedMean) * (hrAdaptive / 60);
        [adaptiveDetected, adaptivePos, adaptiveDepth, adaptiveConf] = notchDetectIEM(protoAdaptive.trimmedMean, fsProtoAdaptive);

        disp(['Subject ' subjectID ' adaptive-harmonic: notchDetected=' num2str(adaptiveDetected) ', pos=' num2str(adaptivePos, '%.4f') ', depth=' num2str(adaptiveDepth, '%.4f') ', confidence=' num2str(adaptiveConf, '%.4f')]);

        rowAdaptive = {subjectID, 'adaptiveHarmonic', num2str(adaptiveDetected), num2str(adaptivePos, '%.4f'), num2str(adaptiveDepth, '%.4f'), num2str(adaptiveConf, '%.4f'), num2str(fsProtoAdaptive, '%.4f'), num2str(hrAdaptive, '%.4f'), num2str(statsAdaptive.beatsAveraged), 'adaptiveHarmonic', '0'};
        writelines(strjoin(rowAdaptive, ','), csvPath, 'WriteMode', 'append');

        if adaptiveDetected
            adaptiveDetectedCount = adaptiveDetectedCount + 1;
            if adaptiveConf >= confidenceThreshold
                adaptiveConfidentCount = adaptiveConfidentCount + 1;
            end
        end

        % === Confidence-gate condition (Segment 14 Task 2 logic) ===
        gateHarmonicMethodUsed = 'adaptiveHarmonic';
        gateWasSubstituted = false;
        gateDetected = adaptiveDetected;
        gatePos = adaptivePos;
        gateDepth = adaptiveDepth;
        gateConf = adaptiveConf;
        gateFsProto = fsProtoAdaptive;
        gateHr = hrAdaptive;
        gateBeatsAveraged = statsAdaptive.beatsAveraged;

        if adaptiveConf <= confidenceGateBar
            [R_gau, ~, ~] = harmonicSelectiveGaussianFilter(R_detrended, frameRate, 6, sharedF0Hz, 0.15);
            [G_gau, ~, ~] = harmonicSelectiveGaussianFilter(G_detrended, frameRate, 6, sharedF0Hz, 0.15);
            [B_gau, ~, ~] = harmonicSelectiveGaussianFilter(B_detrended, frameRate, 6, sharedF0Hz, 0.15);
            pulseGaussian = chromCombine(R_gau, G_gau, B_gau, R, G, B);

            [pulseGaussianFixed, ~] = fixPolarityByGroundTruth(pulseGaussian, roiTimestamps, gt.ppg, gt.timestamp);
            [sigGaussianUniform, ~, fsGaussianUniform] = resampleUniform(pulseGaussianFixed, roiTimestamps);
            [protoGaussian, ~, ~, statsGaussian] = ensembleAverageBeats(sigGaussianUniform, fsGaussianUniform);

            hrGaussian = fftHeartRate(sigGaussianUniform, fsGaussianUniform);
            fsProtoGaussian = numel(protoGaussian.trimmedMean) * (hrGaussian / 60);
            [gaussianDetected, gaussianPos, gaussianDepth, gaussianConf] = notchDetectIEM(protoGaussian.trimmedMean, fsProtoGaussian);

            [~, gateHarmonicMethodUsed, ~, gateWasSubstituted] = harmonicFilterConfidenceGate( ...
                pulseAdaptiveFixed, adaptiveConf, 'adaptiveHarmonic', ...
                {pulseGaussianFixed}, gaussianConf, {'gaussian015'}, confidenceGateBar);

            if gateWasSubstituted
                gateDetected = gaussianDetected;
                gatePos = gaussianPos;
                gateDepth = gaussianDepth;
                gateConf = gaussianConf;
                gateFsProto = fsProtoGaussian;
                gateHr = hrGaussian;
                gateBeatsAveraged = statsGaussian.beatsAveraged;
            end
        end

        disp(['Subject ' subjectID ' confidence-gate: notchDetected=' num2str(gateDetected) ', pos=' num2str(gatePos, '%.4f') ', depth=' num2str(gateDepth, '%.4f') ', confidence=' num2str(gateConf, '%.4f') ', methodUsed=' gateHarmonicMethodUsed ', substituted=' num2str(gateWasSubstituted)]);

        rowGate = {subjectID, 'confidenceGate', num2str(gateDetected), num2str(gatePos, '%.4f'), num2str(gateDepth, '%.4f'), num2str(gateConf, '%.4f'), num2str(gateFsProto, '%.4f'), num2str(gateHr, '%.4f'), num2str(gateBeatsAveraged), gateHarmonicMethodUsed, num2str(gateWasSubstituted)};
        writelines(strjoin(rowGate, ','), csvPath, 'WriteMode', 'append');

        if gateDetected
            gateDetectedCount = gateDetectedCount + 1;
        end
        if gateConf > confidenceGateBar
            gatePassCount = gatePassCount + 1;
        end
        if gateWasSubstituted
            gateSubstitutedCount = gateSubstitutedCount + 1;
        end

        % === Tiled ROI condition (own decode -- NOT wavelet-denoised;
        % wavelet placement is ambiguous for per-tile extraction, so this
        % condition is excluded from Item A's decision rule regardless of
        % USE_WAVELET_DENOISE, per PREREGISTRATION.md). ===
        [pulseTiled, roiTimestampsTiled, tileWeights, frameRateTiled] = tiledROIExtraction(videoPath, 'wide'); %#ok<ASGLU>

        [pulseTiledFixed, ~] = fixPolarityByGroundTruth(pulseTiled, roiTimestampsTiled, gt.ppg, gt.timestamp);
        [sigTiledUniform, ~, fsTiledUniform] = resampleUniform(pulseTiledFixed, roiTimestampsTiled);
        [protoTiled, ~, ~, statsTiled] = ensembleAverageBeats(sigTiledUniform, fsTiledUniform);

        hrTiled = fftHeartRate(sigTiledUniform, fsTiledUniform);
        fsProtoTiled = numel(protoTiled.trimmedMean) * (hrTiled / 60);
        [tiledDetected, tiledPos, tiledDepth, tiledConf] = notchDetectIEM(protoTiled.trimmedMean, fsProtoTiled);

        disp(['Subject ' subjectID ' tiled-ROI: notchDetected=' num2str(tiledDetected) ', pos=' num2str(tiledPos, '%.4f') ', depth=' num2str(tiledDepth, '%.4f') ', confidence=' num2str(tiledConf, '%.4f')]);

        rowTiled = {subjectID, 'tiledROI', num2str(tiledDetected), num2str(tiledPos, '%.4f'), num2str(tiledDepth, '%.4f'), num2str(tiledConf, '%.4f'), num2str(fsProtoTiled, '%.4f'), num2str(hrTiled, '%.4f'), num2str(statsTiled.beatsAveraged), 'n/a', '0'};
        writelines(strjoin(rowTiled, ','), csvPath, 'WriteMode', 'append');

        if tiledDetected
            tiledDetectedCount = tiledDetectedCount + 1;
            if tiledConf >= confidenceThreshold
                tiledConfidentCount = tiledConfidentCount + 1;
            end
        end
    catch causeErr
        disp(['Subject ' subjectID ': FAILED -- ' causeErr.message]);
        failedSubjects{end + 1} = subjectID; %#ok<AGROW>
        failedReasons{end + 1} = causeErr.message; %#ok<AGROW>
    end
end

disp('--- Segment 27 Item A batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);
for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end

numSucceeded = numSubjects - numel(failedSubjects);
disp(['Adaptive-harmonic notch detection rate: ' num2str(adaptiveDetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(adaptiveConfidentCount) '/' num2str(numSucceeded) ')']);
disp(['Tiled-ROI notch detection rate:         ' num2str(tiledDetectedCount) '/' num2str(numSucceeded) ' (confident, conf>=' num2str(confidenceThreshold) ': ' num2str(tiledConfidentCount) '/' num2str(numSucceeded) ')']);
disp(['Confidence-gate notch detection rate:   ' num2str(gateDetectedCount) '/' num2str(numSucceeded) ' (pass, conf>' num2str(confidenceGateBar) ': ' num2str(gatePassCount) '/' num2str(numSucceeded) '; substituted ' num2str(gateSubstitutedCount) '/' num2str(numSucceeded) ')']);

disp(['Saved ' csvPath]);
