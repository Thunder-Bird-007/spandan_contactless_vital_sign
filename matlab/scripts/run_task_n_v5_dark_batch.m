% RUN_TASK_N_V5_DARK_BATCH Batch driver for the true v5 (dark) 4-region ROI
% comparison, added as a follow-up to Segment 6 Task N after
% docs/Task_N_v4_v5_Brightness_Verification.md proved by direct pixel
% measurement that v4 is actually the BRIGHT scenario and v5 is the real
% DARK scenario (the reverse of what Task N's original report assumed).
% Task N's existing v4 arm was real v4 data the whole time and is simply
% relabeled "v4 (bright)" in docs/Segment6_Task_N_Multi_Region_ROI.md; this
% script is what actually runs the real dark condition for the first time.
%
% Reuses every piece of Task N's infrastructure completely unmodified:
% roi/extractROISignals.m's 4 region modes (forehead, glabella, malar,
% cheek), filtering/detrendSignal.m -> filtering/bandpassClean.m ->
% pulseextraction/chromCombine.m -> filtering/bandpassClean.m ->
% heartrate/fftHeartRate.m, validation/computeRegionAgreement.m,
% validation/computeRegionSwitchingEstimate.m, validation/computeMetrics.m.
% No pipeline file is touched by this script.
%
% Subject pool: the same 20-subject Task N pool (p1, p3, p4, p6, p7, p8,
% p9, p10, p11, p12, p13, p14, p15, p16, p17, p18, p19, p20, p21, p22).
% v5/source1 was already on disk for 5 of them (p1, p3, p4, p6, p7 -- pulled
% for the brightness check); the other 15 were newly extracted via the same
% targeted per-entry System.IO.Compression.ZipFile extraction discipline
% used throughout this project, from VIPL-HR-V1/data/{p6-10,p11-15,p16-20,
% p21-25}.zip.
%
% Output: appends v5_dark rows to the SAME
% results/metrics/segment6_task_n_region_hr_summary.csv and
% results/metrics/segment6_task_n_validation_summary.csv files Task N's
% original batch script wrote, so all four scenarios (v1, v2, v4-bright,
% v5-dark) end up in one place. Per-region raw traces saved to
% data/processed/VIPL_pX_v5_source1_<region>_rgb_traces.mat (80 files).

subjectList = [1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22];

scenarioNum = 5;
scenarioLabel = 'v5_dark';

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
validationCsvPath = fullfile(metricsRoot, 'segment6_task_n_validation_summary.csv');

% Both CSVs already exist from the v1/v2/v4 batch run -- append, do not
% rewrite headers.
if ~isfile(hrCsvPath)
    hrHeaderLine = "subjectID,scenario,HR_forehead,HR_glabella,HR_malar,HR_cheek,HR_groundtruth";
    writelines(hrHeaderLine, hrCsvPath);
end

if ~isfile(validationCsvPath)
    validationHeaderLine = "scenario,method,mae,rmse,pearsonR,n";
    writelines(validationHeaderLine, validationCsvPath);
end

numSubjects = numel(subjectList);

failedCombos = {};
failedReasons = {};

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
            error('run_task_n_v5_dark_batch:noCleanGT', 'All gt_HR.csv samples were fault codes for %s.', subjectID);
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
    disp([scenarioLabel ': fewer than 3 usable subjects, skipping Action 3-5.']);
else
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
disp('--- Task N v5 (dark) batch complete ---');
disp(['Failed subject combos: ' num2str(numel(failedCombos))]);

for failPos = 1:numel(failedCombos)
    disp(['  ' failedCombos{failPos} ': ' failedReasons{failPos}]);
end
