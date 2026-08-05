% RUN_SEGMENT3_FILTERING_BATCH Batch driver for Segment 3 (detrend +
% bandpass filtering) across a configurable list of subjects that already
% have Segment 2 output.
%
% Each team member edits the SUBJECT LIST section below to their own
% already-processed subset from Segment 2, then runs this script. Every
% subject's output filename is tagged with that subject's own ID, so
% everyone's .mat/.png outputs can be copied into one shared folder
% afterwards without collisions.
%
% For each subject this script:
%   1. Loads data/processed/<subjectID>_rgb_traces.mat (Segment 2 output).
%   2. Calls filtering/detrendSignal.m on R, G, B independently.
%   3. Calls filtering/bandpassClean.m on each detrended channel using
%      that subject's own fs.
%   4. Saves data/processed/<subjectID>_filtered_traces.mat.
%   5. Saves a three-subplot sanity PNG (raw G, detrended G, filtered G)
%      to results/figures/<subjectID>_filtering_sanity.png.
%   6. Prints progress and the parameters used to the console.
%
% If a subject's rgb_traces.mat is missing or fails to load, this script
% logs the reason and moves on to the next subject rather than halting
% the whole batch. A summary of any failures is printed at the end.

subjectList = {'5-gt', '6-gt', '7-gt'};

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
processedDataRoot = fullfile(projectRoot, 'data', 'processed');
figuresRoot = fullfile(projectRoot, 'results', 'figures');

if ~isfolder(processedDataRoot)
    mkdir(processedDataRoot);
end

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

numSubjects = numel(subjectList);
failedSubjects = {};
failedReasons = {};

for subjectPos = 1:numSubjects
    subjectID = subjectList{subjectPos};

    disp(['--- Processing subject ' subjectID ' (' num2str(subjectPos) ' of ' num2str(numSubjects) ') ---']);

    try
        rgbMatPath = fullfile(processedDataRoot, [subjectID '_rgb_traces.mat']);

        if ~isfile(rgbMatPath)
            error('run_segment3_filtering_batch:missingInput', 'Segment 2 output not found: %s', rgbMatPath);
        end

        rgbData = load(rgbMatPath);

        R = rgbData.R;
        G = rgbData.G;
        B = rgbData.B;
        fs = rgbData.fs;

        disp(['Subject ' subjectID ': loaded rgb_traces.mat, fs = ' num2str(fs) ' fps, numFrames = ' num2str(numel(G))]);

        [R_detrended, detrendOrder] = detrendSignal(R);
        [G_detrended, detrendOrder] = detrendSignal(G);
        [B_detrended, detrendOrder] = detrendSignal(B);

        [R_filtered, filterOrder] = bandpassClean(R_detrended, fs);
        [G_filtered, filterOrder] = bandpassClean(G_detrended, fs);
        [B_filtered, filterOrder] = bandpassClean(B_detrended, fs);

        disp(['Subject ' subjectID ': detrend order = ' num2str(detrendOrder) ', filter order = ' num2str(filterOrder)]);

        filteredMatPath = fullfile(processedDataRoot, [subjectID '_filtered_traces.mat']);
        save(filteredMatPath, 'R_filtered', 'G_filtered', 'B_filtered', 'fs', 'subjectID', 'detrendOrder', 'filterOrder');

        disp(['Subject ' subjectID ': saved ' filteredMatPath]);

        numSamples = numel(G);
        timeAxis = (0:numSamples - 1) / fs;

        figureHandle = figure('Visible', 'off');

        subplot(3, 1, 1);
        plot(timeAxis, G);
        title('Raw G(t)');
        xlabel('Time (s)');
        ylabel('Pixel intensity');

        subplot(3, 1, 2);
        plot(timeAxis, G_detrended);
        title('Detrended G(t)');
        xlabel('Time (s)');
        ylabel('Pixel intensity (detrended)');

        subplot(3, 1, 3);
        plot(timeAxis, G_filtered);
        title('Detrended + Bandpass-Filtered G(t)');
        xlabel('Time (s)');
        ylabel('Pixel intensity (filtered)');

        sgtitle(['Subject ' subjectID ' — Segment 3 Filtering Sanity Check']);

        pngOutPath = fullfile(figuresRoot, [subjectID '_filtering_sanity.png']);
        exportgraphics(figureHandle, pngOutPath);
        close(figureHandle);

        disp(['Subject ' subjectID ': saved ' pngOutPath]);
    catch causeErr
        disp(['Subject ' subjectID ': FAILED — ' causeErr.message]);
        failedSubjects{end + 1} = subjectID;
        failedReasons{end + 1} = causeErr.message;
    end
end

disp('--- Batch complete ---');
disp(['Subjects attempted: ' num2str(numSubjects)]);
disp(['Subjects failed: ' num2str(numel(failedSubjects))]);

for failPos = 1:numel(failedSubjects)
    disp(['  ' failedSubjects{failPos} ': ' failedReasons{failPos}]);
end
