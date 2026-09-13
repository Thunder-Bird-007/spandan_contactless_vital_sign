% RUN_SEGMENT7_TASK_K_TEMPLATE_COLLAPSE_BATCH Segment 7 Task K --
% template-collapse diagnostic per arXiv:2606.03802 ("Template Collapse
% and Information-Theoretic Limits in Camera rPPG Pulse Morphology
% Restoration"). Computes, for every subject with a REAL ground-truth
% contact-PPG WAVEFORM (not just scalar HR), both:
%   (a) the rPPG ensemble-average beat prototype (baseline ROI ->
%       detrend -> wide-band -> adaptiveHarmonicFilter, ABPF's own
%       existing operating point -> chromCombine -> polarity-fix ->
%       resampleUniform -> ensembleAverageBeats), and
%   (b) the SAME subject's ground-truth contact-PPG ensemble-average beat
%       prototype (gt.ppg fed through resampleUniform/ensembleAverageBeats
%       directly -- no ROI/filtering, it is already a clean contact
%       signal).
% Both prototypes are morphology/ensembleAverageBeats.m's own
% trimmedMean output, 1 x beatSamples (256 by default) -- already
% cycle-normalized to [0,1], so no further length-alignment is needed
% before computing cross-subject correlation.
%
% Does NOT modify roi/extractROISignals.m, filtering/detrendSignal.m,
% morphology/bandpassMorphology.m, morphology/adaptiveHarmonicFilter.m,
% pulseextraction/chromCombine.m, morphology/fixPolarityByGroundTruth.m,
% morphology/resampleUniform.m, or morphology/ensembleAverageBeats.m --
% new, additive script only, reusing all of the above exactly as
% scripts/run_segment7_task_h_facemesh_roi_batch.m and
% scripts/run_segment7_task_j_facemesh_hybrid_roi_batch.m do.
%
% SUBJECT UNIVERSE (confirmed, not assumed -- see
% docs/Segment7_Task_K_Template_Collapse_Diagnostic.md for how this was
% checked): the handoff's default guess ("likely only the 5 UBFC
% ground-truth subjects") undercounts. Real ground-truth PPG WAVEFORM
% (not scalar HR) exists for:
%   - UBFC DATASET_1 (5): gtdump.xmp column 4, ~62 Hz, WITH real
%     per-sample timestamps (column 1).
%   - UBFC DATASET_2 (up to 42): ground_truth.txt line 1, one sample per
%     video frame (~29-30 Hz), WITH real per-frame timestamps (line 3).
%   - VIPL-HR (up to 107, this run restricted to scenario v1/source1 --
%     the "stable" scenario, most comparable to UBFC's own setup, so
%     v2 (motion) / v3 (talking) / v4 (dark) / v7 (exercise) etc. don't
%     confound the correlation-matrix comparison with scenario-driven
%     shape differences unrelated to template collapse): wave.csv,
%     ~60 Hz nominal (CONTEC CMS60C, same sensor family as UBFC
%     DATASET_1's oximeter), but NO per-sample timestamp array -- see
%     the per-subject processing note below for how this is handled.
%
% CHECKPOINTED / RESUMABLE: each subject's outcome is appended to the
% summary CSV immediately (try/catch per subject, same discipline as
% every other batch script in this project), and both prototypes are
% saved to a combined .mat cache as soon as they're computed, so a run
% that is interrupted partway still leaves usable partial results and a
% rerun does not need to start over (subjects already present in the
% cache are skipped).
%
% Output:
%   results/metrics/segment7_task_k_template_collapse_summary.csv
%   data/processed/segment7_task_k_prototypes.mat (struct array: subjectID,
%     datasetSource, rppgPrototype [1x256], gtPrototype [1x256], success)

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
ubfcD1Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_1');
ubfcD2Root = fullfile(projectRoot, 'data', 'raw', 'UBFC-rPPG', 'DATASET_2');
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
processedRoot = fullfile(projectRoot, 'data', 'processed');

if ~isfolder(metricsRoot); mkdir(metricsRoot); end
if ~isfolder(processedRoot); mkdir(processedRoot); end

csvPath = fullfile(metricsRoot, 'segment7_task_k_template_collapse_summary.csv');
matPath = fullfile(processedRoot, 'segment7_task_k_prototypes.mat');

% --- Build the combined subject list. ---
subjects = struct('source', {}, 'id', {}, 'videoPath', {}, 'gtPath', {}, 'subjectNum', {});

% UBFC DATASET_1 (5).
d1List = {'5-gt', '6-gt', '7-gt', '12-gt', 'after-exercise'};
for k = 1:numel(d1List)
    subjDir = fullfile(ubfcD1Root, d1List{k});
    aviFiles = dir(fullfile(subjDir, '*.avi'));
    if isempty(aviFiles); continue; end
    gtPath = fullfile(subjDir, 'gtdump.xmp');
    if ~isfile(gtPath); continue; end
    entry.source = 'ubfc_d1';
    entry.id = d1List{k};
    entry.videoPath = fullfile(subjDir, aviFiles(1).name);
    entry.gtPath = gtPath;
    entry.subjectNum = NaN;
    subjects(end + 1) = entry; %#ok<AGROW>
end

% UBFC DATASET_2 (dynamic discovery -- zip layout may nest one extra
% folder level; check both).
d2SubjectDirs = dir(fullfile(ubfcD2Root, 'subject*'));
d2SubjectDirs = d2SubjectDirs([d2SubjectDirs.isdir]);
if isempty(d2SubjectDirs)
    nested = dir(fullfile(ubfcD2Root, '*', 'subject*'));
    nested = nested([nested.isdir]);
    d2SubjectDirs = nested;
end
for k = 1:numel(d2SubjectDirs)
    subjDir = fullfile(d2SubjectDirs(k).folder, d2SubjectDirs(k).name);
    videoPath = fullfile(subjDir, 'vid.avi');
    gtPath = fullfile(subjDir, 'ground_truth.txt');
    if ~isfile(videoPath) || ~isfile(gtPath); continue; end
    entry.source = 'ubfc_d2';
    entry.id = d2SubjectDirs(k).name;
    entry.videoPath = videoPath;
    entry.gtPath = gtPath;
    entry.subjectNum = NaN;
    subjects(end + 1) = entry; %#ok<AGROW>
end

% VIPL-HR v1/source1, subjects with wave.csv present.
viplSubjectDirs = dir(fullfile(viplRoot, 'p*'));
viplSubjectDirs = viplSubjectDirs([viplSubjectDirs.isdir]);
for k = 1:numel(viplSubjectDirs)
    subjName = viplSubjectDirs(k).name; % e.g. 'p84'
    subjNumStr = subjName(2:end);
    subjNum = str2double(subjNumStr);
    if isnan(subjNum); continue; end
    wavePath = fullfile(viplRoot, subjName, 'v1', 'source1', 'wave.csv');
    videoPath = fullfile(viplRoot, subjName, 'v1', 'source1', 'video.avi');
    if ~isfile(wavePath) || ~isfile(videoPath); continue; end
    entry.source = 'vipl';
    entry.id = subjName;
    entry.videoPath = videoPath;
    entry.gtPath = '';
    entry.subjectNum = subjNum;
    subjects(end + 1) = entry; %#ok<AGROW>
end

numSubjects = numel(subjects);
fprintf('Segment 7 Task K: %d subjects total (UBFC-D1 %d, UBFC-D2 %d, VIPL-v1s1 %d).\n', ...
    numSubjects, numel(d1List), numel(d2SubjectDirs), numel(viplSubjectDirs));

% --- Resume support: load existing cache if present. ---
if isfile(matPath)
    loaded = load(matPath);
    results = loaded.results;
    doneIds = {results.id};
    fprintf('Resuming: %d subjects already in cache.\n', numel(doneIds));
else
    results = struct('source', {}, 'id', {}, 'rppgPrototype', {}, 'gtPrototype', {}, 'success', {}, 'failReason', {});
    doneIds = {};
    headerLine = "subjectID,source,success,failReason,beatsAveraged_rppg,beatsAveraged_gt,elapsedSec";
    writelines(headerLine, csvPath);
end

for subjPos = 1:numSubjects
    s = subjects(subjPos);
    compositeId = [s.source '_' s.id];

    if any(strcmp(doneIds, compositeId))
        continue
    end

    fprintf('--- Task K subject %d/%d: %s (%s) ---\n', subjPos, numSubjects, s.id, s.source);
    subjTic = tic;

    try
        [frames, frameRate, ~] = loadUBFCOrVIPLVideo(s);

        [R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate);

        [Rd, ~] = detrendSignal(R);
        [Gd, ~] = detrendSignal(G);
        [Bd, ~] = detrendSignal(B);

        [Rw, ~, ~] = bandpassMorphology(Rd, frameRate, 'wide');
        [Gw, ~, ~] = bandpassMorphology(Gd, frameRate, 'wide');
        [Bw, ~, ~] = bandpassMorphology(Bd, frameRate, 'wide');
        pulseWide = chromCombine(Rw, Gw, Bw, R, G, B);
        f0Hz = fftHeartRate(pulseWide, frameRate) / 60;

        [Rahf, ~, ~] = adaptiveHarmonicFilter(Rd, frameRate, 6, f0Hz);
        [Gahf, ~, ~] = adaptiveHarmonicFilter(Gd, frameRate, 6, f0Hz);
        [Bahf, ~, ~] = adaptiveHarmonicFilter(Bd, frameRate, 6, f0Hz);
        pulseAdaptive = chromCombine(Rahf, Gahf, Bahf, R, G, B);

        [gtPPG, gtTimestamps, gtNominalFs] = loadGTWaveform(s, projectRoot);

        if ~isempty(gtTimestamps)
            [pulseFixed, ~] = fixPolarityByGroundTruth(pulseAdaptive, roiTimestamps, gtPPG, gtTimestamps);
        else
            % VIPL: no per-sample rPPG-side ground-truth timestamp array
            % problem here (roiTimestamps is real); polarity-fix still
            % needs SOME gt timestamp axis to correlate against, so build
            % an assumed-uniform one at gtNominalFs (see loadGTWaveform).
            gtTimestampsAssumed = (0:numel(gtPPG) - 1) / gtNominalFs;
            [pulseFixed, ~] = fixPolarityByGroundTruth(pulseAdaptive, roiTimestamps, gtPPG, gtTimestampsAssumed);
        end

        [sigUniform, ~, uniformFs] = resampleUniform(pulseFixed, roiTimestamps);
        [rppgProto, ~, ~, rppgStats] = ensembleAverageBeats(sigUniform, uniformFs);

        % --- Ground-truth prototype: same ensembleAverageBeats machinery,
        % applied directly to the contact-PPG waveform (no ROI/filtering
        % -- it's already a clean physiological signal). ---
        if ~isempty(gtTimestamps)
            [gtUniform, ~, gtUniformFs] = resampleUniform(gtPPG, gtTimestamps, 250);
        else
            gtUniform = gtPPG(:)';
            gtUniformFs = gtNominalFs;
        end
        [gtProto, ~, ~, gtStats] = ensembleAverageBeats(gtUniform, gtUniformFs);

        elapsedSec = toc(subjTic);
        fprintf('Subject %s: rPPG beats=%d, GT beats=%d (%.0f s)\n', s.id, rppgStats.beatsAveraged, gtStats.beatsAveraged, elapsedSec);

        row = {compositeId, s.source, '1', '', num2str(rppgStats.beatsAveraged), num2str(gtStats.beatsAveraged), num2str(elapsedSec, '%.1f')};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        newEntry.source = s.source;
        newEntry.id = compositeId;
        newEntry.rppgPrototype = rppgProto.trimmedMean;
        newEntry.gtPrototype = gtProto.trimmedMean;
        newEntry.success = true;
        newEntry.failReason = '';
        results(end + 1) = newEntry; %#ok<AGROW>
        save(matPath, 'results', '-v7');
    catch causeErr
        elapsedSec = toc(subjTic);
        disp(['Subject ' compositeId ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
        row = {compositeId, s.source, '0', ['"' strrep(causeErr.message, '"', '''') '"'], '', '', num2str(elapsedSec, '%.1f')};
        writelines(strjoin(row, ','), csvPath, 'WriteMode', 'append');

        newEntry.source = s.source;
        newEntry.id = compositeId;
        newEntry.rppgPrototype = [];
        newEntry.gtPrototype = [];
        newEntry.success = false;
        newEntry.failReason = causeErr.message;
        results(end + 1) = newEntry; %#ok<AGROW>
        save(matPath, 'results', '-v7');
    end
end

numSucceeded = sum([results.success]);
fprintf('--- Segment 7 Task K batch complete: %d/%d subjects succeeded ---\n', numSucceeded, numel(results));
fprintf('Saved %s and %s\n', csvPath, matPath);

function [frames, frameRate, numFrames] = loadUBFCOrVIPLVideo(s)
switch s.source
    case {'ubfc_d1', 'ubfc_d2'}
        [frames, frameRate, numFrames] = loadUBFCVideo(s.videoPath);
    case 'vipl'
        [frames, frameRate, numFrames, ~] = loadVIPLVideo(fileparts(fileparts(fileparts(fileparts(s.videoPath)))), s.subjectNum, 1, 1);
    otherwise
        error('run_segment7_task_k_template_collapse_batch:badSource', 'Unknown source "%s".', s.source);
end
end

function [gtPPG, gtTimestamps, gtNominalFs] = loadGTWaveform(s, projectRoot)
switch s.source
    case 'ubfc_d1'
        gt = loadGroundTruth(s.gtPath, 'dataset1');
        gtPPG = gt.ppg;
        gtTimestamps = gt.timestamp;
        gtNominalFs = [];
    case 'ubfc_d2'
        gt = loadGroundTruth(s.gtPath, 'dataset2');
        gtPPG = gt.ppg;
        gtTimestamps = gt.timestamp;
        gtNominalFs = [];
    case 'vipl'
        viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
        gt = loadVIPLGroundTruth(viplRoot, s.subjectNum, 1, 1);
        gtPPG = gt.ppg;
        gtTimestamps = []; % no per-sample timestamp array for wave.csv
        gtNominalFs = 60;  % CONTEC CMS60C nominal rate, same sensor family as UBFC DATASET_1's oximeter -- see docs/VIPL_DATA_FORMAT.md Section 5b. Shape-normalized prototype output is robust to this being only nominal, not exactly measured (see this script's header / the Task K doc for why).
    otherwise
        error('run_segment7_task_k_template_collapse_batch:badSource', 'Unknown source "%s".', s.source);
end
end
