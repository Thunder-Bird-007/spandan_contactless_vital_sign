% RUN_SPANDAN_INTERACTIVE Interactive, single-video demo driver: pops a
% uigetfile dialog, lets the user pick ANY video file, auto-detects which
% of three input classes it belongs to (UBFC-style with continuous ground
% truth / VIPL-style / arbitrary with no ground truth), runs the full
% pipeline, and shows ONE combined figure + numeric summary on screen.
% Nothing is saved to disk by default -- this is an interactive
% look-and-inspect tool, not a batch pipeline.
%
% STANDALONE, SELF-CONTAINED FILE -- READ THIS BEFORE EDITING ANYTHING
% ELSE IN THIS PROJECT. By explicit request, this single .m file has NO
% dependency on any other .m file in this repo: it does not call
% pipeline/estimateVitalsAndMorphology.m, roi/extractROISignals.m,
% filtering/detrendSignal.m, filtering/bandpassClean.m,
% morphology/bandpassMorphology.m, morphology/adaptiveHarmonicFilter.m,
% pulseextraction/chromCombine.m, pulseextraction/posCombine.m,
% heartrate/fftHeartRate.m, spo2/ratioOfRatios.m, spo2/calibrateSpO2.m,
% morphology/fixPolarity.m, morphology/fixPolarityByGroundTruth.m,
% morphology/resampleUniform.m, morphology/ensembleAverageBeats.m,
% morphology/notchDetectIEM.m, io/loadUBFCVideo.m, io/loadVIPLVideo.m,
% io/loadVIPLGroundTruth.m, io/loadGroundTruth.m, or
% scripts/run_spandan_full_demo.m across the file system. Every one of
% those functions is instead reproduced VERBATIM below as a local function
% of this same script (same name, same body, same math -- copied, not
% re-derived), so MATLAB resolves every call to the LOCAL copy defined in
% this file before ever consulting the MATLAB path. Practical consequence:
% this file can be copied by itself to any folder, on any machine, with no
% `addpath`/`startup.m`/repo checkout at all, and `run_spandan_interactive`
% still works -- the ONLY things it still needs at runtime are (a) a
% standard MATLAB install with the Computer Vision Toolbox
% (vision.CascadeObjectDetector, used by the inlined extractROISignals) and
% Signal Processing Toolbox (butter/filtfilt/sgolayfilt, used by several
% inlined functions) -- exactly the same toolboxes the rest of this
% project already requires, not a new dependency -- and (b) whatever
% ground-truth/data files happen to sit next to the video the user picks
% (gtdump.xmp, ground_truth.txt, gt_HR.csv/gt_SpO2.csv), which are DATA,
% not code, and are looked up relative to the PICKED VIDEO's own path, not
% this script's location, so they are found correctly regardless of where
% this file itself has been copied to.
%
% KNOWN TRADEOFF OF THIS DESIGN, STATED PLAINLY: matlab/src/ remains the
% single source of truth for this project's validated pipeline (that is
% what tests/segment7_task_f_regression_test.m checks against, and what
% every batch/report script in matlab/scripts/ still calls). The copies
% below are a deliberate, explicit duplication for standalone portability
% only -- if a function in matlab/src/ is ever revised, the matching copy
% here will silently go stale unless someone updates it too. This is a
% real cost of the "one independent file" requirement, not swept under
% the rug: nothing in matlab/src/ was modified to produce this file (it
% remains byte-for-byte what Segment 7 Task F validated), and this file
% does not modify or replace it.
%
% ONE DELIBERATE BEHAVIORAL DIVERGENCE FROM matlab/src/, ON TOP OF THE
% PORTABILITY-ONLY DUPLICATION ABOVE: Cases 2/3 (no ground truth) pick
% Branch 2's waveform polarity via chooseHeuristicPolarityByNotchConfidence
% below, NOT via a plain call to the (inlined, otherwise-unmodified)
% fixPolarity skewness heuristic that matlab/src/pipeline/
% estimateVitalsAndMorphology.m still uses for the same no-ground-truth
% case. This was added after a live demo review caught the skewness rule
% flipping a VIPL clip into an orientation with no real dicrotic notch,
% confirmed by comparing both orientations end-to-end -- see that
% function's own header for the full evidence and reasoning. This is a
% real, intentional divergence, not a bug: it is not applied to
% matlab/src/morphology/fixPolarity.m or matlab/src/pipeline/
% estimateVitalsAndMorphology.m (both untouched), and a human should
% decide separately whether the same fix belongs there too.
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
% signals the result is not trustworthy. Added after a live demo review
% on VIPL p4/v1/source1 surfaced exactly this: 92 candidate beats found
% from zero-crossings in a ~34s clip (physically only ~37 should exist at
% the ~66 bpm this clip's own f0 estimate reported), 85 of them rejected
% by the duration/quality gates as incoherent, leaving only 7-8 real
% cycles averaged -- diagnosed as the shared cardiac-frequency estimate
% (from a plain FFT peak-pick on a wide 0.5-8 Hz band) landing far enough
% from the true rate (65.96 bpm estimated vs 74.37 bpm ground truth, an
% ~11% error -- ordinary by this project's own validated HR-estimation
% accuracy, but catastrophic for morphology/adaptiveHarmonicFilter.m's
% narrow +/-1-FFT-bin combs, which have essentially zero tolerance for f0
% error) that the harmonic comb mostly passed noise instead of real
% cardiac harmonics. This is the SAME failure family Segment 7 Task E
% already documented (a wrong f0 estimate breaking the harmonic comb),
% just a milder manifestation than that doc's dramatic 69.4->140.8 bpm
% example. It is NOT a polarity bug -- both orientations showed low
% confidence on that clip (0.04 and 0.18), unlike the
% genuinely-polarity-flipped case chooseHeuristicPolarityByNotchConfidence
% fixes above.
%
% THRESHOLD CHOICE, READ BEFORE ADDING A beatsAveraged CUTOFF BACK: an
% earlier version of this function also flagged low beatsAveraged as
% unreliable on its own (< 15). That was WRONG and has been removed after
% it false-positived on VIPL p1/v1/source1 -- a clip already confirmed
% correct (0.92 confidence, textbook notch shape) that only averaged 9
% beats, simply because VIPL clips (~30-40s) are much shorter than UBFC's
% (~80s) and so naturally contain fewer cardiac cycles. Beat COUNT is not
% a valid reliability signal by itself; notchDetectIEM's own confidence
% (which already correctly separated p1's 0.92 from p4's 0.04/0.18) is
% the only trigger used below. beatsAveraged is still reported in the
% warning text for context, never as a pass/fail criterion.
%
% This is also not something this file can fix by itself:
% morphology/ensembleAverageBeats.m and morphology/notchDetectIEM.m were
% validated only on 5 UBFC subjects (see matlab/docs/
% Segment7_Task_B_Notch_Quantification.md); nothing established the
% morphology pipeline generalizes across VIPL's 107 real-world subjects
% the way the production HR/SpO2 path was validated to. The honest fix
% here is to say so plainly rather than present a noise-driven waveform
% as if it were a measured result.
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

function renderInteractiveFigure(result, branch2Fallback, caseID, subjectLabel, groundTruthOverlay, gtHRTrue, gtSpO2True, faceDropWarning, fpsMismatchWarning, morphologyReliabilityWarning, exportPngPath)
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

% =====================================================================
% INLINED PIPELINE FUNCTIONS -- verbatim, standalone copies of
% matlab/src/**.m (see this file's header for why). Each function below
% keeps the SAME name and SAME body as its matlab/src/ original so it is a
% straightforward side-by-side diff against the source of truth, not a
% re-derivation. Comments trimmed to the essential "what/why" (the full
% rationale/history for each lives in the original matlab/src/ file's own
% header -- not duplicated here to keep this already-long file navigable).
% =====================================================================

function result = estimateVitalsAndMorphology(videoInput, groundTruth, calibParams, opts)
% Standalone copy of matlab/src/pipeline/estimateVitalsAndMorphology.m
% (Segment 7 Task F). Runs Branch 1 (production HR/SpO2, unchanged
% detrendSignal -> bandpassClean -> chromCombine/posCombine ->
% fftHeartRate; ratioOfRatios -> calibrateSpO2) and Branch 2 (morphology:
% a shared wide-band f0 -> adaptiveHarmonicFilter -> chromCombine ->
% fixPolarityByGroundTruth/fixPolarity -> resampleUniform ->
% ensembleAverageBeats -> notchDetectIEM) off ONE shared ROI extraction,
% never merging the two filter choices (Segment 7 Task E's finding: the
% wide band + harmonic comb that Branch 2 needs measurably hurts HR
% accuracy on Branch 1's job).

if nargin < 2
    groundTruth = [];
end
if nargin < 3
    calibParams = [];
end
if nargin < 4 || isempty(opts)
    opts = struct();
end
if ~isfield(opts, 'roiMode') || isempty(opts.roiMode)
    opts.roiMode = 'forehead';
end
if ~isfield(opts, 'beatOpts') || isempty(opts.beatOpts)
    opts.beatOpts = struct();
end
if ~isfield(opts, 'subjectID')
    opts.subjectID = '';
end

if ischar(videoInput) || isstring(videoInput)
    [frames, frameRate, ~] = loadUBFCVideo(char(videoInput));
    [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate, opts.roiMode);
elseif isstruct(videoInput)
    if ~isfield(videoInput, 'R') || ~isfield(videoInput, 'G') || ~isfield(videoInput, 'B') || ~isfield(videoInput, 'fs')
        error('estimateVitalsAndMorphology:badCachedInput', 'videoInput struct must have fields R, G, B, and fs.');
    end
    R = videoInput.R;
    G = videoInput.G;
    B = videoInput.B;
    frameRate = videoInput.fs;
    if isfield(videoInput, 'roiTimestamps') && ~isempty(videoInput.roiTimestamps)
        roiTimestamps = videoInput.roiTimestamps;
    else
        roiTimestamps = (0:(numel(R) - 1)) / frameRate;
    end
else
    error('estimateVitalsAndMorphology:badVideoInput', 'videoInput must be a video path (char/string) or a struct with fields R, G, B, fs.');
end

[R_detrended, ~] = detrendSignal(R);
[G_detrended, ~] = detrendSignal(G);
[B_detrended, ~] = detrendSignal(B);

% --- Branch 1: production HR/SpO2. ---
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

branch1 = struct();
branch1.R_filtered = R_filtered;
branch1.G_filtered = G_filtered;
branch1.B_filtered = B_filtered;
branch1.pulseChromFiltered = pulseChromFiltered;
branch1.pulsePosFiltered = pulsePosFiltered;
branch1.HR_chrom = HR_chrom;
branch1.HR_pos = HR_pos;
branch1.HR_green = HR_green;
branch1.Rvalue = Rvalue;
branch1.spo2Pct = spo2Pct;
branch1.calibParamsUsed = calibParams;

% --- Branch 2: morphology (notch). ---
[R_wide, ~, ~] = bandpassMorphology(R_detrended, frameRate, 'wide');
[G_wide, ~, ~] = bandpassMorphology(G_detrended, frameRate, 'wide');
[B_wide, ~, ~] = bandpassMorphology(B_detrended, frameRate, 'wide');
pulseWide = chromCombine(R_wide, G_wide, B_wide, R, G, B);
sharedF0Hz = fftHeartRate(pulseWide, frameRate) / 60;

[R_ahf, ~, ~] = adaptiveHarmonicFilter(R_detrended, frameRate, 6, sharedF0Hz);
[G_ahf, ~, ~] = adaptiveHarmonicFilter(G_detrended, frameRate, 6, sharedF0Hz);
[B_ahf, ~, ~] = adaptiveHarmonicFilter(B_detrended, frameRate, 6, sharedF0Hz);
pulseAdaptive = chromCombine(R_ahf, G_ahf, B_ahf, R, G, B);

useGroundTruth = ~isempty(groundTruth);

if useGroundTruth
    [pulseAdaptiveFixed, wasFlipped] = fixPolarityByGroundTruth(pulseAdaptive, roiTimestamps, groundTruth.ppg, groundTruth.timestamp);
    polarityMethod = 'groundTruth';

    [sigAdaptiveUniform, timeUniform, fsAdaptiveUniform] = resampleUniform(pulseAdaptiveFixed, roiTimestamps);
    [prototype, iqrBand, beatMatrix, beatStats] = ensembleAverageBeats(sigAdaptiveUniform, fsAdaptiveUniform, opts.beatOpts);
    hrBpmUsed = fftHeartRate(sigAdaptiveUniform, fsAdaptiveUniform);
    effectiveFsHz = numel(prototype.trimmedMean) * (hrBpmUsed / 60);
    [notchDetected, notchPositionNormalized, notchDepth, notchConfidence, notchConfidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFsHz);
else
    % NO GROUND TRUTH AVAILABLE -- confidence-anchored polarity, NOT the
    % plain skewness-only morphology/fixPolarity.m rule. See
    % chooseHeuristicPolarityByNotchConfidence's own header below for the
    % full justification: a live demo review on VIPL p1/v1/source1 caught
    % the skewness rule flipping a clip it should not have (flipped
    % orientation: no real notch, notchDetectIEM confidence 0.04; as-is
    % orientation: a clean textbook notch at confidence 0.92) -- the SAME
    % systematic bias morphology/fixPolarity.m's own header already
    % documents on this project's 5 UBFC subjects (it flipped all 5, but
    % ground truth says only 3 of 5 needed flipping). This diverges from
    % matlab/src/pipeline/estimateVitalsAndMorphology.m's Branch 2 (which
    % still calls the plain morphology/fixPolarity.m, unmodified) --
    % intentionally, and only in this standalone file; see this file's
    % top-of-file header for that tradeoff stated plainly.
    chosen = chooseHeuristicPolarityByNotchConfidence(pulseAdaptive, frameRate, roiTimestamps, opts.beatOpts);

    pulseAdaptiveFixed = chosen.pulseAdaptiveFixed;
    wasFlipped = chosen.wasFlipped;
    polarityMethod = chosen.polarityMethod;
    sigAdaptiveUniform = chosen.sigAdaptiveUniform;
    timeUniform = chosen.timeUniform;
    fsAdaptiveUniform = chosen.fsAdaptiveUniform;
    prototype = chosen.prototype;
    iqrBand = chosen.iqrBand;
    beatMatrix = chosen.beatMatrix;
    beatStats = chosen.beatStats;
    hrBpmUsed = chosen.hrBpmUsed;
    effectiveFsHz = chosen.effectiveFsHz;
    notchDetected = chosen.notchDetected;
    notchPositionNormalized = chosen.notchPositionNormalized;
    notchDepth = chosen.notchDepth;
    notchConfidence = chosen.notchConfidence;
    notchConfidenceRaw = chosen.notchConfidenceRaw;
end

branch2 = struct();
branch2.sharedF0Hz = sharedF0Hz;
branch2.pulseAdaptive = pulseAdaptive;
branch2.pulseAdaptiveFixed = pulseAdaptiveFixed;
branch2.polarityMethod = polarityMethod;
branch2.wasFlipped = wasFlipped;
branch2.sigUniform = sigAdaptiveUniform;
branch2.timeUniform = timeUniform;
branch2.uniformFs = fsAdaptiveUniform;
branch2.prototype = prototype;
branch2.iqrBand = iqrBand;
branch2.beatMatrix = beatMatrix;
branch2.beatStats = beatStats;
branch2.hrBpmUsed = hrBpmUsed;
branch2.effectiveFsHz = effectiveFsHz;
branch2.notchDetected = notchDetected;
branch2.notchPositionNormalized = notchPositionNormalized;
branch2.notchDepth = notchDepth;
branch2.notchConfidence = notchConfidence;
branch2.notchConfidenceRaw = notchConfidenceRaw;

result = struct();
result.subjectID = opts.subjectID;
result.frameRate = frameRate;
result.roiTimestamps = roiTimestamps;
result.R = R;
result.G = G;
result.B = B;
result.hrBpm = struct('chrom', HR_chrom, 'pos', HR_pos, 'green', HR_green);
result.spo2Pct = spo2Pct;
result.prototype = prototype;
result.iqrBand = iqrBand;
result.notch = struct();
result.notch.detected = notchDetected;
result.notch.position = notchPositionNormalized;
result.notch.depth = notchDepth;
result.notch.confidence = notchConfidence;
result.notch.confidenceRaw = notchConfidenceRaw;
result.branch1 = branch1;
result.branch2 = branch2;

end

function branchTwoResult = chooseHeuristicPolarityByNotchConfidence(pulseAdaptive, frameRate, roiTimestamps, beatOpts)
% CHOOSEHEURISTICPOLARITYBYNOTCHCONFIDENCE No-ground-truth Branch 2
% polarity selection used ONLY by this standalone file's Cases 2/3 (VIPL /
% arbitrary video -- no continuous contact-PPG reference available).
%
% WHY THIS EXISTS, READ BEFORE REVERTING TO THE PLAIN SKEWNESS RULE:
% matlab/src/morphology/fixPolarity.m's own header already documents a
% systematic bias found on this project's 5 UBFC subjects: the skewness
% heuristic flipped ALL 5 (every skew value came out negative), while the
% ground-truth-anchored rule needed to flip only 3 of them -- a
% systematic all-flip, not scatter, hypothesized there to be forehead
% camera-rPPG's waveform asymmetry running opposite to the fingertip-PPG
% convention the skewness rule was originally derived from. This
% project's own supervisor caught the SAME failure live, on a 6th subject
% (VIPL p1/v1/source1, reviewing this file's Case-2 output): skew came out
% negative (-0.330) so morphology/fixPolarity.m flipped it, but the
% FLIPPED orientation shows no real notch at all (smooth monotonic decay;
% notchDetectIEM confidence 0.04, noise-level), while the UNFLIPPED
% orientation shows a textbook systolic-peak -> notch -> dicrotic-wave
% shape at confidence 0.92 -- diagnosed and confirmed (both orientations
% run end-to-end and compared) before this fix was written, not guessed.
%
% Rather than hardcode "always invert the skewness rule" from an n=6
% sample, this function instead runs BOTH candidate orientations all the
% way through resampleUniform -> ensembleAverageBeats -> notchDetectIEM
% and keeps whichever orientation's notchDetectIEM reports the higher
% confidenceRaw (the UNCLIPPED confidence metric -- see this file's own
% copy of notchDetectIEM's header for why confidenceRaw, not the
% min(1,...)-clipped confidence, is the right one to compare on). This is
% self-correcting regardless of which direction any given camera/ROI's
% skew bias happens to run, rather than betting on this project's small
% sample continuing to point the same way forever. If
% ensembleAverageBeats fails (too-few-beats) for one orientation but not
% the other, the surviving orientation is used; if it fails for BOTH, one
% of the two original errors is rethrown so the caller's existing
% too-few-beats guardrail (see safeEstimate below) still applies
% unchanged.
%
% THIS DIVERGES FROM matlab/src/pipeline/estimateVitalsAndMorphology.m's
% Branch 2 (which still calls the plain, unmodified
% morphology/fixPolarity.m for its own heuristic fallback) --
% intentionally, and only in this standalone file; that source-of-truth
% file is NOT changed by this fix. See this file's top-of-file header for
% that tradeoff stated plainly, and tell a human reviewer this finding
% likely applies to matlab/src/morphology/fixPolarity.m too, as a
% separate, deliberately-not-silent decision -- it is not fixed there by
% this change.
%
% Output: branchTwoResult, a struct with fields pulseAdaptiveFixed,
% wasFlipped, polarityMethod ('heuristicConfidenceAnchored'),
% sigAdaptiveUniform, timeUniform, fsAdaptiveUniform, prototype, iqrBand,
% beatMatrix, beatStats, hrBpmUsed, effectiveFsHz, notchDetected,
% notchPositionNormalized, notchDepth, notchConfidence, notchConfidenceRaw
% -- the same set of values the caller would otherwise have unpacked from
% a single fixPolarity() + resampleUniform() + ensembleAverageBeats() +
% notchDetectIEM() call sequence.

candidateSigns = [1, -1];
results = cell(1, 2);
candidateErrors = cell(1, 2);

for c = 1:2
    try
        candSig = candidateSigns(c) * pulseAdaptive;
        [sigU, timeU, fsU] = resampleUniform(candSig, roiTimestamps);
        [proto, iqrB, beatM, beatS] = ensembleAverageBeats(sigU, fsU, beatOpts);
        hrUsed = fftHeartRate(sigU, fsU);
        effFs = numel(proto.trimmedMean) * (hrUsed / 60);
        [nDet, nPos, nDepth, nConf, nConfRaw] = notchDetectIEM(proto.trimmedMean, effFs);

        r = struct();
        r.pulseAdaptiveFixed = candSig;
        r.wasFlipped = (candidateSigns(c) == -1);
        r.sigAdaptiveUniform = sigU;
        r.timeUniform = timeU;
        r.fsAdaptiveUniform = fsU;
        r.prototype = proto;
        r.iqrBand = iqrB;
        r.beatMatrix = beatM;
        r.beatStats = beatS;
        r.hrBpmUsed = hrUsed;
        r.effectiveFsHz = effFs;
        r.notchDetected = nDet;
        r.notchPositionNormalized = nPos;
        r.notchDepth = nDepth;
        r.notchConfidence = nConf;
        r.notchConfidenceRaw = nConfRaw;
        results{c} = r;
    catch candErr
        candidateErrors{c} = candErr;
    end
end

if isempty(results{1}) && isempty(results{2})
    if ~isempty(candidateErrors{1})
        rethrow(candidateErrors{1});
    else
        rethrow(candidateErrors{2});
    end
elseif isempty(results{1})
    disp('run_spandan_interactive: confidence-anchored polarity -- as-is orientation failed ensembleAverageBeats, using flipped.');
    chosen = results{2};
elseif isempty(results{2})
    disp('run_spandan_interactive: confidence-anchored polarity -- flipped orientation failed ensembleAverageBeats, using as-is.');
    chosen = results{1};
else
    if results{1}.notchConfidenceRaw >= results{2}.notchConfidenceRaw
        chosen = results{1};
        chosenLabel = 'as-is';
    else
        chosen = results{2};
        chosenLabel = 'flipped';
    end
    disp(['run_spandan_interactive: confidence-anchored polarity -- as-is confRaw=' num2str(results{1}.notchConfidenceRaw) ', flipped confRaw=' num2str(results{2}.notchConfidenceRaw) ' -> chose ' chosenLabel '.']);
end

chosen.polarityMethod = 'heuristicConfidenceAnchored';
branchTwoResult = chosen;

end

function gt = loadGroundTruth(gtPath, datasetFormat)
% Standalone copy of matlab/src/io/loadGroundTruth.m.
gt = struct();

if strcmp(datasetFormat, 'dataset1')
    rawData = readmatrix(gtPath, 'Delimiter', ',', 'FileType', 'text');
    gt.timestamp = rawData(:, 1) / 1000;
    gt.hr = rawData(:, 2);
    gt.spo2 = rawData(:, 3);
    gt.ppg = rawData(:, 4);
elseif strcmp(datasetFormat, 'dataset2')
    rawData = readmatrix(gtPath, 'FileType', 'text');
    gt.ppg = rawData(1, :);
    gt.hr = rawData(2, :);
    gt.timestamp = rawData(3, :);
    gt.spo2 = [];
else
    error('loadGroundTruth:badFormat', 'Unknown datasetFormat "%s", expected ''dataset1'' or ''dataset2''.', datasetFormat);
end

end

function [frames, frameRate, numFrames] = loadUBFCVideo(videoPath)
% Standalone copy of matlab/src/io/loadUBFCVideo.m (a generic VideoReader
% wrapper despite its name -- works on any video file).
if ~isfile(videoPath)
    error('loadUBFCVideo:fileNotFound', 'Video file not found: %s', videoPath);
end

frames = VideoReader(videoPath);
frameRate = frames.FrameRate;
numFrames = frames.NumFrames;

end

function [frames, frameRate, numFrames, videoPath] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum)
% Standalone copy of matlab/src/io/loadVIPLVideo.m. Corrects frameRate
% against time.txt when present (source1/source3) -- VIPL's own ReadMe.pdf
% states these containers are re-encoded and their container frame rate
% does not reflect real acquisition timing.
if sourceNum == 4
    error('loadVIPLVideo:nirNotSupported', 'source4 is the VIPL-HR NIR camera, not RGB.');
end
if sourceNum ~= 1 && sourceNum ~= 2 && sourceNum ~= 3
    error('loadVIPLVideo:badSource', 'sourceNum must be 1, 2, or 3 (got %s).', num2str(sourceNum));
end

subjectFolder = ['p' num2str(subjectNum)];
scenarioFolder = ['v' num2str(scenarioNum)];
sourceFolder = ['source' num2str(sourceNum)];

videoPath = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder, 'video.avi');

if ~isfile(videoPath)
    error('loadVIPLVideo:fileNotFound', 'Video file not found: %s', videoPath);
end

frames = VideoReader(videoPath);
containerFrameRate = frames.FrameRate;
numFrames = frames.NumFrames;

timePath = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder, 'time.txt');

if isfile(timePath)
    frameTimestampsMs = readmatrix(timePath, 'FileType', 'text');
    numTimestamps = numel(frameTimestampsMs);

    if numTimestamps >= 2
        elapsedSec = (frameTimestampsMs(numTimestamps) - frameTimestampsMs(1)) / 1000;
        timestampFrameRate = (numTimestamps - 1) / elapsedSec;
        relativeDiff = abs(timestampFrameRate - containerFrameRate) / containerFrameRate;

        if relativeDiff > 0.05
            disp(['loadVIPLVideo: WARNING -- container FrameRate (' num2str(containerFrameRate) ' fps) disagrees with time.txt-derived FrameRate (' num2str(timestampFrameRate) ' fps) by ' num2str(100 * relativeDiff) '% for ' videoPath '. Using the time.txt-derived value.']);
        end

        frameRate = timestampFrameRate;
    else
        disp(['loadVIPLVideo: time.txt found but has fewer than 2 timestamps, falling back to container FrameRate for ' videoPath]);
        frameRate = containerFrameRate;
    end
else
    disp(['loadVIPLVideo: no time.txt for source' num2str(sourceNum) ' (' videoPath '), using container FrameRate = ' num2str(containerFrameRate) ' fps.']);
    frameRate = containerFrameRate;
end

end

function gt = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, sourceNum)
% Standalone copy of matlab/src/io/loadVIPLGroundTruth.m. gt.ppg (wave.csv,
% ~60 Hz) is NOT the same length as gt.timestamp/gt.hr/gt.spo2 (1 Hz) --
% intentionally not used as a continuous overlay anywhere in this file.
subjectFolder = ['p' num2str(subjectNum)];
scenarioFolder = ['v' num2str(scenarioNum)];
sourceFolder = ['source' num2str(sourceNum)];

gtFolder = fullfile(viplRoot, subjectFolder, scenarioFolder, sourceFolder);

hrPath = fullfile(gtFolder, 'gt_HR.csv');
spo2Path = fullfile(gtFolder, 'gt_SpO2.csv');
wavePath = fullfile(gtFolder, 'wave.csv');

if ~isfile(hrPath)
    error('loadVIPLGroundTruth:fileNotFound', 'gt_HR.csv not found: %s', hrPath);
end
if ~isfile(spo2Path)
    error('loadVIPLGroundTruth:fileNotFound', 'gt_SpO2.csv not found: %s', spo2Path);
end
if ~isfile(wavePath)
    error('loadVIPLGroundTruth:fileNotFound', 'wave.csv not found: %s', wavePath);
end

hrTable = readtable(hrPath);
spo2Table = readtable(spo2Path);
waveTable = readtable(wavePath);

hrValues = hrTable.HR;
spo2Values = spo2Table.SpO2;
ppgValues = waveTable.Wave;

numHRSamples = numel(hrValues);
numSpO2Samples = numel(spo2Values);

if numHRSamples ~= numSpO2Samples
    disp(['loadVIPLGroundTruth: WARNING -- gt_HR.csv has ' num2str(numHRSamples) ' rows but gt_SpO2.csv has ' num2str(numSpO2Samples) ' rows for ' gtFolder ', truncating both to the shorter length.']);
end

numCommonSamples = min(numHRSamples, numSpO2Samples);

hr = zeros(numCommonSamples, 1);
spo2 = zeros(numCommonSamples, 1);
timestamp = zeros(numCommonSamples, 1);

for samplePos = 1:numCommonSamples
    hr(samplePos) = hrValues(samplePos);
    spo2(samplePos) = spo2Values(samplePos);
    timestamp(samplePos) = samplePos - 1;
end

gt = struct();
gt.timestamp = timestamp;
gt.hr = hr;
gt.spo2 = spo2;
gt.ppg = ppgValues;

end

function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(frames, frameRate, roiMode)
% Standalone copy of matlab/src/roi/extractROISignals.m. Viola-Jones face
% detection every 5th frame (reusing the last good box between detections),
% largest-area box wins on multi-detect, forehead/glabella/malar/cheek ROI
% fractions of the face box.
if nargin < 3 || isempty(roiMode)
    roiMode = 'forehead';
end

validRoiModes = {'forehead', 'glabella', 'malar', 'cheek'};
if ~ismember(roiMode, validRoiModes)
    error('extractROISignals:badRoiMode', 'roiMode must be one of forehead, glabella, malar, cheek (got %s).', roiMode);
end

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
debugFrame.regionBBoxes = struct();
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
            disp(['Frame ' num2str(frameIdx) ': face detector found nothing, reusing last known bounding box.']);
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
        disp(['Frame ' num2str(frameIdx) ': no bounding box available yet, using centered fallback box.']);
        currentBBox = [round(0.2 * frameWidth), round(0.2 * frameHeight), round(0.6 * frameWidth), round(0.6 * frameHeight)];
    end

    regionBBoxes = computeRegionBBoxes(currentBBox, frameWidth, frameHeight);

    switch roiMode
        case 'forehead'
            pixelPatches = {img(regionBBoxes.forehead(2):regionBBoxes.forehead(2) + regionBBoxes.forehead(4), regionBBoxes.forehead(1):regionBBoxes.forehead(1) + regionBBoxes.forehead(3), :)};
            currentROIBBox = regionBBoxes.forehead;
        case 'glabella'
            pixelPatches = {img(regionBBoxes.glabella(2):regionBBoxes.glabella(2) + regionBBoxes.glabella(4), regionBBoxes.glabella(1):regionBBoxes.glabella(1) + regionBBoxes.glabella(3), :)};
            currentROIBBox = regionBBoxes.glabella;
        case 'malar'
            pixelPatches = {img(regionBBoxes.malarLeft(2):regionBBoxes.malarLeft(2) + regionBBoxes.malarLeft(4), regionBBoxes.malarLeft(1):regionBBoxes.malarLeft(1) + regionBBoxes.malarLeft(3), :), img(regionBBoxes.malarRight(2):regionBBoxes.malarRight(2) + regionBBoxes.malarRight(4), regionBBoxes.malarRight(1):regionBBoxes.malarRight(1) + regionBBoxes.malarRight(3), :)};
            currentROIBBox = regionBBoxes.malarLeft;
        case 'cheek'
            pixelPatches = {img(regionBBoxes.cheekLeft(2):regionBBoxes.cheekLeft(2) + regionBBoxes.cheekLeft(4), regionBBoxes.cheekLeft(1):regionBBoxes.cheekLeft(1) + regionBBoxes.cheekLeft(3), :), img(regionBBoxes.cheekRight(2):regionBBoxes.cheekRight(2) + regionBBoxes.cheekRight(4), regionBBoxes.cheekRight(1):regionBBoxes.cheekRight(1) + regionBBoxes.cheekRight(3), :)};
            currentROIBBox = regionBBoxes.cheekLeft;
    end

    redPool = [];
    greenPool = [];
    bluePool = [];

    for patchIdx = 1:numel(pixelPatches)
        roiPatch = pixelPatches{patchIdx};
        redPool = [redPool; double(reshape(roiPatch(:, :, 1), [], 1))]; %#ok<AGROW>
        greenPool = [greenPool; double(reshape(roiPatch(:, :, 2), [], 1))]; %#ok<AGROW>
        bluePool = [bluePool; double(reshape(roiPatch(:, :, 3), [], 1))]; %#ok<AGROW>
    end

    R(frameIdx) = mean(redPool);
    G(frameIdx) = mean(greenPool);
    B(frameIdx) = mean(bluePool);
    roiTimestamps(frameIdx) = (frameIdx - 1) / frameRate;

    if frameIdx == debugFrame.frameIndex
        debugFrame.image = img;
        debugFrame.faceBBox = currentBBox;
        debugFrame.regionBBoxes = regionBBoxes;
        debugFrame.roiBBox = currentROIBBox;
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
    debugFrame.regionBBoxes = regionBBoxes;
    debugFrame.roiBBox = currentROIBBox;
    debugFrame.frameIndex = frameIdx;
end

end

function regionBBoxes = computeRegionBBoxes(faceBBox, frameWidth, frameHeight)
faceX = faceBBox(1);
faceY = faceBBox(2);
faceW = faceBBox(3);
faceH = faceBBox(4);

regionBBoxes = struct();
regionBBoxes.forehead = clampedBBox(faceX, faceY, faceW, faceH, 0.30, 0.70, 0.10, 0.30, frameWidth, frameHeight);
regionBBoxes.glabella = clampedBBox(faceX, faceY, faceW, faceH, 0.42, 0.58, 0.32, 0.40, frameWidth, frameHeight);
regionBBoxes.malarLeft = clampedBBox(faceX, faceY, faceW, faceH, 0.15, 0.32, 0.45, 0.58, frameWidth, frameHeight);
regionBBoxes.malarRight = clampedBBox(faceX, faceY, faceW, faceH, 0.68, 0.85, 0.45, 0.58, frameWidth, frameHeight);
regionBBoxes.cheekLeft = clampedBBox(faceX, faceY, faceW, faceH, 0.10, 0.35, 0.55, 0.75, frameWidth, frameHeight);
regionBBoxes.cheekRight = clampedBBox(faceX, faceY, faceW, faceH, 0.65, 0.90, 0.55, 0.75, frameWidth, frameHeight);
end

function bbox = clampedBBox(faceX, faceY, faceW, faceH, xFracLo, xFracHi, yFracLo, yFracHi, frameWidth, frameHeight)
x1 = max(1, round(faceX + xFracLo * faceW));
x2 = min(frameWidth, round(faceX + xFracHi * faceW));
y1 = max(1, round(faceY + yFracLo * faceH));
y2 = min(frameHeight, round(faceY + yFracHi * faceH));
bbox = [x1, y1, x2 - x1, y2 - y1];
end

function [signalDetrended, detrendOrder] = detrendSignal(signalRaw, polyOrder)
% Standalone copy of matlab/src/filtering/detrendSignal.m.
if nargin < 2
    polyOrder = 3;
end
detrendOrder = polyOrder;
signalDetrended = detrend(signalRaw, detrendOrder);
end

function [signalFiltered, filterOrder] = bandpassClean(signalDetrended, frameRate)
% Standalone copy of matlab/src/filtering/bandpassClean.m (0.7-4.0 Hz,
% order-2 Butterworth, zero-phase).
filterOrder = 2;
lowCutoffHz = 0.7;
highCutoffHz = 4.0;
nyquistHz = frameRate / 2;
lowCutoffNormalized = lowCutoffHz / nyquistHz;
highCutoffNormalized = highCutoffHz / nyquistHz;
[filterCoeffB, filterCoeffA] = butter(filterOrder, [lowCutoffNormalized, highCutoffNormalized], 'bandpass');
signalFiltered = filtfilt(filterCoeffB, filterCoeffA, signalDetrended);
end

function [sigFiltered, filterOrder, bandUsed] = bandpassMorphology(sigDetrended, frameRate, bandMode)
% Standalone copy of matlab/src/morphology/bandpassMorphology.m (order-3
% Butterworth; 'wide' = 0.5-8.0 Hz, 'mid' = 0.6-6.0 Hz, 'legacy' = 0.7-4.0 Hz).
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
        error('bandpassMorphology:badBandMode', 'bandMode must be one of ''wide'', ''mid'', ''legacy'' (got %s).', bandMode);
end

filterOrder = 3;
nyquistHz = frameRate / 2;

if highCutoffHz >= nyquistHz
    error('bandpassMorphology:cutoffAboveNyquist', 'highCutoffHz (%.2f Hz) for bandMode ''%s'' is at or above the Nyquist frequency (%.2f Hz) for frameRate %.2f Hz.', highCutoffHz, bandMode, nyquistHz, frameRate);
end

lowCutoffNormalized = lowCutoffHz / nyquistHz;
highCutoffNormalized = highCutoffHz / nyquistHz;

[filterCoeffB, filterCoeffA] = butter(filterOrder, [lowCutoffNormalized, highCutoffNormalized], 'bandpass');
sigFiltered = filtfilt(filterCoeffB, filterCoeffA, sigDetrended);

bandUsed = [lowCutoffHz, highCutoffHz];
end

function pulseSignal = chromCombine(R, G, B, RRaw, GRaw, BRaw)
% Standalone copy of matlab/src/pulseextraction/chromCombine.m (CHROM, de
% Haan & Jeanne 2013).
meanRRaw = mean(RRaw);
meanGRaw = mean(GRaw);
meanBRaw = mean(BRaw);

Rn = R / meanRRaw;
Gn = G / meanGRaw;
Bn = B / meanBRaw;

Xs = 3*Rn - 2*Gn;
Ys = 1.5*Rn + Gn - 1.5*Bn;

alpha = std(Xs) / std(Ys);

pulseSignal = Xs - alpha*Ys;
end

function pulseSignal = posCombine(R, G, B, frameRate, RRaw, GRaw, BRaw) %#ok<INUSD>
% Standalone copy of matlab/src/pulseextraction/posCombine.m (POS, Wang et
% al. 2017). frameRate accepted for signature consistency, not used by
% this whole-signal formula (matches the original).
meanRRaw = mean(RRaw);
meanGRaw = mean(GRaw);
meanBRaw = mean(BRaw);

Rn = R / meanRRaw;
Gn = G / meanGRaw;
Bn = B / meanBRaw;

S1 = Gn - Bn;
S2 = Gn + Bn - 2*Rn;

pulseSignal = S1 + (std(S1)/std(S2))*S2;
end

function [hrBpm, freqSpectrum, powerSpectrum] = fftHeartRate(pulseSignal, frameRate)
% Standalone copy of matlab/src/heartrate/fftHeartRate.m (FFT peak-pick,
% 0.7-4 Hz search band).
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
    error('fftHeartRate:emptyBand', 'No FFT bins fall inside the 0.7-4 Hz band -- signal too short for the given frameRate.');
end

peakPower = max(powerInBand);
peakIndex = find(powerInBand == peakPower, 1);
peakFreqHz = freqInBand(peakIndex);

hrBpm = peakFreqHz * 60;
end

function R = ratioOfRatios(R_filtered, G_filtered, B_filtered, R_raw, G_raw, B_raw, fs) %#ok<INUSD,INUSL>
% Standalone copy of matlab/src/spo2/ratioOfRatios.m. fs accepted for
% signature consistency, not used by this whole-clip formula.
DC_R = mean(R_raw);
DC_B = mean(B_raw);

AC_R = std(R_filtered);
AC_B = std(B_filtered);

R = (AC_R / DC_R) / (AC_B / DC_B);
end

function [spo2Est, calibParams] = calibrateSpO2(R, groundTruthSpO2, calibParams)
% Standalone copy of matlab/src/spo2/calibrateSpO2.m (linear
% SpO2 = A - B*R).
if isempty(calibParams)
    fitCoeffs = polyfit(R, groundTruthSpO2, 1);
    slopeCoeff = fitCoeffs(1);
    interceptCoeff = fitCoeffs(2);

    A = interceptCoeff;
    B = -slopeCoeff;

    calibParams = struct();
    calibParams.A = A;
    calibParams.B = B;
else
    A = calibParams.A;
    B = calibParams.B;
end

spo2Est = A - B * R;
end

function [sigFiltered, f0Hz, harmonicsUsedHz] = adaptiveHarmonicFilter(sigDetrended, frameRate, numHarmonics, f0HzOverride)
% Standalone copy of matlab/src/morphology/adaptiveHarmonicFilter.m
% (harmonic-comb filter: keep only narrow bins around f0 and its
% harmonics, zero everything else, IFFT back).
if nargin < 3 || isempty(numHarmonics)
    numHarmonics = 6;
end
if nargin < 4
    f0HzOverride = [];
end

sigRow = sigDetrended(:)';
N = numel(sigRow);

if isempty(f0HzOverride)
    hrBpm = fftHeartRate(sigRow, frameRate);
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

function [sigOriented, wasFlipped, skewValue] = fixPolarity(sig, frameRate)
% Standalone copy of matlab/src/morphology/fixPolarity.m (skewness
% heuristic; requires >= 10s of data).
minDurationSec = 10;

if numel(sig) / frameRate < minDurationSec
    error('fixPolarity:tooShort', 'sig must cover at least %.0f s of data (got %.2f s at %.2f Hz).', minDurationSec, numel(sig) / frameRate, frameRate);
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

function [sigOriented, wasFlipped] = fixPolarityByGroundTruth(sig, sigTimestamps, gtPPG, gtTimestamps)
% Standalone copy of matlab/src/morphology/fixPolarityByGroundTruth.m
% (cross-correlation against resampled ground-truth contact PPG).
sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';
gtPPGRow = gtPPG(:)';
gtTimestampsRow = gtTimestamps(:)';

overlapLowSec = max(sigTimestampsRow(1), gtTimestampsRow(1));
overlapHighSec = min(sigTimestampsRow(end), gtTimestampsRow(end));

if overlapHighSec <= overlapLowSec
    error('fixPolarityByGroundTruth:noOverlap', 'sigTimestamps and gtTimestamps do not overlap in time.');
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

function [sigUniform, timeUniform, targetFs] = resampleUniform(sig, sigTimestamps, targetFs)
% Standalone copy of matlab/src/morphology/resampleUniform.m ('pchip'
% resample onto a uniform 250 Hz-default grid using REAL timestamps).
if nargin < 3 || isempty(targetFs)
    targetFs = 250;
end

sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';

if numel(sigRow) ~= numel(sigTimestampsRow)
    error('resampleUniform:sizeMismatch', 'sig and sigTimestamps must have the same number of elements.');
end

timeUniform = sigTimestampsRow(1):(1 / targetFs):sigTimestampsRow(end);
sigUniform = interp1(sigTimestampsRow, sigRow, timeUniform, 'pchip');
end

function [prototype, iqrBand, beatMatrix, stats] = ensembleAverageBeats(sig, fs, opts)
% Standalone copy of matlab/src/morphology/ensembleAverageBeats.m: segment
% on negative-going zero crossings, duration-gate, two-anchor time-warp
% (systolic peak -> cycle fraction 0.25), two-pass correlation quality
% gate, trimmed-mean + median prototype, per-sample IQR stability band.
if nargin < 3 || isempty(opts)
    opts = struct();
end

opts = applyDefaultOpt(opts, 'beatSamples', 256);
opts = applyDefaultOpt(opts, 'systolicAnchorFraction', 0.25);
opts = applyDefaultOpt(opts, 'durationRejectFraction', 0.30);
opts = applyDefaultOpt(opts, 'qualityKeepFraction', 0.25);
opts = applyDefaultOpt(opts, 'trimPercent', 20);

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
    error('ensembleAverageBeats:tooFewBeats', 'Only %d beat(s) found from negative-going zero crossings -- need at least 3 to form an ensemble average.', max(numBeatsFound, 0));
end

beatDurations = diff(crossingTimes);
medianDuration = median(beatDurations);

durationOkMask = abs(beatDurations - medianDuration) / medianDuration <= opts.durationRejectFraction;
beatsRejectedByDuration = sum(~durationOkMask);

survivingBeatIdx = find(durationOkMask);
numSurviving = numel(survivingBeatIdx);

if numSurviving < 2
    error('ensembleAverageBeats:tooFewBeatsAfterDurationGate', 'Only %d beat(s) survived the duration gate -- need at least 2 to form an ensemble average.', numSurviving);
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

function opts = applyDefaultOpt(opts, fieldName, defaultValue)
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

function [notchDetected, notchPositionNormalized, notchDepth, confidence, confidenceRaw] = notchDetectIEM(prototype, fs)
% Standalone copy of matlab/src/morphology/notchDetectIEM.m (Iterative
% Envelope Mean method, Pal et al. 2024).
betaStopThreshold = 0.1;
maxIterations = 20;
sgPolyOrder = 4;
sgFrameLen = 25;
minGapSec = 0.1;

protoRow = prototype(:)';
N = numel(protoRow);

protoRange = max(protoRow) - min(protoRow);
if protoRange <= 0
    error('notchDetectIEM:flatSignal', 'prototype is constant -- cannot normalize or detect a notch.');
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

for iterIdx = 1:maxIterations %#ok<FXUP>
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
