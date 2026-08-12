% RUN_VIPL_DEVICE_STRATIFIED_EVAL Task L, Action 4. Computes HR
% MAE/RMSE/r separately for source1 (Logitech C310 webcam), source2
% (HUAWEI P9 phone), and source3 (RealSense F200 RGB), both pooled
% across all available scenarios and broken out per scenario -- the
% actual answer to "will the real demo underperform because it uses a
% phone, not a webcam."
%
% Pipeline stage: Stage 6 (validation), Task L. This does not touch or
% recompute anything upstream -- it only reads the per-subject
% data/processed/VIPL_pX_vY_sourceZ_hr_estimates.mat files that
% run_vipl_integration_batch.m, run_vipl_phone_v1_batch.m, and
% run_vipl_phone_v8v9_batch.m already wrote, parses (subject, scenario,
% source) back out of each file's subjectID, and pools/stratifies.
%
% HR gets no leave-one-out treatment here (same reasoning already
% documented in validation/runLOSOStratified.m's header: fftHeartRate.m
% has no fitted parameter, nothing can leak between subjects, so a
% direct pooled comparison is already fair). The estimator reported is
% the Task J switching estimator (validation/computeSwitchingEstimate.m,
% CHROM/POS gated by the already-derived 29.27% relative-disagreement
% threshold) since that is this project's validated best HR estimator --
% raw CHROM and POS are reported alongside it for reference, not as the
% headline numbers.
%
% Output: results/metrics/segment6_device_stratified_hr_metrics.csv,
% one row per (grouping label, estimator) pair, columns
% group,estimator,n,MAE,RMSE,r.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

disagreementThreshold = 0.2927;

matFiles = dir(fullfile(processedDataRoot, 'VIPL_p*_hr_estimates.mat'));

numFiles = numel(matFiles);

disp(['Found ' num2str(numFiles) ' VIPL *_hr_estimates.mat files in ' processedDataRoot]);

subjectID = cell(numFiles, 1);
subjectNum = zeros(numFiles, 1);
scenarioNum = zeros(numFiles, 1);
sourceNum = zeros(numFiles, 1);
HR_chrom = zeros(numFiles, 1);
HR_pos = zeros(numFiles, 1);
HR_groundtruth = zeros(numFiles, 1);

validCount = 0;

for filePos = 1:numFiles
    matPath = fullfile(matFiles(filePos).folder, matFiles(filePos).name);
    loaded = load(matPath, 'HR_chrom', 'HR_pos', 'HR_groundtruth', 'subjectID');

    tokens = regexp(loaded.subjectID, 'VIPL_p(\d+)_v(\d+)_source(\d+)', 'tokens');

    if isempty(tokens)
        disp(['SKIPPING (subjectID did not match VIPL_pX_vY_sourceZ pattern): ' loaded.subjectID]);
        continue;
    end

    parsedSubject = str2double(tokens{1}{1});
    parsedScenario = str2double(tokens{1}{2});
    parsedSource = str2double(tokens{1}{3});

    if isnan(loaded.HR_chrom) || isnan(loaded.HR_pos) || isnan(loaded.HR_groundtruth)
        disp(['SKIPPING (NaN estimate or ground truth): ' loaded.subjectID]);
        continue;
    end

    validCount = validCount + 1;
    subjectID{validCount} = loaded.subjectID;
    subjectNum(validCount) = parsedSubject;
    scenarioNum(validCount) = parsedScenario;
    sourceNum(validCount) = parsedSource;
    HR_chrom(validCount) = loaded.HR_chrom;
    HR_pos(validCount) = loaded.HR_pos;
    HR_groundtruth(validCount) = loaded.HR_groundtruth;
end

subjectID = subjectID(1:validCount);
subjectNum = subjectNum(1:validCount);
scenarioNum = scenarioNum(1:validCount);
sourceNum = sourceNum(1:validCount);
HR_chrom = HR_chrom(1:validCount);
HR_pos = HR_pos(1:validCount);
HR_groundtruth = HR_groundtruth(1:validCount);

disp(['Usable rows after NaN/parse filtering: ' num2str(validCount)]);

[HR_switched, usedPos] = computeSwitchingEstimate(HR_chrom, HR_pos, disagreementThreshold);

disp(['Switching estimator: POS selected for ' num2str(sum(usedPos)) ' of ' num2str(validCount) ' subjects (threshold ' num2str(disagreementThreshold) ')']);

metricsCsvPath = fullfile(metricsRoot, 'segment6_device_stratified_hr_metrics.csv');
metricsHeaderLine = "group,estimator,n,MAE,RMSE,r";
writelines(metricsHeaderLine, metricsCsvPath);

groupLabels = {};
groupMasks = {};

for srcPos = 1:3
    groupLabels{end + 1} = ['source' num2str(srcPos) '_pooled'];
    groupMasks{end + 1} = (sourceNum == srcPos);
end

scenarioValues = unique(scenarioNum)';

for scenarioPos = scenarioValues
    for srcPos = 1:3
        thisMask = (sourceNum == srcPos) & (scenarioNum == scenarioPos);

        if sum(thisMask) == 0
            continue;
        end

        groupLabels{end + 1} = ['source' num2str(srcPos) '_v' num2str(scenarioPos)];
        groupMasks{end + 1} = thisMask;
    end
end

v1PhoneMask = (sourceNum == 2) & (scenarioNum == 1);
v1WebcamMask = (sourceNum == 1) & (scenarioNum == 1);
v8Mask = (sourceNum == 2) & (scenarioNum == 8);
v9Mask = (sourceNum == 2) & (scenarioNum == 9);
v8v9Mask = v8Mask | v9Mask;

groupLabels{end + 1} = 'v1_phone_vs_v1_webcam__v1_phone';
groupMasks{end + 1} = v1PhoneMask;

groupLabels{end + 1} = 'v1_phone_vs_v1_webcam__v1_webcam';
groupMasks{end + 1} = v1WebcamMask;

groupLabels{end + 1} = 'handheld_v8v9_pooled';
groupMasks{end + 1} = v8v9Mask;

numGroups = numel(groupLabels);

for groupPos = 1:numGroups
    groupMask = groupMasks{groupPos};
    groupLabel = groupLabels{groupPos};
    n = sum(groupMask);

    if n == 0
        continue;
    end

    gt = HR_groundtruth(groupMask);

    estimatorNames = {'chrom', 'pos', 'switched'};
    estimatorValues = {HR_chrom(groupMask), HR_pos(groupMask), HR_switched(groupMask)};

    for estPos = 1:numel(estimatorNames)
        estName = estimatorNames{estPos};
        estVals = estimatorValues{estPos};

        absErr = abs(estVals - gt);
        MAE = mean(absErr);
        RMSE = sqrt(mean((estVals - gt) .^ 2));

        if n >= 2 && std(estVals) > 0 && std(gt) > 0
            corrMatrix = corrcoef(estVals, gt);
            r = corrMatrix(1, 2);
        else
            r = NaN;
        end

        disp([groupLabel ' (' estName ', n=' num2str(n) '): MAE=' num2str(MAE) ', RMSE=' num2str(RMSE) ', r=' num2str(r)]);

        rowParts = {groupLabel, estName, num2str(n), num2str(MAE), num2str(RMSE), num2str(r)};
        rowLine = strjoin(rowParts, ',');
        writelines(rowLine, metricsCsvPath, 'WriteMode', 'append');
    end
end

disp(['Saved ' metricsCsvPath]);
disp('--- Task L device-stratified evaluation complete ---');
