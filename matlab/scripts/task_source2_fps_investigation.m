% TASK_SOURCE2_FPS_INVESTIGATION Segment 8 (post-review follow-up). Derives
% each VIPL-HR source2 (HUAWEI P9 phone) subject's TRUE frame rate WITHOUT
% ever touching ground truth, using the fact (docs/VIPL_DATA_FORMAT.md)
% that sibling sources within one (subject, scenario) folder are recorded
% in the same session, so a sibling source's own time.txt timestamps span
% the real session duration that source2's frames were captured over.
%
%   trueFps_source2 = source2_NumFrames / (session duration from a sibling
%                      source's time.txt)
%
% loadVIPLVideo.m is NOT modified and NOT called for source2 here (it has
% no time.txt for source2 and would just fall back to the container's
% 25 fps, which is exactly the number being investigated) -- this script
% opens VideoReader directly for source2 (NumFrames only) and reads a
% sibling source's time.txt directly for the session duration, mirroring
% loadVIPLVideo.m's own elapsed-time formula ((last - first timestamp) /
% 1000) without needing to call that function.
%
% gt_HR.csv / gt_HR / any ground-truth file is NEVER read by this script --
% using it to pick or tune a frame rate would be circular (see this task's
% own brief). Only NumFrames (from source2's video.avi) and time.txt (from
% a sibling source) are read.
%
% Sibling preference: source3 first (RGB, and confirmed identical time.txt
% content to source4 per docs/VIPL_DATA_FORMAT.md), falling back to
% source4 (NIR, but same acquisition session / same time.txt) if source3's
% time.txt is unavailable for a given subject. source1 is also checked as
% a third fallback for completeness. If a subject has NO sibling with a
% time.txt at all, it is EXCLUDED and flagged, never guessed.
%
% Output: results/metrics/segment8_source2_fps_investigation.csv (NEW
% file; no existing metrics file is touched).

subjectNums = [84, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107];
scenarioNum = 1; % all 12 are v1, per results/metrics/segment4_hr_summary_vipl.csv
siblingPreferenceOrder = [3, 1, 4]; % source3 first, then source1, then source4

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

csvPath = fullfile(metricsRoot, 'segment8_source2_fps_investigation.csv');
headerLine = "subjectID,source2_NumFrames,siblingSource,siblingDurationSec,trueFps_source2,containerFps,ratioTrueToContainer";
writelines(headerLine, csvPath);

numSubjects = numel(subjectNums);
excludedSubjects = {};

fprintf('%-20s %14s %10s %16s %12s %12s %10s\n', 'subjectID', 'source2Frames', 'sibling', 'siblingDurSec', 'trueFps', 'containerFps', 'ratio');

for idx = 1:numSubjects
    subjectNum = subjectNums(idx);
    subjectID = ['VIPL_p' num2str(subjectNum) '_v' num2str(scenarioNum) '_source2'];

    source2VideoPath = fullfile(viplRoot, ['p' num2str(subjectNum)], ['v' num2str(scenarioNum)], 'source2', 'video.avi');

    if ~isfile(source2VideoPath)
        disp([subjectID ': source2 video.avi not found at ' source2VideoPath ' -- excluding.']);
        excludedSubjects{end + 1} = subjectID; %#ok<AGROW>
        continue;
    end

    source2Reader = VideoReader(source2VideoPath);
    source2NumFrames = source2Reader.NumFrames;
    containerFps = source2Reader.FrameRate;

    % --- Find the first available sibling source's time.txt, in
    % preference order, WITHOUT touching gt_HR.csv/gt_SpO2.csv. ---
    siblingSourceUsed = NaN;
    siblingDurationSec = NaN;

    for siblingSourceNum = siblingPreferenceOrder
        timePath = fullfile(viplRoot, ['p' num2str(subjectNum)], ['v' num2str(scenarioNum)], ...
            ['source' num2str(siblingSourceNum)], 'time.txt');

        if isfile(timePath)
            frameTimestampsMs = readmatrix(timePath, 'FileType', 'text');
            numTimestamps = numel(frameTimestampsMs);

            if numTimestamps >= 2
                % Same elapsed-time formula as loadVIPLVideo.m.
                siblingDurationSec = (frameTimestampsMs(numTimestamps) - frameTimestampsMs(1)) / 1000;
                siblingSourceUsed = siblingSourceNum;
                break;
            else
                disp([subjectID ': source' num2str(siblingSourceNum) '/time.txt has fewer than 2 timestamps, trying next sibling.']);
            end
        end
    end

    if isnan(siblingSourceUsed)
        disp([subjectID ': NO sibling source (checked source3, source1, source4) has a usable time.txt -- excluding rather than guessing.']);
        excludedSubjects{end + 1} = subjectID; %#ok<AGROW>
        continue;
    end

    trueFpsSource2 = source2NumFrames / siblingDurationSec;
    ratioTrueToContainer = trueFpsSource2 / containerFps;

    fprintf('%-20s %14d %10s %16.4f %12.4f %12.4f %10.4f\n', subjectID, source2NumFrames, ...
        ['source' num2str(siblingSourceUsed)], siblingDurationSec, trueFpsSource2, containerFps, ratioTrueToContainer);

    rowParts = {subjectID, num2str(source2NumFrames), ['source' num2str(siblingSourceUsed)], ...
        num2str(siblingDurationSec, '%.6f'), num2str(trueFpsSource2, '%.6f'), num2str(containerFps, '%.6f'), num2str(ratioTrueToContainer, '%.6f')};
    rowLine = strjoin(rowParts, ',');
    writelines(rowLine, csvPath, 'WriteMode', 'append');
end

disp(' ');
disp(['--- Task Source2 FPS investigation complete. Saved ' csvPath ' ---']);
disp(['Subjects excluded (no usable sibling time.txt): ' num2str(numel(excludedSubjects))]);
for k = 1:numel(excludedSubjects)
    disp(['  ' excludedSubjects{k}]);
end
