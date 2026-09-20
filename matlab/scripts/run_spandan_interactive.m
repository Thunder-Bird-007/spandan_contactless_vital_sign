% RUN_SPANDAN_INTERACTIVE Interactive, single-video demo driver, TRULY
% STANDALONE: every pipeline function it calls is reproduced verbatim as a
% local function in THIS file. No addpath, no repo checkout, no sibling
% file or folder is needed beyond the video you pick (and, optionally,
% that video's own ground-truth sidecar file(s), which is a DATA
% requirement of the "show ground-truth comparison" feature, not a code
% dependency -- see CASE DETECTION below). Copy this one .m file to any
% machine with MATLAB (+ the toolboxes listed under REQUIREMENTS) and a
% video, and press Run.
%
% USAGE: open this file in MATLAB (any current folder) and press Run, or
% type run_spandan_interactive at the prompt. Nothing to configure first.
%
% REQUIREMENTS (standard MATLAB toolboxes -- these are installed add-ons,
% not repo files, so they are not a violation of "no file/directory
% dependency"; they are the same requirement any MATLAB installation of
% this pipeline has always had):
%   - Image Processing Toolbox      (reading/cropping video frames)
%   - Computer Vision Toolbox        (vision.CascadeObjectDetector)
%   - Signal Processing Toolbox      (butter, filtfilt, sgolayfilt, xcorr)
%   - Wavelet Toolbox                (wavedec, waverec, detcoef)
%
% =====================================================================
% DESIGN HISTORY -- READ BEFORE EDITING ANYTHING ELSE IN THIS FILE
% =====================================================================
% v1 (original): a deliberately standalone, dependency-free file with
% every pipeline function reproduced verbatim as a local copy, so it
% could be copied alone to any machine. That design's own header stated
% its tradeoff plainly: matlab/src/ stays the source of truth, and the
% copies here would "silently go stale unless someone updates them too."
% That is exactly what happened -- by 2026-09-14 this file was quietly
% running a frozen, months-stale snapshot of the pipeline, missing
% Segments 10-16 (cPACE, the mid-band bandpass option, the harmonic-
% selective Gaussian filter, and Segment 14's confidence gate).
%
% v2 (Segment 17, 2026-09-14): reversed course -- dropped the local
% copies entirely, added matlab/src/ to the MATLAB path at runtime, and
% called pipeline/estimateVitalsAndMorphology.m and every other pipeline
% function directly off the path, the SAME functions every batch script
% in matlab/scripts/ already uses. Fixed the staleness problem, but broke
% the "one file, no repo checkout" property this file exists for --
% v2 could no longer be copied alone to a machine without the rest of the
% repo, and Abrar (rightly) rejected that tradeoff.
%
% v3 (THIS VERSION, 2026-09-19): standalone again, like v1, but built
% differently to avoid v1's failure mode. Every function below was
% copied verbatim from the CURRENT matlab/src/ (as of this date) in one
% pass, immediately after actually auditing matlab/src/ against
% SESSION_HANDOFF.md's own "promoted to default" claims -- which caught a
% real bug in the process: DWT wavelet-shrinkage denoising
% (filtering/waveletDenoise.m) was documented project-wide as the
% production Branch 1 default (SESSION_HANDOFF.md Segment 8 Action 7,
% wired into scripts/run_segment3_filtering_batch.m and
% scripts/run_vipl_integration_batch.m) but had NEVER actually been added
% to pipeline/estimateVitalsAndMorphology.m -- the one shared function
% this file (and v2's own addpath-based redirection) actually called.
% That gap has been fixed HERE, and separately fixed in
% matlab/src/pipeline/estimateVitalsAndMorphology.m itself (2026-09-19),
% so both the shared function and this standalone copy now agree. This
% file being standalone is a periodic snapshot, not a live mirror: it
% WILL go stale again the next time matlab/src/ changes, exactly as v1's
% own header warned. There is no way to have both "one file, zero
% dependencies" and "automatically always current" at once -- that is a
% real, structural tradeoff, not an oversight. The mitigation is
% discipline, not code: whenever matlab/src/ changes something in the
% call graph documented below, re-diff this file against matlab/src/ by
% hand (or ask a future Claude session to do it) rather than assuming it
% is still current. Consider checking this file's own "as of" date
% against matlab/src/'s most recent relevant file mtimes before a demo
% that matters (a defense, a supervisor meeting).
%
% WHAT THIS FILE MIRRORS, AS OF 2026-09-19 (cross-check against
% matlab/src/pipeline/estimateVitalsAndMorphology.m's own header when in
% doubt):
%   Branch 1 (production HR/SpO2): waveletDenoise (db4, 3-level, default
%     true) -> detrendSignal -> bandpassClean -> chromCombine/posCombine
%     -> fftHeartRate -> HR_chrom/HR_pos/HR_green; ratioOfRatios ->
%     calibrateSpO2 (Case 1 only, calibParams supplied) -> SpO2%.
%   Branch 2 (morphology/notch): SAME wavelet-denoised + detrended input
%     -> shared f0 from a wide-band CHROM pulse (bandpassMorphology
%     'wide' -> chromCombine -> fftHeartRate) -> adaptiveHarmonicFilter
%     (ABPF, the harmonic comb, numHarmonics=6, forced onto the shared
%     f0) per channel -> chromCombine -> fixPolarityByGroundTruth (Case 1)
%     or fixPolarity (heuristic, Cases 2/3) -> resampleUniform (250 Hz)
%     -> ensembleAverageBeats -> notchDetectIEM. Segment 14's confidence
%     gate (default on): if ABPF's own notch confidence <= 0.3,
%     harmonicSelectiveGaussianFilter (alpha=0.15) is computed as a
%     fallback candidate and harmonicFilterConfidenceGate decides whether
%     to substitute it -- never overriding an already-successful ABPF
%     result, per Segment 13's own settled design.
%
% ONE REAL PIECE OF FUNCTIONALITY THIS FILE DOES NOT HAVE, FLAGGED (not
% silently lost): the old v1 standalone file had its own local
% chooseHeuristicPolarityByNotchConfidence, used ONLY for Cases 2/3 (no
% ground truth available), which ran Branch 2's waveform both ways and
% kept whichever orientation notchDetectIEM scored higher confidence on,
% rather than trusting the plain skewness rule (fixPolarity below). That
% fix was never ported into matlab/src/ and is not reproduced here either
% -- this file's Cases 2/3 use the same plain skewness heuristic
% production and the Android app use. If it still matters, the right fix
% is a human decision to add a polarityMethod hook to fixPolarity's call
% site below (or to matlab/src/morphology/fixPolarity.m itself) -- not
% done here as a side effect of this rewrite.
%
% SpO2 CALIBRATION, HONESTLY CAVEATED: Case 1 only. A truly standalone
% file cannot read other subjects' cached data/processed/*_rgb_traces.mat
% files the way v1/v2 did (that's exactly the kind of directory
% dependency this rewrite removes), so the 5-subject UBFC DATASET_1
% (R_value, SpO2_true) calibration table below is EMBEDDED as literal
% numbers, copied from results/metrics/segment5_dataset1_calibration.csv.
% CAVEAT, STATED PLAINLY: those 5 R_value numbers were computed under the
% PRE-wavelet-denoising pipeline (that CSV predates the Segment 8 Action 7
% wavelet promotion). This file's own Branch 1 now applies wavelet
% denoising by default (useWaveletDenoise below), so the picked clip's own
% R value is computed under a DIFFERENT pipeline than the 5 training
% R values it gets compared against -- a real, currently-unquantified
% train/test mismatch, not assumed negligible. If calibrated SpO2 accuracy
% matters for a real result (not just a live demo number), a human should
% regenerate results/metrics/segment5_dataset1_calibration.csv by rerunning
% the (now wavelet-fixed) pipeline on those 5 known subjects and paste the
% updated numbers into knownCalibrationSubjects below, and this comment
% should be updated to say that was done.
%
% CASE DETECTION (by files found next to the picked video, never asked of
% the user -- this reads DATA sidecar files that are part of a dataset's
% own format, not this repo's code, so it is not the kind of dependency
% this rewrite removes):
%   Case 1 -- UBFC-style, continuous ground truth: gtdump.xmp (dataset1
%             format) or ground_truth.txt (dataset2 format) sits next to
%             the picked video. Shows a ground-truth PPG overlay +
%             ground-truth HR/SpO2 numbers, and attempts calibrated SpO2
%             (see the caveat above).
%   Case 2 -- VIPL-style: the picked path matches
%             .../p<N>/v<N>/source<N>/video.avi AND gt_HR.csv + gt_SpO2.csv
%             sit next to it. Corrects frameRate against time.txt when
%             present (source1/3/4); source2 has no time.txt and is used
%             as-is (a known, documented accuracy limitation). VIPL's own
%             gt.ppg is NOT used as a continuous overlay (not aligned to
%             video time) -- only gt_HR.csv/gt_SpO2.csv's per-second means.
%   Case 3 -- arbitrary video, no ground truth found by either check
%             above: generic VideoReader decode, no ground truth, no
%             calibration -- spo2Pct is NaN and reported plainly as "not
%             calibrated, no reference available". This is the expected
%             case for "pick any video with no known ground truth" --
%             most videos land here.
%
% GUARDRAILS (unchanged from v2):
%   - Too-few-beats (ensembleAverageBeats:tooFewBeats /
%     ensembleAverageBeats:tooFewBeatsAfterDurationGate): Branch 2 failing
%     would otherwise abort the whole estimate and lose Branch 1's
%     already-good HR/SpO2 too. This script wraps the call in try/catch
%     (safeEstimate below); on either identifier it recomputes JUST
%     Branch 1 inline (same wavelet -> detrend -> bandpass -> CHROM/POS ->
%     fftHeartRate sequence as the main path), then still shows HR/SpO2
%     with the morphology panel replaced by a clear text note.
%   - Unreliable face detection: after ROI extraction, if
%     numel(droppedFrameIdx)/numFrames exceeds 30%, a clear warning is
%     printed and shown on the figure.
%   - Case 3 scalar-frame-rate mismatch (checkFrameRateMismatch below):
%     Case 3 has no sidecar metadata to correct VideoReader.FrameRate the
%     way VIPL source1/3/4 has via time.txt -- a real 52.1-vs-~63-bpm
%     error was traced to exactly this on a VIPL source2 clip. A freshly
%     recorded phone clip is frequently variable-frame-rate and exposed to
%     the same failure mode. This script compares VideoReader.FrameRate
%     against NumFrames/Duration; if they disagree by more than ~3%, it
%     warns that the reported HR may carry a proportional scale error. It
%     does NOT silently "correct" frameRate -- there is no reliable ground
%     truth for an arbitrary video, so this warns rather than guesses.
%   - Morphology reliability: if Branch 2 "succeeds" mechanically but
%     notchDetectIEM's own confidence is low, the waveform panels are
%     flagged as unreliable rather than presented as a measured result
%     (checkMorphologyReliability below -- see its own header).
%   - Large/long videos: never calls read(videoReaderObj) or otherwise
%     pre-buffers frames; streams with hasFrame/readFrame throughout.
%
% The core "given a resolved videoPath, do everything" logic lives in the
% local function runSpandanInteractiveCore(videoPath, exportPngPath) below
% specifically so it can be invoked directly with a hardcoded path for
% testing without needing to click through a uigetfile dialog.
% exportPngPath is optional and testing-only (exportgraphics to a PNG in
% addition to showing the on-screen figure) -- the normal interactive path
% below never passes it, and the figure this function creates is always a
% normal visible figure(), never 'Visible','off'.

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
% class, run the pipeline (all local functions below, see this file's own
% header for the exact call graph mirrored), render the combined figure,
% and return the result struct (mainly so a caller/test can inspect it).
% exportPngPath is optional (testing only, see this file's header).

if nargin < 2
    exportPngPath = '';
end

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

        rawGForDisplay = G; % TRUE raw (pre-wavelet) trace, kept only for panel (i) -- see runPipelineOnROI below

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

        calibParams = tryFitCaseOneCalibration(subjectLabel);

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

        rawGForDisplay = G;

        faceDropWarning = checkFaceDropRate(droppedFrameIdx, numFrames);

        videoInputStruct = struct('R', R, 'G', G, 'B', B, 'fs', frameRate, 'roiTimestamps', roiTimestamps);

        gtVIPL = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, sourceNum);
        gtHRTrue = mean(gtVIPL.hr);
        gtSpO2True = mean(gtVIPL.spo2);
        % gt.ppg intentionally NOT used here -- not aligned/usable as a
        % continuous overlay (see loadVIPLGroundTruth's own header below).

        calibParams = []; % never calibrated for VIPL in this script

        [result, branch2Fallback] = safeEstimate(videoInputStruct, [], calibParams, subjectLabel, frameRate);

    otherwise
        % --- Case 3: arbitrary video, no ground truth found. ---
        [frames, frameRate, numFrames] = loadUBFCVideo(videoPath); % generic VideoReader wrapper

        % Case 3 has no sidecar metadata (no time.txt the way VIPL's
        % loadVIPLVideo has for source1/3/4) to correct frameRate against,
        % so it trusts VideoReader.FrameRate as-is -- exactly the
        % situation that produced a real 52.1-vs-~63-bpm error on a VIPL
        % source2 phone clip. A freshly recorded phone demo clip is
        % frequently variable-frame-rate and exposed to the exact same
        % failure mode. This is a non-fatal SANITY CHECK only --
        % NumFrames/Duration is not a ground-truth frame rate either
        % (Duration itself can be a container-metadata artifact), so it
        % is never used to "correct" frameRate, only to warn.
        fpsMismatchWarning = checkFrameRateMismatch(frames, frameRate);
        if ~isempty(fpsMismatchWarning)
            disp(['run_spandan_interactive: WARNING -- ' fpsMismatchWarning]);
        end

        [R, G, B, roiTimestamps, droppedFrameIdx, ~] = extractROISignals(frames, frameRate, 'forehead');

        rawGForDisplay = G;

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

renderInteractiveFigure(result, branch2Fallback, caseID, subjectLabel, groundTruthOverlay, gtHRTrue, gtSpO2True, faceDropWarning, fpsMismatchWarning, morphologyReliabilityWarning, rawGForDisplay, exportPngPath);

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
% catastrophic for the harmonic comb's narrow +/-1-FFT-bin combs, which
% have essentially zero tolerance for f0 error) that the harmonic comb
% mostly passed noise instead of real cardiac harmonics. It is NOT a
% polarity bug -- both orientations showed low confidence on that clip
% (0.04 and 0.18).
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
% This is also not something this file can fix by itself: the ensemble-
% averaging/notch-detection functions below were validated only on 5 UBFC
% subjects; nothing established the morphology pipeline generalizes across
% VIPL's 107 real-world subjects the way the production HR/SpO2 path was
% validated to. The honest fix here is to say so plainly rather than
% present a noise-driven waveform as if it were a measured result.
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
% (VIPL's own loadVIPLVideo below does an actual ground-truth-free
% correction for source1/3/4, because VIPL provides real per-frame
% timestamps via time.txt; no such sidecar exists for an arbitrary video).
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

function calibParams = tryFitCaseOneCalibration(subjectLabel)
% TRYFITCASEONECALIBRATION Leave-one-out linear SpO2 calibration
% (calibrateSpO2 below, unmodified) fit on an EMBEDDED literal table of
% (R_value, SpO2_true) pairs for the 5 UBFC DATASET_1 subjects this
% project has ground truth for, copied verbatim from
% results/metrics/segment5_dataset1_calibration.csv. Excludes
% subjectLabel itself if it matches one of the known IDs (never fit and
% predict on the same subject). Returns [] if fewer than 2 other subjects
% remain after exclusion.
%
% CAVEAT (read this file's own top-of-file header, "SpO2 CALIBRATION,
% HONESTLY CAVEATED", for the full explanation): these 5 R_value numbers
% were computed under the PRE-wavelet-denoising pipeline. This file's own
% Branch 1 (runPipelineOnROI below) now wavelet-denoises by default, so
% the picked clip's own R value and these 5 training R values come from
% two different pipelines -- a real, currently-unquantified train/test
% mismatch, disclosed here rather than silently assumed harmless.

knownCalibrationSubjects = struct( ...
    'id',    {'5-gt',    '6-gt',    '7-gt',    '12-gt',   'after-exercise'}, ...
    'R',     {0.83583,   0.85947,   0.86383,   0.52026,   0.71762}, ...
    'SpO2',  {98.8911,   96.5468,   96.4386,   95.9930,   97.9614});

trainR = [];
trainSpO2 = [];

for idx = 1:numel(knownCalibrationSubjects)
    if strcmp(knownCalibrationSubjects(idx).id, subjectLabel)
        continue; % never train on the subject being predicted
    end
    trainR(end + 1) = knownCalibrationSubjects(idx).R; %#ok<AGROW>
    trainSpO2(end + 1) = knownCalibrationSubjects(idx).SpO2; %#ok<AGROW>
end

if numel(trainR) < 2
    calibParams = [];
    disp('run_spandan_interactive: fewer than 2 other known-calibration subjects available -- skipping SpO2 calibration (spo2Pct will be NaN).');
    return;
end

[~, calibParams] = calibrateSpO2(trainR, trainSpO2, []);
disp(['run_spandan_interactive: fit leave-one-out SpO2 calibration on ' num2str(numel(trainR)) ' embedded known UBFC subject(s). CAVEAT: these R values predate this file''s wavelet-denoise default -- see this file''s own header.']);

end

function [result, branch2Fallback] = safeEstimate(videoInputStruct, groundTruth, calibParams, subjectLabel, frameRate)
% SAFEESTIMATE Calls runPipelineOnROI (below -- this file's own local,
% standalone equivalent of pipeline/estimateVitalsAndMorphology.m,
% including the same 2026-09-19 wavelet-denoise fix applied to that
% shared function). On the two documented too-few-beats error
% identifiers, recomputes JUST Branch 1 inline (replicating the same
% wavelet -> detrend -> bandpass -> CHROM/POS sequence, using the same
% local functions) so a short clip still reports valid HR/SpO2 instead of
% losing everything. branch2Fallback is [] on success, or a struct with a
% .message field describing the fallback when Branch 2 failed.

branch2Fallback = [];

try
    result = runPipelineOnROI(videoInputStruct, groundTruth, calibParams, struct('subjectID', subjectLabel));
catch causeErr
    if strcmp(causeErr.identifier, 'ensembleAverageBeats:tooFewBeats') || strcmp(causeErr.identifier, 'ensembleAverageBeats:tooFewBeatsAfterDurationGate')
        disp(['run_spandan_interactive: WARNING -- morphology (Branch 2) failed (' causeErr.identifier '): ' causeErr.message]);
        disp('run_spandan_interactive: falling back to Branch-1-only (HR/SpO2 still valid; no ensemble-averaged waveform for this clip).');

        R = waveletDenoise(videoInputStruct.R);
        G = waveletDenoise(videoInputStruct.G);
        B = waveletDenoise(videoInputStruct.B);

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

function renderInteractiveFigure(result, branch2Fallback, caseID, subjectLabel, groundTruthOverlay, gtHRTrue, gtSpO2True, faceDropWarning, fpsMismatchWarning, morphologyReliabilityWarning, rawGForDisplay, exportPngPath)
% RENDERINTERACTIVEFIGURE Builds the combined 3x2 (+ optional GT overlay)
% figure and shows it on screen (a normal visible figure() -- this is an
% interactive tool, never 'Visible','off'). rawGForDisplay is the TRUE
% raw (pre-wavelet-denoise) G(t) trace, captured by the caller BEFORE
% runPipelineOnROI's internal wavelet-denoise step runs, so panel (i)
% shows genuinely raw pixel data and is labeled accordingly -- see this
% file's own header note on the wavelet fix for why result.G is no longer
% the right signal for this panel.

NUM_CYCLES_MULTIPANEL = 8; % tunable: how many real cardiac cycles the multi-cycle panel shows
MULTIPANEL_START_OFFSET_SEC = 5; % skip filter-startup transient

figHandle = figure('Position', [80 80 1400 1350]);
tl = tiledlayout(figHandle, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- Panel (i): TRUE raw ROI trace (pre-wavelet-denoise G(t)), plus a
% Case-1 ground-truth PPG overlay on a secondary y-axis when available. ---
axRaw = nexttile(tl);
rawTimeAxis = result.roiTimestamps;
plot(axRaw, rawTimeAxis, rawGForDisplay, 'LineWidth', 1.1, 'Color', [0.20 0.45 0.20], 'DisplayName', 'Raw ROI G(t)');
xlabel(axRaw, 'Time (s)');
ylabel(axRaw, 'Raw pixel intensity');
xlim(axRaw, [rawTimeAxis(1), rawTimeAxis(end)]);
box(axRaw, 'on');

if ~isempty(groundTruthOverlay)
    yyaxis(axRaw, 'right');
    plot(axRaw, groundTruthOverlay.timestamp, groundTruthOverlay.ppg, 'Color', [0.75 0.30 0.10], 'LineWidth', 0.8);
    ylabel(axRaw, 'Ground-truth PPG (raw)');
    yyaxis(axRaw, 'left');
    title(axRaw, '(i) Raw ROI trace, G(t) (pre-wavelet), with ground-truth PPG overlay');
else
    title(axRaw, '(i) Raw ROI trace, G(t) (pre-wavelet)');
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
% note as panel (iii) when Branch 2 failed on this clip. Reuses
% result.branch2.sigUniform/uniformFs -- Branch 2's own pre-ensemble-
% averaging signal, already polarity-fixed by whichever method
% runPipelineOnROI used (fixPolarityByGroundTruth for Case 1, fixPolarity
% for Cases 2/3). Real continuous samples only -- never tiles/repeats
% panel (iii). ---
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

    % Segment 14's confidence gate is production default -- surface which
    % filter it actually used for this clip, so "run the current
    % pipeline" is visibly true, not just claimed.
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

if isfield(result, 'waveletDenoiseUsed') && result.waveletDenoiseUsed
    summaryLines{end + 1} = 'Pre-step: DWT wavelet-shrinkage denoise (db4, 3-level) applied before detrend/bandpass.';
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
% so a reader can visually count cycles.

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
% PIPELINE ORCHESTRATOR -- local, standalone equivalent of
% matlab/src/pipeline/estimateVitalsAndMorphology.m. Kept as close to
% byte-identical to that file as a local-function rewrite allows; see
% that file's own header (also fixed 2026-09-19) for the fully-commented
% version of everything below. Renamed runPipelineOnROI (not
% estimateVitalsAndMorphology) purely so grepping this file never
% confuses this local copy with the shared matlab/src/ function during a
% future stale-diff check.
% =====================================================================
function result = runPipelineOnROI(videoInput, groundTruth, calibParams, opts)

if nargin < 2
    groundTruth = [];
end
if nargin < 3
    calibParams = [];
end
if nargin < 4 || isempty(opts)
    opts = struct();
end
if ~isfield(opts, 'beatOpts') || isempty(opts.beatOpts)
    opts.beatOpts = struct();
end
if ~isfield(opts, 'subjectID')
    opts.subjectID = '';
end
if ~isfield(opts, 'useWaveletDenoise') || isempty(opts.useWaveletDenoise)
    opts.useWaveletDenoise = true; % matches matlab/src/'s own 2026-09-19 fix
end
if ~isfield(opts, 'useConfidenceGate') || isempty(opts.useConfidenceGate)
    opts.useConfidenceGate = true; % Segment 14 Task 2 promotion
end

if ~isfield(videoInput, 'R') || ~isfield(videoInput, 'G') || ~isfield(videoInput, 'B') || ~isfield(videoInput, 'fs')
    error('runPipelineOnROI:badInput', 'videoInput struct must have fields R, G, B, and fs.');
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

if opts.useWaveletDenoise
    R = waveletDenoise(R);
    G = waveletDenoise(G);
    B = waveletDenoise(B);
end

[R_detrended, ~] = detrendSignal(R);
[G_detrended, ~] = detrendSignal(G);
[B_detrended, ~] = detrendSignal(B);

% === Branch 1: production HR/SpO2. ===
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

% === Branch 2: morphology (notch). ===
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
else
    [pulseAdaptiveFixed, wasFlipped, ~] = fixPolarity(pulseAdaptive, frameRate);
    polarityMethod = 'heuristic';
end

[sigAdaptiveUniform, timeUniform, fsAdaptiveUniform] = resampleUniform(pulseAdaptiveFixed, roiTimestamps);
[prototype, iqrBand, beatMatrix, beatStats] = ensembleAverageBeats(sigAdaptiveUniform, fsAdaptiveUniform, opts.beatOpts);

hrBpmUsed = fftHeartRate(sigAdaptiveUniform, fsAdaptiveUniform);
effectiveFsHz = numel(prototype.trimmedMean) * (hrBpmUsed / 60);
[notchDetected, notchPositionNormalized, notchDepth, notchConfidence, notchConfidenceRaw] = notchDetectIEM(prototype.trimmedMean, effectiveFsHz);

abpfNotchConfidence = notchConfidence;
harmonicMethodUsed = 'adaptiveHarmonic';
gateSubstituted = false;
gaussianNotchConfidence = NaN;
confidenceGateBar = 0.3;

if opts.useConfidenceGate && abpfNotchConfidence <= confidenceGateBar
    [R_gau, ~, ~] = harmonicSelectiveGaussianFilter(R_detrended, frameRate, 6, sharedF0Hz, 0.15);
    [G_gau, ~, ~] = harmonicSelectiveGaussianFilter(G_detrended, frameRate, 6, sharedF0Hz, 0.15);
    [B_gau, ~, ~] = harmonicSelectiveGaussianFilter(B_detrended, frameRate, 6, sharedF0Hz, 0.15);
    pulseGaussian = chromCombine(R_gau, G_gau, B_gau, R, G, B);

    if useGroundTruth
        [pulseGaussianFixed, wasFlippedGaussian] = fixPolarityByGroundTruth(pulseGaussian, roiTimestamps, groundTruth.ppg, groundTruth.timestamp);
    else
        [pulseGaussianFixed, wasFlippedGaussian, ~] = fixPolarity(pulseGaussian, frameRate);
    end

    [sigGaussianUniform, timeUniformGaussian, fsGaussianUniform] = resampleUniform(pulseGaussianFixed, roiTimestamps);
    [prototypeGaussian, iqrBandGaussian, beatMatrixGaussian, beatStatsGaussian] = ensembleAverageBeats(sigGaussianUniform, fsGaussianUniform, opts.beatOpts);
    hrBpmUsedGaussian = fftHeartRate(sigGaussianUniform, fsGaussianUniform);
    effectiveFsHzGaussian = numel(prototypeGaussian.trimmedMean) * (hrBpmUsedGaussian / 60);
    [notchDetectedGaussian, notchPositionNormalizedGaussian, notchDepthGaussian, notchConfidenceGaussian, notchConfidenceRawGaussian] = ...
        notchDetectIEM(prototypeGaussian.trimmedMean, effectiveFsHzGaussian);
    gaussianNotchConfidence = notchConfidenceGaussian;

    [~, harmonicMethodUsed, ~, gateSubstituted] = harmonicFilterConfidenceGate( ...
        pulseAdaptiveFixed, abpfNotchConfidence, 'adaptiveHarmonic', ...
        {pulseGaussianFixed}, notchConfidenceGaussian, {'gaussian015'}, confidenceGateBar);

    if gateSubstituted
        pulseAdaptive = pulseGaussian;
        pulseAdaptiveFixed = pulseGaussianFixed;
        wasFlipped = wasFlippedGaussian;
        sigAdaptiveUniform = sigGaussianUniform;
        timeUniform = timeUniformGaussian;
        fsAdaptiveUniform = fsGaussianUniform;
        prototype = prototypeGaussian;
        iqrBand = iqrBandGaussian;
        beatMatrix = beatMatrixGaussian;
        beatStats = beatStatsGaussian;
        hrBpmUsed = hrBpmUsedGaussian;
        effectiveFsHz = effectiveFsHzGaussian;
        notchDetected = notchDetectedGaussian;
        notchPositionNormalized = notchPositionNormalizedGaussian;
        notchDepth = notchDepthGaussian;
        notchConfidence = notchConfidenceGaussian;
        notchConfidenceRaw = notchConfidenceRawGaussian;
    end
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
branch2.harmonicMethodUsed = harmonicMethodUsed;
branch2.gateSubstituted = gateSubstituted;
branch2.abpfNotchConfidence = abpfNotchConfidence;
branch2.gaussianNotchConfidence = gaussianNotchConfidence;

result = struct();
result.subjectID = opts.subjectID;
result.frameRate = frameRate;
result.roiTimestamps = roiTimestamps;
result.R = R;
result.G = G;
result.B = B;
result.waveletDenoiseUsed = opts.useWaveletDenoise;

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
result.notch.methodUsed = harmonicMethodUsed;

result.branch1 = branch1;
result.branch2 = branch2;

end

% =====================================================================
% FILTERING (verbatim from matlab/src/filtering/*.m)
% =====================================================================

function [sigDenoised, thresholdUsed, sigmaEstimate] = waveletDenoise(sig, waveletName, numLevels)
% WAVELETDENOISE DWT wavelet-shrinkage denoising via Donoho-Johnstone
% universal soft-thresholding (db4, 3-level default). Verbatim copy of
% matlab/src/filtering/waveletDenoise.m -- see that file for the full
% method writeup and references. Segment 8 Action 4/7: promoted to the
% default Branch 1 pre-step, ahead of detrendSignal/bandpassClean.

if nargin < 2 || isempty(waveletName)
    waveletName = 'db4';
end
if nargin < 3 || isempty(numLevels)
    numLevels = 3;
end

sigRow = sig(:)';
n = numel(sigRow);

[coeffs, bookkeeping] = wavedec(sigRow, numLevels, waveletName);

d1 = detcoef(coeffs, bookkeeping, 1);
sigmaEstimate = median(abs(d1)) / 0.6745;

thresholdUsed = sigmaEstimate * sqrt(2 * log(n));

coeffsThresholded = coeffs;
approxLength = bookkeeping(1);

detailStart = approxLength + 1;
for levelPos = numLevels:-1:1
    levelLength = bookkeeping(numLevels - levelPos + 2);
    detailEnd = detailStart + levelLength - 1;

    levelDetail = coeffsThresholded(detailStart:detailEnd);
    levelDetailSoft = sign(levelDetail) .* max(abs(levelDetail) - thresholdUsed, 0);
    coeffsThresholded(detailStart:detailEnd) = levelDetailSoft;

    detailStart = detailEnd + 1;
end

sigDenoised = waverec(coeffsThresholded, bookkeeping, waveletName);

if numel(sigDenoised) > n
    sigDenoised = sigDenoised(1:n);
elseif numel(sigDenoised) < n
    sigDenoised = [sigDenoised, repmat(sigDenoised(end), 1, n - numel(sigDenoised))];
end

end

function [signalDetrended, detrendOrder] = detrendSignal(signalRaw, polyOrder)
% DETRENDSIGNAL Remove slow drift/trend from a raw ROI color-channel
% signal via polynomial detrending (order 3 default). Verbatim copy of
% matlab/src/filtering/detrendSignal.m.
if nargin < 2
    polyOrder = 3;
end
detrendOrder = polyOrder;
signalDetrended = detrend(signalRaw, detrendOrder);
end

function [signalFiltered, filterOrder] = bandpassClean(signalDetrended, frameRate)
% BANDPASSCLEAN Bandpass-filter a detrended signal to the 0.7-4 Hz
% physiological HR band (2nd-order Butterworth, zero-phase filtfilt).
% Verbatim copy of matlab/src/filtering/bandpassClean.m.
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
% BANDPASSMORPHOLOGY Wider bandpass filter (default 0.5-8 Hz, 3rd-order
% Butterworth) for waveform morphology, as opposed to bandpassClean's
% narrow HR-detection band. Verbatim copy of
% matlab/src/morphology/bandpassMorphology.m.
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

% =====================================================================
% PULSE EXTRACTION (verbatim from matlab/src/pulseextraction/*.m)
% =====================================================================

function pulseSignal = chromCombine(R, G, B, RRaw, GRaw, BRaw)
% CHROMCOMBINE CHROM algorithm (de Haan & Jeanne, 2013). Verbatim copy of
% matlab/src/pulseextraction/chromCombine.m.
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
% POSCOMBINE POS algorithm (Wang et al., 2017). frameRate accepted for
% signature consistency, not used by this project's whole-signal formula
% (see matlab/src/pulseextraction/posCombine.m's own header). Verbatim
% copy of that file.
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

% =====================================================================
% HEART RATE (verbatim from matlab/src/heartrate/fftHeartRate.m)
% =====================================================================

function [hrBpm, freqSpectrum, powerSpectrum] = fftHeartRate(pulseSignal, frameRate)
% FFTHEARTRATE FFT peak-pick within the 0.7-4 Hz band. Verbatim copy of
% matlab/src/heartrate/fftHeartRate.m.
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

% =====================================================================
% SPO2 (verbatim from matlab/src/spo2/*.m)
% =====================================================================

function R = ratioOfRatios(R_filtered, G_filtered, B_filtered, R_raw, G_raw, B_raw, fs) %#ok<INUSD,INUSL>
% RATIOOFRATIOS AC/DC ratio-of-ratios for SpO2 (Blue substitutes for
% Infrared). Verbatim copy of matlab/src/spo2/ratioOfRatios.m.
DC_R = mean(R_raw);
DC_B = mean(B_raw);

AC_R = std(R_filtered);
AC_B = std(B_filtered);

R = (AC_R / DC_R) / (AC_B / DC_B);
end

function [spo2Est, calibParams] = calibrateSpO2(R, groundTruthSpO2, calibParams)
% CALIBRATESPO2 Linear R -> SpO2% calibration, SpO2 = A - B*R. Verbatim
% copy of matlab/src/spo2/calibrateSpO2.m.
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

% =====================================================================
% MORPHOLOGY (verbatim from matlab/src/morphology/*.m)
% =====================================================================

function [sigFiltered, f0Hz, harmonicsUsedHz] = adaptiveHarmonicFilter(sigDetrended, frameRate, numHarmonics, f0HzOverride)
% ADAPTIVEHARMONICFILTER "ABPF" -- harmonic-comb filter (Moco et al.):
% keep only narrow bins around the cardiac fundamental and its harmonics,
% zero everything else, IFFT back. Verbatim copy of
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

function [sigFiltered, f0Hz, harmonicsUsedHz] = harmonicSelectiveGaussianFilter(sigDetrended, frameRate, numHarmonics, f0HzOverride, alpha)
% HARMONICSELECTIVEGAUSSIANFILTER Gaussian-tapered harmonic filter
% (Dominguez-Hernandez et al. 2026), the Segment 14 confidence-gate
% fallback candidate when ABPF's own notch confidence fails the 0.3 bar.
% Verbatim copy of matlab/src/morphology/harmonicSelectiveGaussianFilter.m.
if nargin < 3 || isempty(numHarmonics)
    numHarmonics = 6;
end
if nargin < 4
    f0HzOverride = [];
end
if nargin < 5 || isempty(alpha)
    alpha = 0.5;
end

sigRow = sigDetrended(:)';
N = numel(sigRow);

if isempty(f0HzOverride)
    hrBpm = fftHeartRate(sigRow, frameRate);
    f0Hz = hrBpm / 60;
else
    f0Hz = f0HzOverride;
end

sigma = alpha * f0Hz;
if sigma <= 0
    error('harmonicSelectiveGaussianFilter:badSigma', 'alpha*f0Hz must be positive (got alpha=%.4g, f0Hz=%.4g).', alpha, f0Hz);
end

freqResolution = frameRate / N;
nyquistHz = frameRate / 2;

binIdx = (0:N - 1);
freqAxis = binIdx * freqResolution;
freqAxis(freqAxis > nyquistHz) = freqAxis(freqAxis > nyquistHz) - frameRate;

mask = zeros(1, N);
harmonicsUsedHz = [];

for h = 1:numHarmonics
    harmonicFreqHz = h * f0Hz;
    if harmonicFreqHz <= nyquistHz
        harmonicsUsedHz(end + 1) = harmonicFreqHz; %#ok<AGROW>
    end
    mask = mask + exp(-((freqAxis - harmonicFreqHz) .^ 2) / (sigma ^ 2)) ...
                + exp(-((freqAxis + harmonicFreqHz) .^ 2) / (sigma ^ 2));
end

fullFFT = fft(sigRow);
filteredFFT = fullFFT .* mask;
sigFiltered = real(ifft(filteredFFT));
end

function [selectedSignal, selectedMethodLabel, selectedNotchConfidence, wasSubstituted] = ...
    harmonicFilterConfidenceGate(primarySignal, primaryNotchConfidence, primaryMethodLabel, ...
    fallbackSignals, fallbackNotchConfidences, fallbackMethodLabels, confidenceThreshold)
% HARMONICFILTERCONFIDENCEGATE Segment 13/14's settled gate: keep the
% primary (ABPF) signal wherever its own notch confidence already clears
% the bar; substitute the best fallback candidate only where it fails.
% Verbatim copy of matlab/src/morphology/harmonicFilterConfidenceGate.m.
if nargin < 7 || isempty(confidenceThreshold)
    confidenceThreshold = 0.3;
end

if ~iscell(fallbackSignals)
    fallbackSignals = {fallbackSignals};
end
if ~iscell(fallbackMethodLabels)
    fallbackMethodLabels = {fallbackMethodLabels};
end
fallbackNotchConfidences = fallbackNotchConfidences(:)';

if numel(fallbackSignals) ~= numel(fallbackNotchConfidences) || numel(fallbackSignals) ~= numel(fallbackMethodLabels)
    error('harmonicFilterConfidenceGate:sizeMismatch', ...
        'fallbackSignals, fallbackNotchConfidences, and fallbackMethodLabels must all have the same number of candidates.');
end

if ~isnan(primaryNotchConfidence) && primaryNotchConfidence > confidenceThreshold
    selectedSignal = primarySignal;
    selectedMethodLabel = primaryMethodLabel;
    selectedNotchConfidence = primaryNotchConfidence;
    wasSubstituted = false;
    return
end

[bestConf, bestIdx] = max(fallbackNotchConfidences);
selectedSignal = fallbackSignals{bestIdx};
selectedMethodLabel = fallbackMethodLabels{bestIdx};
selectedNotchConfidence = bestConf;
wasSubstituted = true;
end

function [sigOriented, wasFlipped, skewValue] = fixPolarity(sig, frameRate)
% FIXPOLARITY Skewness-heuristic polarity correction (no ground truth
% available). CAVEAT (see matlab/src/morphology/fixPolarity.m's own
% header): measured to agree with the ground-truth-anchored rule on only
% 3/5 UBFC subjects -- kept as the documented no-reference fallback, not
% a silently-assumed-reliable default. Verbatim copy of that file.
minDurationSec = 10;

if numel(sig) / frameRate < minDurationSec
    error('fixPolarity:tooShort', 'sig must cover at least %.0f s of data (got %.2f s at %.2f Hz) -- skewness over a shorter window is not reliable enough to anchor polarity.', minDurationSec, numel(sig) / frameRate, frameRate);
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
% FIXPOLARITYBYGROUNDTRUTH Cross-correlation polarity correction against
% contact-PPG ground truth. Verbatim copy of
% matlab/src/morphology/fixPolarityByGroundTruth.m.
sigRow = sig(:)';
sigTimestampsRow = sigTimestamps(:)';
gtPPGRow = gtPPG(:)';
gtTimestampsRow = gtTimestamps(:)';

overlapLowSec = max(sigTimestampsRow(1), gtTimestampsRow(1));
overlapHighSec = min(sigTimestampsRow(end), gtTimestampsRow(end));

if overlapHighSec <= overlapLowSec
    error('fixPolarityByGroundTruth:noOverlap', 'sigTimestamps and gtTimestamps do not overlap in time -- cannot align rPPG and ground-truth PPG.');
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
% RESAMPLEUNIFORM Resample onto a uniform 250 Hz grid using REAL per-frame
% timestamps (pchip, not spline, to avoid fabricating notch-like
% overshoot). Verbatim copy of matlab/src/morphology/resampleUniform.m.
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
% ENSEMBLEAVERAGEBEATS Segment, time-align, and coherently average
% cardiac cycles from a uniform-grid pulse signal. Verbatim copy of
% matlab/src/morphology/ensembleAverageBeats.m (including its own local
% helpers, renamed with an eab_ prefix below only to avoid any risk of
% colliding with another local function of the same generic name
% elsewhere in this file).
if nargin < 3 || isempty(opts)
    opts = struct();
end

opts = eab_applyDefault(opts, 'beatSamples', 256);
opts = eab_applyDefault(opts, 'systolicAnchorFraction', 0.25);
opts = eab_applyDefault(opts, 'durationRejectFraction', 0.30);
opts = eab_applyDefault(opts, 'qualityKeepFraction', 0.25);
opts = eab_applyDefault(opts, 'trimPercent', 20);

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
    correlations(rowIdx) = eab_pearsonCorrRow(beatMatrixWarped(rowIdx, :), roughTemplate);
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
    q1(colIdx) = eab_localPercentile(beatMatrix(:, colIdx), 25);
    q3(colIdx) = eab_localPercentile(beatMatrix(:, colIdx), 75);
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

function opts = eab_applyDefault(opts, fieldName, defaultValue)
if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
    opts.(fieldName) = defaultValue;
end
end

function r = eab_pearsonCorrRow(x, y)
xc = x - mean(x);
yc = y - mean(y);
r = sum(xc .* yc) / sqrt(sum(xc.^2) * sum(yc.^2));
end

function p = eab_localPercentile(columnData, percentile)
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
% NOTCHDETECTIEM Dicrotic notch detection via the Iterative Envelope Mean
% method (Pal et al. 2024). Verbatim copy of
% matlab/src/morphology/notchDetectIEM.m -- see that file's own header
% for the full algorithm writeup, references, and implementation-fidelity
% caveat.
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

% =====================================================================
% ROI EXTRACTION (verbatim from matlab/src/roi/extractROISignals.m)
% =====================================================================

function [R, G, B, roiTimestamps, droppedFrameIdx, debugFrame] = extractROISignals(frames, frameRate, roiMode)
% EXTRACTROISIGNALS Detect face (Viola-Jones), crop a face-box-relative
% ROI, average per-frame. Verbatim copy of
% matlab/src/roi/extractROISignals.m -- see that file's own header for
% the region-geometry rationale.
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

    regionBBoxes = eroi_computeRegionBBoxes(currentBBox, frameWidth, frameHeight);

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

function regionBBoxes = eroi_computeRegionBBoxes(faceBBox, frameWidth, frameHeight)
faceX = faceBBox(1);
faceY = faceBBox(2);
faceW = faceBBox(3);
faceH = faceBBox(4);

regionBBoxes = struct();
regionBBoxes.forehead = eroi_clampedBBox(faceX, faceY, faceW, faceH, 0.30, 0.70, 0.10, 0.30, frameWidth, frameHeight);
regionBBoxes.glabella = eroi_clampedBBox(faceX, faceY, faceW, faceH, 0.42, 0.58, 0.32, 0.40, frameWidth, frameHeight);
regionBBoxes.malarLeft = eroi_clampedBBox(faceX, faceY, faceW, faceH, 0.15, 0.32, 0.45, 0.58, frameWidth, frameHeight);
regionBBoxes.malarRight = eroi_clampedBBox(faceX, faceY, faceW, faceH, 0.68, 0.85, 0.45, 0.58, frameWidth, frameHeight);
regionBBoxes.cheekLeft = eroi_clampedBBox(faceX, faceY, faceW, faceH, 0.10, 0.35, 0.55, 0.75, frameWidth, frameHeight);
regionBBoxes.cheekRight = eroi_clampedBBox(faceX, faceY, faceW, faceH, 0.65, 0.90, 0.55, 0.75, frameWidth, frameHeight);
end

function bbox = eroi_clampedBBox(faceX, faceY, faceW, faceH, xFracLo, xFracHi, yFracLo, yFracHi, frameWidth, frameHeight)
x1 = max(1, round(faceX + xFracLo * faceW));
x2 = min(frameWidth, round(faceX + xFracHi * faceW));
y1 = max(1, round(faceY + yFracLo * faceH));
y2 = min(frameHeight, round(faceY + yFracHi * faceH));

bbox = [x1, y1, x2 - x1, y2 - y1];
end

% =====================================================================
% I/O (verbatim from matlab/src/io/*.m)
% =====================================================================

function [frames, frameRate, numFrames] = loadUBFCVideo(videoPath)
% LOADUBFCVIDEO Generic VideoReader wrapper (the name is historical --
% used for UBFC-style AND arbitrary/Case-3 videos, see this file's own
% Case 3 comment). Verbatim copy of matlab/src/io/loadUBFCVideo.m.
if ~isfile(videoPath)
    error('loadUBFCVideo:fileNotFound', 'Video file not found: %s', videoPath);
end

frames = VideoReader(videoPath);
frameRate = frames.FrameRate;
numFrames = frames.NumFrames;
end

function [frames, frameRate, numFrames, videoPath] = loadVIPLVideo(viplRoot, subjectNum, scenarioNum, sourceNum)
% LOADVIPLVIDEO VIPL-HR loader: corrects frameRate against time.txt for
% source1/3/4 (container fps can be wrong for those), uses container fps
% as-is for source2 (no time.txt exists for it -- a known, documented
% accuracy limitation, not an oversight). Verbatim copy of
% matlab/src/io/loadVIPLVideo.m.
if sourceNum == 4
    error('loadVIPLVideo:nirNotSupported', 'source4 is the VIPL-HR NIR camera, not RGB. This pipeline is RGB-only.');
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
    disp(['loadVIPLVideo: no time.txt for source' num2str(sourceNum) ' (' videoPath '), using container FrameRate = ' num2str(containerFrameRate) ' fps -- known accuracy limitation for source2.']);
    frameRate = containerFrameRate;
end
end

function gt = loadGroundTruth(gtPath, datasetFormat)
% LOADGROUNDTRUTH UBFC-rPPG ground truth loader (dataset1: gtdump.xmp,
% dataset2: ground_truth.txt). Verbatim copy of
% matlab/src/io/loadGroundTruth.m.
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

function gt = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, sourceNum)
% LOADVIPLGROUNDTRUTH VIPL-HR ground truth loader (gt_HR.csv, gt_SpO2.csv,
% wave.csv). gt.ppg is at wave.csv's own ~60 Hz rate and is NOT the same
% length as gt.timestamp/gt.hr/gt.spo2 (per-second) -- not used as a
% continuous overlay by this file for exactly that reason. Verbatim copy
% of matlab/src/io/loadVIPLGroundTruth.m.
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
