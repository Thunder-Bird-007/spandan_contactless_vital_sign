% RUN_TASK_N_V4_V5_BRIGHTNESS_CHECK Direct pixel-brightness verification of
% which VIPL-HR scenario (v4 or v5) is actually the dark one.
%
% Task N's report (docs/Segment6_Task_N_Multi_Region_ROI.md) claims, from
% VIPL-HR-V1/ReadMe.pdf text, that v4 is dark and v5 is bright -- which
% contradicts the published VIPL-HR paper's own Table 3 (Niu et al.),
% where Situation 4 = Bright and Situation 5 = Dark. This script settles
% it with the most direct possible evidence: real frame brightness, not
% another text source. It is a pure read-only verification pass -- it
% does not call or modify any pipeline file (roi/extractROISignals.m,
% filtering/*, pulseextraction/*, heartrate/*, spo2/*, or any validation/*
% function).
%
% For each of 5 subjects with both v4/source1 and v5/source1 on disk, this
% script:
%   1. Opens both videos via plain VideoReader (not io/loadVIPLVideo.m --
%      no fs/timing logic is needed here, only pixel content).
%   2. Reads the frame at round(numFrames/2), same "representative
%      midpoint frame" logic already used by roi/extractROISignals.m's
%      debugFrame.frameIndex, for an apples-to-apples comparison with the
%      existing per-subject sanity PNGs.
%   3. Converts each frame to grayscale (rgb2gray) and computes its mean
%      pixel intensity (0-255 scale) over the FULL frame -- not just the
%      face/ROI -- as a simple, objective brightness number.
%   4. Saves a side-by-side image (v4 frame left, v5 frame right, each
%      labeled with its scenario and measured mean intensity) to
%      results/figures/v4_v5_brightness_check_pX.png.
%   5. Appends one row to
%      results/metrics/task_n_v4_v5_brightness_check.csv.

subjectList = [1, 3, 4, 6, 7];

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
figuresRoot = fullfile(projectRoot, 'results', 'figures');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'task_n_v4_v5_brightness_check.csv');
csvHeaderLine = "subjectID,v4_mean_intensity,v5_mean_intensity,brighter_scenario";
writelines(csvHeaderLine, csvPath);

numSubjects = numel(subjectList);

for subjectPos = 1:numSubjects
    subjectNum = subjectList(subjectPos);
    subjectID = ['p' num2str(subjectNum)];

    disp(['--- Processing ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    v4Path = fullfile(viplRoot, subjectID, 'v4', 'source1', 'video.avi');
    v5Path = fullfile(viplRoot, subjectID, 'v5', 'source1', 'video.avi');

    vr4 = VideoReader(v4Path);
    vr5 = VideoReader(v5Path);

    frameIdx4 = round(vr4.NumFrames / 2);
    frameIdx5 = round(vr5.NumFrames / 2);

    img4 = read(vr4, frameIdx4);
    img5 = read(vr5, frameIdx5);

    gray4 = rgb2gray(img4);
    gray5 = rgb2gray(img5);

    meanIntensity4 = mean(double(gray4(:)));
    meanIntensity5 = mean(double(gray5(:)));

    if meanIntensity4 > meanIntensity5
        brighterScenario = 'v4';
    elseif meanIntensity5 > meanIntensity4
        brighterScenario = 'v5';
    else
        brighterScenario = 'tie';
    end

    disp([subjectID ': v4 mean intensity = ' num2str(meanIntensity4) ', v5 mean intensity = ' num2str(meanIntensity5) ', brighter = ' brighterScenario]);

    label4 = ['v4 (frame ' num2str(frameIdx4) ') -- mean intensity = ' num2str(meanIntensity4, '%.2f')];
    label5 = ['v5 (frame ' num2str(frameIdx5) ') -- mean intensity = ' num2str(meanIntensity5, '%.2f')];

    img4Annotated = insertText(img4, [10 10], label4, 'FontSize', 18, 'BoxColor', 'yellow', 'BoxOpacity', 0.7, 'TextColor', 'black');
    img5Annotated = insertText(img5, [10 10], label5, 'FontSize', 18, 'BoxColor', 'yellow', 'BoxOpacity', 0.7, 'TextColor', 'black');

    targetHeight = max(size(img4Annotated, 1), size(img5Annotated, 1));
    img4Resized = imresize(img4Annotated, [targetHeight NaN]);
    img5Resized = imresize(img5Annotated, [targetHeight NaN]);

    sideBySide = [img4Resized, img5Resized];

    pngOutPath = fullfile(figuresRoot, ['v4_v5_brightness_check_' subjectID '.png']);
    imwrite(sideBySide, pngOutPath);

    disp([subjectID ': saved ' pngOutPath]);

    csvRowParts = {subjectID, num2str(meanIntensity4), num2str(meanIntensity5), brighterScenario};
    csvRowLine = strjoin(csvRowParts, ',');
    writelines(csvRowLine, csvPath, 'WriteMode', 'append');
end

disp(' ');
disp('--- v4/v5 brightness check complete ---');
