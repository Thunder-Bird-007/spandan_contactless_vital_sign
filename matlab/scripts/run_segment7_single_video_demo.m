% RUN_SEGMENT7_SINGLE_VIDEO_DEMO Single, self-contained MATLAB file that
% runs this project's ADOPTED-BEST Segment 7 morphology/dicrotic-notch
% pipeline end to end on ONE video chosen interactively by the person
% running it -- no other project file needs to be on the MATLAB path.
%
% WHAT THIS IS: every function this pipeline needs (video loading, face
% ROI extraction, detrending, wide-band CHROM, the adaptive
% harmonic-comb filter (ABPF), both polarity-fix rules, uniform
% resampling, beat ensemble-averaging, and IEM dicrotic-notch detection)
% has been copied, UNCHANGED in logic, into this one file as local
% functions, per an explicit request to merge the separate pipeline
% files into a single runnable tool. The original files under
% matlab/src/ are untouched -- this is a new, additive, standalone copy,
% not a replacement for them. If matlab/src/ is later changed, this file
% will NOT pick up those changes automatically; regenerate it if that
% matters.
%
% SCOPE (by explicit choice, confirmed 2026-08-27): Segment 7's
% morphology/notch pipeline ONLY -- ROI extraction, filtering, waveform
% reconstruction, beat averaging, and dicrotic-notch detection. This does
% NOT include Segment 4's heart-rate-only path or Segment 5's SpO2
% estimation (SpO2 needs a calibration dataset beyond just a video, and
% was explicitly left out of this tool's scope).
%
% PIPELINE (identical call sequence to
% scripts/run_segment7_fig6_labeled_prototype_batch.m /
% scripts/run_segment7_task_b_branch2_batch.m's "adaptiveHarmonic"
% condition -- this project's confirmed best-supported single
% configuration, per docs/Segment7_Task_B_Notch_Quantification.md):
%   video -> face-detect + forehead ROI -> per-channel detrend
%   -> wide-band (0.5-8 Hz) CHROM pulse -> FFT f0 estimate (shared
%   across channels) -> per-channel adaptive harmonic-comb filter (ABPF,
%   6 harmonics, shared f0) -> CHROM combine -> polarity fix -> resample
%   onto a uniform 250 Hz grid -> segment + time-warp + quality-gate +
%   trim-mean beats into one prototype cycle -> IEM dicrotic-notch
%   detection.
%
% DATASET SUPPORT (auto-detected, added 2026-08-27 after being asked "why
% can't we use this for VIPL"): this file works on BOTH UBFC-rPPG and
% VIPL-HR videos, transparently, with no dataset-selection step --
%   - FRAME RATE: VideoReader.FrameRate is trustworthy for UBFC, but
%     VIPL-HR's own ReadMe documents that its container frame rate is a
%     re-encoding artifact, not the real acquisition rate (measured
%     disagreement up to ~20% for some subjects) -- see
%     matlab/src/io/loadVIPLVideo.m for the original finding. This file
%     checks for a sibling time.txt next to whichever video was picked
%     (VIPL's source1/source3 convention; UBFC videos never have one,
%     VIPL source2 never has one either) and, if present, recomputes the
%     real frame rate from it instead of trusting the container -- same
%     >5% disagreement warning as loadVIPLVideo.m.
%   - GROUND TRUTH: the optional GT dialog recognizes THREE formats now:
%     UBFC dataset1 (gtdump.xmp), UBFC dataset2 (ground_truth.txt), and
%     VIPL-HR's 3-file-per-video layout (gt_HR.csv + gt_SpO2.csv +
%     wave.csv all in the same folder -- click any one of the three, all
%     three get loaded together). See matlab/src/io/loadVIPLGroundTruth.m
%     for VIPL's authoritative format. VIPL's wave.csv carries no
%     timestamp column of its own; this file reconstructs one assuming a
%     CONSTANT ~60 Hz sample rate (the CONTEC CMS60C sensor's documented
%     native rate, per that same source file) -- an approximation, not a
%     measured per-sample timestamp, flagged both here and on-screen.
%
% POLARITY FIX (auto-detected, confirmed 2026-08-27): this pipeline's
% best-supported result used morphology/fixPolarityByGroundTruth.m,
% which needs a ground-truth contact-PPG trace to anchor against. A
% second file-picker dialog (Cancel-able) offers this as OPTIONAL. If
% provided and parseable (any of the three formats above), the
% ground-truth-anchored fix is used (the validated best case). If
% skipped or unparseable, this falls back to morphology/fixPolarity.m's
% skewness heuristic -- KNOWN, per that function's own header, to
% disagree with the ground-truth-anchored answer on 2/5 of this
% project's own UBFC subjects (an all-flip bias, not random scatter), so
% a heuristic-only run's polarity (and therefore its notch-position
% reading) should be treated with correspondingly less confidence than a
% ground-truth-anchored run. This is stated on-screen at runtime, not
% just here.
%
% OUTPUTS: two ON-SCREEN, INTERACTIVE MATLAB figure windows (nothing
% auto-saved to disk):
%   1. The labeled single-cycle beat prototype (systolic peak, dicrotic
%      notch [only if detected], "second wave" [only if a post-notch
%      local max exists -- pure plotting annotation, not a new detection
%      algorithm], end-of-cycle/diastolic point) -- same style as
%      results/figures/segment7_fig6_labeled_prototype_*.png.
%   2. A ~12-cardiac-cycle continuous waveform window (real time axis, no
%      beat-averaging) with systolic-peak markers for visual cycle
%      counting -- same style as
%      results/figures/segment7_fig7_multicycle_waveform_*.png.
% Per-subject notch metrics (notchDetected, position, depth, confidence,
% confidenceRaw) and pipeline diagnostics (HR, beats averaged, polarity
% method used) are printed to the Command Window.
%
% USAGE: just run this file (F5, or `run(...)` from the command line, or
% `matlab -batch` from the command line, though the -batch/-nodisplay
% forms cannot show the uigetfile dialogs or figure windows). A file
% dialog asks for the video first (UBFC .avi or a VIPL-HR video.avi
% alike), then a second (Cancel-able) dialog asks for an optional
% ground-truth file (UBFC or VIPL-HR format, auto-detected).
%
% TOOLBOX DEPENDENCIES (same as the underlying matlab/src/ functions):
% Computer Vision Toolbox (vision.CascadeObjectDetector, face detection)
% and Signal Processing Toolbox (butter, filtfilt, sgolayfilt, xcorr,
% findpeaks).
%
% ADVANCED/TESTING HOOK (optional, off by default): normal usage prompts
% via uigetfile every time. To skip the dialogs -- e.g. to verify this
% script from an automated/non-interactive run -- pre-assign
% `videoPathOverride` (and, optionally, `gtPathOverride`) as variables in
% the base workspace before running this script. Leave both unset/empty
% for the normal interactive experience.

if ~exist('videoPathOverride', 'var')
    videoPathOverride = '';
end
if ~exist('gtPathOverride', 'var')
    gtPathOverride = '';
end
automatedMode = ~isempty(videoPathOverride);

close all;

%% === Step 0: pick the video (and, optionally, a ground-truth file) ===
if automatedMode
    videoPath = videoPathOverride;
    if ~isfile(videoPath)
        error('run_segment7_single_video_demo:overrideVideoNotFound', 'videoPathOverride does not point to an existing file: %s', videoPath);
    end
    [videoDirForGtDefault, videoNameNoExt, videoExt] = fileparts(videoPath);
    videoFile = [videoNameNoExt videoExt];
else
    thisFileDir = fileparts(mfilename('fullpath'));
    projectRootGuess = fileparts(fileparts(thisFileDir));
    defaultVideoDir = fullfile(projectRootGuess, 'data', 'raw'); % parent of both UBFC-rPPG/ and VIPL-HR/
    if ~isfolder(defaultVideoDir)
        defaultVideoDir = pwd;
    end

    [videoFile, videoDir] = uigetfile( ...
        {'*.avi;*.mp4;*.mov;*.mkv', 'Video files (*.avi, *.mp4, *.mov, *.mkv)'; '*.*', 'All files'}, ...
        'Select a facial video', defaultVideoDir);

    if isequal(videoFile, 0)
        disp('No video selected -- exiting.');
        return
    end
    videoPath = fullfile(videoDir, videoFile);
    videoDirForGtDefault = videoDir;
    [~, videoNameNoExt] = fileparts(videoFile);
end

haveGT = false;
gt = [];

if automatedMode
    if ~isempty(gtPathOverride)
        if ~isfile(gtPathOverride)
            error('run_segment7_single_video_demo:overrideGtNotFound', 'gtPathOverride does not point to an existing file: %s', gtPathOverride);
        end
        gt = tryLoadGroundTruthLocal(gtPathOverride);
        haveGT = ~isempty(gt);
        if ~haveGT
            warning('run_segment7_single_video_demo:overrideGtUnparseable', 'gtPathOverride could not be parsed as either known UBFC ground-truth format -- continuing WITHOUT ground truth.');
        end
    end
else
    [gtFile, gtDir] = uigetfile( ...
        {'*.xmp;*.txt;*.csv', 'Ground-truth files (UBFC *.xmp/*.txt, VIPL-HR *.csv)'; '*.*', 'All files'}, ...
        'OPTIONAL: select a ground-truth file -- UBFC gtdump.xmp/ground_truth.txt, or VIPL-HR gt_HR.csv/gt_SpO2.csv/wave.csv (Cancel to skip)', videoDirForGtDefault);

    if ~isequal(gtFile, 0)
        gtPath = fullfile(gtDir, gtFile);
        gt = tryLoadGroundTruthLocal(gtPath);
        haveGT = ~isempty(gt);
        if ~haveGT
            warning('run_segment7_single_video_demo:gtUnparseable', 'Could not parse the selected file (or its folder) as a known ground-truth format (UBFC dataset1 gtdump.xmp, UBFC dataset2 ground_truth.txt, or VIPL-HR gt_HR.csv+gt_SpO2.csv+wave.csv) -- continuing WITHOUT ground truth.');
        end
    end
end

disp('=== Segment 7 single-video demo ===');
disp(['Video: ' videoPath]);
if haveGT
    disp(['Ground truth: provided and parsed (' gt.sourceFormat ') -- polarity will use the ground-truth-anchored fix (fixPolarityByGroundTruth), this pipeline''s validated best case.']);
    if strcmp(gt.sourceFormat, 'VIPL-HR')
        disp('  NOTE: VIPL-HR''s wave.csv has no per-sample timestamp of its own -- gt.timestamp above was reconstructed assuming a CONSTANT ~60 Hz sample rate (the documented native rate of its sensor), not measured directly. Good enough for the polarity cross-correlation, not a precision timing reference.');
    end
else
    disp('Ground truth: none -- polarity will use the skewness heuristic (fixPolarity). NOTE: that heuristic is documented to disagree with the ground-truth-anchored answer on 2/5 of this project''s own UBFC subjects (a systematic all-flip bias, not random noise) -- treat this run''s notch position/second-wave reading with correspondingly less confidence.');
end

%% === Step 1: decode video + face-detect + forehead ROI ===
try
    [frames, frameRate, numFrames] = loadVideoLocal(videoPath);
    disp(['Decoded: ' num2str(numFrames) ' frames at ' num2str(frameRate, '%.2f') ' fps.']);

    disp('Detecting face and extracting the forehead ROI (this can take a while for long videos)...');
    [R, G, B, roiTimestamps, droppedFrameIdx, ~] = extractROISignalsLocal(frames, frameRate);
    if ~isempty(droppedFrameIdx)
        disp([num2str(numel(droppedFrameIdx)) ' frame(s) used a fallback bounding box (face not (re)detected on that frame).']);
    end

    %% === Step 2: per-channel detrend ===
    [R_detrended, ~] = detrendSignalLocal(R);
    [G_detrended, ~] = detrendSignalLocal(G);
    [B_detrended, ~] = detrendSignalLocal(B);

    %% === Step 3: shared cardiac f0, from the wide-band CHROM pulse ===
    [R_wide, ~, ~] = bandpassMorphologyLocal(R_detrended, frameRate, 'wide');
    [G_wide, ~, ~] = bandpassMorphologyLocal(G_detrended, frameRate, 'wide');
    [B_wide, ~, ~] = bandpassMorphologyLocal(B_detrended, frameRate, 'wide');
    pulseWide = chromCombineLocal(R_wide, G_wide, B_wide, R, G, B);
    sharedF0Hz = fftHeartRateLocal(pulseWide, frameRate) / 60;

    %% === Step 4: adaptive harmonic-comb filter (ABPF) per channel, then CHROM ===
    [R_ahf, ~, ~] = adaptiveHarmonicFilterLocal(R_detrended, frameRate, 6, sharedF0Hz);
    [G_ahf, ~, ~] = adaptiveHarmonicFilterLocal(G_detrended, frameRate, 6, sharedF0Hz);
    [B_ahf, ~, ~] = adaptiveHarmonicFilterLocal(B_detrended, frameRate, 6, sharedF0Hz);
    pulseAdaptive = chromCombineLocal(R_ahf, G_ahf, B_ahf, R, G, B);

    %% === Step 5: polarity fix (auto-detected) ===
    if haveGT
        [pulseFixed, wasFlipped] = fixPolarityByGroundTruthLocal(pulseAdaptive, roiTimestamps, gt.ppg, gt.timestamp);
        polarityMethodStr = 'ground-truth-anchored (fixPolarityByGroundTruth)';
    else
        [pulseFixed, wasFlipped, skewValue] = fixPolarityLocal(pulseAdaptive, frameRate);
        polarityMethodStr = ['skewness heuristic (fixPolarity), skew=' num2str(skewValue, '%.4f')];
    end
    disp(['Polarity fix: ' polarityMethodStr '. Flipped: ' num2str(wasFlipped) '.']);

    %% === Step 6: uniform resample + beat ensemble average ===
    [sigUniform, ~, fsUniform] = resampleUniformLocal(pulseFixed, roiTimestamps);
    [prototype, ~, ~, beatStats] = ensembleAverageBeatsLocal(sigUniform, fsUniform);

    hrBpm = fftHeartRateLocal(sigUniform, fsUniform);
    effectiveFs = numel(prototype.trimmedMean) * (hrBpm / 60);

    %% === Step 7: IEM dicrotic-notch detection ===
    [notchDetected, notchPos, notchDepth, confidence, confidenceRaw] = notchDetectIEMLocal(prototype.trimmedMean, effectiveFs);
catch causeErr
    disp(['FAILED -- ' causeErr.message]);
    disp('(No figures were produced. Common causes: video too short/too few valid beats for ensembleAverageBeats, or the ground-truth file''s timestamps do not overlap the video''s.)');
    rethrow(causeErr);
end

%% === Console report ===
disp('--- Results ---');
disp(['Heart rate (FFT estimate): ' num2str(hrBpm, '%.2f') ' bpm']);
disp(['Beats found: ' num2str(beatStats.beatsFound) ', rejected by duration: ' num2str(beatStats.beatsRejectedByDuration) ', rejected by quality: ' num2str(beatStats.beatsRejectedByQuality) ', averaged into prototype: ' num2str(beatStats.beatsAveraged)]);
disp(['Dicrotic notch detected: ' num2str(notchDetected)]);
if notchDetected
    disp(['  Position (cycle fraction, 0-1): ' num2str(notchPos, '%.4f')]);
    disp(['  Depth (normalized to peak-to-trough range): ' num2str(notchDepth, '%.4f')]);
    disp(['  Confidence (clipped to [0,1]): ' num2str(confidence, '%.4f')]);
    disp(['  Confidence (raw, unclipped -- use this to compare against other runs, see notchDetectIEMLocal''s header): ' num2str(confidenceRaw, '%.4f')]);
    disp('  (This project''s own established bar: confidence >= 0.3 is treated as a confident detection, not just a candidate.)');
else
    disp('  (no valid notch candidate found by the IEM method on this prototype)');
end

%% === Figure 1: labeled single-cycle beat prototype ===
proto = prototype.trimmedMean;
N = numel(proto);
cycleFrac = linspace(0, 1, N);
markers = computeCycleMarkersLocal(proto, cycleFrac, notchDetected, notchPos);

displayName = strrep(videoNameNoExt, '_', '\_');

fig1Handle = figure('Name', 'Labeled beat prototype', 'NumberTitle', 'off');
ax1Handle = axes(fig1Handle);
titleLines1 = {[displayName ' -- labeled beat prototype'], ...
    'adopted-best pipeline: CHROM+wide+ABPF+polarity-fix+ensemble'};
drawLabeledPrototypeLocal(ax1Handle, cycleFrac, proto, markers, titleLines1, false);

%% === Figure 2: continuous multi-cycle waveform ===
numCyclesToShow = 12;
startOffsetSec = 5; % skip filter-startup transient at the very beginning

cycleDurationSec = 60 / hrBpm;
windowDurationSec = numCyclesToShow * cycleDurationSec;
totalDurationSec = numel(sigUniform) / fsUniform;
windowStartSec = min(startOffsetSec, max(0, totalDurationSec - windowDurationSec - 1));
if windowStartSec + windowDurationSec > totalDurationSec
    windowDurationSec = totalDurationSec - windowStartSec;
end

startSample = max(1, round(windowStartSec * fsUniform) + 1);
endSample = min(numel(sigUniform), startSample + round(windowDurationSec * fsUniform) - 1);

sigWindow = sigUniform(startSample:endSample);
timeWindow = (0:(numel(sigWindow) - 1)) / fsUniform;

minPeakDistSamples = max(1, round(0.5 * cycleDurationSec * fsUniform));
[peakVals, peakLocs] = findpeaks(sigWindow, 'MinPeakDistance', minPeakDistSamples);
peakTimes = timeWindow(peakLocs);

fig2Handle = figure('Name', 'Multi-cycle waveform', 'NumberTitle', 'off', 'Position', [100 100 1300 480]);
ax2Handle = axes(fig2Handle);
titleLines2 = {[displayName ' -- continuous rPPG waveform, ~' num2str(numel(peakVals)) ' cycles'], ...
    'adopted-best pipeline (no beat-averaging)'};
drawMultiCycleWaveformLocal(ax2Handle, timeWindow, sigWindow, peakTimes, peakVals, titleLines2, false);

disp('Done -- two figure windows opened (labeled single-cycle prototype, multi-cycle waveform).');


%% ======================================================================
%  LOCAL FUNCTIONS -- copied, unchanged in logic, from matlab/src/. See
%  each header for the pipeline stage it implements; cross-references to
%  "docs/..." and "scripts/..." below point at this project's normal
%  file layout, not files bundled inside this standalone copy.
%% ======================================================================

function gt = tryLoadGroundTruthLocal(gtPath)
% Tries UBFC's two known single-file ground-truth formats first
% (dataset1, since that is this project's main locally-available data,
% then dataset2), then falls back to checking whether the selected
% file's own FOLDER holds VIPL-HR's 3-file layout (gt_HR.csv +
% gt_SpO2.csv + wave.csv) -- so clicking any one of those three VIPL
% files is enough. Returns [] if none of the three parse into a usable
% (timestamp, ppg) pair. Not itself a copy of an existing project
% function -- added here purely so one optional file-picker dialog does
% not also have to ask the user which dataset/format they picked.
gt = [];

formatsToTry = {'dataset1', 'dataset2'};
for idx = 1:numel(formatsToTry)
    try
        candidate = loadGroundTruthLocal(gtPath, formatsToTry{idx});
        if numel(candidate.timestamp) > 1 && numel(candidate.ppg) > 1 && numel(candidate.timestamp) == numel(candidate.ppg)
            gt = candidate;
            return
        end
    catch
        % try the next format
    end
end

try
    gtFolder = fileparts(gtPath);
    hrPath = fullfile(gtFolder, 'gt_HR.csv');
    spo2Path = fullfile(gtFolder, 'gt_SpO2.csv');
    wavePath = fullfile(gtFolder, 'wave.csv');
    if isfile(hrPath) && isfile(spo2Path) && isfile(wavePath)
        candidate = loadVIPLGroundTruthLocal(hrPath, spo2Path, wavePath);
        if numel(candidate.timestamp) > 1 && numel(candidate.ppg) > 1 && numel(candidate.timestamp) == numel(candidate.ppg)
            gt = candidate;
        end
    end
catch
    gt = [];
end
end

function gt = loadGroundTruthLocal(gtPath, datasetFormat)
% LOADGROUNDTRUTH (copy) -- see matlab/src/io/loadGroundTruth.m for full
% documentation. UBFC DATASET_1's gtdump.xmp: comma-delimited, no
% header, columns [timestamp_ms, HR_bpm, SpO2_pct, PPG_raw]. UBFC
% DATASET_2's ground_truth.txt: whitespace-delimited, no header, 3 rows
% [PPG_signal; HR_bpm; timestamp_sec], no SpO2 field.
gt = struct();

if strcmp(datasetFormat, 'dataset1')
    rawData = readmatrix(gtPath, 'Delimiter', ',', 'FileType', 'text');
    gt.timestamp = rawData(:, 1) / 1000;
    gt.hr = rawData(:, 2);
    gt.spo2 = rawData(:, 3);
    gt.ppg = rawData(:, 4);
    gt.sourceFormat = 'UBFC dataset1 (gtdump.xmp)';
elseif strcmp(datasetFormat, 'dataset2')
    rawData = readmatrix(gtPath, 'FileType', 'text');
    gt.ppg = rawData(1, :);
    gt.hr = rawData(2, :);
    gt.timestamp = rawData(3, :);
    gt.spo2 = [];
    gt.sourceFormat = 'UBFC dataset2 (ground_truth.txt)';
else
    error('loadGroundTruthLocal:badFormat', 'Unknown datasetFormat "%s", expected ''dataset1'' or ''dataset2''.', datasetFormat);
end
end

function gt = loadVIPLGroundTruthLocal(hrPath, spo2Path, wavePath)
% LOADVIPLGROUNDTRUTH (adapted) -- see
% matlab/src/io/loadVIPLGroundTruth.m for the authoritative version and
% full format writeup. VIPL-HR ships ground truth as three separate
% files (gt_HR.csv, gt_SpO2.csv at 1 Hz; wave.csv, the BVP waveform, at
% its sensor's native rate), none sharing a common timestamp column.
% This demo only actually USES gt.ppg/gt.timestamp (for the polarity
% cross-correlation); gt.hr/gt.spo2 are loaded too, for parity with the
% original struct shape, but are not consumed anywhere in this file.
hrTable = readtable(hrPath);
spo2Table = readtable(spo2Path);
waveTable = readtable(wavePath);

hrValues = hrTable.HR;
spo2Values = spo2Table.SpO2;
ppgValues = waveTable.Wave;

numCommonSamples = min(numel(hrValues), numel(spo2Values));

gt = struct();
gt.hr = hrValues(1:numCommonSamples);
gt.spo2 = spo2Values(1:numCommonSamples);

% wave.csv carries NO timestamp column of its own. Per this project's
% own VIPL-HR documentation, the sensor (CONTEC CMS60C) samples at
% roughly ~60 Hz -- there is no more precise per-sample timing anywhere
% in the dataset itself, so gt.timestamp here is a CONSTANT-60-Hz
% APPROXIMATION, not a measured value. Adequate for
% fixPolarityByGroundTruthLocal's cross-correlation (which only needs
% consistent relative timing over a several-second overlap), not a
% precision timing reference for anything else.
assumedWaveFsHz = 60;
ppgRow = ppgValues(:)';
gt.ppg = ppgRow;
gt.timestamp = (0:numel(ppgRow) - 1) / assumedWaveFsHz;
gt.sourceFormat = 'VIPL-HR';
end

function [frames, frameRate, numFrames] = loadVideoLocal(videoPath)
% LOADUBFCVIDEO (copy, generalized) -- see matlab/src/io/loadUBFCVideo.m
% and matlab/src/io/loadVIPLVideo.m. Opens any video VideoReader can
% read. frameRate normally comes straight from the container
% (VideoReader.FrameRate, trustworthy for UBFC), EXCEPT when a sibling
% time.txt file sits next to the video -- VIPL-HR's source1/source3
% convention, and VIPL-HR's own ReadMe documents that its container
% frame rate is a re-encoding artifact, not the real acquisition rate
% (measured disagreement up to ~20% for some subjects). When time.txt is
% present, the real frame rate is recomputed from its per-frame
% millisecond timestamps instead, with the same >5% disagreement warning
% loadVIPLVideo.m prints. VIPL-HR's source2 has no time.txt either (a
% documented accuracy limitation for that source, not an oversight) and
% falls through to the container rate, same as UBFC.
if ~isfile(videoPath)
    error('loadVideoLocal:fileNotFound', 'Video file not found: %s', videoPath);
end
frames = VideoReader(videoPath);
containerFrameRate = frames.FrameRate;
numFrames = frames.NumFrames;

[videoFolder, ~, ~] = fileparts(videoPath);
timePath = fullfile(videoFolder, 'time.txt');

if isfile(timePath)
    frameTimestampsMs = readmatrix(timePath, 'FileType', 'text');
    numTimestamps = numel(frameTimestampsMs);

    if numTimestamps >= 2
        elapsedSec = (frameTimestampsMs(numTimestamps) - frameTimestampsMs(1)) / 1000;
        timestampFrameRate = (numTimestamps - 1) / elapsedSec;

        relativeDiff = abs(timestampFrameRate - containerFrameRate) / containerFrameRate;
        if relativeDiff > 0.05
            disp(['loadVideoLocal: WARNING -- container FrameRate (' num2str(containerFrameRate) ' fps) disagrees with a sibling time.txt-derived FrameRate (' num2str(timestampFrameRate) ' fps) by ' num2str(100 * relativeDiff, '%.1f') '%. Using the time.txt-derived value (VIPL-HR''s documented re-encoding gotcha, not a bug in this file).']);
        end

        frameRate = timestampFrameRate;
    else
        disp('loadVideoLocal: sibling time.txt found but has fewer than 2 timestamps -- falling back to the container frame rate.');
        frameRate = containerFrameRate;
    end
else
    frameRate = containerFrameRate;
end
end

function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignalsLocal(frames, frameRate)
% EXTRACTROISIGNALS (copy, forehead-only) -- see
% matlab/src/roi/extractROISignals.m for the full multi-region version
% (this copy hardcodes roiMode='forehead', the adopted-best pipeline's
% baseline ROI -- no tiling, no alternate region). Detects the largest
% Viola-Jones face bounding box every 5th frame (deliberately the
% LARGEST box, not bboxes(1,:), to avoid a real false-positive bug found
% earlier in this project -- see matlab/src/roi/extractROISignals.m's
% own history), reuses the last known-good box in between and as a
% fallback when detection fails.
detectEveryN = 5;
faceDetector = vision.CascadeObjectDetector();
frames.CurrentTime = 0;
numFrames = frames.NumFrames;

R = zeros(1, numFrames);
G = zeros(1, numFrames);
B = zeros(1, numFrames);
roiTimestamps = zeros(1, numFrames);
frameDroppedFlag = false(1, numFrames);

lastGoodBBox = [];

debugFrame = struct();
debugFrame.image = [];
debugFrame.faceBBox = [];
debugFrame.roiBBox = [];
debugFrame.frameIndex = round(numFrames / 2);

frameIdx = 0;

while hasFrame(frames)
    frameIdx = frameIdx + 1;
    if frameIdx > numFrames
        break
    end

    img = readFrame(frames);
    [frameHeight, frameWidth, ~] = size(img);

    runDetectionThisFrame = mod(frameIdx - 1, detectEveryN) == 0;

    if runDetectionThisFrame
        bboxes = step(faceDetector, img);
        if isempty(bboxes)
            frameDroppedFlag(frameIdx) = true;
            currentBBox = lastGoodBBox;
        else
            bestBBox = bboxes(1, :);
            bestArea = bboxes(1, 3) * bboxes(1, 4);
            for boxRow = 2:size(bboxes, 1)
                thisArea = bboxes(boxRow, 3) * bboxes(boxRow, 4);
                if thisArea > bestArea
                    bestArea = thisArea;
                    bestBBox = bboxes(boxRow, :);
                end
            end
            currentBBox = bestBBox;
            lastGoodBBox = currentBBox;
        end
    else
        currentBBox = lastGoodBBox;
    end

    if isempty(currentBBox)
        frameDroppedFlag(frameIdx) = true;
        currentBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
    end

    foreheadBBox = clampedBBoxLocal(currentBBox(1), currentBBox(2), currentBBox(3), currentBBox(4), 0.30, 0.70, 0.10, 0.30, frameWidth, frameHeight);

    roiPatch = img(foreheadBBox(2):foreheadBBox(2) + foreheadBBox(4), foreheadBBox(1):foreheadBBox(1) + foreheadBBox(3), :);

    R(frameIdx) = mean(double(reshape(roiPatch(:, :, 1), [], 1)));
    G(frameIdx) = mean(double(reshape(roiPatch(:, :, 2), [], 1)));
    B(frameIdx) = mean(double(reshape(roiPatch(:, :, 3), [], 1)));
    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    if frameIdx == debugFrame.frameIndex
        debugFrame.image = img;
        debugFrame.faceBBox = currentBBox;
        debugFrame.roiBBox = foreheadBBox;
        debugFrame.frameIndex = frameIdx;
    end
end

actualNumFrames = frameIdx;
if actualNumFrames < numFrames
    R = R(1:actualNumFrames);
    G = G(1:actualNumFrames);
    B = B(1:actualNumFrames);
    roiTimestamps = roiTimestamps(1:actualNumFrames);
    frameDroppedFlag = frameDroppedFlag(1:actualNumFrames);
end

droppedFrameIdx = find(frameDroppedFlag);

if isempty(debugFrame.image)
    debugFrame.image = img;
    debugFrame.faceBBox = currentBBox;
    debugFrame.roiBBox = foreheadBBox;
    debugFrame.frameIndex = frameIdx;
end
end

function bbox = clampedBBoxLocal(faceX, faceY, faceW, faceH, xFracLo, xFracHi, yFracLo, yFracHi, frameWidth, frameHeight)
x1 = max(1, round(faceX + xFracLo * faceW));
x2 = min(frameWidth, round(faceX + xFracHi * faceW));
y1 = max(1, round(faceY + yFracLo * faceH));
y2 = min(frameHeight, round(faceY + yFracHi * faceH));
bbox = [x1, y1, x2 - x1, y2 - y1];
end

function [signalDetrended, detrendOrder] = detrendSignalLocal(signalRaw, polyOrder)
% DETRENDSIGNAL (copy) -- see matlab/src/filtering/detrendSignal.m.
if nargin < 2
    polyOrder = 3;
end
detrendOrder = polyOrder;
signalDetrended = detrend(signalRaw, detrendOrder);
end

function [sigFiltered, filterOrder, bandUsed] = bandpassMorphologyLocal(sigDetrended, frameRate, bandMode)
% BANDPASSMORPHOLOGY (copy) -- see matlab/src/morphology/bandpassMorphology.m.
if nargin < 3 || isempty(bandMode)
    bandMode = 'wide';
end
switch bandMode
    case 'wide'
        lowCutoffHz = 0.5;
        highCutoffHz = 8.0;
    case 'mid'
        lowCutoffHz = 0.6;
        highCutoffHz = 6.0;
    case 'legacy'
        lowCutoffHz = 0.7;
        highCutoffHz = 4.0;
    otherwise
        error('bandpassMorphologyLocal:badBandMode', 'bandMode must be one of ''wide'', ''mid'', ''legacy'' (got %s).', bandMode);
end

filterOrder = 3;
nyquistHz = frameRate / 2;

if highCutoffHz >= nyquistHz
    error('bandpassMorphologyLocal:cutoffAboveNyquist', 'highCutoffHz (%.2f Hz) for bandMode ''%s'' is at or above the Nyquist frequency (%.2f Hz) for frameRate %.2f Hz.', highCutoffHz, bandMode, nyquistHz, frameRate);
end

lowCutoffNormalized = lowCutoffHz / nyquistHz;
highCutoffNormalized = highCutoffHz / nyquistHz;

[filterCoeffB, filterCoeffA] = butter(filterOrder, [lowCutoffNormalized, highCutoffNormalized], 'bandpass');
sigFiltered = filtfilt(filterCoeffB, filterCoeffA, sigDetrended);

bandUsed = [lowCutoffHz, highCutoffHz];
end

function pulseSignal = chromCombineLocal(R, G, B, RRaw, GRaw, BRaw)
% CHROMCOMBINE (copy) -- see matlab/src/pulseextraction/chromCombine.m.
meanRRaw = mean(RRaw);
meanGRaw = mean(GRaw);
meanBRaw = mean(BRaw);

Rn = R / meanRRaw;
Gn = G / meanGRaw;
Bn = B / meanBRaw;

Xs = 3 * Rn - 2 * Gn;
Ys = 1.5 * Rn + Gn - 1.5 * Bn;

alpha = std(Xs) / std(Ys);
pulseSignal = Xs - alpha * Ys;
end

function [hrBpm, freqSpectrum, powerSpectrum] = fftHeartRateLocal(pulseSignal, frameRate)
% FFTHEARTRATE (copy) -- see matlab/src/heartrate/fftHeartRate.m.
signalLength = length(pulseSignal);
fftResult = fft(pulseSignal);

numPositiveBins = floor(signalLength / 2) + 1;
fftPositive = fftResult(1:numPositiveBins);

freqResolution = frameRate / signalLength;
freqSpectrum = (0:numPositiveBins - 1) * freqResolution;
powerSpectrum = abs(fftPositive);

lowBandHz = 0.7;
highBandHz = 4.0;
bandMask = freqSpectrum >= lowBandHz & freqSpectrum <= highBandHz;

freqInBand = freqSpectrum(bandMask);
powerInBand = powerSpectrum(bandMask);

if isempty(freqInBand)
    error('fftHeartRateLocal:emptyBand', 'No FFT bins fall inside the 0.7-4 Hz band -- signal too short for the given frameRate.');
end

peakPower = max(powerInBand);
peakIndex = find(powerInBand == peakPower, 1);
peakFreqHz = freqInBand(peakIndex);

hrBpm = peakFreqHz * 60;
end

function [sigFiltered, f0Hz, harmonicsUsedHz] = adaptiveHarmonicFilterLocal(sigDetrended, frameRate, numHarmonics, f0HzOverride)
% ADAPTIVEHARMONICFILTER (copy) -- see
% matlab/src/morphology/adaptiveHarmonicFilter.m.
if nargin < 3 || isempty(numHarmonics)
    numHarmonics = 6;
end
if nargin < 4
    f0HzOverride = [];
end

sigRow = sigDetrended(:)';
N = numel(sigRow);

if isempty(f0HzOverride)
    hrBpm = fftHeartRateLocal(sigRow, frameRate);
    f0Hz = hrBpm / 60;
else
    f0Hz = f0HzOverride;
end

freqResolution = frameRate / N;
nyquistBinIdx = floor(N / 2) + 1;

fullFFT = fft(sigRow);
mask = zeros(1, N);
harmonicsUsedHz = [];

for h = 1:numHarmonics
    harmonicFreqHz = h * f0Hz;
    centerBinIdx = round(harmonicFreqHz / freqResolution) + 1;

    if centerBinIdx > nyquistBinIdx
        continue
    end

    harmonicsUsedHz(end + 1) = harmonicFreqHz; %#ok<AGROW>

    for offset = -1:1
        binIdx = centerBinIdx + offset;
        if binIdx < 2 || binIdx > nyquistBinIdx
            continue
        end
        mask(binIdx) = 1;
        mirrorBinIdx = N - binIdx + 2;
        if mirrorBinIdx >= 1 && mirrorBinIdx <= N
            mask(mirrorBinIdx) = 1;
        end
    end
end

filteredFFT = fullFFT .* mask;
sigFiltered = real(ifft(filteredFFT));
end

function [sigOriented, wasFlipped] = fixPolarityByGroundTruthLocal(sig, sigTimestamps, gtPPG, gtTimestamps)
% FIXPOLARITYBYGROUNDTRUTH (copy) -- see
% matlab/src/morphology/fixPolarityByGroundTruth.m.
sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';
gtPPGRow = gtPPG(:)';
gtTimestampsRow = gtTimestamps(:)';

overlapLowSec = max(sigTimestampsRow(1), gtTimestampsRow(1));
overlapHighSec = min(sigTimestampsRow(end), gtTimestampsRow(end));

if overlapHighSec <= overlapLowSec
    error('fixPolarityByGroundTruthLocal:noOverlap', 'sigTimestamps and gtTimestamps do not overlap in time -- cannot align rPPG and ground-truth PPG.');
end

overlapMask = sigTimestampsRow >= overlapLowSec & sigTimestampsRow <= overlapHighSec;

sigOverlap = sigRow(overlapMask);
sigTimestampsOverlap = sigTimestampsRow(overlapMask);

gtResampled = interp1(gtTimestampsRow, gtPPGRow, sigTimestampsOverlap, 'pchip');

sigZeroMean = sigOverlap - mean(sigOverlap);
gtZeroMean = gtResampled - mean(gtResampled);

xcorrPositive = xcorr(sigZeroMean, gtZeroMean);
xcorrNegative = xcorr(-sigZeroMean, gtZeroMean);

maxPositive = max(xcorrPositive);
maxNegative = max(xcorrNegative);

wasFlipped = maxNegative > maxPositive;

if wasFlipped
    sigOriented = -sig;
else
    sigOriented = sig;
end
end

function [sigOriented, wasFlipped, skewValue] = fixPolarityLocal(sig, frameRate)
% FIXPOLARITY (copy) -- see matlab/src/morphology/fixPolarity.m. CAVEAT
% (from that file's own header, restated here): measured on this
% project's 5 UBFC subjects, this heuristic disagreed with the
% ground-truth-anchored rule on 2/5 -- an all-flip bias, not scatter.
% Kept as the documented no-ground-truth fallback, not a silent default.
minDurationSec = 10;

if numel(sig) / frameRate < minDurationSec
    error('fixPolarityLocal:tooShort', 'sig must cover at least %.0f s of data (got %.2f s at %.2f Hz) -- skewness over a shorter window is not reliable enough to anchor polarity.', minDurationSec, numel(sig) / frameRate, frameRate);
end

sigRow = sig(:)';
N = numel(sigRow);
sigMean = mean(sigRow);
sigCentered = sigRow - sigMean;

populationStd = sqrt(sum(sigCentered.^2) / N);
thirdMoment = sum(sigCentered.^3) / N;

skewValue = thirdMoment / (populationStd^3);
wasFlipped = skewValue < 0;

if wasFlipped
    sigOriented = -sig;
else
    sigOriented = sig;
end
end

function [sigUniform, timeUniform, targetFs] = resampleUniformLocal(sig, sigTimestamps, targetFs)
% RESAMPLEUNIFORM (copy) -- see matlab/src/morphology/resampleUniform.m.
if nargin < 3 || isempty(targetFs)
    targetFs = 250;
end

sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';

if numel(sigRow) ~= numel(sigTimestampsRow)
    error('resampleUniformLocal:sizeMismatch', 'sig and sigTimestamps must have the same number of elements.');
end

timeUniform = sigTimestampsRow(1):(1 / targetFs):sigTimestampsRow(end);
sigUniform = interp1(sigTimestampsRow, sigRow, timeUniform, 'pchip');
end

function [prototype, iqrBand, beatMatrix, stats] = ensembleAverageBeatsLocal(sig, fs, opts)
% ENSEMBLEAVERAGEBEATS (copy) -- see
% matlab/src/morphology/ensembleAverageBeats.m.
if nargin < 3 || isempty(opts)
    opts = struct();
end

opts = applyDefaultLocal(opts, 'beatSamples', 256);
opts = applyDefaultLocal(opts, 'systolicAnchorFraction', 0.25);
opts = applyDefaultLocal(opts, 'durationRejectFraction', 0.30);
opts = applyDefaultLocal(opts, 'qualityKeepFraction', 0.25);
opts = applyDefaultLocal(opts, 'trimPercent', 20);

sigRow = sig(:)';
N = numel(sigRow);
timeAxis = (0:N - 1) / fs;

sigZeroMean = sigRow - mean(sigRow);

crossingTimes = [];
for i = 1:(N - 1)
    if sigZeroMean(i) >= 0 && sigZeroMean(i + 1) < 0
        frac = sigZeroMean(i) / (sigZeroMean(i) - sigZeroMean(i + 1));
        crossingTimes(end + 1) = timeAxis(i) + frac * (timeAxis(i + 1) - timeAxis(i)); %#ok<AGROW>
    end
end

numBeatsFound = numel(crossingTimes) - 1;

if numBeatsFound < 3
    error('ensembleAverageBeatsLocal:tooFewBeats', 'Only %d beat(s) found from negative-going zero crossings -- need at least 3 to form an ensemble average.', max(numBeatsFound, 0));
end

beatDurations = diff(crossingTimes);
medianDuration = median(beatDurations);

durationOkMask = abs(beatDurations - medianDuration) / medianDuration <= opts.durationRejectFraction;
beatsRejectedByDuration = sum(~durationOkMask);

survivingBeatIdx = find(durationOkMask);
numSurviving = numel(survivingBeatIdx);

if numSurviving < 2
    error('ensembleAverageBeatsLocal:tooFewBeatsAfterDurationGate', 'Only %d beat(s) survived the duration gate -- need at least 2 to form an ensemble average.', numSurviving);
end

beatSamples = opts.beatSamples;
beatMatrixResampled = zeros(numSurviving, beatSamples);

for rowIdx = 1:numSurviving
    k = survivingBeatIdx(rowIdx);
    t0 = crossingTimes(k);
    t1 = crossingTimes(k + 1);
    queryTimes = linspace(t0, t1, beatSamples);
    beatMatrixResampled(rowIdx, :) = interp1(timeAxis, sigRow, queryTimes, 'pchip');
end

targetFrac = linspace(0, 1, beatSamples);
origFrac = linspace(0, 1, beatSamples);
peakAnchorFrac = opts.systolicAnchorFraction;

beatMatrixWarped = zeros(numSurviving, beatSamples);

for rowIdx = 1:numSurviving
    beatValues = beatMatrixResampled(rowIdx, :);
    [~, peakIdx] = max(beatValues);
    peakFracOrig = origFrac(peakIdx);

    if peakFracOrig <= 0 || peakFracOrig >= 1
        beatMatrixWarped(rowIdx, :) = beatValues;
        continue
    end

    newFrac = zeros(1, beatSamples);
    firstLeg = origFrac <= peakFracOrig;
    secondLeg = ~firstLeg;

    newFrac(firstLeg) = origFrac(firstLeg) * (peakAnchorFrac / peakFracOrig);
    newFrac(secondLeg) = peakAnchorFrac + (origFrac(secondLeg) - peakFracOrig) * ((1 - peakAnchorFrac) / (1 - peakFracOrig));

    beatMatrixWarped(rowIdx, :) = interp1(newFrac, beatValues, targetFrac, 'pchip');
end

roughTemplate = mean(beatMatrixWarped, 1);

correlations = zeros(numSurviving, 1);
for rowIdx = 1:numSurviving
    correlations(rowIdx) = pearsonCorrRowLocal(beatMatrixWarped(rowIdx, :), roughTemplate);
end

[~, sortOrder] = sort(correlations, 'descend');
numKeep = max(1, ceil(numSurviving * opts.qualityKeepFraction));
keepIdx = sortOrder(1:numKeep);

beatsRejectedByQuality = numSurviving - numKeep;
beatMatrix = beatMatrixWarped(keepIdx, :);

prototype = struct();
prototype.trimmedMean = trimmean(beatMatrix, opts.trimPercent, 1);
prototype.median = median(beatMatrix, 1);

q1 = zeros(1, beatSamples);
q3 = zeros(1, beatSamples);
for colIdx = 1:beatSamples
    q1(colIdx) = localPercentileLocal(beatMatrix(:, colIdx), 25);
    q3(colIdx) = localPercentileLocal(beatMatrix(:, colIdx), 75);
end

iqrBand = struct();
iqrBand.q1 = q1;
iqrBand.q3 = q3;
iqrBand.width = q3 - q1;
iqrBand.meanWidth = mean(iqrBand.width);

prototypeRange = max(prototype.trimmedMean) - min(prototype.trimmedMean);
if prototypeRange > 0
    iqrBand.meanWidthNormalized = iqrBand.meanWidth / prototypeRange;
else
    iqrBand.meanWidthNormalized = NaN;
end

stats = struct();
stats.beatsFound = numBeatsFound;
stats.beatsRejectedByDuration = beatsRejectedByDuration;
stats.beatsRejectedByQuality = beatsRejectedByQuality;
stats.beatsAveraged = size(beatMatrix, 1);
stats.snrGainEstimate = sqrt(stats.beatsAveraged);
end

function opts = applyDefaultLocal(opts, fieldName, defaultValue)
if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
    opts.(fieldName) = defaultValue;
end
end

function r = pearsonCorrRowLocal(x, y)
xc = x - mean(x);
yc = y - mean(y);
r = sum(xc .* yc) / sqrt(sum(xc.^2) * sum(yc.^2));
end

function p = localPercentileLocal(columnData, percentile)
sortedData = sort(columnData(:));
n = numel(sortedData);

if n == 1
    p = sortedData(1);
    return
end

position = 1 + (percentile / 100) * (n - 1);
lowerIdx = floor(position);
upperIdx = ceil(position);
weight = position - lowerIdx;

p = sortedData(lowerIdx) * (1 - weight) + sortedData(upperIdx) * weight;
end

function [notchDetected, notchPositionNormalized, notchDepth, confidence, confidenceRaw] = notchDetectIEMLocal(prototype, fs)
% NOTCHDETECTIEM (copy) -- see matlab/src/morphology/notchDetectIEM.m for
% the full algorithm writeup, references, and confidence/confidenceRaw
% documentation.
betaStopThreshold = 0.1;
maxIterations = 20;
sgPolyOrder = 4;
sgFrameLen = 25;
minGapSec = 0.1;

protoRow = prototype(:)';
N = numel(protoRow);

protoRange = max(protoRow) - min(protoRow);
if protoRange <= 0
    error('notchDetectIEMLocal:flatSignal', 'prototype is constant -- cannot normalize or detect a notch.');
end
protoNorm = (protoRow - min(protoRow)) / protoRange;

frameLen = min(sgFrameLen, N);
if mod(frameLen, 2) == 0
    frameLen = frameLen - 1;
end
frameLen = max(frameLen, sgPolyOrder + 1 + mod(sgPolyOrder + 1, 2));
frameLen = min(frameLen, N - (1 - mod(N, 2)));

currentSignal = protoNorm;
previousResidualVar = var(currentSignal);
finalResidual = currentSignal;

for iterIdx = 1:maxIterations
    smoothed = sgolayfilt(currentSignal, sgPolyOrder, frameLen);

    firstDeriv = gradient(smoothed);
    secondDeriv = gradient(firstDeriv);

    upperAnchors = [1, N];
    lowerAnchors = [1, N];

    for i = 1:(N - 1)
        if secondDeriv(i) >= 0 && secondDeriv(i + 1) < 0
            upperAnchors(end + 1) = i; %#ok<AGROW>
        elseif secondDeriv(i) < 0 && secondDeriv(i + 1) >= 0
            lowerAnchors(end + 1) = i; %#ok<AGROW>
        end
    end

    upperAnchors = unique(upperAnchors);
    lowerAnchors = unique(lowerAnchors);

    upperEnvelope = interp1(upperAnchors, currentSignal(upperAnchors), 1:N, 'pchip');
    lowerEnvelope = interp1(lowerAnchors, currentSignal(lowerAnchors), 1:N, 'pchip');

    meanEnvelope = (upperEnvelope + lowerEnvelope) / 2;
    residual = currentSignal - meanEnvelope;

    residualVar = var(residual);
    finalResidual = residual;

    if abs(previousResidualVar - residualVar) < betaStopThreshold
        break
    end

    previousResidualVar = residualVar;
    currentSignal = residual;
end

[~, peakIdx] = max(protoNorm);
minGapSamples = max(round(minGapSec * fs), 1);
searchStart = peakIdx + minGapSamples;

notchDetected = false;
notchIdx = NaN;

for i = max(searchStart, 2):(N - 1)
    isLocalMin = finalResidual(i - 1) > finalResidual(i) && finalResidual(i) < finalResidual(i + 1);
    if isLocalMin && finalResidual(i) < 0
        notchDetected = true;
        notchIdx = i;
        break
    end
end

if notchDetected
    notchPositionNormalized = (notchIdx - 1) / (N - 1);

    shoulderValue = max(protoNorm(peakIdx:notchIdx));
    notchDepth = (shoulderValue - protoNorm(notchIdx)) / (max(protoNorm) - min(protoNorm));

    residualStd = std(finalResidual);
    confidenceRaw = abs(finalResidual(notchIdx)) / (residualStd + eps);
    confidence = min(1, confidenceRaw);
else
    notchPositionNormalized = NaN;
    notchDepth = NaN;
    confidence = 0;
    confidenceRaw = 0;
end
end

function markers = computeCycleMarkersLocal(proto, cycleFrac, notchDetected, notchPositionNormalized)
% Pure plotting-annotation helper -- see
% scripts/run_segment7_fig6_labeled_prototype_batch.m's
% computeCycleMarkers for the full rationale (identical logic here).
N = numel(proto);

[~, sysIdx] = min(abs(cycleFrac - 0.25));
markers.systolic.idx = sysIdx;
markers.systolic.x = cycleFrac(sysIdx);
markers.systolic.y = proto(sysIdx);

markers.diastolicEnd.idx = N;
markers.diastolicEnd.x = cycleFrac(N);
markers.diastolicEnd.y = proto(N);

markers.notch.found = logical(notchDetected);
if markers.notch.found
    notchIdx = round(notchPositionNormalized * (N - 1)) + 1;
    notchIdx = min(max(notchIdx, 1), N);
    markers.notch.idx = notchIdx;
    markers.notch.x = cycleFrac(notchIdx);
    markers.notch.y = proto(notchIdx);
else
    markers.notch.idx = NaN;
    markers.notch.x = NaN;
    markers.notch.y = NaN;
end

markers.secondWave.found = false;
markers.secondWave.idx = NaN;
markers.secondWave.x = NaN;
markers.secondWave.y = NaN;
if markers.notch.found
    for j = (markers.notch.idx + 1):(N - 1)
        if proto(j - 1) < proto(j) && proto(j) > proto(j + 1)
            markers.secondWave.found = true;
            markers.secondWave.idx = j;
            markers.secondWave.x = cycleFrac(j);
            markers.secondWave.y = proto(j);
            break
        end
    end
end
end

function drawLabeledPrototypeLocal(axHandle, cycleFrac, proto, markers, titleStr, compact)
% Plots the trimmed-mean prototype with small labeled markers at the four
% cycle landmarks -- see
% scripts/run_segment7_fig6_labeled_prototype_batch.m's
% drawLabeledPrototype (identical logic here).
axes(axHandle); %#ok<LAXES>
hold(axHandle, 'on');

plot(axHandle, cycleFrac, proto, 'LineWidth', 1.8, 'Color', [0.15 0.25 0.55]);

if compact
    markerSize = 6;
    fontSize = 7;
    labelDy = 0.06 * range(proto);
else
    markerSize = 9;
    fontSize = 10;
    labelDy = 0.05 * range(proto);
end

plot(axHandle, markers.systolic.x, markers.systolic.y, 'o', 'MarkerSize', markerSize, ...
    'MarkerFaceColor', [0.85 0.20 0.20], 'MarkerEdgeColor', 'k');
text(axHandle, markers.systolic.x, markers.systolic.y + labelDy, 'Systolic peak', ...
    'FontSize', fontSize, 'HorizontalAlignment', 'center', 'Color', [0.85 0.20 0.20]);

if markers.notch.found
    plot(axHandle, markers.notch.x, markers.notch.y, 'v', 'MarkerSize', markerSize, ...
        'MarkerFaceColor', [0.95 0.60 0.10], 'MarkerEdgeColor', 'k');
    text(axHandle, markers.notch.x, markers.notch.y - labelDy, 'Dicrotic notch', ...
        'FontSize', fontSize, 'HorizontalAlignment', 'center', 'Color', [0.80 0.50 0.05]);
end

if markers.secondWave.found
    plot(axHandle, markers.secondWave.x, markers.secondWave.y, '^', 'MarkerSize', markerSize, ...
        'MarkerFaceColor', [0.20 0.55 0.30], 'MarkerEdgeColor', 'k');
    text(axHandle, markers.secondWave.x, markers.secondWave.y + labelDy, 'Second wave', ...
        'FontSize', fontSize, 'HorizontalAlignment', 'center', 'Color', [0.15 0.45 0.25]);
end

plot(axHandle, markers.diastolicEnd.x, markers.diastolicEnd.y, 's', 'MarkerSize', markerSize, ...
    'MarkerFaceColor', [0.30 0.30 0.30], 'MarkerEdgeColor', 'k');
text(axHandle, markers.diastolicEnd.x, markers.diastolicEnd.y + labelDy, 'Diastolic end', ...
    'FontSize', fontSize, 'HorizontalAlignment', 'right', 'Color', [0.25 0.25 0.25]);

hold(axHandle, 'off');
xlabel(axHandle, 'Cycle fraction (systolic peak anchored at 0.25)');
ylabel(axHandle, 'Pulse amplitude (a.u.)');
title(axHandle, titleStr, 'Interpreter', 'none');
xlim(axHandle, [0 1]);
box(axHandle, 'on');
end

function drawMultiCycleWaveformLocal(axHandle, timeWindow, sigWindow, peakTimes, peakVals, titleStr, compact)
% Plots a continuous multi-cycle waveform segment with systolic-peak
% markers -- see
% scripts/run_segment7_fig7_multicycle_waveform_batch.m's
% drawMultiCycleWaveform (identical logic here).
axes(axHandle); %#ok<LAXES>
hold(axHandle, 'on');
plot(axHandle, timeWindow, sigWindow, 'LineWidth', 1.3, 'Color', [0.15 0.25 0.55]);
if compact
    markerSize = 5;
    fontSize = 8;
else
    markerSize = 7;
    fontSize = 10;
end
plot(axHandle, peakTimes, peakVals, 'o', 'MarkerSize', markerSize, ...
    'MarkerFaceColor', [0.85 0.20 0.20], 'MarkerEdgeColor', 'k', 'LineStyle', 'none');
hold(axHandle, 'off');
xlabel(axHandle, 'Time (s)');
ylabel(axHandle, 'Pulse amplitude (a.u.)');
title(axHandle, titleStr, 'Interpreter', 'none', 'FontSize', fontSize + 2);
set(axHandle, 'FontSize', fontSize);
xlim(axHandle, [timeWindow(1), timeWindow(end)]);
box(axHandle, 'on');
end
