% RUN_SEGMENT6_TASK_J_SWITCHING Segment 6 "Task J" driver: builds and
% validates a per-subject CHROM/POS switching estimator using Task I's
% data-derived 29.27% relative-disagreement threshold (below threshold ->
% CHROM, at/above threshold -> POS).
%
% This script does NOT reprocess any video or raw trace, and does NOT
% modify pulseextraction/chromCombine.m, pulseextraction/posCombine.m,
% heartrate/fftHeartRate.m, or any other Segment 2-5 algorithm file. It
% only reads the already-computed results/metrics/
% segment6_hr_agreement_flags.csv (built by run_segment6_task_i_agreement.m),
% calls the new validation/computeSwitchingEstimate.m and the existing
% unmodified validation/computeMetrics.m, and writes one new output CSV.
%
% Outputs:
%   results/metrics/segment6_hr_switching_metrics.csv - one row per
%     method (chrom_alone, pos_alone, switched), scope=pooled, N, MAE,
%     RMSE, Pearson r.
%
% See Segment6_Refinement_Notes.md Task J for the full-pool validation
% numbers and the failure-mode check (does switching ever pick the worse
% of the two estimates for an individual subject).

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

disagreementThresholdPercent = 29.27;
disagreementThresholdFraction = disagreementThresholdPercent / 100;

disp('=== Segment 6 Task J: loading pooled HR agreement data (segment6_hr_agreement_flags.csv, built by Task I) ===');

agreementCsvPath = fullfile(metricsRoot, 'segment6_hr_agreement_flags.csv');
agreementTable = readtable(agreementCsvPath);
numSubjects = height(agreementTable);

disp(['Loaded ' num2str(numSubjects) ' pooled HR subjects from ' agreementCsvPath]);
disp(['Using Task I''s stored threshold: ' num2str(disagreementThresholdPercent) '% relative disagreement (fraction ' num2str(disagreementThresholdFraction) ').']);

hrSubjectID = {};
hrDataset = {};
hrChrom = [];
hrPos = [];
hrGroundtruth = [];

for rowPos = 1:numSubjects
    hrSubjectID{end + 1} = extractTextTaskJ(agreementTable.subjectID, rowPos);
    hrDataset{end + 1} = extractTextTaskJ(agreementTable.dataset, rowPos);
    hrChrom(end + 1) = agreementTable.HR_chrom(rowPos);
    hrPos(end + 1) = agreementTable.HR_pos(rowPos);
    hrGroundtruth(end + 1) = agreementTable.HR_groundtruth(rowPos);
end

disp(' ');
disp('=== Part 1: computing the switched estimate (computeSwitchingEstimate.m) ===');

[HR_switched, usedPos] = computeSwitchingEstimate(hrChrom, hrPos, disagreementThresholdFraction);

numSwitchedToPos = 0;

for i = 1:numSubjects
    if usedPos(i)
        numSwitchedToPos = numSwitchedToPos + 1;
    end
end

disp(['Switch fired (used POS instead of CHROM) for ' num2str(numSwitchedToPos) ' of ' num2str(numSubjects) ' subjects (' num2str(numSwitchedToPos / numSubjects * 100) '%).']);

disp(' ');
disp('=== Part 2: full N=112 pool validation -- switched vs. CHROM-alone vs. POS-alone ===');
disp('CAVEAT: this is the SAME 112-subject pool the 29.27% threshold was derived from in Task I. This is NOT a clean out-of-sample validation of the switching rule -- results below are reported "on this pool," not as a generalizable guarantee.');

switchedMetrics = computeMetrics(HR_switched, hrGroundtruth);
chromMetrics = computeMetrics(hrChrom, hrGroundtruth);
posMetrics = computeMetrics(hrPos, hrGroundtruth);

disp(' ');
disp('Method           | N   | MAE     | RMSE    | Pearson r');
disp(['CHROM alone      | ' num2str(chromMetrics.n) ' | ' num2str(chromMetrics.mae) ' | ' num2str(chromMetrics.rmse) ' | ' num2str(chromMetrics.pearsonR)]);
disp(['POS alone        | ' num2str(posMetrics.n) ' | ' num2str(posMetrics.mae) ' | ' num2str(posMetrics.rmse) ' | ' num2str(posMetrics.pearsonR)]);
disp(['Switched (J)     | ' num2str(switchedMetrics.n) ' | ' num2str(switchedMetrics.mae) ' | ' num2str(switchedMetrics.rmse) ' | ' num2str(switchedMetrics.pearsonR)]);

disp(' ');
disp('=== Part 3: failure-mode check -- does switching ever make things worse? ===');
disp('For every subject where the switch fired (used POS instead of CHROM), comparing abs_error_chrom vs abs_error_pos for that specific subject.');

numSwitchHelped = 0;
numSwitchHurt = 0;
numSwitchTied = 0;

for i = 1:numSubjects
    if ~usedPos(i)
        continue;
    end

    absErrorChromThis = abs(hrChrom(i) - hrGroundtruth(i));
    absErrorPosThis = abs(hrPos(i) - hrGroundtruth(i));

    if absErrorPosThis < absErrorChromThis
        numSwitchHelped = numSwitchHelped + 1;
    elseif absErrorPosThis > absErrorChromThis
        numSwitchHurt = numSwitchHurt + 1;
    else
        numSwitchTied = numSwitchTied + 1;
    end
end

disp(['Of the ' num2str(numSwitchedToPos) ' subjects where the switch fired:']);
disp(['  Switch HELPED (POS error < CHROM error): ' num2str(numSwitchHelped) ' subjects.']);
disp(['  Switch HURT (POS error > CHROM error):   ' num2str(numSwitchHurt) ' subjects.']);
disp(['  Tied (POS error == CHROM error):         ' num2str(numSwitchTied) ' subjects.']);

disp(' ');
disp('=== Saving switching metrics CSV ===');

switchingCsvPath = fullfile(metricsRoot, 'segment6_hr_switching_metrics.csv');
switchingHeaderLine = "method,scope,n,mae,rmse,pearson_r";
writelines(switchingHeaderLine, switchingCsvPath);

chromRow = strjoin({'chrom_alone', 'pooled', num2str(chromMetrics.n), num2str(chromMetrics.mae), num2str(chromMetrics.rmse), num2str(chromMetrics.pearsonR)}, ',');
posRow = strjoin({'pos_alone', 'pooled', num2str(posMetrics.n), num2str(posMetrics.mae), num2str(posMetrics.rmse), num2str(posMetrics.pearsonR)}, ',');
switchedRow = strjoin({'switched', 'pooled', num2str(switchedMetrics.n), num2str(switchedMetrics.mae), num2str(switchedMetrics.rmse), num2str(switchedMetrics.pearsonR)}, ',');

writelines(chromRow, switchingCsvPath, 'WriteMode', 'append');
writelines(posRow, switchingCsvPath, 'WriteMode', 'append');
writelines(switchedRow, switchingCsvPath, 'WriteMode', 'append');

disp(['Saved ' switchingCsvPath]);

disp(' ');
disp('--- Segment 6 Task J batch complete ---');

function textVal = extractTextTaskJ(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
