% TASK_SOURCE2_OCTAVE_CHECK Segment 8 (post-review follow-up), Action 3.
% Tests the leading explanation for why source2's ORIGINAL (25 fps
% container, uncorrected) CHROM ratio (+11.5% median, biased HIGH) does
% NOT match the direction/magnitude a pure fs scale error predicts
% (source2 POS's 0.816 median ratio matches the predicted 0.833 closely;
% a pure fs error would bias BOTH methods low by the same factor, since fs
% enters fftHeartRate.m's frequency axis identically for both -- see
% heartrate/fftHeartRate.m's freqResolution = frameRate / signalLength).
%
% Segment 7 Task E already documented a harmonic lock-on failure mode:
% morphology/adaptiveHarmonicFilter.m's harmonic comb can lock onto 2x/0.5x
% the true rate when its f0 estimate is off. This script checks the
% ANALOGOUS but distinct possibility for the PRODUCTION path used here
% (chromCombine.m -> fftHeartRate.m's plain FFT peak-pick, no harmonic
% comb): whether HR_chrom's FFT peak-pick simply locked onto a harmonic
% (~2x) or subharmonic (~0.5x) of the true cardiac rate, using either
% ground truth or HR_pos (which tracks the predicted pure-fs-error
% direction) as the reference for "true rate".
%
% Reads ONLY results/metrics/segment4_hr_summary_vipl.csv (the EXISTING,
% unmodified, ORIGINAL/25fps-container CHROM and POS numbers for these 12
% subjects) -- this script writes no CSV, does not touch that file, and
% calls no pipeline function; it is a pure arithmetic check over already-
% computed numbers.

thisFileDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(thisFileDir));
metricsRoot = fullfile(projectRoot, 'results', 'metrics');
oldCsvPath = fullfile(metricsRoot, 'segment4_hr_summary_vipl.csv');

oldTable = readtable(oldCsvPath, 'TextType', 'string');

isSource2 = endsWith(oldTable.subjectID, '_source2');
source2Table = oldTable(isSource2, :);

numSubjects = height(source2Table);

% Octave-error tolerance: within 10% of exactly 2x or 0.5x.
octaveTolerance = 0.10;

octaveHitsVsGT = 0;
octaveHitsVsPos = 0;

fprintf('%-24s %10s %10s %10s %14s %14s\n', 'subjectID', 'HR_chrom', 'HR_pos', 'GT', 'ratio_vs_GT', 'ratio_vs_POS');

for idx = 1:numSubjects
    subjectID = char(source2Table.subjectID(idx));
    hrChrom = source2Table.HR_chrom(idx);
    hrPos = source2Table.HR_pos(idx);
    hrGT = source2Table.HR_groundtruth(idx);

    ratioVsGT = hrChrom / hrGT;
    ratioVsPos = hrChrom / hrPos;

    isOctaveVsGT = isNearOctave(ratioVsGT, octaveTolerance);
    isOctaveVsPos = isNearOctave(ratioVsPos, octaveTolerance);

    if isOctaveVsGT
        octaveHitsVsGT = octaveHitsVsGT + 1;
    end
    if isOctaveVsPos
        octaveHitsVsPos = octaveHitsVsPos + 1;
    end

    flagStr = '';
    if isOctaveVsGT
        flagStr = [flagStr ' <-- ~octave-of-GT'];
    end
    if isOctaveVsPos
        flagStr = [flagStr ' <-- ~octave-of-POS'];
    end

    fprintf('%-24s %10.2f %10.2f %10.2f %14.4f %14.4f%s\n', subjectID, hrChrom, hrPos, hrGT, ratioVsGT, ratioVsPos, flagStr);
end

disp(' ');
disp(['--- Octave-error check across ' num2str(numSubjects) ' source2 subjects (tolerance +/-' num2str(100 * octaveTolerance) '% of exactly 2x or 0.5x) ---']);
disp(['HR_chrom near an octave of ground truth:  ' num2str(octaveHitsVsGT) ' / ' num2str(numSubjects)]);
disp(['HR_chrom near an octave of HR_pos:        ' num2str(octaveHitsVsPos) ' / ' num2str(numSubjects)]);

if octaveHitsVsGT >= ceil(numSubjects / 2) || octaveHitsVsPos >= ceil(numSubjects / 2)
    disp('CONCLUSION: octave (2x/0.5x) lock-on accounts for at least half of the 12 source2 CHROM discrepancies -- consistent with the leading explanation.');
else
    disp('CONCLUSION: octave (2x/0.5x) lock-on does NOT account for most of the 12 source2 CHROM discrepancies. The leading explanation does NOT hold up under this direct test -- left OPEN, not replaced with a second guess.');
end

function result = isNearOctave(ratio, tolerance)
% ISNEAROCTAVE True if ratio is within `tolerance` (relative) of exactly
% 2.0 or exactly 0.5.
result = (abs(ratio - 2.0) / 2.0 <= tolerance) || (abs(ratio - 0.5) / 0.5 <= tolerance);
end
