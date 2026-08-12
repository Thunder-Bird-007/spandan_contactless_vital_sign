% RUN_SEGMENT6_TASK_N_MULTI_REGION_BATCH Batch driver for Segment 6 Task N
% (multi-region ROI investigation). Runs the UNMODIFIED Segment 3
% (detrend/bandpass) + Segment 4 (CHROM, FFT) pipeline separately for each
% of roi/extractROISignals.m's four region modes (forehead, glabella,
% malar, cheek), on a paired 20-subject subset across three VIPL-HR
% scenarios: v1 (stable baseline), v2 (large head motion), and v4 (dark
% -- see the correction note below).
%
% CORRECTION vs this task's own brief: the brief calls the low-light arm
% "v5". VIPL-HR-V1/ReadMe.pdf (the authoritative source, checked directly
% for this task) states v4 is the DARK scenario (ceiling lamp off) and v5
% is the BRIGHT scenario (filament lamp on) -- the exact opposite of what
% the brief assumed. This project's own docs/VIPL_Scenario_Coverage.md
% independently has the same v4/v5 mix-up in its prose (its per-scenario
% coverage table's raw digit counts are unaffected, only the English
% description column is swapped). This script therefore extracts and
% processes v4, not v5, for the "dark/low-light" arm, and
% docs/Segment6_Task_N_Multi_Region_ROI.md flags this loudly rather than
% silently using the wrong scenario. v4/source1 was extracted from the
% VIPL-HR zip archives (targeted per-entry extraction, not a full-archive
% unzip, same discipline as the existing v7 extraction) for the same 20
% subjects as v2, alongside v1 (already locally extracted).
%
% Subject selection: 20 subjects with source1 present in v1, v2, AND v4
% per docs/VIPL_Scenario_Coverage.md's coverage matrix, so the same 20
% subjects are directly comparable across all three scenarios and all
% four regions -- p2, p5 (missing source1 in v2), and p84 (missing
% source1 in v1) were skipped to keep the subset clean; the next 20
% eligible subject IDs after that filter were taken in ID order.
%
% For each (subjectNum, scenarioNum) pair, for each region mode, this
% script:
%   1. Calls io/loadVIPLVideo.m to open the video and get its real fs
%      (re-derived from time.txt, same as the existing v1/v7 scripts).
%   2. Calls roi/extractROISignals.m with that region's roiMode to get
%      R(t), G(t), B(t), and saves
%      data/processed/VIPL_pX_vY_source1_<region>_rgb_traces.mat.
%   3. Runs filtering/detrendSignal.m -> filtering/bandpassClean.m ->
%      pulseextraction/chromCombine.m -> filtering/bandpassClean.m ->
%      heartrate/fftHeartRate.m, completely unmodified from Segment 3/4,
%      to get HR_region.
% After all four regions are done for a subject/scenario, it:
%   4. Saves one sanity PNG (results/figures/VIPL_pX_vY_source1_multi_
%      region_sanity.png) drawing all four regions' boundaries (forehead,
%      glabella, malar-left, malar-right, cheek-left, cheek-right) on one
%      representative frame, using the region boxes captured by
%      extractROISignals.m's debugFrame.regionBBoxes (computed on every
%      frame regardless of which single roiMode that particular call
%      extracted from, so this is available even off the forehead run).
%   5. Loads ground truth via io/loadVIPLGroundTruth.m, strips the
%      documented HR==255 fault code, and takes HR_groundtruth = mean of
%      the remaining values.
%   6. Appends one row per subject/scenario to
%      results/metrics/segment6_task_n_region_hr_summary.csv with all
%      four regions' HR estimates and HR_groundtruth (ground truth is
%      recorded here for later validation -- see Action 5 below -- but is
%      NOT used by any region-selection logic in this script).
%
% After all subjects/scenarios are processed, for EACH scenario
% separately (never pooled across scenarios, since the whole point is to
% compare regions per condition):
%   7. Calls validation/computeRegionAgreement.m and
%      validation/computeRegionSwitchingEstimate.m across that scenario's
%      20 subjects -- ground truth is NOT an input to either call, only
%      the four per-region HR vectors, per this task's design constraint.
%   8. Calls validation/computeMetrics.m five times (forehead alone,
%      glabella alone, malar alone, cheek alone, switching estimate)
%      against HR_groundtruth -- this is Action 5, the ONLY place ground
%      truth is used to judge which region/strategy was actually better.
%   9. Appends rows to
%      results/metrics/segment6_task_n_validation_summary.csv (one row
%      per scenario per region/strategy).
%
% If a subject/scenario fails (missing file, corrupt video, detector
% error), this script logs the error, records that subject as unusable
% for every region in that scenario (so the four-region vectors passed to
% computeRegionAgreement.m/computeRegionSwitchingEstimate.m stay aligned
% one-to-one), and moves on -- same discipline as the existing VIPL batch
% scripts.

subjectList = [1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22];

scenarioList = [1, 2, 4];
scenarioLabels = containers.Map({1, 2, 4}, {'v1_baseline', 'v2_motion', 'v4_dark'});

regionList = {'forehead', 'glabella', 'malar', 'cheek'};

sourceNum = 1;

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(processedDataRoot)
    mkdir(processedDataRoot);
end

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

hrCsvPath = fullfile(metricsRoot, 'segment6_task_n_region_hr_summary.csv');
hrHeaderLine = "subjectID,scenario,HR_forehead,HR_glabella,HR_malar,HR_cheek,HR_groundtruth";
writelines(hrHeaderLine, hrCsvPath);

validationCsvPath = fullfile(metricsRoot, 'segment6_task_n_validation_summary.csv');
validationHeaderLine = "scenario,method,mae,rmse,pearsonR,n";
writelines(validationHeaderLine, validationCsvPath);

numSubjects = numel(subjectList);
numScenarios = numel(scenarioList);

failedCombos = {};
failedReasons = {};

for scenarioPos = 1:numScenarios
    scenarioNum = scenarioList(scenarioPos);
    scenarioLabel = scenarioLabels(scenarioNum);

    disp(['=== Scenario ' scenarioLabel ' (v' num2str(scenarioNum) ') ===']);

    HR_forehead_scenario = nan(numSubjects, 1);
    HR_glabella_scenario = nan(numSubjects, 1);
    HR_malar_scenario = nan(numSubjects, 1);
    HR_cheek_scenario = nan(numSubjects, 1);
    HR_groundtruth_scenario = nan(numSubjects, 1);
    subjectUsable = false(numSubjects, 1);

    for subjectPos = 1:numSubjects
        subjectNum = subjectList(subjectPos);
        subjectID = ['VIPL_p' num2str(subjectNum) '_v' num2str(scenarioNum) '_source' num2str(sourceNum)];

        disp(['--- Processing ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

        try
            [vrCheck, fs, numFrames, videoPath] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum);

            disp([subjectID ': loaded ' videoPath ', fs = ' num2str(fs) ' fps, numFrames = ' num2str(numFrames)]);

            HR_region = struct();
            debugFrameForPng = [];

            for regionIdx = 1:numel(regionList)
                regionName = regionList{regionIdx};

                [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(vrCheck, fs, regionName);

                if regionIdx == 1
                    debugFrameForPng = debugFrame;
                end

                rgbMatOutPath = fullfile(processedDataRoot, [subjectID '_' regionName '_rgb_traces.mat']);
                save(rgbMatOutPath, 'R', 'G', 'B', 'fs', 'subjectID', 'regionName');

                [R_detrended, detrendOrder] = detrendSignal(R);
                [G_detrended, detrendOrder] = detrendSignal(G);
                [B_detrended, detrendOrder] = detrendSignal(B);

                [R_filtered, filterOrder] = bandpassClean(R_detrended, fs);
                [G_filtered, filterOrder] = bandpassClean(G_detrended, fs);
                [B_filtered, filterOrder] = bandpassClean(B_detrended, fs);

                pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
                pulseChromFiltered = bandpassClean(pulseChrom, fs);
                [HR_chrom, freqSpectrumChrom, powerSpectrumChrom] = fftHeartRate(pulseChromFiltered, fs);

                HR_region.(regionName) = HR_chrom;

                disp([subjectID ': region ' regionName ' -- HR_chrom = ' num2str(HR_chrom) ' bpm, dropped frames = ' num2str(numel(droppedFrameIdx))]);
            end

            annotatedImg = insertObjectAnnotation(debugFrameForPng.image, 'rectangle', debugFrameForPng.faceBBox, 'Face', 'Color', 'yellow', 'LineWidth', 3);
            annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrameForPng.regionBBoxes.forehead, 'Forehead', 'Color', 'green', 'LineWidth', 2);
            annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrameForPng.regionBBoxes.glabella, 'Glabella', 'Color', 'cyan', 'LineWidth', 2);
            annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrameForPng.regionBBoxes.malarLeft, 'Malar-L', 'Color', 'magenta', 'LineWidth', 2);
            annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrameForPng.regionBBoxes.malarRight, 'Malar-R', 'Color', 'magenta', 'LineWidth', 2);
            annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrameForPng.regionBBoxes.cheekLeft, 'Cheek-L', 'Color', 'red', 'LineWidth', 2);
            annotatedImg = insertObjectAnnotation(annotatedImg, 'rectangle', debugFrameForPng.regionBBoxes.cheekRight, 'Cheek-R', 'Color', 'red', 'LineWidth', 2);

            roiPngOutPath = fullfile(figuresRoot, [subjectID '_multi_region_sanity.png']);
            imwrite(annotatedImg, roiPngOutPath);

            disp([subjectID ': saved ' roiPngOutPath]);

            gt = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, sourceNum);

            hrFaultMask = gt.hr == 255;
            numHRFaultSamples = sum(hrFaultMask);

            if numHRFaultSamples > 0
                disp([subjectID ': FAULT CODES -- ' num2str(numHRFaultSamples) ' HR sample(s) == 255. Stripping before mean().']);
            end

            hrClean = gt.hr(~hrFaultMask);

            if isempty(hrClean)
                error('run_segment6_task_n_multi_region_batch:noCleanGT', 'All gt_HR.csv samples were fault codes for %s.', subjectID);
            end

            HR_groundtruth = mean(hrClean);

            disp([subjectID ': HR_groundtruth = ' num2str(HR_groundtruth) ' bpm (fault-stripped)']);

            HR_forehead_scenario(subjectPos) = HR_region.forehead;
            HR_glabella_scenario(subjectPos) = HR_region.glabella;
            HR_malar_scenario(subjectPos) = HR_region.malar;
            HR_cheek_scenario(subjectPos) = HR_region.cheek;
            HR_groundtruth_scenario(subjectPos) = HR_groundtruth;
            subjectUsable(subjectPos) = true;

            hrRowParts = {subjectID, scenarioLabel, num2str(HR_region.forehead), num2str(HR_region.glabella), num2str(HR_region.malar), num2str(HR_region.cheek), num2str(HR_groundtruth)};
            hrRowLine = strjoin(hrRowParts, ',');
            writelines(hrRowLine, hrCsvPath, 'WriteMode', 'append');

            disp([subjectID ': appended row to ' hrCsvPath]);
        catch causeErr
            disp([subjectID ': FAILED -- ' causeErr.message]);
            failedCombos{end + 1} = subjectID;
            failedReasons{end + 1} = causeErr.message;
        end
    end

    usableIdx = find(subjectUsable);
    numUsable = numel(usableIdx);

    disp([scenarioLabel ': ' num2str(numUsable) ' of ' num2str(numSubjects) ' subjects usable.']);

    if numUsable < 3
        disp([scenarioLabel ': fewer than 3 usable subjects, skipping Action 3-5 for this scenario.']);
        continue
    end

    HR_forehead_usable = HR_forehead_scenario(usableIdx);
    HR_glabella_usable = HR_glabella_scenario(usableIdx);
    HR_malar_usable = HR_malar_scenario(usableIdx);
    HR_cheek_usable = HR_cheek_scenario(usableIdx);
    HR_groundtruth_usable = HR_groundtruth_scenario(usableIdx);

    relativeSpread = computeRegionAgreement(HR_forehead_usable, HR_glabella_usable, HR_malar_usable, HR_cheek_usable);
    [HR_switched, selectedRegion] = computeRegionSwitchingEstimate(HR_forehead_usable, HR_glabella_usable, HR_malar_usable, HR_cheek_usable);

    disp([scenarioLabel ': mean relative cross-region spread = ' num2str(mean(relativeSpread)) ', median = ' num2str(median(relativeSpread))]);

    switchCounts = containers.Map({'forehead', 'glabella', 'malar', 'cheek'}, {0, 0, 0, 0});
    for i = 1:numUsable
        switchCounts(selectedRegion{i}) = switchCounts(selectedRegion{i}) + 1;
    end
    disp([scenarioLabel ': region selection counts -- forehead=' num2str(switchCounts('forehead')) ', glabella=' num2str(switchCounts('glabella')) ', malar=' num2str(switchCounts('malar')) ', cheek=' num2str(switchCounts('cheek'))]);

    metricsForehead = computeMetrics(HR_forehead_usable, HR_groundtruth_usable);
    metricsGlabella = computeMetrics(HR_glabella_usable, HR_groundtruth_usable);
    metricsMalar = computeMetrics(HR_malar_usable, HR_groundtruth_usable);
    metricsCheek = computeMetrics(HR_cheek_usable, HR_groundtruth_usable);
    metricsSwitched = computeMetrics(HR_switched, HR_groundtruth_usable);

    methodMetrics = {metricsForehead, metricsGlabella, metricsMalar, metricsCheek, metricsSwitched};
    methodNames = {'forehead', 'glabella', 'malar', 'cheek', 'switching'};

    for methodIdx = 1:numel(methodMetrics)
        m = methodMetrics{methodIdx};
        disp([scenarioLabel ': ' methodNames{methodIdx} ' -- MAE = ' num2str(m.mae) ', RMSE = ' num2str(m.rmse) ', r = ' num2str(m.pearsonR) ', n = ' num2str(m.n)]);

        validationRowParts = {scenarioLabel, methodNames{methodIdx}, num2str(m.mae), num2str(m.rmse), num2str(m.pearsonR), num2str(m.n)};
        validationRowLine = strjoin(validationRowParts, ',');
        writelines(validationRowLine, validationCsvPath, 'WriteMode', 'append');
    end
end

disp(' ');
disp('--- Segment 6 Task N multi-region batch complete ---');
disp(['Failed subject/scenario combos: ' num2str(numel(failedCombos))]);

for failPos = 1:numel(failedCombos)
    disp(['  ' failedCombos{failPos} ': ' failedReasons{failPos}]);
end
