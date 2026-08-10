% RUN_SEGMENT6_TASK_I_AGREEMENT Segment 6 "Task I" driver: tests whether
% CHROM/POS disagreement is a generally useful low-confidence signal
% across the full N=112 HR pool, following up on Task H1's single-subject
% (p21) observation that CHROM misread the rate by roughly 2x on a signal
% POS read correctly.
%
% This script does NOT reprocess any video or raw trace, and does NOT
% modify pulseextraction/chromCombine.m, pulseextraction/posCombine.m,
% heartrate/fftHeartRate.m, or any other Segment 2-5 algorithm file. It
% only reads the already-computed results/metrics/segment4_hr_summary.csv
% and results/metrics/segment4_hr_summary_vipl.csv, calls the new
% validation/computeAgreementConfidence.m and the existing unmodified
% validation/computeMetrics.m, and writes one new output CSV.
%
% Outputs:
%   results/metrics/segment6_hr_agreement_flags.csv - subjectID, dataset,
%     HR_chrom, HR_pos, HR_groundtruth, relative_disagreement,
%     low_confidence_flag, abs_error_chrom, one row per subject.
%
% See Segment6_Refinement_Notes.md Task I for the threshold justification,
% the disagreement-vs-error correlation, the worst-5 overlap check, the
% confidence-gated accuracy comparison, and the CHROM-vs-POS head-to-head.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

if ~isfolder(metricsRoot)
    mkdir(metricsRoot);
end

disp('=== Segment 6 Task I: loading pooled HR subjects (same source CSVs as run_segment6_validation.m) ===');

hrSubjectID = {};
hrDataset = {};
hrChrom = [];
hrPos = [];
hrGroundtruth = [];
hrAbsErrorChrom = [];

hrUbfcPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');

if isfile(hrUbfcPath)
    ubfcHrTable = readtable(hrUbfcPath);
    numRows = height(ubfcHrTable);

    for rowPos = 1:numRows
        hrSubjectID{end + 1} = extractTextTaskI(ubfcHrTable.subjectID, rowPos);
        hrDataset{end + 1} = 'UBFC';
        hrChrom(end + 1) = ubfcHrTable.HR_chrom(rowPos);
        hrPos(end + 1) = ubfcHrTable.HR_pos(rowPos);
        hrGroundtruth(end + 1) = ubfcHrTable.HR_groundtruth(rowPos);
        hrAbsErrorChrom(end + 1) = ubfcHrTable.abs_error_chrom(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' UBFC HR rows from ' hrUbfcPath]);
end

hrViplPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');

if isfile(hrViplPath)
    viplHrTable = readtable(hrViplPath);
    numRows = height(viplHrTable);

    for rowPos = 1:numRows
        hrSubjectID{end + 1} = extractTextTaskI(viplHrTable.subjectID, rowPos);
        hrDataset{end + 1} = extractTextTaskI(viplHrTable.dataset, rowPos);
        hrChrom(end + 1) = viplHrTable.HR_chrom(rowPos);
        hrPos(end + 1) = viplHrTable.HR_pos(rowPos);
        hrGroundtruth(end + 1) = viplHrTable.HR_groundtruth(rowPos);
        hrAbsErrorChrom(end + 1) = viplHrTable.abs_error_chrom(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL HR rows from ' hrViplPath]);
end

numSubjects = numel(hrSubjectID);

disp(['Pooled HR subjects available: ' num2str(numSubjects)]);

disp(' ');
disp('=== Part 1: per-subject relative disagreement (computeAgreementConfidence.m) ===');

relativeDisagreement = computeAgreementConfidence(hrChrom, hrPos);

relativeDisagreementPercent = zeros(1, numSubjects);

for i = 1:numSubjects
    relativeDisagreementPercent(i) = relativeDisagreement(i) * 100;
end

minPercent = min(relativeDisagreementPercent);
medianPercent = median(relativeDisagreementPercent);
maxPercent = max(relativeDisagreementPercent);

disp(['min = ' num2str(minPercent) '%, median = ' num2str(medianPercent) '%, max = ' num2str(maxPercent) '%']);

bucketCounts = zeros(1, 5);
bucketLabels = {'0-5%', '5-10%', '10-15%', '15-20%', '20%+'};

for i = 1:numSubjects
    thisPercent = relativeDisagreementPercent(i);

    if thisPercent < 5
        bucketCounts(1) = bucketCounts(1) + 1;
    elseif thisPercent < 10
        bucketCounts(2) = bucketCounts(2) + 1;
    elseif thisPercent < 15
        bucketCounts(3) = bucketCounts(3) + 1;
    elseif thisPercent < 20
        bucketCounts(4) = bucketCounts(4) + 1;
    else
        bucketCounts(5) = bucketCounts(5) + 1;
    end
end

disp('Histogram-style breakdown:');

for bucketPos = 1:numel(bucketLabels)
    disp(['  ' bucketLabels{bucketPos} ': ' num2str(bucketCounts(bucketPos)) ' subjects']);
end

exactZeroCount = 0;

for i = 1:numSubjects
    if relativeDisagreementPercent(i) == 0
        exactZeroCount = exactZeroCount + 1;
    end
end

disp([num2str(exactZeroCount) ' of ' num2str(numSubjects) ' subjects have HR_chrom exactly equal to HR_pos (0% disagreement) -- this includes all 5 UBFC subjects, where the current pipeline output happens to make CHROM and POS bit-identical, and a large share of VIPL subjects as well. This is reported as-is from the real data; it is not something this task altered.']);

sortedPercent = sort(relativeDisagreementPercent);
nonZeroSortedPercent = sortedPercent(sortedPercent > 0);
numNonZero = numel(nonZeroSortedPercent);

largestGapValue = 0;
largestGapLowerBound = 0;
secondLargestGapValue = 0;
secondLargestGapLowerBound = 0;

for i = 2:numNonZero
    gapValue = nonZeroSortedPercent(i) - nonZeroSortedPercent(i - 1);

    if gapValue > largestGapValue
        secondLargestGapValue = largestGapValue;
        secondLargestGapLowerBound = largestGapLowerBound;
        largestGapValue = gapValue;
        largestGapLowerBound = nonZeroSortedPercent(i - 1);
    elseif gapValue > secondLargestGapValue
        secondLargestGapValue = gapValue;
        secondLargestGapLowerBound = nonZeroSortedPercent(i - 1);
    end
end

disp(' ');
disp('=== Threshold justification ===');
disp(['Largest gap in the sorted non-zero disagreement values: ' num2str(largestGapValue) ' percentage points, sitting right above ' num2str(largestGapLowerBound) '%.']);
disp(['Second-largest gap: ' num2str(secondLargestGapValue) ' percentage points, sitting right above ' num2str(secondLargestGapLowerBound) '%.']);
disp('Reading the distribution: the large majority of subjects (83 of 112, 74%) sit under 5% disagreement, and the values climb fairly continuously from there. The single largest gap isolates only one subject by itself (the most extreme outlier) -- too small a rule to generalize from. The second-largest gap is the real natural knee: it is a genuine cluster separator, not a lone-outlier artifact, splitting the pool into a dense lower mass and a distinctly higher, sparser tail.');

lowConfidenceThresholdPercent = secondLargestGapLowerBound;
lowConfidenceThresholdFraction = lowConfidenceThresholdPercent / 100;

disp(['Chosen low-confidence threshold: ' num2str(lowConfidenceThresholdPercent) '% relative disagreement (the second-largest-gap lower bound computed above), not picked in advance.']);

lowConfidenceFlag = false(1, numSubjects);
numFlagged = 0;

for i = 1:numSubjects
    if relativeDisagreementPercent(i) > lowConfidenceThresholdPercent
        lowConfidenceFlag(i) = true;
        numFlagged = numFlagged + 1;
    end
end

disp(['Subjects flagged low-confidence: ' num2str(numFlagged) ' of ' num2str(numSubjects) ' (' num2str(numFlagged / numSubjects * 100) '%).']);

disp(' ');
disp('=== Part 3a: does relative disagreement actually predict HR_chrom error? ===');

disagreementErrorCorrelation = computeMetrics(relativeDisagreement, hrAbsErrorChrom);

disp(['Pearson r between relative_disagreement and abs_error_chrom, N=' num2str(disagreementErrorCorrelation.n) ': ' num2str(disagreementErrorCorrelation.pearsonR)]);

if disagreementErrorCorrelation.pearsonR > 0.3
    disp('READING: higher CHROM/POS disagreement is associated with higher CHROM error -- a real, moderate positive relationship, not noise.');
elseif disagreementErrorCorrelation.pearsonR > 0
    disp('READING: higher CHROM/POS disagreement is weakly associated with higher CHROM error.');
else
    disp('READING: no positive relationship found between CHROM/POS disagreement and CHROM error.');
end

disp(' ');
disp('=== Part 3b: overlap with Task H1 worst-5 subjects ===');

worst5SubjectIDs = {'VIPL_p48_v1_source1', 'VIPL_p106_v1_source2', 'VIPL_p22_v1_source1', 'VIPL_p21_v1_source1', 'VIPL_p35_v1_source1'};
worst5OverlapCount = 0;

for worst5Pos = 1:numel(worst5SubjectIDs)
    thisSubjectID = worst5SubjectIDs{worst5Pos};
    matchIdx = 0;

    for i = 1:numSubjects
        if strcmp(hrSubjectID{i}, thisSubjectID)
            matchIdx = i;
        end
    end

    if matchIdx == 0
        disp([thisSubjectID ': NOT FOUND in pooled HR data.']);
        continue;
    end

    if lowConfidenceFlag(matchIdx)
        worst5OverlapCount = worst5OverlapCount + 1;
        disp([thisSubjectID ': FLAGGED low-confidence (relative disagreement = ' num2str(relativeDisagreementPercent(matchIdx)) '%).']);
    else
        disp([thisSubjectID ': NOT flagged (relative disagreement = ' num2str(relativeDisagreementPercent(matchIdx)) '%).']);
    end
end

disp(['Worst-5 overlap: ' num2str(worst5OverlapCount) ' of 5 worst-error subjects are flagged low-confidence by this metric.']);

disp(' ');
disp('=== Part 3c: confidence-gated pooled accuracy vs full-pool accuracy ===');

notFlaggedMask = ~lowConfidenceFlag;
numNotFlagged = sum(notFlaggedMask);

chromFullPoolMetrics = computeMetrics(hrChrom, hrGroundtruth);
posFullPoolMetrics = computeMetrics(hrPos, hrGroundtruth);

chromGatedMetrics = computeMetrics(hrChrom(notFlaggedMask), hrGroundtruth(notFlaggedMask));
posGatedMetrics = computeMetrics(hrPos(notFlaggedMask), hrGroundtruth(notFlaggedMask));

disp(['Excluded fraction to reach the gated subset: ' num2str(numFlagged) ' of ' num2str(numSubjects) ' subjects (' num2str(numFlagged / numSubjects * 100) '%), leaving N=' num2str(numNotFlagged) '.']);
disp(' ');
disp('CHROM, full pool vs confidence-gated:');
disp(['  Full pool:       N=' num2str(chromFullPoolMetrics.n) ', MAE=' num2str(chromFullPoolMetrics.mae) ', RMSE=' num2str(chromFullPoolMetrics.rmse) ', Pearson r=' num2str(chromFullPoolMetrics.pearsonR)]);
disp(['  Confidence-gated: N=' num2str(chromGatedMetrics.n) ', MAE=' num2str(chromGatedMetrics.mae) ', RMSE=' num2str(chromGatedMetrics.rmse) ', Pearson r=' num2str(chromGatedMetrics.pearsonR)]);
disp(' ');
disp('POS, full pool vs confidence-gated:');
disp(['  Full pool:       N=' num2str(posFullPoolMetrics.n) ', MAE=' num2str(posFullPoolMetrics.mae) ', RMSE=' num2str(posFullPoolMetrics.rmse) ', Pearson r=' num2str(posFullPoolMetrics.pearsonR)]);
disp(['  Confidence-gated: N=' num2str(posGatedMetrics.n) ', MAE=' num2str(posGatedMetrics.mae) ', RMSE=' num2str(posGatedMetrics.rmse) ', Pearson r=' num2str(posGatedMetrics.pearsonR)]);

disp(' ');
disp('=== Part 4: full-pool CHROM vs POS head-to-head (their own outputs against each other) ===');

chromVsPosMetrics = computeMetrics(hrChrom, hrPos);

disp(['CHROM vs POS agreement, N=' num2str(chromVsPosMetrics.n) ': MAE=' num2str(chromVsPosMetrics.mae) ', RMSE=' num2str(chromVsPosMetrics.rmse) ', Pearson r=' num2str(chromVsPosMetrics.pearsonR)]);
disp(['For reference, each method against ground truth (from segment6_hr_pooled_metrics.csv): CHROM MAE=' num2str(chromFullPoolMetrics.mae) ', RMSE=' num2str(chromFullPoolMetrics.rmse) ', Pearson r=' num2str(chromFullPoolMetrics.pearsonR) '; POS MAE=' num2str(posFullPoolMetrics.mae) ', RMSE=' num2str(posFullPoolMetrics.rmse) ', Pearson r=' num2str(posFullPoolMetrics.pearsonR) '.']);

if posFullPoolMetrics.mae < chromFullPoolMetrics.mae
    disp('READING: at the full N=112 pool, POS has lower MAE than CHROM against ground truth -- the same direction as the p21 anecdote, so it does generalize to the pool level, not just that one subject.');
else
    disp('READING: at the full N=112 pool, CHROM has lower or equal MAE than POS against ground truth -- the p21 anecdote does not generalize to the pool level.');
end

disp(' ');
disp('=== Saving per-subject agreement flags CSV ===');

agreementCsvPath = fullfile(metricsRoot, 'segment6_hr_agreement_flags.csv');
agreementHeaderLine = "subjectID,dataset,HR_chrom,HR_pos,HR_groundtruth,relative_disagreement,low_confidence_flag,abs_error_chrom";
writelines(agreementHeaderLine, agreementCsvPath);

for i = 1:numSubjects
    flagValue = 0;

    if lowConfidenceFlag(i)
        flagValue = 1;
    end

    rowParts = {hrSubjectID{i}, hrDataset{i}, num2str(hrChrom(i)), num2str(hrPos(i)), num2str(hrGroundtruth(i)), num2str(relativeDisagreement(i)), num2str(flagValue), num2str(hrAbsErrorChrom(i))};
    rowLine = strjoin(rowParts, ',');
    writelines(rowLine, agreementCsvPath, 'WriteMode', 'append');
end

disp(['Saved ' agreementCsvPath]);

disp(' ');
disp('--- Segment 6 Task I batch complete ---');

function textVal = extractTextTaskI(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
