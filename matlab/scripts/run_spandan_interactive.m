% RUN_SPANDAN_INTERACTIVE Interactive, single-video demo driver: pops a
% uigetfile dialog, lets the user pick ANY video file, auto-detects which
% of three input classes it belongs to (UBFC-style with continuous ground
% truth / VIPL-style / arbitrary with no ground truth), runs the full
% pipeline via pipeline/estimateVitalsAndMorphology.m, and shows ONE
% combined figure + numeric summary on screen. Nothing is saved to disk
% by default -- this is an interactive look-and-inspect tool, not a batch
% pipeline.
%
% Does NOT modify estimateVitalsAndMorphology.m, extractROISignals.m,
% bandpassClean.m, bandpassMorphology.m, adaptiveHarmonicFilter.m,
% chromCombine.m, posCombine.m, fftHeartRate.m, ratioOfRatios.m,
% calibrateSpO2.m, ensembleAverageBeats.m, notchDetectIEM.m, fixPolarity.m,
% fixPolarityByGroundTruth.m, resampleUniform.m, runLOSO.m,
% computeMetrics.m, or run_spandan_full_demo.m -- this file only calls
% those (unmodified) functions.
%
% FIGURE LAYOUT NOTE: the 3x2 tiledlayout below (raw ROI trace / production
% CHROM pulse with HR / single-cycle morphology prototype with IQR band +
% notch marker / multi-cycle continuous waveform (NEW, Segment 8
% follow-up) / text summary panel spanning the bottom row) deliberately
% mirrors run_spandan_full_demo.m's own renderSpandanDemoFigure layout by
% design (same panel order, same visual conventions) -- it is NOT
% re-derived from scratch. It is a SEPARATE implementation
% (renderInteractiveFigure below, including its own local copy of
% extractMultiCycleWindow) rather than a call into that script's function
% because MATLAB script-local functions are only callable from within the
% SAME script's own execution and cannot be imported or called from a
% different file -- sharing it would require modifying
% run_spandan_full_demo.m, which is out of scope for this task. This
% version additionally supports a 6th, optional ground-truth-PPG-overlay
% region (Case 1 only) and a fallback message on BOTH the single-cycle and
% multi-cycle panels when Branch 2 fails on a too-short clip (see the
% too-few-beats guardrail below), neither of which run_spandan_full_demo.m
% needed since it only ever runs on Branch-2-safe UBFC clips.
%
% CASE DETECTION (by files found next to the picked video, never asked of
% the user):
%   Case 1 -- UBFC-style, continuous ground truth: gtdump.xmp (dataset1
%             format) or ground_truth.txt (dataset2 format) sits next to
%             the picked video. Uses io/loadGroundTruth.m,
%             fixPolarityByGroundTruth.m (via estimateVitalsAndMorphology's
%             own groundTruth argument), and shows a ground-truth PPG
%             overlay + ground-truth HR/SpO2 numbers.
%   Case 2 -- VIPL-style: the picked path matches
%             .../p<N>/v<N>/source<N>/video.avi AND gt_HR.csv + gt_SpO2.csv
%             sit next to it. Uses io/loadVIPLVideo.m (NOT loadUBFCVideo.m
%             -- corrects frameRate against time.txt) and
%             io/loadVIPLGroundTruth.m for a ground-truth HR/SpO2
%             comparison; the heuristic fixPolarity.m is used for Branch 2
%             (groundTruth=[] is passed) because VIPL's gt.ppg is
%             explicitly not usable as a continuous, aligned overlay (see
%             io/loadVIPLGroundTruth.m's own header) -- resampling it to
%             make it usable is out of scope here.
%   Case 3 -- arbitrary video, no ground truth found by either check
%             above: io/loadUBFCVideo.m (a generic VideoReader wrapper
%             despite its name) + groundTruth=[] + calibParams=[], so
%             spo2Pct is NaN and is reported plainly as "not calibrated,
%             no reference available" rather than a fabricated number.
%
% SpO2 CALIBRATION: for Case 1 only, this script attempts a leave-one-out
% linear calibration (spo2/calibrateSpO2.m, unmodified) using whichever OF
% the OTHER cached UBFC DATASET_1 subjects' data/processed/<id>_rgb_traces.mat
% files exist on disk (the picked subject's own file, if it matches one of
% those IDs, is excluded from the training set -- never fit and predict on
% the same subject). If fewer than 2 other cached subjects are available,
% or the picked video is not a recognized UBFC DATASET_1 subject at all,
% calibration is skipped and spo2Pct is left as NaN with a clear on-figure
% label -- this is an acceptable minimum per this task's brief. Cases 2
% and 3 never attempt calibration (calibParams=[] always) --
% pipeline/estimateVitalsAndMorphology.m never fits its own calibration by
% design (see its own header / spo2/calibrateSpO2.m's header).
%
% GUARDRAILS:
%   - Too-few-beats (ensembleAverageBeats:tooFewBeats /
%     ensembleAverageBeats:tooFewBeatsAfterDurationGate): estimateVitals-
%     AndMorphology.m runs Branch 1 then Branch 2 sequentially in one
%     function, so a Branch-2 error() aborts the whole call and would
%     otherwise lose Branch 1's already-good HR/SpO2 too. This script
%     wraps the call in try/catch; on either of those two identifiers it
%     recomputes JUST Branch 1 inline, replicating
%     estimateVitalsAndMorphology.m's own Branch-1 sequence
%     (detrendSignal -> bandpassClean -> chromCombine/posCombine ->
%     fftHeartRate; ratioOfRatios -> calibrateSpO2 if calibParams
%     available) using the SAME unmodified functions, then still shows
%     HR/SpO2 with the morphology panel replaced by a clear text note.
%     Any other error identifier is re-thrown.
%   - Unreliable face detection: after extractROISignals.m, if
%     numel(droppedFrameIdx)/numFrames exceeds 30%, a clear warning is
%     printed and shown on the figure.
%   - Case 3 scalar-frame-rate mismatch (checkFrameRateMismatch below):
%     Case 3 has no sidecar metadata to correct VideoReader.FrameRate
%     against the way io/loadVIPLVideo.m does for VIPL source1/source3/
%     source4 (see docs/VIPL_DATA_FORMAT.md Section 4 -- a real 52.1-vs-
%     ~63-bpm error was traced to exactly this: a container fps that does
%     not reflect true acquisition timing). A freshly recorded phone clip
%     is frequently variable-frame-rate and exposed to the same failure
%     mode. This script compares VideoReader.FrameRate against
%     NumFrames/Duration; if they disagree by more than ~3%, it prints and
%     shows an on-figure warning that the reported HR may carry a
%     proportional scale error. It does NOT silently "correct" frameRate
%     -- there is no reliable ground truth for an arbitrary video, so this
%     warns rather than guesses.
%   - Large/long videos: never calls read(videoReaderObj) or otherwise
%     pre-buffers frames; relies entirely on the existing
%     hasFrame/readFrame streaming already inside loadUBFCVideo.m/
%     loadVIPLVideo.m + extractROISignals.m.
%
% Usage:
%   run_spandan_interactive            % pops uigetfile, shows the figure
%
% The core "given a resolved videoPath, do everything" logic lives in the
% local function runSpandanInteractiveCore(videoPath, exportPngPath) below
% specifically so it can be invoked directly with a hardcoded path for
% testing (see the throwaway smoke-test script used to verify this file,
% not committed as part of this repo) without needing to click through a
% uigetfile dialog. exportPngPath is optional and ONLY for that testing
% use (exportgraphics to a PNG in addition to showing the on-screen
% figure) -- the normal interactive path below never passes it, and the
% figure this function creates is always a normal visible figure(), never
% 'Visible','off'.

[pickedFile, pickedPath] = uigetfile( ...
    {'*.avi;*.mp4;*.mov;*.mkv', 'Video files (*.avi,*.mp4,*.mov,*.mkv)'; '*.*', 'All Files (*.*)'}, ...
    'Select a video for the Spandan pipeline');

if isequal(pickedFile, 0)
    disp('run_spandan_interactive: no file selected, exiting.');
    return;
end

videoPath = fullfile(pickedPath, pickedFile);

runSpandanInteractiveCore(videoPath);

function result = runSpandanInteractiveCore(videoPath, exportPngPath)
% RUNSPANDANINTERACTIVECORE Given a resolved video path, detect its input
% class, run the pipeline, render the combined figure, and return the
% result struct (mainly so a caller/test can inspect it). exportPngPath is
% optional (testing only, see header above).

if nargin < 2
    exportPngPath = '';
end

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));

videoDir = fileparts(videoPath);

% === Case detection ===
gtdumpPath = fullfile(videoDir, 'gtdump.xmp');
groundTruthTxtPath = fullfile(videoDir, 'ground_truth.txt');

% VIPL-style path pattern: .../p<N>/v<N>/source<N>/video.avi
viplTokens = regexp(strrep(videoPath, '\', '/'), '/p(\d+)/v(\d+)/source(\d+)/[^/]+$', 'tokens', 'once');
viplGtHRPath = fullfile(videoDir, 'gt_HR.csv');
viplGtSpO2Path = fullfile(videoDir, 'gt_SpO2.csv');
isVIPLCase = ~isempty(viplTokens) && isfile(viplGtHRPath) && isfile(viplGtSpO2Path);

if isfile(gtdumpPath)
    caseID = 1;
    gtFormat = 'dataset1';
    gtPath = gtdumpPath;
elseif isfile(groundTruthTxtPath)
    caseID = 1;
    gtFormat = 'dataset2';
    gtPath = groundTruthTxtPath;
elseif isVIPLCase
    caseID = 2;
else
    caseID = 3;
end

disp(['run_spandan_interactive: selected video: ' videoPath]);
disp(['run_spandan_interactive: detected case ' num2str(caseID) ' (' caseDescription(caseID) ')']);

groundTruthOverlay = []; % Case 1 only: struct with .ppg/.timestamp for the overlay panel
gtHRTrue = NaN;
gtSpO2True = NaN;
calibParams = [];
faceDropWarning = '';
fpsMismatchWarning = ''; % Case 3 only -- see checkFrameRateMismatch below
subjectLabel = pickedLabel(videoPath);

switch caseID
    case 1
        % --- UBFC-style: continuous ground truth available. ---
        gt = loadGroundTruth(gtPath, gtFormat);

        [frames, frameRate, numFrames] = loadUBFCVideo(videoPath);
        [R, G, B, roiTimestamps, droppedFrameIdx, ~] = extractROISignals(frames, frameRate, 'forehead');

        faceDropWarning = checkFaceDropRate(droppedFrameIdx, numFrames);

        videoInputStruct = struct('R', R, 'G', G, 'B', B, 'fs', frameRate, 'roiTimestamps', roiTimestamps);

        groundTruthOverlay = struct('ppg', gt.ppg, 'timestamp', gt.timestamp);

        videoDurationSec = numel(R) / frameRate;
        inClipMask = gt.timestamp <= videoDurationSec;
        gtHRTrue = mean(gt.hr(inClipMask));
        if strcmp(gtFormat, 'dataset1')
            gtSpO2True = mean(gt.spo2(inClipMask));
        else
            gtSpO2True = NaN; % dataset2 has no SpO2 field
        end

        calibParams = tryFitCaseOneCalibration(projectRoot, subjectLabel);

        [result, branch2Fallback] = safeEstimate(videoInputStruct, groundTruthOverlay, calibParams, subjectLabel, frameRate);

    case 2
        % --- VIPL-style: correct-frame-rate loader + VIPL ground truth. ---
        subjectNum = str2double(viplTokens{1});
        scenarioNum = str2double(viplTokens{2});
        sourceNum = str2double(viplTokens{3});

        % viplRoot is the ancestor 3 levels up from the folder containing
        % video.avi (.../viplRoot/pN/vN/sourceN/video.avi).
        sourceFolderPath = videoDir;
        scenarioFolderPath = fileparts(sourceFolderPath);
        subjectFolderPath = fileparts(scenarioFolderPath);
        viplRoot = fileparts(subjectFolderPath);

        [frames, frameRate, numFrames, ~] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum);
        [R, G, B, roiTimestamps, droppedFrameIdx, ~] = extractROISignals(frames, frameRate, 'forehead');

        faceDropWarning = checkFaceDropRate(droppedFrameIdx, numFrames);

        videoInputStruct = struct('R', R, 'G', G, 'B', B, 'fs', frameRate, 'roiTimestamps', roiTimestamps);

        gtVIPL = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, sourceNum);
        gtHRTrue = mean(gtVIPL.hr);
        gtSpO2True = mean(gtVIPL.spo2);
        % gt.ppg intentionally NOT used here -- not aligned/usable as a
        % continuous overlay (see io/loadVIPLGroundTruth.m's own header).

        calibParams = []; % never calibrated for VIPL in this script

        [result, branch2Fallback] = safeEstimate(videoInputStruct, [], calibParams, subjectLabel, frameRate);

    otherwise
        % --- Case 3: arbitrary video, no ground truth found. ---
        [frames, frameRate, numFrames] = loadUBFCVideo(videoPath); % generic VideoReader wrapper

        % Case 3 has no sidecar metadata (no time.txt the way VIPL's
        % loadVIPLVideo.m has for source1/source3/source4) to correct
        % frameRate against, so it trusts VideoReader.FrameRate as-is --
        % exactly the situation that produced a real 52.1-vs-~63-bpm error
        % on a VIPL source2 phone clip (container fps disagreeing with the
        % true acquisition rate; see docs/VIPL_DATA_FORMAT.md Section 4).
        % A freshly recorded phone demo clip is frequently variable-
        % frame-rate and exposed to the exact same failure mode. This is a
        % non-fatal SANITY CHECK only -- NumFrames/Duration is not a
        % ground-truth frame rate either (Duration itself can be a
        % container-metadata artifact), so it is never used to "correct"
        % frameRate, only to warn that the reported HR below may carry a
        % proportional scale error.
        fpsMismatchWarning = checkFrameRateMismatch(frames, frameRate);
        if ~isempty(fpsMismatchWarning)
            disp(['run_spandan_interactive: WARNING -- ' fpsMismatchWarning]);
        end

        [R, G, B, roiTimestamps, droppedFrameIdx, ~] = extractROISignals(frames, frameRate, 'forehead');

        faceDropWarning = checkFaceDropRate(droppedFrameIdx, numFrames);

        videoInputStruct = struct('R', R, 'G', G, 'B', B, 'fs', frameRate, 'roiTimestamps', roiTimestamps);

        calibParams = []; % no reference available -- spo2Pct stays NaN

        [result, branch2Fallback] = safeEstimate(videoInputStruct, [], calibParams, subjectLabel, frameRate);
end

if ~isempty(faceDropWarning)
    disp(['run_spandan_interactive: WARNING -- ' faceDropWarning]);
end

renderInteractiveFigure(result, branch2Fallback, caseID, subjectLabel, groundTruthOverlay, gtHRTrue, gtSpO2True, faceDropWarning, fpsMismatchWarning, exportPngPath);

end

function label = pickedLabel(videoPath)
% PICKEDLABEL Short label for on-figure titles: the immediate parent
% folder name of the picked video (e.g. '5-gt', 'source1'), falling back
% to the file name itself if that folder has no useful name.
[parentDir, ~, ~] = fileparts(videoPath);
[~, folderName] = fileparts(parentDir);
if isempty(folderName)
    [~, fileName, ~] = fileparts(videoPath);
    label = fileName;
else
    label = folderName;
end
end

function desc = caseDescription(caseID)
switch caseID
    case 1
        desc = 'UBFC-style, continuous ground truth';
    case 2
        desc = 'VIPL-style';
    otherwise
        desc = 'arbitrary video, no ground truth found';
end
end

function warningMsg = checkFaceDropRate(droppedFrameIdx, numFrames)
% CHECKFACEDROPRATE Returns a non-empty warning string if face detection
% failed on more than 30% of frames, else ''.
warningMsg = '';
if numFrames <= 0
    return;
end
dropFraction = numel(droppedFrameIdx) / numFrames;
if dropFraction > 0.30
    warningMsg = sprintf('face detection failed on %.1f%% of frames (%d of %d) -- results below may not be trustworthy.', 100 * dropFraction, numel(droppedFrameIdx), numFrames);
end
end

function warningMsg = checkFrameRateMismatch(frames, frameRate)
% CHECKFRAMERATEMISMATCH Returns a non-empty warning string if
% VideoReader.FrameRate (frameRate, the value the pipeline actually uses
% as fs) disagrees with the independent NumFrames/Duration estimate by
% more than a few percent, else ''. Non-fatal, does NOT modify frameRate
% -- there is no reliable ground truth for an arbitrary picked video, so
% this only warns rather than guessing which of the two numbers is right
% (see io/loadVIPLVideo.m's own time.txt-based correction for the one
% case in this project where an actual ground-truth-free correction IS
% possible, because VIPL provides real per-frame timestamps; no such
% sidecar exists here).
warningMsg = '';

if frames.Duration <= 0 || frameRate <= 0
    return;
end

altFrameRate = frames.NumFrames / frames.Duration;
relDiff = abs(altFrameRate - frameRate) / frameRate;

if relDiff > 0.03
    warningMsg = sprintf(['VideoReader.FrameRate (%.3f fps) disagrees with NumFrames/Duration ' ...
        '(%.3f fps) by %.1f%% -- this video may be variable-frame-rate or its container fps may ' ...
        'not reflect true acquisition timing (the exact failure mode that produced a real ' ...
        '52.1-vs-~63-bpm error on a VIPL source2 phone clip). The HR reported below may carry a ' ...
        'proportional scale error; it is NOT auto-corrected since there is no reliable ground ' ...
        'truth for an arbitrary video.'], frameRate, altFrameRate, 100 * relDiff);
end
end

function calibParams = tryFitCaseOneCalibration(projectRoot, subjectLabel)
% TRYFITCASEONECALIBRATION Leave-one-out linear SpO2 calibration
% (spo2/calibrateSpO2.m, unmodified) fit on whichever OTHER cached UBFC
% DATASET_1 subjects' data/processed/<id>_rgb_traces.mat files exist on
% disk. Excludes subjectLabel itself if it matches one of the known IDs
% (never fit and predict on the same subject). Returns [] if fewer than 2
% other cached subjects are available.

knownSubjectIDs = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
processedDir = fullfile(projectRoot, 'data', 'processed');
dataset1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');

trainR = [];
trainSpO2 = [];

for idx = 1:numel(knownSubjectIDs)
    thisID = knownSubjectIDs{idx};
    if strcmp(thisID, subjectLabel)
        continue; % never train on the subject being predicted
    end

    rgbMatPath = fullfile(processedDir, [thisID '_rgb_traces.mat']);
    gtPath = fullfile(dataset1Root, thisID, 'gtdump.xmp');

    if ~isfile(rgbMatPath) || ~isfile(gtPath)
        continue; % not cached / not this dataset format -- skip silently
    end

    try
        cached = load(rgbMatPath);
        gt = loadGroundTruth(gtPath, 'dataset1');

        [R_detrended, ~] = detrendSignal(cached.R);
        [G_detrended, ~] = detrendSignal(cached.G);
        [B_detrended, ~] = detrendSignal(cached.B);
        [R_filtered, ~] = bandpassClean(R_detrended, cached.fs);
        [G_filtered, ~] = bandpassClean(G_detrended, cached.fs);
        [B_filtered, ~] = bandpassClean(B_detrended, cached.fs);
        Rvalue = ratioOfRatios(R_filtered, G_filtered, B_filtered, cached.R, cached.G, cached.B, cached.fs);

        videoDurationSec = numel(cached.R) / cached.fs;
        inClipMask = gt.timestamp <= videoDurationSec;
        spo2InClip = gt.spo2(inClipMask);
        if isempty(spo2InClip)
            continue;
        end

        trainR(end + 1) = Rvalue; %#ok<AGROW>
        trainSpO2(end + 1) = mean(spo2InClip); %#ok<AGROW>
    catch
        continue; % any failure on a training subject just excludes it
    end
end

if numel(trainR) < 2
    calibParams = [];
    disp('run_spandan_interactive: fewer than 2 other cached UBFC subjects available -- skipping SpO2 calibration (spo2Pct will be NaN).');
    return;
end

[~, calibParams] = calibrateSpO2(trainR, trainSpO2, []);
disp(['run_spandan_interactive: fit leave-one-out SpO2 calibration on ' num2str(numel(trainR)) ' other cached UBFC subject(s).']);

end

function [result, branch2Fallback] = safeEstimate(videoInputStruct, groundTruth, calibParams, subjectLabel, frameRate)
% SAFEESTIMATE Calls estimateVitalsAndMorphology.m; on the two documented
% too-few-beats error identifiers, recomputes JUST Branch 1 inline
% (replicating that function's own unmodified Branch-1 sequence) so a
% short clip still reports valid HR/SpO2 instead of losing everything.
% branch2Fallback is [] on success, or a struct with a .message field
% describing the fallback when Branch 2 failed.

branch2Fallback = [];

try
    result = estimateVitalsAndMorphology(videoInputStruct, groundTruth, calibParams, struct('subjectID', subjectLabel));
catch causeErr
    if strcmp(causeErr.identifier, 'ensembleAverageBeats:tooFewBeats') || strcmp(causeErr.identifier, 'ensembleAverageBeats:tooFewBeatsAfterDurationGate')
        disp(['run_spandan_interactive: WARNING -- morphology (Branch 2) failed (' causeErr.identifier '): ' causeErr.message]);
        disp('run_spandan_interactive: falling back to Branch-1-only (HR/SpO2 still valid; no ensemble-averaged waveform for this clip).');

        R = videoInputStruct.R;
        G = videoInputStruct.G;
        B = videoInputStruct.B;

        [R_detrended, ~] = detrendSignal(R);
        [G_detrended, ~] = detrendSignal(G);
        [B_detrended, ~] = detrendSignal(B);

        [R_filtered, ~] = bandpassClean(R_detrended, frameRate);
        [G_filtered, ~] = bandpassClean(G_detrended, frameRate);
        [B_filtered, ~] = bandpassClean(B_detrended, frameRate);

        pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);
        pulseChromFiltered = bandpassClean(pulseChrom, frameRate);
        [HR_chrom, ~, ~] = fftHeartRate(pulseChromFiltered, frameRate);

        pulsePos = posCombine(R_filtered, G_filtered, B_filtered, frameRate, R, G, B);
        pulsePosFiltered = bandpassClean(pulsePos, frameRate);
        [HR_pos, ~, ~] = fftHeartRate(pulsePosFiltered, frameRate);

        [HR_green, ~, ~] = fftHeartRate(G_filtered, frameRate);

        Rvalue = ratioOfRatios(R_filtered, G_filtered, B_filtered, R, G, B, frameRate);

        if isempty(calibParams)
            spo2Pct = NaN;
        else
            [spo2Pct, ~] = calibrateSpO2(Rvalue, [], calibParams);
        end

        result = struct();
        result.subjectID = subjectLabel;
        result.frameRate = frameRate;
        result.roiTimestamps = videoInputStruct.roiTimestamps;
        result.R = R;
        result.G = G;
        result.B = B;
        result.hrBpm = struct('chrom', HR_chrom, 'pos', HR_pos, 'green', HR_green);
        result.spo2Pct = spo2Pct;
        result.prototype = [];
        result.iqrBand = [];
        result.notch = struct('detected', false, 'position', NaN, 'depth', NaN, 'confidence', NaN, 'confidenceRaw', NaN);
        result.branch1 = struct('pulseChromFiltered', pulseChromFiltered, 'Rvalue', Rvalue);
        result.branch2 = [];

        branch2Fallback = struct('message', ['Clip too short for a reliable ensemble-averaged waveform (' causeErr.identifier '). HR/SpO2 above are still valid.']);
    else
        rethrow(causeErr);
    end
end

end

function renderInteractiveFigure(result, branch2Fallback, caseID, subjectLabel, groundTruthOverlay, gtHRTrue, gtSpO2True, faceDropWarning, fpsMismatchWarning, exportPngPath)
% RENDERINTERACTIVEFIGURE Builds the combined 3x2 (+ optional GT overlay)
% figure and shows it on screen (a normal visible figure() -- this is an
% interactive tool, never 'Visible','off'). Mirrors
% run_spandan_full_demo.m's renderSpandanDemoFigure layout by design (see
% this file's header comment) but is a separate implementation, including
% its own local copy of the multi-cycle-window helper (extractMultiCycleWindow
% below) for the same "MATLAB script-local functions can't be imported
% across files" reason already documented in this file's header.

NUM_CYCLES_MULTIPANEL = 8; % tunable: how many real cardiac cycles the multi-cycle panel shows (fig7 used 12)
MULTIPANEL_START_OFFSET_SEC = 5; % skip filter-startup transient, same convention as fig7

figHandle = figure('Position', [80 80 1400 1350]);
tl = tiledlayout(figHandle, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- Panel (i): raw ROI trace (raw G(t)), plus a Case-1 ground-truth PPG
% overlay on a secondary y-axis when available. ---
axRaw = nexttile(tl);
rawTimeAxis = result.roiTimestamps;
plot(axRaw, rawTimeAxis, result.G, 'LineWidth', 1.1, 'Color', [0.20 0.45 0.20], 'DisplayName', 'Raw ROI G(t)');
xlabel(axRaw, 'Time (s)');
ylabel(axRaw, 'Raw pixel intensity');
xlim(axRaw, [rawTimeAxis(1), rawTimeAxis(end)]);
box(axRaw, 'on');

if ~isempty(groundTruthOverlay)
    yyaxis(axRaw, 'right');
    plot(axRaw, groundTruthOverlay.timestamp, groundTruthOverlay.ppg, 'Color', [0.75 0.30 0.10], 'LineWidth', 0.8);
    ylabel(axRaw, 'Ground-truth PPG (raw)');
    yyaxis(axRaw, 'left');
    title(axRaw, '(i) Raw ROI trace, G(t), with ground-truth PPG overlay');
else
    title(axRaw, '(i) Raw ROI trace, G(t)');
end

% --- Panel (ii): production pulse (Branch 1, CHROM) with HR annotated ---
axProd = nexttile(tl);
prodPulse = result.branch1.pulseChromFiltered;
prodTimeAxis = (0:(numel(prodPulse) - 1)) / result.frameRate;
plot(axProd, prodTimeAxis, prodPulse, 'LineWidth', 1.1, 'Color', [0.15 0.25 0.55]);
xlabel(axProd, 'Time (s)');
ylabel(axProd, 'Pulse amplitude (a.u.)');
title(axProd, ['(ii) Production pulse (CHROM), HR = ' num2str(result.hrBpm.chrom, '%.1f') ' bpm']);
xlim(axProd, [prodTimeAxis(1), prodTimeAxis(end)]);
box(axProd, 'on');

% --- Panel (iii): morphology ensemble-averaged waveform, IQR band
% shaded, notch position marked -- OR a fallback text note if Branch 2
% failed on this clip. ---
axMorph = nexttile(tl);
if ~isempty(branch2Fallback)
    axis(axMorph, 'off');
    text(axMorph, 0.5, 0.5, {'(iii) Morphology waveform unavailable', '', branch2Fallback.message}, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 11, 'Interpreter', 'none');
else
    cycleFrac = linspace(0, 1, numel(result.prototype.trimmedMean));
    hold(axMorph, 'on');
    fill(axMorph, [cycleFrac, fliplr(cycleFrac)], [result.iqrBand.q3, fliplr(result.iqrBand.q1)], ...
        [0.75 0.80 0.95], 'EdgeColor', 'none', 'FaceAlpha', 0.6, 'DisplayName', 'IQR band (beat-to-beat spread)');
    plot(axMorph, cycleFrac, result.prototype.trimmedMean, 'LineWidth', 1.8, 'Color', [0.10 0.15 0.45], 'DisplayName', 'Ensemble-averaged beat');
    if result.notch.detected
        xline(axMorph, cycleFrac(round(result.notch.position * (numel(cycleFrac) - 1)) + 1), '--', 'Color', [0.80 0.15 0.15], 'LineWidth', 1.6, 'DisplayName', 'Detected notch');
        notchLabel = ['notch detected @ ' num2str(result.notch.position, '%.3f') ' (conf ' num2str(result.notch.confidence, '%.2f') ')'];
    else
        notchLabel = 'no notch detected';
    end
    hold(axMorph, 'off');
    xlabel(axMorph, 'Cycle fraction (systolic peak anchored at 0.25)');
    ylabel(axMorph, 'Pulse amplitude (a.u.)');
    title(axMorph, {'(iii) Single-cycle prototype (ensemble-averaged beat)', ...
        [notchLabel ' -- resolvable HERE (averaging raises SNR)']}, 'FontSize', 10);
    legend(axMorph, 'Location', 'best', 'FontSize', 7);
    xlim(axMorph, [0 1]);
    box(axMorph, 'on');
end

% --- Panel (iv): multi-cycle continuous waveform (NEW, Segment 8
% follow-up) -- OR the SAME fallback note as panel (iii) when Branch 2
% failed on this clip (result.branch2.sigUniform is a Branch-2 field, so
% the too-few-beats guardrail that loses Branch 2 loses this too; there is
% no separate continuous signal available from the Branch-1-only
% fallback). Reuses result.branch2.sigUniform/uniformFs -- the SAME
% pre-ensemble-averaging signal
% scripts/run_segment7_fig7_multicycle_waveform_batch.m plots, since
% estimateVitalsAndMorphology.m's Branch 2 is byte-identical to that
% script's own chain up to (and including) resampleUniform.m -- and
% already used fixPolarityByGroundTruth for Case 1 (groundTruth supplied
% above) / the fixPolarity heuristic for Cases 2 and 3 (groundTruth=[]
% above), exactly the polarity policy this task requires, with no extra
% branching needed here. Real continuous samples only -- never
% tiles/repeats panel (iii). ---
axMulti = nexttile(tl);
if ~isempty(branch2Fallback)
    axis(axMulti, 'off');
    text(axMulti, 0.5, 0.5, {'(iv) Multi-cycle waveform unavailable', '', branch2Fallback.message}, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 11, 'Interpreter', 'none');
else
    [timeWindowMulti, sigWindowMulti, peakTimesMulti, peakValsMulti, actualCyclesShownMulti] = ...
        extractMultiCycleWindow(result.branch2.sigUniform, result.branch2.uniformFs, NUM_CYCLES_MULTIPANEL, MULTIPANEL_START_OFFSET_SEC);
    hold(axMulti, 'on');
    plot(axMulti, timeWindowMulti, sigWindowMulti, 'LineWidth', 1.2, 'Color', [0.15 0.25 0.55]);
    plot(axMulti, peakTimesMulti, peakValsMulti, 'o', 'MarkerSize', 6, 'MarkerFaceColor', [0.85 0.20 0.20], ...
        'MarkerEdgeColor', 'k', 'LineStyle', 'none', 'DisplayName', 'Systolic peaks (visual aid)');
    hold(axMulti, 'off');
    xlabel(axMulti, 'Time (s)');
    ylabel(axMulti, 'Pulse amplitude (a.u.)');
    title(axMulti, {['(iv) Multi-cycle waveform, real time, ~' num2str(actualCyclesShownMulti) ' measured cycles'], ...
        'Same signal as (iii), pre-averaging -- notch LESS visible per-beat (SNR limit, not a regression)'}, 'FontSize', 10);
    xlim(axMulti, [timeWindowMulti(1), timeWindowMulti(end)]);
    box(axMulti, 'on');
end

% --- Panel (v): text summary ---
axText = nexttile(tl, 5, [1 2]);
axis(axText, 'off');

summaryLines = { ...
    ['Subject/clip: ' subjectLabel], ...
    ['Input class: Case ' num2str(caseID) ' (' caseDescription(caseID) ')'], ...
    '', ...
    'Heart rate (measured):', ...
    ['  CHROM: ' num2str(result.hrBpm.chrom, '%.1f') ' bpm'], ...
    ['  POS:   ' num2str(result.hrBpm.pos, '%.1f') ' bpm'], ...
    ['  Green: ' num2str(result.hrBpm.green, '%.1f') ' bpm'] ...
    };

if ~isnan(gtHRTrue)
    summaryLines{end + 1} = ['  Ground truth: ' num2str(gtHRTrue, '%.1f') ' bpm'];
end

summaryLines{end + 1} = '';

if isnan(result.spo2Pct)
    summaryLines{end + 1} = 'SpO2: not calibrated, no reference available';
else
    summaryLines{end + 1} = ['SpO2 (calibrated): ' num2str(result.spo2Pct, '%.1f') ' %'];
end

if ~isnan(gtSpO2True)
    summaryLines{end + 1} = ['  Ground truth SpO2: ' num2str(gtSpO2True, '%.1f') ' %'];
end

summaryLines{end + 1} = '';

if isempty(branch2Fallback)
    if result.notch.detected
        notchLine = ['Notch: detected, position ' num2str(result.notch.position, '%.3f') ', depth ' num2str(result.notch.depth, '%.3f') ', confidence ' num2str(result.notch.confidence, '%.3f')];
    else
        notchLine = 'Notch: not detected';
    end
    summaryLines{end + 1} = notchLine;
    summaryLines{end + 1} = ['Beats averaged: ' num2str(result.branch2.beatStats.beatsAveraged)];
else
    summaryLines{end + 1} = 'Notch: unavailable (clip too short, see panels iii/iv)';
end

if ~isempty(faceDropWarning)
    summaryLines{end + 1} = '';
    summaryLines{end + 1} = ['WARNING: ' faceDropWarning];
end

if ~isempty(fpsMismatchWarning)
    summaryLines{end + 1} = '';
    summaryLines{end + 1} = ['WARNING: ' fpsMismatchWarning];
end

text(axText, 0.02, 0.95, summaryLines, 'VerticalAlignment', 'top', 'FontSize', 11, 'Interpreter', 'none');
title(axText, '(v) Summary');

title(tl, ['Spandan interactive demo -- ' subjectLabel], 'Interpreter', 'none', 'FontWeight', 'bold');

if ~isempty(exportPngPath)
    exportgraphics(figHandle, exportPngPath); % testing only -- see header
end

end

function [timeWindow, sigWindow, peakTimes, peakVals, actualCyclesShown] = extractMultiCycleWindow(sigUniform, uniformFs, numCyclesToShow, startOffsetSec)
% EXTRACTMULTICYCLEWINDOW Picks a numCyclesToShow-cardiac-cycle window of
% a continuous uniform-grid signal, starting startOffsetSec seconds in to
% skip filter-startup transients, and marks systolic peaks with a plain
% findpeaks() scan (annotation only, gated by this signal's own HR) purely
% so a reader can visually count cycles. Local re-implementation of
% scripts/run_segment7_fig7_multicycle_waveform_batch.m's own per-subject
% windowing logic (that script is not modified and not called from here --
% see this file's header for why) -- same formulas, reused deliberately
% rather than re-derived. A separate copy of the same-named helper in
% scripts/run_spandan_full_demo.m, for the same reason.

hrBpm = fftHeartRate(sigUniform, uniformFs);
cycleDurationSec = 60 / hrBpm;
windowDurationSec = numCyclesToShow * cycleDurationSec;

totalDurationSec = numel(sigUniform) / uniformFs;
windowStartSec = min(startOffsetSec, max(0, totalDurationSec - windowDurationSec - 1));
if windowStartSec + windowDurationSec > totalDurationSec
    windowDurationSec = totalDurationSec - windowStartSec;
end

startSample = max(1, round(windowStartSec * uniformFs) + 1);
endSample = min(numel(sigUniform), startSample + round(windowDurationSec * uniformFs) - 1);

sigWindow = sigUniform(startSample:endSample);
timeWindow = (0:(numel(sigWindow) - 1)) / uniformFs; % window-relative time, seconds

minPeakDistSamples = max(1, round(0.5 * cycleDurationSec * uniformFs));
[peakVals, peakLocs] = findpeaks(sigWindow, 'MinPeakDistance', minPeakDistSamples);
peakTimes = timeWindow(peakLocs);
actualCyclesShown = numel(peakVals);

end
