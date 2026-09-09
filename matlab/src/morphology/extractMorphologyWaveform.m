function result = extractMorphologyWaveform(videoPath, bandMode, opts, groundTruth)
% EXTRACTMORPHOLOGYWAVEFORM Run the Segment 7 Task A/B morphology
% pipeline end-to-end on one UBFC video: ROI -> wide bandpass -> CHROM ->
% polarity fix -> uniform resample -> ensemble-averaged beat.
%
% Pipeline stage: Segment 7 Task A, Action 5 (NEW, additive) — chains:
%   1. roi/extractROISignals.m       (forehead ROI, UNCHANGED, default
%                                      roiMode)
%   2. filtering/detrendSignal.m     (UNCHANGED, on R/G/B independently)
%   3. morphology/bandpassMorphology.m (NEW -- replaces
%                                      filtering/bandpassClean.m for THIS
%                                      pipeline only; bandpassClean.m
%                                      itself is never called here and is
%                                      never modified)
%   4. pulseextraction/chromCombine.m (UNCHANGED -- CHROM, not POS, is
%                                      used here; see
%                                      docs/Segment7_Task_A_Morphology_Pipeline.md
%                                      for why: posCombine.m is this
%                                      project's own non-canonical
%                                      whole-signal simplification of
%                                      POS, and using it here would
%                                      confound "did widening the band
%                                      help morphology" with "is our POS
%                                      formula itself correct" -- POS is
%                                      left for a second handoff)
%   5. Polarity fix (see groundTruth below for which rule) --
%      morphology/fixPolarity.m (heuristic) or
%      morphology/fixPolarityByGroundTruth.m (ground-truth-anchored).
%   6. morphology/resampleUniform.m  (NEW -- uniform high-rate grid using
%                                      REAL per-frame timestamps)
%   7. morphology/ensembleAverageBeats.m (NEW -- beat segmentation, time
%                                      warp, quality gate, coherent
%                                      average -- the core deliverable)
%
% Segment 7 Task B, Action 1 changes step 5's DEFAULT: this function
% still defaults to morphology/fixPolarity.m's skewness heuristic when
% no ground truth is supplied (unchanged from Task A -- see the
% backward-compatibility note below), but now accepts an optional
% groundTruth argument that, when supplied, switches step 5 to
% morphology/fixPolarityByGroundTruth.m instead. See
% morphology/fixPolarity.m's own header for WHY this switch matters: the
% skewness heuristic agreed with the ground-truth-anchored rule on only
% 3/5 UBFC subjects in Task A, with a systematic all-flip bias, not
% random scatter. scripts/run_segment7_morphology_batch.m (as of Task B)
% always passes groundTruth for every UBFC subject, since ground truth
% is available for all of them -- the heuristic-only path here remains
% available for contexts with no ground truth (Android, an early
% self-collected dataset).
%
% BACKWARD COMPATIBILITY (load-bearing for Segment 7 Task B, Action 6's
% regression check): calling this function with the original 2-arg or
% 3-arg signature (groundTruth omitted) takes EXACTLY the same code path
% as Task A's version of this file -- the heuristic fixPolarity.m branch
% below is untouched logic, just reached via an if/else instead of being
% the only option. A snapshot of this function's pre-Task-B, 2-arg
% output for subject 5-gt is compared byte-for-byte (isequal) against a
% fresh 2-arg call in tests/segment7_task_b_regression_test.m.
%
% This function does NOT modify or call into pipeline/estimateVitals.m
% (itself still an unimplemented stub as of Segment 7) and does not touch
% any file under the HR path (filtering/bandpassClean.m,
% heartrate/fftHeartRate.m, heartrate/windowedHeartRate.m,
% validation/runLOSO.m).
%
% Inputs:
%   videoPath   - string/char, full path to a subject's UBFC .avi file.
%   bandMode    - (optional) string/char, forwarded to
%                 morphology/bandpassMorphology.m: 'wide' (default),
%                 'mid', or 'legacy'.
%   opts        - (optional) struct, forwarded to
%                 morphology/ensembleAverageBeats.m.
%   groundTruth - (optional) struct with fields .ppg and .timestamp
%                 (io/loadGroundTruth.m's gt.ppg / gt.timestamp for the
%                 same subject). If supplied and non-empty, step 5 uses
%                 morphology/fixPolarityByGroundTruth.m instead of
%                 morphology/fixPolarity.m. Omit (or pass []) to keep
%                 Task A's original heuristic-only behaviour.
%
% Outputs:
%   result - struct with fields:
%              frameRate            - scalar, Hz, from io/loadUBFCVideo.m.
%              roiTimestamps        - vector, seconds,
%                                      extractROISignals.m's real
%                                      per-frame timestamps.
%              R, G, B              - raw ROI traces (extractROISignals.m
%                                      output, pre-detrend/pre-filter).
%              pulseChrom           - CHROM-combined pulse signal, at the
%                                      native frame rate, AFTER
%                                      morphology/bandpassMorphology.m
%                                      and BEFORE the polarity fix (kept
%                                      for the before/after polarity
%                                      figure, Action 6 FIG 3).
%              bandUsed             - 1x2 vector [lowHz, highHz], from
%                                      morphology/bandpassMorphology.m.
%              pulseOriented        - pulseChrom after the polarity fix
%                                      actually used (see polarityMethod).
%              polarityMethod       - 'groundTruth' or 'heuristic',
%                                      whichever step 5 actually used.
%              wasFlipped           - logical, whichever rule was
%                                      actually used (polarityMethod).
%              heuristicWasFlipped  - logical, morphology/fixPolarity.m's
%                                      own answer, ALWAYS computed
%                                      (cheap, no video re-decode)
%                                      regardless of polarityMethod, so
%                                      callers can compare the two rules
%                                      without a second pass.
%              skewValue            - scalar, morphology/fixPolarity.m's
%                                      skewness value (always computed).
%              gtAnchoredWasFlipped - logical, or [] if groundTruth was
%                                      not supplied --
%                                      morphology/fixPolarityByGroundTruth.m's
%                                      answer.
%              sigUniform           - pulseOriented resampled onto the
%                                      uniform grid,
%                                      morphology/resampleUniform.m's
%                                      output.
%              timeUniform          - the uniform time grid.
%              uniformFs            - scalar, Hz, the uniform grid's rate.
%              prototype            - morphology/ensembleAverageBeats.m's
%                                      prototype struct (trimmedMean,
%                                      median).
%              iqrBand              - morphology/ensembleAverageBeats.m's
%                                      iqrBand struct.
%              beatMatrix           - morphology/ensembleAverageBeats.m's
%                                      final aligned beat matrix.
%              beatStats            - morphology/ensembleAverageBeats.m's
%                                      stats struct.

if nargin < 2 || isempty(bandMode)
    bandMode = 'wide';
end

if nargin < 3
    opts = struct();
end

if nargin < 4
    groundTruth = [];
end

[frames, frameRate, ~] = loadUBFCVideo(videoPath);
[R, G, B, roiTimestamps, ~, ~] = extractROISignals(frames, frameRate);

[R_detrended, ~] = detrendSignal(R);
[G_detrended, ~] = detrendSignal(G);
[B_detrended, ~] = detrendSignal(B);

[R_filtered, filterOrder, bandUsed] = bandpassMorphology(R_detrended, frameRate, bandMode); %#ok<ASGLU>
[G_filtered, ~, ~] = bandpassMorphology(G_detrended, frameRate, bandMode);
[B_filtered, ~, ~] = bandpassMorphology(B_detrended, frameRate, bandMode);

pulseChrom = chromCombine(R_filtered, G_filtered, B_filtered, R, G, B);

[pulseHeuristic, heuristicWasFlipped, skewValue] = fixPolarity(pulseChrom, frameRate);

useGroundTruth = ~isempty(groundTruth);

if useGroundTruth
    [pulseOriented, gtAnchoredWasFlipped] = fixPolarityByGroundTruth(pulseChrom, roiTimestamps, groundTruth.ppg, groundTruth.timestamp);
    polarityMethod = 'groundTruth';
    wasFlipped = gtAnchoredWasFlipped;
else
    pulseOriented = pulseHeuristic;
    gtAnchoredWasFlipped = [];
    polarityMethod = 'heuristic';
    wasFlipped = heuristicWasFlipped;
end

[sigUniform, timeUniform, uniformFs] = resampleUniform(pulseOriented, roiTimestamps);

[prototype, iqrBand, beatMatrix, beatStats] = ensembleAverageBeats(sigUniform, uniformFs, opts);

result = struct();
result.frameRate = frameRate;
result.roiTimestamps = roiTimestamps;
result.R = R;
result.G = G;
result.B = B;
result.pulseChrom = pulseChrom;
result.bandUsed = bandUsed;
result.pulseOriented = pulseOriented;
result.polarityMethod = polarityMethod;
result.wasFlipped = wasFlipped;
result.heuristicWasFlipped = heuristicWasFlipped;
result.skewValue = skewValue;
result.gtAnchoredWasFlipped = gtAnchoredWasFlipped;
result.sigUniform = sigUniform;
result.timeUniform = timeUniform;
result.uniformFs = uniformFs;
result.prototype = prototype;
result.iqrBand = iqrBand;
result.beatMatrix = beatMatrix;
result.beatStats = beatStats;

end
