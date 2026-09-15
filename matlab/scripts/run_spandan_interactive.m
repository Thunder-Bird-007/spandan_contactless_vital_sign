% RUN_SPANDAN_INTERACTIVE Interactive, single-video demo driver: adds this
% repo's matlab/src to the MATLAB path (self-locating -- works no matter
% what MATLAB's current folder is), pops a uigetfile dialog so you can pick
% ANY video file anywhere on the computer, auto-detects which of three
% input classes it belongs to (UBFC-style with continuous ground truth /
% VIPL-style / arbitrary with no ground truth), runs the FULL, CURRENT
% production pipeline (pipeline/estimateVitalsAndMorphology.m -- Branch 1
% HR/SpO2 and Branch 2 morphology/notch, including Segment 14's confidence
% gate, exactly as every other script in this repo calls it, at whatever
% that function currently does), and shows ONE combined figure + numeric
% summary on screen. Nothing is saved to disk by default -- this is an
% interactive look-and-inspect tool, not a batch pipeline.
%
% USAGE: open this file in MATLAB (any current folder) and press Run, or
% type run_spandan_interactive at the prompt. No addpath/startup.m needed
% first -- the path bootstrap a few lines below does that automatically.
%
% =====================================================================
% DESIGN CHANGE, 2026-09-14 (Segment 17) -- READ BEFORE EDITING ANYTHING
% ELSE IN THIS FILE
% =====================================================================
% This file used to be a deliberately standalone, dependency-free .m file:
% every pipeline function it called (estimateVitalsAndMorphology,
% chromCombine, adaptiveHarmonicFilter, notchDetectIEM, and 16 others) was
% reproduced VERBATIM as a local copy, specifically so the file could be
% copied alone to any machine with no repo checkout. That design's own
% header stated its tradeoff plainly: matlab/src/ stays the source of
% truth, and the copies here would "silently go stale unless someone
% updates them too." That is exactly what happened -- Segments 10-16
% (cPACE, the mid-band bandpass option, the harmonic-selective Gaussian
% filter, and Segment 14's confidence gate, now the ACTUAL production
% default) were never ported into this file's local copies, so by
% 2026-09-14 this "single file that runs the pipeline" was quietly running
% a frozen, months-stale snapshot of the pipeline from Segment 7/8, not
% the current one -- silently, with no on-screen indication.
%
% Per Abrar's explicit request (one file, runs the CURRENT pipeline, pick
% any video on the machine), this file now does the opposite: it adds
% matlab/src/ to the MATLAB path at the top of the script (self-locating
% via mfilename('fullpath'), so it works regardless of MATLAB's current
% folder) and calls pipeline/estimateVitalsAndMorphology.m and every other
% pipeline function directly off the path -- the SAME functions every
% batch/report script in matlab/scripts/ already uses. The cost, stated
% plainly per this project's own evaluation-honesty discipline: this file
% can no longer be copied alone to a machine with no repo checkout -- it
% needs matlab/src/ to sit next to matlab/scripts/, same as every other
% script here. That is the price of never silently going stale again.
%
% ONE REAL PIECE OF FUNCTIONALITY THIS CHANGE DROPS, FLAGGED (not silently
% lost): the old standalone file had its own local
% chooseHeuristicPolarityByNotchConfidence, used ONLY for Cases 2/3 (no
% ground truth available). It ran Branch 2's waveform both ways (as-is and
% flipped) and kept whichever orientation notchDetectIEM.m scored higher
% confidence on, rather than trusting morphology/fixPolarity.m's plain
% skewness rule. That fix was written after a live demo review caught the
% skewness rule flipping a VIPL clip (p1/v1/source1) into an orientation
% with NO real notch (notchDetectIEM confidence 0.04 flipped vs 0.92
% as-is) -- confirmed by running both orientations end-to-end, not a
% guess -- and morphology/fixPolarity.m's own header separately documents
% the same skewness rule flipping ALL 5 UBFC subjects when ground truth
% says only 3 of 5 actually needed it. That fix was NEVER ported into
% matlab/src/ -- it only ever lived in this one standalone file's local
% copy of the pipeline. Calling the real, current
% pipeline/estimateVitalsAndMorphology.m now means Cases 2/3 are back to
% the plain morphology/fixPolarity.m heuristic -- the SAME one production
% and the Android app already use for no-ground-truth input. That is
% arguably the more honest "current pipeline" answer (it is what the
% actual shipped product does), but the underlying skewness-rule bias this
% old fix worked around is still real and is still not addressed in
% matlab/src/. If it still matters, the right fix is to port a version of
% chooseHeuristicPolarityByNotchConfidence's confidence-anchored logic
% into matlab/src/morphology/fixPolarity.m (or add it as a new
% opts.polarityMethod hook on estimateVitalsAndMorphology.m) as a real,
% validated segment of work -- a human should decide that; it is
% deliberately not done as a side effect of this file's rewrite.
%
% CASE DETECTION (by files found next to the picked video, never asked of
% the user):
%   Case 1 -- UBFC-style, continuous ground truth: gtdump.xmp (dataset1
%             format) or ground_truth.txt (dataset2 format) sits next to
%             the picked video. Uses io/loadGroundTruth.m and
%             morphology/fixPolarityByGroundTruth.m (via
%             estimateVitalsAndMorphology's own groundTruth argument), and
%             shows a ground-truth PPG overlay + ground-truth HR/SpO2
%             numbers.
%   Case 2 -- VIPL-style: the picked path matches
%             .../p<N>/v<N>/source<N>/video.avi AND gt_HR.csv + gt_SpO2.csv
%             sit next to it. Uses io/loadVIPLVideo.m (NOT loadUBFCVideo.m
%             -- corrects frameRate against time.txt) and
%             io/loadVIPLGroundTruth.m for a ground-truth HR/SpO2
%             comparison; groundTruth=[] is passed to the pipeline because
%             VIPL's gt.ppg is explicitly not usable as a continuous,
%             aligned overlay (see io/loadVIPLGroundTruth.m's own header).
%   Case 3 -- arbitrary video, no ground truth found by either check
%             above: io/loadUBFCVideo.m (a generic VideoReader wrapper
%             despite its name) + groundTruth=[] + calibParams=[], so
%             spo2Pct is NaN and is reported plainly as "not calibrated,
%             no reference available" rather than a fabricated number.
%             This is the expected case for "pick any video on my
%             computer" -- most videos will land here.
%
% SpO2 CALIBRATION: for Case 1 only, this script attempts a leave-one-out
% linear calibration (spo2/calibrateSpO2.m, unmodified) using whichever OF
% the OTHER cached UBFC DATASET_1 subjects' data/processed/<id>_rgb_traces.mat
% files exist on disk (the picked subject's own file, if it matches one of
% those IDs, is excluded from the training set -- never fit and predict on
% the same subject). If fewer than 2 other cached subjects are available,
% or the picked video is not a recognized UBFC DATASET_1 subject at all,
% calibration is skipped and spo2Pct is left as NaN with a clear on-figure
% label. Cases 2 and 3 never attempt calibration (calibParams=[] always) --
% pipeline/estimateVitalsAndMorphology.m never fits its own calibration by
% design (see its own header / spo2/calibrateSpO2.m's header).
%
% GUARDRAILS:
%   - Too-few-beats (ensembleAverageBeats:tooFewBeats /
%     ensembleAverageBeats:tooFewBeatsAfterDurationGate): Branch 2 failing
%     would otherwise abort the whole estimateVitalsAndMorphology.m call
%     and lose Branch 1's already-good HR/SpO2 too. This script wraps the
%     call in try/catch (safeEstimate below); on either of those two
%     identifiers it recomputes JUST Branch 1 inline (detrendSignal ->
%     bandpassClean -> chromCombine/posCombine -> fftHeartRate;
%     ratioOfRatios -> calibrateSpO2 if calibParams available), using the
%     SAME unmodified path functions, then still shows HR/SpO2 with the
%     morphology panel replaced by a clear text note. Any other error
%     identifier is re-thrown.
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
% The core "given a resolved videoPath, do everything" logic lives in the
% local function runSpandanInteractiveCore(videoPath, exportPngPath) below
% specifically so it can be invoked directly with a hardcoded path for
% testing without needing to click through a uigetfile dialog.
% exportPngPath is optional and testing-only (exportgraphics to a PNG in
% addition to showing the on-screen figure) -- the normal interactive path
% below never passes it, and the figure this function creates is always a
% normal visible figure(), never 'Visible','off'.

% === Path bootstrap: put matlab/src/ (and all its subfolders) on the
% MATLAB path, self-located relative to THIS file, so the script works no
% matter what MATLAB's current folder is and needs no manual addpath or
% startup.m call first. Mirrors startup.m's own addpath(genpath(...)) call
% exactly; safe to run every time (addpath of an already-added folder is a
% no-op). ===
thisScriptDir = fileparts(mfilename('fullpath'));
matlabRoot = fileparts(thisScriptDir);
srcRoot = fullfile(matlabRoot, 'src');
if ~isfolder(srcRoot)
    error('run_spandan_interactive:srcNotFound', ...
        'Could not find matlab/src/ next to matlab/scripts/ (expected at %s). This file must stay inside the repo''s matlab/scripts/ folder.', srcRoot);
end
addpath(genpath(srcRoot));

[pickedFile, pickedPath] = uigetfile( ...
    {'*.avi;*.mp4;*.mov;*.mkv', 'Video files (*.avi,*.mp4,*.mov,*.mkv)'; '*.*', 'All Files (*.*)'}, ...
    'Select a video for the Spandan pipeline');

if isequal(pickedFile, 0)
    disp('run_spandan_interactive: no file selected, exiting.');
    return;
end

videoPath = fullfile(pickedPath, pickedFile);

% Top-level safety net -- ANY uncaught error anywhere in the pipeline
% (bad/corrupt video, a clip too short even for Branch 1, an unexpected
% edge case not covered by the guardrails below) is caught HERE so this
% tool never crashes out to a bare MATLAB error in front of a live
% audience. It shows a plain, honest error figure instead. This is a
% presentation-safety net, not a substitute for the specific, targeted
% guardrails inside runSpandanInteractiveCore -- those still run first and
% still produce the detailed, informative warnings/fallbacks documented
% throughout this file; this is only the last-resort catch-all.
try
    runSpandanInteractiveCore(videoPath);
catch topLevelErr
    disp(['run_spandan_interactive: FAILED for ' videoPath ' -- ' topLevelErr.identifier ' -- ' topLevelErr.message]);
    figHandle = figure('Position', [80 80 900 400]);
    axis off;
    text(0.5, 0.5, { ...
        'This clip could not be processed.', '', ...
        ['File: ' videoPath], '', ...
        ['Reason: ' topLevelErr.message], '', ...
        'Try a different video, or a longer clip with a clearly visible face.'}, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 12, 'Interpreter', 'none');
    title(figHandle.CurrentAxes, 'Spandan interactive demo -- processing failed', 'FontSize', 13, 'Color', [0.75 0.10 0.10]);
end

function result = runSpandanInteractiveCore(videoPath, exportPngPath)
% RUNSPANDANINTERACTIVECORE Given a resolved video path, detect its input
% class, run the CURRENT production pipeline
% (pipeline/estimateVitalsAndMorphology.m, off the MATLAB path), render
% the combined figure, and return the result struct (mainly so a
% caller/test can inspect it). exportPngPath is optional (testing only,
% see this file's header).

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

morphologyReliabilityWarning = checkMorphologyReliability(branch2Fallback, result);
if ~isempty(morphologyReliabilityWarning)
    disp(['run_spandan_interactive: WARNING -- ' morphologyReliabilityWarning]);
end

renderInteractiveFigure(result, branch2Fallback, caseID, subjectLabel, groundTruthOverlay, gtHRTrue, gtSpO2True, faceDropWarning, fpsMismatchWarning, morphologyReliabilityWarning, exportPngPath);

end

function warningMsg = checkMorphologyReliability(branch2Fallback, result)
% CHECKMORPHOLOGYRELIABILITY Returns a non-empty warning string when
% Branch 2 (the morphology/notch waveform) "succeeded" mechanically
% (ensembleAverageBeats did not throw) but notchDetectIEM's own confidence
% signals the result is not trustworthy. Added after a live demo review on
% VIPL p4/v1/source1 surfaced exactly this: 92 candidate beats found from
% zero-crossings in a ~34s clip (physically only ~37 should exist at the
% ~66 bpm this clip's own f0 estimate reported), 85 of them rejected by
% the duration/quality gates as incoherent, leaving only 7-8 real cycles
% averaged -- diagnosed as the shared cardiac-frequency estimate (from a
% plain FFT peak-pick on a wide 0.5-8 Hz band) landing far enough from the
% true rate (65.96 bpm estimated vs 74.37 bpm ground truth, an ~11% error
% -- ordinary by this project's own validated HR-estimation accuracy, but
% catastrophic for morphology/adaptiveHarmonicFilter.m's narrow +/-1-FFT-
% bin combs, which have essentially zero tolerance for f0 error) that the
% harmonic comb mostly passed noise instead of real cardiac harmonics.
% This is the SAME failure family Segment 7 Task E already documented (a
% wrong f0 estimate breaking the harmonic comb), just a milder
% manifestation than that doc's dramatic 69.4->140.8 bpm example. It is
% NOT a polarity bug -- both orientations showed low confidence on that
% clip (0.04 and 0.18).
%
% THRESHOLD CHOICE, READ BEFORE ADDING A beatsAveraged CUTOFF BACK: an
% earlier version of this function also flagged low beatsAveraged as
% unreliable on its own (< 15). That was WRONG and has been removed after
% it false-positived on VIPL p1/v1/source1 -- a clip already confirmed
% correct (0.92 confidence, textbook notch shape) that only averaged 9
% beats, simply because VIPL clips (~30-40s) are much shorter than UBFC's
% (~80s) and so naturally contain fewer cardiac cycles. Beat COUNT is not
% a valid reliability signal by itself; notchDetectIEM's own confidence
% (which already correctly separated p1's 0.92 from p4's 0.04/0.18) is the
% only trigger used below. beatsAveraged is still reported in the warning
% text for context, never as a pass/fail criterion.
%
% This is also not something this file can fix by itself:
% morphology/ensembleAverageBeats.m and morphology/notchDetectIEM.m were
% validated only on 5 UBFC subjects (see matlab/docs/
% Segment7_Task_B_Notch_Quantification.md); nothing established the
% morphology pipeline generalizes across VIPL's 107 real-world subjects
% the way the production HR/SpO2 path was validated to. The honest fix
% here is to say so plainly rather than present a noise-driven waveform as
% if it were a measured result.
warningMsg = '';

if ~isempty(branch2Fallback)
    return; % already has its own too-short-clip message
end

lowConfidenceThreshold = 0.3; % same "confident detection" bar this project uses elsewhere

beatsAveraged = result.branch2.beatStats.beatsAveraged;
confidenceRaw = result.notch.confidenceRaw;

lowConfidence = ~result.notch.detected || confidenceRaw < lowConfidenceThreshold;

if lowConfidence
    warningMsg = sprintf(['morphology/notch result is UNRELIABLE for this clip: notch confidence is %.3f ' ...
        '(< %.1f threshold; %d beat(s) were averaged, for context). This usually means the shared ' ...
        'cardiac-frequency estimate feeding the harmonic-comb filter was off enough to corrupt beat ' ...
        'segmentation -- see checkMorphologyReliability''s own header for the full diagnosis. Treat the waveform ' ...
        'panels below as NOT a measured result for this clip; HR/SpO2 above are computed independently and are ' ...
        'not affected by this.'], confidenceRaw, lowConfidenceThreshold, beatsAveraged);
end

end

function lines = wrapWarningText(text, maxCharsPerLine)
% WRAPWARNINGTEXT Greedy word-wrap of a long warning string into a cell
% array of lines, each <= maxCharsPerLine characters, so a long warning
% (e.g. checkMorphologyReliability's) reads cleanly in the summary panel's
% text() call instead of running off the figure.
words = strsplit(text, ' ');
lines = {};
currentLine = '';

for w = 1:numel(words)
    word = words{w};
    if isempty(currentLine)
        candidate = word;
    else
        candidate = [currentLine ' ' word];
    end

    if numel(candidate) > maxCharsPerLine && ~isempty(currentLine)
        lines{end + 1} = currentLine; %#ok<AGROW>
        currentLine = word;
    else
        currentLine = candidate;
    end
end

if ~isempty(currentLine)
    lines{end + 1} = currentLine; %#ok<AGROW>
end

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
% SAFEESTIMATE Calls the CURRENT pipeline/estimateVitalsAndMorphology.m
% (off the MATLAB path, per this file's path bootstrap -- always whatever
% that function currently does, including Segment 14's confidence gate).
% On the two documented too-few-beats error identifiers, recomputes JUST
% Branch 1 inline (replicating that function's own unmodified Branch-1
% sequence, using the same path functions) so a short clip still reports
% valid HR/SpO2 instead of losing everything. branch2Fallback is [] on
% success, or a struct with a .message field describing the fallback when
% Branch 2 failed.

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
        result.notch = struct('detected', false, 'position', NaN, 'depth', NaN, 'confidence', NaN, 'confidenceRaw', NaN, 'methodUsed', '');
        result.branch1 = struct('pulseChromFiltered', pulseChromFiltered, 'Rvalue', Rvalue);
        result.branch2 = [];

        branch2Fallback = struct('message', ['Clip too short for a reliable ensemble-averaged waveform (' causeErr.identifier '). HR/SpO2 above are still valid.']);
    else
        rethrow(causeErr);
    end
end

end

function renderInteractiveFigure(result, branch2Fallback, caseID, subjectLabel, groundTruthOverlay, gtHRTrue, gtSpO2True, faceDropWarning, fpsMismatchWarning, morphologyReliabilityWarning, exportPngPath)
% RENDERINTERACTIVEFIGURE Builds the combined 3x2 (+ optional GT overlay)
% figure and shows it on screen (a normal visible figure() -- this is an
% interactive tool, never 'Visible','off'). Mirrors
% run_spandan_full_demo.m's renderSpandanDemoFigure layout by design but
% is a separate implementation, including its own local copy of the
% multi-cycle-window helper (extractMultiCycleWindow below), since MATLAB
% script-local functions cannot be imported across files.

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
    if isempty(morphologyReliabilityWarning)
        morphTitle = {'(iii) Single-cycle prototype (ensemble-averaged beat)', ...
            [notchLabel ' -- resolvable HERE (averaging raises SNR)']};
        morphTitleColor = [0 0 0];
    else
        morphTitle = {'(iii) Single-cycle prototype -- ** UNRELIABLE FOR THIS CLIP **', ...
            [notchLabel ' -- see summary panel for why']};
        morphTitleColor = [0.75 0.10 0.10];
    end
    title(axMorph, morphTitle, 'FontSize', 10, 'Color', morphTitleColor);
    legend(axMorph, 'Location', 'best', 'FontSize', 7);
    xlim(axMorph, [0 1]);
    box(axMorph, 'on');
end

% --- Panel (iv): multi-cycle continuous waveform -- OR the SAME fallback
% note as panel (iii) when Branch 2 failed on this clip
% (result.branch2.sigUniform is a Branch-2 field, so the too-few-beats
% guardrail that loses Branch 2 loses this too). Reuses
% result.branch2.sigUniform/uniformFs -- Branch 2's own pre-ensemble-
% averaging signal, already polarity-fixed by whichever method
% pipeline/estimateVitalsAndMorphology.m used (fixPolarityByGroundTruth
% for Case 1, fixPolarity for Cases 2/3 -- see this file's top-of-file
% header for the Segment 17 note on that). Real continuous samples only --
% never tiles/repeats panel (iii). ---
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
    if isempty(morphologyReliabilityWarning)
        multiTitle = {['(iv) Multi-cycle waveform, real time, ~' num2str(actualCyclesShownMulti) ' measured cycles'], ...
            'Same signal as (iii), pre-averaging -- notch LESS visible per-beat (SNR limit, not a regression)'};
        multiTitleColor = [0 0 0];
    else
        multiTitle = {'(iv) Multi-cycle waveform -- ** UNRELIABLE FOR THIS CLIP **', ...
            'Extra bumps here are noise, not real heartbeats -- see summary panel for why'};
        multiTitleColor = [0.75 0.10 0.10];
    end
    title(axMulti, multiTitle, 'FontSize', 10, 'Color', multiTitleColor);
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

    % Segment 14's confidence gate is production default (opts.useConfidenceGate
    % = true) -- surface which filter it actually used for this clip, so
    % "run the current pipeline" is visibly true, not just claimed.
    if isfield(result.branch2, 'harmonicMethodUsed')
        if result.branch2.gateSubstituted
            gateLine = 'Morphology filter: Gaussian(0.15) (confidence gate substituted ABPF, which scored below the 0.3 bar)';
        else
            gateLine = 'Morphology filter: ABPF harmonic comb (default; confidence gate kept it)';
        end
        summaryLines{end + 1} = gateLine;
    end
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

if ~isempty(morphologyReliabilityWarning)
    summaryLines{end + 1} = '';
    summaryLines = [summaryLines, wrapWarningText(['WARNING: ' morphologyReliabilityWarning], 95)];
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
% windowing logic (that script is not modified and not called from here)
% -- same formulas, reused deliberately rather than re-derived. A separate
% copy of the same-named helper in scripts/run_spandan_full_demo.m, for
% the same "script-local functions can't be imported across files" reason.
% fftHeartRate below resolves to the real, current
% matlab/src/heartrate/fftHeartRate.m off the MATLAB path (unchanged since
% Segment 4, so this has always matched production).

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
