function gt = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, sourceNum)
% LOADVIPLGROUNDTRUTH Load HR/SpO2/BVP ground truth for a VIPL-HR
% subject/scenario/source video.
%
% Pipeline stage: Stage 1 (input) — supplies the reference HR/SpO2/BVP
% values used later for calibration (Stage 5, spo2/calibrateSpO2.m) and
% validation (Stage 6, validation/runLOSO.m, computeMetrics.m). This is
% the VIPL-HR counterpart of io/loadGroundTruth.m, adapted to VIPL-HR's
% real ground-truth file format — see docs/VIPL_DATA_FORMAT.md Section 5
% for the full format breakdown confirmed from actual files, not just the
% VIPL-HR ReadMe.pdf's description.
%
% VIPL-HR ships ground truth as THREE separate files per video, each at
% its own native sampling rate, unlike UBFC DATASET_1's single 4-column
% file where every column shares one row per oximeter sample:
%   gt_HR.csv   -> one HR (bpm) value per elapsed second, no explicit
%                  per-row timestamp column, no header timestamp either
%                  (just a literal "HR" header over a value column).
%   gt_SpO2.csv -> one SpO2 (%) value per elapsed second, same shape,
%                  header "SpO2".
%   wave.csv    -> the BVP waveform, one sample roughly every ~16-17 ms
%                  (~60 Hz, the CONTEC CMS60C sensor's native rate, same
%                  device family as UBFC DATASET_1's oximeter), header
%                  "Wave".
% gt_HR.csv and gt_SpO2.csv are NOT the same length as wave.csv -- see
% docs/VIPL_DATA_FORMAT.md Section 5 for confirmed row counts. There is
% no shared per-row timestamp across all three files the way UBFC
% DATASET_1's gtdump.xmp has one timestamp column covering all four of
% its own columns.
%
% Design decision (see VIPL_Integration_LineByLine_Explanation.md Part 2
% for the full reasoning): gt.timestamp, gt.hr, and gt.spo2 are returned
% as three parallel vectors at gt_HR.csv/gt_SpO2.csv's native 1-second
% granularity, with gt.timestamp reconstructed as elapsed whole seconds
% (0, 1, 2, ...) since neither file carries an explicit timestamp column
% and the VIPL-HR ReadMe states both are "recorded every second" from a
% shared t=0 start. This keeps gt.timestamp/gt.hr/gt.spo2 directly usable
% by the same timestamp-based masking pattern
% scripts/run_segment5_dataset1_calibration_batch.m already uses for
% UBFC DATASET_1 (gt.timestamp <= videoDurationSec, then index into
% gt.spo2), without that caller needing any changes. gt.ppg is returned
% separately at wave.csv's own native ~60 Hz rate and is NOT the same
% length as gt.timestamp/gt.hr/gt.spo2 -- callers that need the BVP
% waveform aligned to gt.timestamp must resample it themselves; none of
% this project's existing Segment 4/5 batch scripts do so today.
%
% Inputs:
%   viplRoot    - string/char, path to the extracted VIPL-HR root folder
%                 (see io/loadVIPLVideo.m for the same parameter).
%   subjectNum  - scalar, subject number (e.g. 1 for "p1").
%   scenarioNum - scalar, scenario number 1-9 (e.g. 1 for "v1").
%   sourceNum   - scalar, 1, 2, or 3 (must match the source video already
%                 loaded via io/loadVIPLVideo.m for the same triple).
%
% Outputs:
%   gt - struct with fields:
%          gt.timestamp - vector, seconds, reconstructed elapsed whole
%                         seconds (0, 1, 2, ...), one per gt.hr/gt.spo2
%                         sample.
%          gt.hr        - vector, bpm, one value per elapsed second, from
%                         gt_HR.csv.
%          gt.spo2      - vector, percent, one value per elapsed second,
%                         from gt_SpO2.csv.
%          gt.ppg       - vector, raw contact-BVP waveform from
%                         wave.csv, at its own native ~60 Hz sampling
%                         rate (NOT the same length as gt.timestamp --
%                         see the design decision note above).

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
