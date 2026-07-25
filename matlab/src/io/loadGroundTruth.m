function gt = loadGroundTruth(gtPath, datasetFormat)
% LOADGROUNDTRUTH Load pulse-oximeter ground truth for a UBFC-rPPG subject.
%
% Pipeline stage: Stage 1 (input) — supplies the reference PPG/HR/SpO2
% values used later for calibration (Stage 5, spo2/calibrateSpO2.m) and
% validation (Stage 6, validation/runLOSO.m, computeMetrics.m).
%
% UBFC-rPPG ships two different ground-truth formats depending on which
% sub-dataset a subject belongs to — see docs/DATA_FORMAT.md for the full
% breakdown confirmed from the dataset's own readme.txt:
%   'dataset1' -> gtdump.xmp:      comma-delimited, no header, columns are
%                 [timestamp_ms, HR_bpm, SpO2_pct, PPG_raw], one row per
%                 pulse-oximeter sample (~62 Hz, asynchronous with video).
%   'dataset2' -> ground_truth.txt: whitespace-delimited, no header, 3
%                 lines: [PPG_signal; HR_bpm; timestamp_sec], one column
%                 per video frame (already resampled to video frame rate).
%                 Has NO SpO2 field.
%
% Inputs:
%   gtPath        - string/char, full path to the ground-truth file
%                   (gtdump.xmp or ground_truth.txt).
%   datasetFormat - string/char, either 'dataset1' or 'dataset2', selects
%                   which parsing rule above to apply.
%
% Outputs:
%   gt - struct with fields (SpO2 empty/absent for dataset2 subjects):
%          gt.timestamp - vector, seconds
%          gt.ppg       - vector, raw contact-PPG waveform
%          gt.hr        - vector, bpm (sensor-reported; per the official
%                         readme this was NOT used for HR evaluation in
%                         the original paper — kept here for reference/
%                         sanity-checking only)
%          gt.spo2      - vector, percent (dataset1 only)

error('Not implemented yet — see docs/');

end
