function vitals = estimateVitals(videoPath, calibParams)
% ESTIMATEVITALS Run the full Spandan pipeline end-to-end on one video.
%
% Pipeline stage: top-level orchestrator — chains together every stage:
%   1. io/loadUBFCVideo.m           - load video
%   2. roi/extractROISignals.m      - face detect + ROI -> R(t),G(t),B(t)
%   3. filtering/detrendSignal.m,
%      filtering/bandpassClean.m    - detrend + bandpass each channel
%   4. pulseextraction/chromCombine.m or posCombine.m
%                                    - combine channels -> pulse signal
%   5. heartrate/fftHeartRate.m     - FFT -> HR (bpm)
%   6. spo2/ratioOfRatios.m,
%      spo2/calibrateSpO2.m         - AC/DC ratio-of-ratios -> SpO2 (%)
% This is the function validation/runLOSO.m calls per held-out subject.
%
% Inputs:
%   videoPath   - string/char, full path to the subject's video file.
%   calibParams - struct, SpO2 calibration coefficients from
%                 spo2/calibrateSpO2.m (fit on other subjects, never on
%                 this one — see validation/runLOSO.m).
%
% Outputs:
%   vitals - struct with fields: hrBpm, spo2Pct, plus any intermediate
%            signals useful for debugging/plotting (pulseSignal, etc.).

error('Not implemented yet — see docs/');

end
