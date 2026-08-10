function R_centered = centerRPerDataset(R_values, datasetLabels, holdoutIdx)
% CENTERRPERDATASET Subtract each dataset's own training-only mean R from
% every pooled R value, for one LOSO fold.
%
% Pipeline stage: Stage 6 (validation) -- a validation-pool preprocessing
% step, NOT a Segment 5 algorithm change. This function does not touch
% spo2/ratioOfRatios.m or spo2/calibrateSpO2.m at all; it only reshapes
% the R values handed to calibrateSpO2.m before that unmodified function
% ever sees them, so that a per-dataset offset does not get baked into
% the single pooled linear fit calibrateSpO2.m produces.
%
% Why this exists: Segment6_Refinement_Notes.md documents that UBFC and
% VIPL occupy largely non-overlapping raw R ranges for a similar true
% SpO2 range (segment6_R_vs_SpO2_by_dataset.png). Centering each
% dataset's R values on that dataset's own mean removes the between-
% dataset offset while leaving each subject's within-dataset deviation
% from its dataset's mean untouched -- the part of R that can still
% carry a physiological signal.
%
% Leakage-avoidance reasoning (same discipline as runLOSO.m's own
% held-out-subject rule, made explicit here since this function is the
% one place that discipline could quietly break): the mean subtracted
% for each dataset must be computed using ONLY the training subjects of
% THIS fold, i.e. every subject except the one at holdoutIdx. If the
% held-out subject's own R value were allowed to contribute to its
% dataset's mean, the centered R fed to calibrateSpO2.m for that subject
% would already encode information about the very subject being
% predicted -- the same leakage runLOSO.m exists to prevent when fitting
% calibParams. Because holdoutIdx identifies exactly one subject, and
% that subject belongs to exactly one dataset, only that one dataset's
% mean is affected per fold; the other dataset's mean is unchanged from
% a run that used the full pooled set. This function is called fresh
% inside every fold of runLOSO.m's loop, never once globally, so this
% recomputation happens on every single fold and never uses a mean
% computed before the current holdoutIdx was chosen.
%
% Inputs:
%   R_values      - vector, pooled ratio-of-ratios R value per subject,
%                   same length/order as datasetLabels.
%   datasetLabels - cell array of strings, same length as R_values, which
%                   dataset ('UBFC' or 'VIPL') each entry came from.
%   holdoutIdx    - scalar, the index into R_values/datasetLabels of the
%                   subject held out for this LOSO fold. This subject is
%                   excluded when computing each dataset's mean, but it
%                   still receives a centered R value in the output
%                   (using its own dataset's training-only mean).
%
% Outputs:
%   R_centered - vector, same length/order as R_values, each entry with
%                its own dataset's training-only mean R subtracted.

numSubjects = numel(R_values);

if numel(datasetLabels) ~= numSubjects
    error('centerRPerDataset:sizeMismatch', 'R_values and datasetLabels must have the same length.');
end

trainMask = true(1, numSubjects);
trainMask(holdoutIdx) = false;

uniqueDatasets = unique(datasetLabels);
numDatasets = numel(uniqueDatasets);

datasetTrainMean = zeros(1, numDatasets);

for datasetPos = 1:numDatasets
    thisDataset = uniqueDatasets{datasetPos};
    sumR = 0;
    countR = 0;

    for i = 1:numSubjects
        if trainMask(i) && strcmp(datasetLabels{i}, thisDataset)
            sumR = sumR + R_values(i);
            countR = countR + 1;
        end
    end

    if countR == 0
        error('centerRPerDataset:noTrainingData', ['No training subjects remain for dataset ' thisDataset ' after excluding holdoutIdx ' num2str(holdoutIdx) '.']);
    end

    datasetTrainMean(datasetPos) = sumR / countR;
end

R_centered = zeros(1, numSubjects);

for i = 1:numSubjects
    for datasetPos = 1:numDatasets
        if strcmp(datasetLabels{i}, uniqueDatasets{datasetPos})
            R_centered(i) = R_values(i) - datasetTrainMean(datasetPos);
        end
    end
end

end
