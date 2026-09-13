% RUN_SEGMENT8_TASK3_SOURCE2_TIMING_FIX Segment 8 (post-review follow-up),
% Action 3. Per Chen, Lin & Jeong (Sensors 2025, 25(2):588), tests whether
% cubic-spline resampling onto the corrected true frame rate beats the
% already-tried naive constant-relabel fix
% (scripts/task_source2_fpsfix_reprocess.m,
% results/metrics/segment4_hr_summary_vipl_source2_fpsfix.csv) for the 12
% VIPL-HR source2 subjects.
%
% IMPORTANT, established BEFORE writing this script (see
% docs/Segment8_Task3_Source2_Timing_Fix.md for the full reasoning):
% VIPL-HR source2 has NO time.txt (io/loadVIPLVideo.m's own documented
% limitation) -- there is no real per-frame timestamp source for it, only
% an average-rate estimate borrowed from a sibling source's session
% duration (task_source2_fps_investigation.m). Chen/Lin/Jeong's
% cubic-spline correction is designed to fix IRREGULAR per-frame timing
% using REAL per-frame timestamps; without them, "cubic-spline resampling"
% has no real per-frame jitter to correct and reduces to
% filtering/resampleSource2CubicSpline.m's relabel-only mode -- i.e. the
% same operation scripts/task_source2_fpsfix_reprocess.m already
% performed. This script verifies that expectation empirically (not just
% algebraically) by ALSO computing a "naive-spline" condition (spline
% interpolation through the WRONG, fictional container-rate-assumed
% timestamps, evaluated at the corrected-rate grid) to show concretely
% what happens if someone fabricates precision by treating an assumed
% grid as if it were real timing data -- included as a cautionary
% negative control, not because it's expected to win.
%
% Three HR estimates are computed per subject, all via the exact same
% Branch 1 production chain (extractROISignals -> detrendSignal ->
% bandpassClean -> chromCombine/posCombine -> fftHeartRate) used
% everywhere else in this project:
%   1. naive_25fps    - the ORIGINAL, uncorrected baseline (container's
%                        wrong 25 fps throughout). Reuses
%                        results/metrics/segment4_hr_summary_vipl.csv's
%                        already-computed values (not recomputed).
%   2. relabel         - scripts/task_source2_fpsfix_reprocess.m's
%                        already-computed constant-relabel fix. Reuses
%                        results/metrics/segment4_hr_summary_vipl_source2_fpsfix.csv
%                        (not recomputed).
%   3. naive_spline    - NEW: filtering/resampleSource2CubicSpline.m
%                        called with FICTIONAL source timestamps
%                        ((0:N-1)/25, the wrong container rate) as
%                        sourceTimestampsSec, evaluated onto the
%                        corrected trueFps grid -- the "what if someone
%                        did this anyway" condition.
%
% Does NOT modify extractROISignals.m, detrendSignal.m, bandpassClean.m,
% chromCombine.m, posCombine.m, fftHeartRate.m, loadVIPLVideo.m, or
% task_source2_fpsfix_reprocess.m.
%
% Output: results/metrics/segment8_task3_source2_timing_comparison.csv

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
viplRoot = fullfile(projectRoot, 'data', 'raw', 'VIPL-HR');
metricsRoot = fullfile(projectRoot, 'results', 'metrics');

fpsCsvPath = fullfile(metricsRoot, 'segment8_source2_fps_investigation.csv');
naiveCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');
relabelCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl_source2_fpsfix.csv');

fpsTable = readtable(fpsCsvPath, 'TextType', 'string');
naiveTable = readtable(naiveCsvPath, 'TextType', 'string');
relabelTable = readtable(relabelCsvPath, 'TextType', 'string');

outCsvPath = fullfile(metricsRoot, 'segment8_task3_source2_timing_comparison.csv');
headerLine = "subjectID,containerFps,trueFps,HR_groundtruth,HR_chrom_naive25fps,HR_chrom_relabel,HR_chrom_naivespline,abs_err_naive25fps,abs_err_relabel,abs_err_naivespline,relabel_vs_naivespline_identical,maxAbsDiff_relabel_vs_naivespline";
writelines(headerLine, outCsvPath);

numSubjects = height(fpsTable);
fprintf('%-22s %10s %10s %10s %10s %10s %10s %12s\n', 'subjectID', 'GT', 'err_naive', 'err_relbl', 'err_splin', 'trueFps', 'contFps', 'relbl==splin?');

for idx = 1:numSubjects
    subjectID = char(fpsTable.subjectID(idx));
    trueFps = fpsTable.trueFps_source2(idx);
    containerFps = fpsTable.containerFps(idx);

    tok = regexp(subjectID, '^VIPL_p(\d+)_v(\d+)_source2$', 'tokens', 'once');
    subjectNum = str2double(tok{1});
    scenarioNum = str2double(tok{2});

    try
        videoPath = fullfile(viplRoot, ['p' num2str(subjectNum)], ['v' num2str(scenarioNum)], 'source2', 'video.avi');
        videoReaderObj = VideoReader(videoPath);

        [R, G, B, ~, ~, ~] = extractROISignals(videoReaderObj, containerFps, 'forehead');
        N = numel(R);

        % --- Condition 3: naive-spline -- FICTIONAL source timestamps
        % (the wrong container-rate assumption), spline-interpolated onto
        % the corrected trueFps grid. Expected (per this script's header)
        % to be, at best, no better than relabel, and possibly worse
        % (fabricated precision from wrong source timestamps). ---
        fictionalTimestamps = (0:N - 1) / containerFps;
        [R_spline, ~] = resampleSource2CubicSpline(R, fictionalTimestamps, trueFps, N);
        [G_spline, ~] = resampleSource2CubicSpline(G, fictionalTimestamps, trueFps, N);
        [B_spline, ~] = resampleSource2CubicSpline(B, fictionalTimestamps, trueFps, N);

        [R_spline_d, ~] = detrendSignal(R_spline);
        [G_spline_d, ~] = detrendSignal(G_spline);
        [B_spline_d, ~] = detrendSignal(B_spline);
        [R_spline_f, ~] = bandpassClean(R_spline_d, trueFps);
        [G_spline_f, ~] = bandpassClean(G_spline_d, trueFps);
        [B_spline_f, ~] = bandpassClean(B_spline_d, trueFps);
        pulseSpline = chromCombine(R_spline_f, G_spline_f, B_spline_f, R_spline, G_spline, B_spline);
        pulseSplineFiltered = bandpassClean(pulseSpline, trueFps);
        HR_chrom_naivespline = fftHeartRate(pulseSplineFiltered, trueFps);

        % --- Condition 2 (relabel-only mode, computed fresh here too, to
        % directly diff against condition 3 sample-by-sample on the SAME
        % raw R/G/B decode -- not just compared via the old CSV's
        % already-published number, to rule out any decode-run-to-run
        % difference confounding the identical/not-identical check). ---
        [R_relbl, ~] = resampleSource2CubicSpline(R, [], trueFps, N);
        [G_relbl, ~] = resampleSource2CubicSpline(G, [], trueFps, N);
        [B_relbl, ~] = resampleSource2CubicSpline(B, [], trueFps, N);

        maxAbsDiff = max([max(abs(R_relbl - R)), max(abs(G_relbl - G)), max(abs(B_relbl - B))]);
        % (R_relbl should be bit-identical to R -- relabel-only mode does
        % not touch sample values, see resampleSource2CubicSpline.m.)

        [R_relbl_d, ~] = detrendSignal(R_relbl);
        [G_relbl_d, ~] = detrendSignal(G_relbl);
        [B_relbl_d, ~] = detrendSignal(B_relbl);
        [R_relbl_f, ~] = bandpassClean(R_relbl_d, trueFps);
        [G_relbl_f, ~] = bandpassClean(G_relbl_d, trueFps);
        [B_relbl_f, ~] = bandpassClean(B_relbl_d, trueFps);
        pulseRelbl = chromCombine(R_relbl_f, G_relbl_f, B_relbl_f, R_relbl, G_relbl, B_relbl);
        pulseRelblFiltered = bandpassClean(pulseRelbl, trueFps);
        HR_chrom_relabel_recomputed = fftHeartRate(pulseRelblFiltered, trueFps);

        gt = loadVIPLGroundTruth(viplRoot, subjectNum, scenarioNum, 2);
        HR_groundtruth = mean(gt.hr);

        naiveRow = naiveTable(naiveTable.subjectID == subjectID, :);
        HR_chrom_naive25fps = naiveRow.HR_chrom(1);

        relabelRow = relabelTable(relabelTable.subjectID == subjectID, :);
        HR_chrom_relabel_published = relabelRow.HR_chrom_new(1);

        absErrNaive = abs(HR_chrom_naive25fps - HR_groundtruth);
        absErrRelabel = abs(HR_chrom_relabel_published - HR_groundtruth);
        absErrSpline = abs(HR_chrom_naivespline - HR_groundtruth);

        hrIdentical = abs(HR_chrom_relabel_recomputed - HR_chrom_naivespline) < 1e-6;

        fprintf('%-22s %10.2f %10.2f %10.2f %10.2f %10.4f %10.4f %12s\n', subjectID, HR_groundtruth, ...
            absErrNaive, absErrRelabel, absErrSpline, trueFps, containerFps, mat2str(hrIdentical));

        row = {subjectID, num2str(containerFps, '%.4f'), num2str(trueFps, '%.4f'), num2str(HR_groundtruth, '%.4f'), ...
            num2str(HR_chrom_naive25fps, '%.4f'), num2str(HR_chrom_relabel_published, '%.4f'), num2str(HR_chrom_naivespline, '%.4f'), ...
            num2str(absErrNaive, '%.4f'), num2str(absErrRelabel, '%.4f'), num2str(absErrSpline, '%.4f'), ...
            mat2str(hrIdentical), num2str(maxAbsDiff, '%.10f')};
        writelines(strjoin(row, ','), outCsvPath, 'WriteMode', 'append');
    catch causeErr
        disp([subjectID ': FAILED -- ' causeErr.identifier ' -- ' causeErr.message]);
    end
end

disp(' ');
disp(['--- Segment 8 Task 3 timing comparison complete. Saved ' outCsvPath ' ---']);
