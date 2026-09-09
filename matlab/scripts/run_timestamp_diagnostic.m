% RUN_TIMESTAMP_DIAGNOSTIC Diagnostic-only batch driver that measures how
% far real per-frame VideoReader.CurrentTime acquisition timestamps diverge
% from the SYNTHETIC uniform timestamp grid roi/extractROISignals.m builds
% today (roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate, using one
% nominal scalar frameRate).
%
% This script does NOT modify roi/extractROISignals.m or any other
% pipeline file, does NOT wire real per-frame timestamps into anything,
% and does NOT re-run any validation/regression test. It only measures.
% A later, separate, reviewed task would decide whether/how to act on
% these numbers.
%
% For each sample video this script:
%   1. Opens the video with io/loadUBFCVideo.m (UBFC) or io/loadVIPLVideo.m
%      (VIPL) to get the SAME nominal scalar frameRate production code
%      uses today to build extractROISignals.m's uniform grid -- for VIPL
%      source1/source3 that is already time.txt-corrected at the scalar
%      level by loadVIPLVideo.m itself; this diagnostic is checking a
%      DIFFERENT, additional issue (per-frame jitter within a clip, not
%      the average-scalar-is-wrong issue loadVIPLVideo.m already fixes).
%   2. Streams every frame (no preloading, same discipline as
%      extractROISignals.m), reading v.CurrentTime BEFORE each readFrame()
%      call -- the standard MATLAB idiom for real per-frame acquisition
%      time -- and discarding the actual frame data.
%   3. Computes inter-frame intervals from those real timestamps and
%      compares the resulting true mean fps against the nominal fps.
%   4. Appends one row to results/metrics/timestamp_diagnostic.csv.
%
% Sample set (see task instructions for why these specific videos):
%   UBFC: all 5 locally available DATASET_1 ground-truth subjects
%         (5-gt, 6-gt, 7-gt, 12-gt, after-exercise).
%   VIPL: 10 videos spread across source1 (p1, p10, p20, p30, p45),
%         source2 (p2, p15, p40, p55), and source3 (p1 -- the only
%         subject with a source3/video.avi actually extracted locally;
%         verified via `find` before committing to this list). source4
%         is NIR and explicitly unsupported by loadVIPLVideo.m, so it is
%         not used here.
%
% If a video fails to open or decode, this script logs the error via
% disp() and moves on to the next video rather than halting the batch.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
ubfcRoot = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

% --- UBFC sample list: subject folder name only (actual .avi filename
% varies per subject -- see docs/DATA_FORMAT.md -- so it is located with
% dir() at run time rather than hardcoded here). ---
ubfcSubjects = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};

% --- VIPL sample list: (subjectNum, scenarioNum, sourceNum) triples. ---
viplTriples = [
    1,  1, 1
    10, 1, 1
    20, 1, 1
    30, 1, 1
    45, 1, 1
    2,  1, 2
    15, 1, 2
    40, 1, 2
    55, 1, 2
    1,  1, 3
];

csvPath = fullfile(metricsRoot, 'timestamp_diagnostic.csv');
headerLine = "videoID,dataset,nominalFrameRate,trueMeanFps,pctDiff,stdIntervalSec,minIntervalSec,maxIntervalSec,medianIntervalSec,numOutliersOver20pct,numFrames";
writelines(headerLine, csvPath);

allPctDiff = [];
ubfcPctDiff = [];
viplPctDiff = [];
viplSourcePctDiff = containers.Map('KeyType', 'double', 'ValueType', 'any');

allStdInterval = [];
allNumOutliers = [];

numAttempted = 0;
numFailed = 0;

disp('=== Timestamp diagnostic: UBFC subjects ===');

for subjPos = 1:numel(ubfcSubjects)
    subjectID = ubfcSubjects{subjPos};
    numAttempted = numAttempted + 1;

    disp(['--- Measuring ' subjectID ' (' num2str(subjPos) ' of ' num2str(numel(ubfcSubjects)) ') ---']);

    try
        subjectFolder = fullfile(ubfcRoot, subjectID);
        aviFiles = dir(fullfile(subjectFolder, '*.avi'));

        if isempty(aviFiles)
            error('run_timestamp_diagnostic:noAvi', 'No .avi file found in %s', subjectFolder);
        end

        videoPath = fullfile(aviFiles(1).folder, aviFiles(1).name);

        [v, nominalFrameRate, ~] = loadUBFCVideo(videoPath);

        disp([subjectID ': loaded ' videoPath ', nominalFrameRate = ' num2str(nominalFrameRate) ' fps']);

        metrics = measureFrameTimestamps(v);

        disp([subjectID ': numFrames = ' num2str(metrics.numFrames) ', trueMeanFps = ' num2str(metrics.trueMeanFps) ' fps, pctDiff = ' num2str(100 * (metrics.trueMeanFps - nominalFrameRate) / nominalFrameRate) '%']);

        row = writeDiagnosticRow(csvPath, subjectID, 'UBFC', nominalFrameRate, metrics);

        allPctDiff(end + 1) = row.pctDiff; %#ok<AGROW>
        ubfcPctDiff(end + 1) = row.pctDiff; %#ok<AGROW>
        allStdInterval(end + 1) = row.stdIntervalSec; %#ok<AGROW>
        allNumOutliers(end + 1) = row.numOutliersOver20pct; %#ok<AGROW>
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.message]);
        numFailed = numFailed + 1;
    end
end

disp('=== Timestamp diagnostic: VIPL videos ===');

numViplTriples = size(viplTriples, 1);

for triplePos = 1:numViplTriples
    subjectNum = viplTriples(triplePos, 1);
    scenarioNum = viplTriples(triplePos, 2);
    sourceNum = viplTriples(triplePos, 3);

    videoID = ['VIPL_p' num2str(subjectNum) '_v' num2str(scenarioNum) '_source' num2str(sourceNum)];
    numAttempted = numAttempted + 1;

    disp(['--- Measuring ' videoID ' (' num2str(triplePos) ' of ' num2str(numViplTriples) ') ---']);

    try
        [v, nominalFrameRate, ~, videoPath] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum);

        disp([videoID ': loaded ' videoPath ', nominalFrameRate = ' num2str(nominalFrameRate) ' fps']);

        metrics = measureFrameTimestamps(v);

        disp([videoID ': numFrames = ' num2str(metrics.numFrames) ', trueMeanFps = ' num2str(metrics.trueMeanFps) ' fps, pctDiff = ' num2str(100 * (metrics.trueMeanFps - nominalFrameRate) / nominalFrameRate) '%']);

        row = writeDiagnosticRow(csvPath, videoID, 'VIPL', nominalFrameRate, metrics);

        allPctDiff(end + 1) = row.pctDiff; %#ok<AGROW>
        viplPctDiff(end + 1) = row.pctDiff; %#ok<AGROW>
        allStdInterval(end + 1) = row.stdIntervalSec; %#ok<AGROW>
        allNumOutliers(end + 1) = row.numOutliersOver20pct; %#ok<AGROW>

        if isKey(viplSourcePctDiff, sourceNum)
            existing = viplSourcePctDiff(sourceNum);
            existing(end + 1) = row.pctDiff; %#ok<AGROW>
            viplSourcePctDiff(sourceNum) = existing;
        else
            viplSourcePctDiff(sourceNum) = row.pctDiff;
        end
    catch causeErr
        disp([videoID ': FAILED -- ' causeErr.message]);
        numFailed = numFailed + 1;
    end
end

disp('=== Timestamp diagnostic complete ===');
disp(['Videos attempted: ' num2str(numAttempted) ', failed: ' num2str(numFailed)]);
disp(['Saved ' csvPath]);

disp('--- pctDiff summary (trueMeanFps vs nominalFrameRate) ---');
disp(['Overall: mean = ' num2str(mean(allPctDiff)) '%, median = ' num2str(median(allPctDiff)) '% (n=' num2str(numel(allPctDiff)) ')']);

if ~isempty(ubfcPctDiff)
    disp(['UBFC:    mean = ' num2str(mean(ubfcPctDiff)) '%, median = ' num2str(median(ubfcPctDiff)) '% (n=' num2str(numel(ubfcPctDiff)) ')']);
end

if ~isempty(viplPctDiff)
    disp(['VIPL:    mean = ' num2str(mean(viplPctDiff)) '%, median = ' num2str(median(viplPctDiff)) '% (n=' num2str(numel(viplPctDiff)) ')']);
end

sourceKeys = keys(viplSourcePctDiff);
for keyPos = 1:numel(sourceKeys)
    sourceNum = sourceKeys{keyPos};
    vals = viplSourcePctDiff(sourceNum);
    disp(['  VIPL source' num2str(sourceNum) ': mean = ' num2str(mean(vals)) '%, median = ' num2str(median(vals)) '% (n=' num2str(numel(vals)) ')']);
end

disp('--- Jitter summary (real inter-frame interval spread) ---');
disp(['stdIntervalSec: mean = ' num2str(mean(allStdInterval)) ', max = ' num2str(max(allStdInterval))]);
disp(['numOutliersOver20pct: mean = ' num2str(mean(allNumOutliers)) ', max = ' num2str(max(allNumOutliers))]);

function metrics = measureFrameTimestamps(v)
% MEASUREFRAMETIMESTAMPS Stream a VideoReader object frame-by-frame,
% recording each frame's real acquisition time (v.CurrentTime, read
% BEFORE readFrame()) without preloading any frame data, and return
% summary statistics on the resulting inter-frame intervals.

timestamps = [];

while hasFrame(v)
    t = v.CurrentTime;
    readFrame(v); %#ok<NASGU> -- frame data discarded, only timing matters
    timestamps(end + 1) = t; %#ok<AGROW>
end

intervals = diff(timestamps);

metrics.numFrames = numel(timestamps);
metrics.trueMeanFps = 1 / mean(intervals);
metrics.stdIntervalSec = std(intervals);
metrics.minIntervalSec = min(intervals);
metrics.maxIntervalSec = max(intervals);
metrics.medianIntervalSec = median(intervals);
metrics.numOutliersOver20pct = sum(abs(intervals - metrics.medianIntervalSec) / metrics.medianIntervalSec > 0.20);

end

function row = writeDiagnosticRow(csvPath, videoID, dataset, nominalFrameRate, metrics)
% WRITEDIAGNOSTICROW Append one row to the diagnostic CSV and return the
% computed pctDiff/stdIntervalSec/numOutliersOver20pct for summary use.

pctDiff = 100 * (metrics.trueMeanFps - nominalFrameRate) / nominalFrameRate;

rowParts = {videoID, dataset, num2str(nominalFrameRate), num2str(metrics.trueMeanFps), num2str(pctDiff), num2str(metrics.stdIntervalSec), num2str(metrics.minIntervalSec), num2str(metrics.maxIntervalSec), num2str(metrics.medianIntervalSec), num2str(metrics.numOutliersOver20pct), num2str(metrics.numFrames)};
rowLine = strjoin(rowParts, ',');
writelines(rowLine, csvPath, 'WriteMode', 'append');

row.pctDiff = pctDiff;
row.stdIntervalSec = metrics.stdIntervalSec;
row.numOutliersOver20pct = metrics.numOutliersOver20pct;

end
