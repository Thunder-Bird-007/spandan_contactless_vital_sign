% RUN_SEGMENT6_TASK_K_AGREEMENT_BREAKDOWN Follow-up to Task K: checks
% whether Task I's original CHROM-agree/POS-disagree asymmetry (the
% asymmetry switching depends on) still holds once v7 is added to the
% pool.
%
% This script does NOT extract any new data and does NOT modify
% computeAgreementConfidence.m, computeSwitchingEstimate.m,
% computeMetrics.m, Segment6_Refinement_Notes.md, or Task K's own files
% (run_segment6_task_k_pooled_v1_v7.m, Segment6_Task_K_v7_Integration.md).
% It only re-reads results/metrics/segment4_hr_summary.csv,
% segment4_hr_summary_vipl.csv, segment4_hr_summary_v7.csv, and
% results/metrics/segment6_hr_agreement_flags_v1_v7.csv (all already
% computed by Task K), then re-slices those existing numbers through the
% existing unmodified computeMetrics.m.
%
% Outputs:
%   matlab/docs/Segment6_Task_K_Addendum_Agreement_Breakdown.md - the two
%     side-by-side agree/disagree breakdown tables (refit and old
%     threshold) plus the asymmetry verdict.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
docsRoot = fullfile(projectRoot, 'matlab', 'docs');

if ~isfolder(docsRoot)
    mkdir(docsRoot);
end

disp('=== Segment 6 Task K Addendum: does the CHROM-agree/POS-disagree asymmetry survive v7? ===');

disp(' ');
disp('=== Loading pooled v1+v7 HR data (same three source CSVs Task K used) ===');

pooledSubjectID = {};
pooledDataset = {};
pooledChrom = [];
pooledPos = [];
pooledGroundtruth = [];

ubfcPath = fullfile(metricsRoot, 'segment4_hr_summary.csv');

if isfile(ubfcPath)
    ubfcTable = readtable(ubfcPath);
    numRows = height(ubfcTable);

    for rowPos = 1:numRows
        pooledSubjectID{end + 1} = extractTextAddendum(ubfcTable.subjectID, rowPos);
        pooledDataset{end + 1} = 'UBFC';
        pooledChrom(end + 1) = ubfcTable.HR_chrom(rowPos);
        pooledPos(end + 1) = ubfcTable.HR_pos(rowPos);
        pooledGroundtruth(end + 1) = ubfcTable.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' UBFC HR rows from ' ubfcPath]);
end

viplV1Path = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');

if isfile(viplV1Path)
    viplV1Table = readtable(viplV1Path);
    numRows = height(viplV1Table);

    for rowPos = 1:numRows
        pooledSubjectID{end + 1} = extractTextAddendum(viplV1Table.subjectID, rowPos);
        pooledDataset{end + 1} = extractTextAddendum(viplV1Table.dataset, rowPos);
        pooledChrom(end + 1) = viplV1Table.HR_chrom(rowPos);
        pooledPos(end + 1) = viplV1Table.HR_pos(rowPos);
        pooledGroundtruth(end + 1) = viplV1Table.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL v1 HR rows from ' viplV1Path]);
end

viplV7Path = fullfile(metricsRoot, 'segment4_hr_summary_v7.csv');

if isfile(viplV7Path)
    viplV7Table = readtable(viplV7Path);
    numRows = height(viplV7Table);

    for rowPos = 1:numRows
        pooledSubjectID{end + 1} = extractTextAddendum(viplV7Table.subjectID, rowPos);
        pooledDataset{end + 1} = extractTextAddendum(viplV7Table.dataset, rowPos);
        pooledChrom(end + 1) = viplV7Table.HR_chrom(rowPos);
        pooledPos(end + 1) = viplV7Table.HR_pos(rowPos);
        pooledGroundtruth(end + 1) = viplV7Table.HR_groundtruth(rowPos);
    end

    disp(['Loaded ' num2str(numRows) ' VIPL v7 HR rows from ' viplV7Path]);
else
    error('runSegment6TaskKAgreementBreakdown:noV7Data', 'segment4_hr_summary_v7.csv not found -- this addendum expects Task K''s already-extracted v7 data to exist.');
end

numPooled = numel(pooledSubjectID);

disp(['v1+v7 pooled: ' num2str(numPooled) ' subjects.']);

disp(' ');
disp('=== Loading Task K''s already-computed per-subject relative disagreement ===');

agreementFlagsPath = fullfile(metricsRoot, 'segment6_hr_agreement_flags_v1_v7.csv');

if ~isfile(agreementFlagsPath)
    error('runSegment6TaskKAgreementBreakdown:noAgreementFlags', 'segment6_hr_agreement_flags_v1_v7.csv not found -- run scripts/run_segment6_task_k_pooled_v1_v7.m first.');
end

agreementTable = readtable(agreementFlagsPath);
numAgreementRows = height(agreementTable);

disp(['Loaded ' num2str(numAgreementRows) ' rows from ' agreementFlagsPath]);

if numAgreementRows ~= numPooled
    error('runSegment6TaskKAgreementBreakdown:sizeMismatch', 'Agreement flags CSV has %d rows but the pooled HR data has %d subjects -- these must come from the same Task K pool.', numAgreementRows, numPooled);
end

agreementSubjectID = {};

for rowPos = 1:numAgreementRows
    agreementSubjectID{end + 1} = extractTextAddendum(agreementTable.subjectID, rowPos);
end

relativeDisagreementPercent = zeros(1, numPooled);

for i = 1:numPooled
    matchIdx = 0;

    for rowPos = 1:numAgreementRows
        if strcmp(agreementSubjectID{rowPos}, pooledSubjectID{i})
            matchIdx = rowPos;
        end
    end

    if matchIdx == 0
        error('runSegment6TaskKAgreementBreakdown:subjectNotFound', 'Subject %s from the pooled HR data was not found in the agreement flags CSV.', pooledSubjectID{i});
    end

    relativeDisagreementPercent(i) = agreementTable.relative_disagreement(matchIdx) * 100;
end

disp(' ');
disp('=== Splitting the v1+v7 pool by the REFIT threshold (59.54%) ===');

refitThresholdPercent = 59.54;

refitAgreeMask = relativeDisagreementPercent < refitThresholdPercent;
refitDisagreeMask = ~refitAgreeMask;

refitAgreeChromMetrics = computeMetrics(pooledChrom(refitAgreeMask), pooledGroundtruth(refitAgreeMask));
refitAgreePosMetrics = computeMetrics(pooledPos(refitAgreeMask), pooledGroundtruth(refitAgreeMask));
refitDisagreeChromMetrics = computeMetrics(pooledChrom(refitDisagreeMask), pooledGroundtruth(refitDisagreeMask));
refitDisagreePosMetrics = computeMetrics(pooledPos(refitDisagreeMask), pooledGroundtruth(refitDisagreeMask));

refitAgreeWinner = 'CHROM';

if refitAgreePosMetrics.mae < refitAgreeChromMetrics.mae
    refitAgreeWinner = 'POS';
end

refitDisagreeWinner = 'CHROM';

if refitDisagreePosMetrics.mae < refitDisagreeChromMetrics.mae
    refitDisagreeWinner = 'POS';
end

disp('Group    | Threshold source | N   | CHROM MAE | POS MAE | Winner');
disp(['agree    | refit (59.54%)   | ' num2str(refitAgreeChromMetrics.n) ' | ' num2str(refitAgreeChromMetrics.mae) ' | ' num2str(refitAgreePosMetrics.mae) ' | ' refitAgreeWinner]);
disp(['disagree | refit (59.54%)   | ' num2str(refitDisagreeChromMetrics.n) ' | ' num2str(refitDisagreeChromMetrics.mae) ' | ' num2str(refitDisagreePosMetrics.mae) ' | ' refitDisagreeWinner]);

disp(' ');
disp('=== Splitting the v1+v7 pool by the OLD v1-only threshold (29.27%) ===');

oldThresholdPercent = 29.27;

oldAgreeMask = relativeDisagreementPercent < oldThresholdPercent;
oldDisagreeMask = ~oldAgreeMask;

oldAgreeChromMetrics = computeMetrics(pooledChrom(oldAgreeMask), pooledGroundtruth(oldAgreeMask));
oldAgreePosMetrics = computeMetrics(pooledPos(oldAgreeMask), pooledGroundtruth(oldAgreeMask));
oldDisagreeChromMetrics = computeMetrics(pooledChrom(oldDisagreeMask), pooledGroundtruth(oldDisagreeMask));
oldDisagreePosMetrics = computeMetrics(pooledPos(oldDisagreeMask), pooledGroundtruth(oldDisagreeMask));

oldAgreeWinner = 'CHROM';

if oldAgreePosMetrics.mae < oldAgreeChromMetrics.mae
    oldAgreeWinner = 'POS';
end

oldDisagreeWinner = 'CHROM';

if oldDisagreePosMetrics.mae < oldDisagreeChromMetrics.mae
    oldDisagreeWinner = 'POS';
end

disp('Group    | Threshold source | N   | CHROM MAE | POS MAE | Winner');
disp(['agree    | old (29.27%)     | ' num2str(oldAgreeChromMetrics.n) ' | ' num2str(oldAgreeChromMetrics.mae) ' | ' num2str(oldAgreePosMetrics.mae) ' | ' oldAgreeWinner]);
disp(['disagree | old (29.27%)     | ' num2str(oldDisagreeChromMetrics.n) ' | ' num2str(oldDisagreeChromMetrics.mae) ' | ' num2str(oldDisagreePosMetrics.mae) ' | ' oldDisagreeWinner]);

disp(' ');
disp('=== Comparison against Task I''s original v1-only finding ===');
disp('Task I (v1-only, N=112, 29.27% threshold): agree subset (N=104) CHROM MAE=6.5407 < POS MAE=6.9863 (CHROM wins); disagree subset (N=8) drags CHROM below POS at the full-pool level, i.e. POS wins the disagree tail.');

refitPatternHolds = strcmp(refitAgreeWinner, 'CHROM') && strcmp(refitDisagreeWinner, 'POS');
oldPatternHolds = strcmp(oldAgreeWinner, 'CHROM') && strcmp(oldDisagreeWinner, 'POS');

if refitPatternHolds
    disp('Refit threshold (59.54%) on v1+v7: pattern HOLDS -- CHROM still wins the agree subset, POS still wins the disagree subset.');
else
    disp(['Refit threshold (59.54%) on v1+v7: pattern DOES NOT HOLD as originally found -- agree subset winner is ' refitAgreeWinner ', disagree subset winner is ' refitDisagreeWinner '.']);
end

if oldPatternHolds
    disp('Old threshold (29.27%) on v1+v7: pattern HOLDS -- CHROM still wins the agree subset, POS still wins the disagree subset.');
else
    disp(['Old threshold (29.27%) on v1+v7: pattern DOES NOT HOLD as originally found -- agree subset winner is ' oldAgreeWinner ', disagree subset winner is ' oldDisagreeWinner '.']);
end

disp(' ');
disp('--- Segment 6 Task K Addendum batch complete ---');

reportPath = fullfile(docsRoot, 'Segment6_Task_K_Addendum_Agreement_Breakdown.md');

reportLines = {};
reportLines{end + 1} = '# Segment 6 Task K Addendum: Does the CHROM-Agree/POS-Disagree Asymmetry Survive v7?';
reportLines{end + 1} = '';
reportLines{end + 1} = 'Follow-up to Task K. On the pooled v1+v7 dataset (N=218), plain POS (MAE';
reportLines{end + 1} = '11.36) now beats both switching variants (old-threshold 11.52, refit-';
reportLines{end + 1} = 'threshold 11.65) -- a reversal of Task J''s v1-only finding that switching';
reportLines{end + 1} = 'beat both individual methods. This addendum checks WHY, by re-slicing';
reportLines{end + 1} = 'Task K''s already-computed data: does the asymmetry Task I originally found';
reportLines{end + 1} = '(CHROM wins where CHROM and POS agree, POS wins where they disagree)';
reportLines{end + 1} = 'still hold once v7 is in the pool?';
reportLines{end + 1} = '';
reportLines{end + 1} = 'This is a read-only re-slice of existing numbers: no new video processing,';
reportLines{end + 1} = 'no changes to computeAgreementConfidence.m, computeSwitchingEstimate.m, or';
reportLines{end + 1} = 'Task K''s own files. Source data: segment4_hr_summary.csv,';
reportLines{end + 1} = 'segment4_hr_summary_vipl.csv, segment4_hr_summary_v7.csv, and';
reportLines{end + 1} = 'segment6_hr_agreement_flags_v1_v7.csv, all already produced by';
reportLines{end + 1} = 'run_segment6_task_k_pooled_v1_v7.m.';
reportLines{end + 1} = '';
reportLines{end + 1} = '## Agree/disagree breakdown, refit threshold (59.54%)';
reportLines{end + 1} = '';
reportLines{end + 1} = '| Group | N | CHROM MAE | POS MAE | Winner |';
reportLines{end + 1} = '|---|---|---|---|---|';
reportLines{end + 1} = ['| agree (< 59.54%) | ' num2str(refitAgreeChromMetrics.n) ' | ' num2str(refitAgreeChromMetrics.mae) ' | ' num2str(refitAgreePosMetrics.mae) ' | ' refitAgreeWinner ' |'];
reportLines{end + 1} = ['| disagree (>= 59.54%) | ' num2str(refitDisagreeChromMetrics.n) ' | ' num2str(refitDisagreeChromMetrics.mae) ' | ' num2str(refitDisagreePosMetrics.mae) ' | ' refitDisagreeWinner ' |'];
reportLines{end + 1} = '';
reportLines{end + 1} = '## Agree/disagree breakdown, old v1-only threshold (29.27%)';
reportLines{end + 1} = '';
reportLines{end + 1} = '| Group | N | CHROM MAE | POS MAE | Winner |';
reportLines{end + 1} = '|---|---|---|---|---|';
reportLines{end + 1} = ['| agree (< 29.27%) | ' num2str(oldAgreeChromMetrics.n) ' | ' num2str(oldAgreeChromMetrics.mae) ' | ' num2str(oldAgreePosMetrics.mae) ' | ' oldAgreeWinner ' |'];
reportLines{end + 1} = ['| disagree (>= 29.27%) | ' num2str(oldDisagreeChromMetrics.n) ' | ' num2str(oldDisagreeChromMetrics.mae) ' | ' num2str(oldDisagreePosMetrics.mae) ' | ' oldDisagreeWinner ' |'];
reportLines{end + 1} = '';
reportLines{end + 1} = '## Comparison against Task I''s original v1-only finding';
reportLines{end + 1} = '';
reportLines{end + 1} = 'Task I (v1-only, N=112, 29.27% threshold, Segment6_Refinement_Notes.md';
reportLines{end + 1} = 'Section I.4-5): agree subset (N=104) CHROM MAE=6.5407 vs POS MAE=6.9863 --';
reportLines{end + 1} = 'CHROM wins. Disagree subset (N=8) is what drags CHROM''s full-pool MAE below';
reportLines{end + 1} = 'POS''s at the full N=112 level -- POS wins the disagree tail. This asymmetry';
reportLines{end + 1} = '(CHROM-agree, POS-disagree) is the entire mechanical reason Task J''s';
reportLines{end + 1} = 'switching estimator beat both individual methods.';
reportLines{end + 1} = '';

if refitPatternHolds
    reportLines{end + 1} = 'On the v1+v7 pool with the refit (59.54%) threshold, the pattern **holds**: CHROM still wins the agree subset, POS still wins the disagree subset.';
else
    reportLines{end + 1} = ['On the v1+v7 pool with the refit (59.54%) threshold, the pattern **does not hold** as originally found: the agree-subset winner is ' refitAgreeWinner ', the disagree-subset winner is ' refitDisagreeWinner '.'];
end

reportLines{end + 1} = '';

if oldPatternHolds
    reportLines{end + 1} = 'With the old (29.27%) threshold, the pattern **holds**: CHROM still wins the agree subset, POS still wins the disagree subset.';
else
    reportLines{end + 1} = ['With the old (29.27%) threshold, the pattern **does not hold** as originally found: the agree-subset winner is ' oldAgreeWinner ', the disagree-subset winner is ' oldDisagreeWinner '.'];
end

reportLines{end + 1} = '';
reportLines{end + 1} = '## Verdict';
reportLines{end + 1} = '';

if ~refitPatternHolds && ~oldPatternHolds
    reportLines{end + 1} = ['The CHROM-agree/POS-disagree asymmetry that made switching win on the v1-only pool has flipped on the v1+v7 pool under both threshold choices: POS now wins the agree subset too (refit: CHROM MAE=' num2str(refitAgreeChromMetrics.mae) ' vs POS MAE=' num2str(refitAgreePosMetrics.mae) '; old: CHROM MAE=' num2str(oldAgreeChromMetrics.mae) ' vs POS MAE=' num2str(oldAgreePosMetrics.mae) '). This is the direct explanation for switching''s aggregate loss in Task K: the switching rule keeps CHROM in the majority-agree case precisely where CHROM is now the worse method, so it is actively steering toward the worse estimate most of the time. The rule itself has not changed -- the asymmetry it was built to exploit is what disappeared once v7''s higher-HR, higher-motion subjects entered the pool.'];
elseif refitPatternHolds && oldPatternHolds
    reportLines{end + 1} = 'The CHROM-agree/POS-disagree asymmetry still holds on the v1+v7 pool under both threshold choices, so switching''s aggregate loss in Task K is NOT explained by this asymmetry flipping -- the explanation lies elsewhere (e.g. in how v7 redistributes subjects between the two subsets, or in the disagree subset''s size/composition, not in which method wins within each subset).';
else
    reportLines{end + 1} = ['The asymmetry holds for one threshold choice but not the other on the v1+v7 pool (refit-threshold pattern holds: ' mat2str(refitPatternHolds) '; old-threshold pattern holds: ' mat2str(oldPatternHolds) '), so the explanation for switching''s aggregate loss in Task K depends on which threshold is being scored and cannot be reduced to a single flip/no-flip statement.'];
end

reportLines{end + 1} = '';

reportText = strjoin(reportLines, newline);
writelines(reportText, reportPath);

disp(['Saved ' reportPath]);

function textVal = extractTextAddendum(tableColumn, rowPos)

if iscell(tableColumn)
    textVal = tableColumn{rowPos};
else
    textVal = char(tableColumn(rowPos));
end

end
