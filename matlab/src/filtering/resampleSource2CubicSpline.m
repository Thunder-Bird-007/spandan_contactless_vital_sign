function [sigResampled, timeUniform] = resampleSource2CubicSpline(sig, sourceTimestampsSec, targetFs, targetNumSamples)
% RESAMPLESOURCE2CUBICSPLINE Segment 8 Action 3 -- cubic-spline resample
% of a per-frame trace onto a uniform grid at a corrected frame rate.
%
% Pipeline stage: Segment 8 (post-review follow-up), Action 3. Per Chen,
% Lin & Jeong ("Low-Complexity Timing Correction Methods for Heart Rate
% Estimation Using Remote Photoplethysmography," Sensors 2025, 25(2):588),
% a single corrected constant frame rate (what
% scripts/task_source2_fpsfix_reprocess.m already tried) only fixes the
% AVERAGE rate, not irregular per-frame timing within a clip -- their
% fix: cubic-spline-resample the raw trace from its REAL per-frame
% capture timestamps onto a uniform grid at the corrected rate.
%
% CRITICAL DATA-AVAILABILITY CAVEAT (read before calling this for VIPL-HR
% source2 specifically -- see docs/Segment8_Task3_Source2_Timing_Fix.md
% for the full reasoning and the empirical numbers that motivated it):
% this function's cubic-spline correction is only SOUND when
% sourceTimestampsSec are REAL measured per-frame capture instants (e.g.
% VIPL-HR source1/source3/source4, which ship a real time.txt). VIPL-HR
% source2 has NO time.txt -- there is no real per-frame timestamp source
% for it, only an average-rate estimate (borrowed from a sibling source's
% session duration, io/loadVIPLVideo.m's own documented limitation).
% Calling this function for source2 with FICTIONAL assumed-uniform
% timestamps (e.g. (0:N-1)/25, the wrong container rate) as
% sourceTimestampsSec does NOT recover any real timing information --
% the spline would interpolate through timestamps that were never real
% capture instants in the first place, fabricating false sub-frame
% precision rather than correcting genuine jitter. For that case, the
% mathematically sound operation is a pure relabel (same sample values,
% new uniform time axis at the corrected average rate) -- which is
% EXACTLY what scripts/task_source2_fpsfix_reprocess.m already computed.
% This function's 'relabelOnly' mode (targetNumSamples == numel(sig))
% exists specifically to make that equivalence explicit and callable
% rather than reimplemented ad hoc: it does NOT invoke interp1 at all
% when sourceTimestampsSec is not provided (empty), it just re-timestamps
% the existing samples onto the uniform target grid.
%
% Inputs:
%   sig                  - 1 x N vector, raw per-frame trace.
%   sourceTimestampsSec  - 1 x N vector, REAL per-sample capture times in
%                          seconds (e.g. a source1/3/4 time.txt, /1000),
%                          or [] if only an average-rate estimate exists
%                          (source2's case -- see caveat above). When [],
%                          this function performs a pure relabel (no
%                          interpolation, no fabricated precision) rather
%                          than silently pretending it has real timing
%                          data to spline through.
%   targetFs             - scalar, Hz, the corrected/target uniform rate.
%   targetNumSamples     - (optional) scalar, number of samples in the
%                          output grid. Defaults to numel(sig) (i.e. same
%                          frame count, just corrected spacing).
%
% Outputs:
%   sigResampled - 1 x targetNumSamples vector.
%   timeUniform  - 1 x targetNumSamples vector, seconds, the uniform grid
%                  actually used: (0:targetNumSamples-1)/targetFs.

sigRow = sig(:)';
N = numel(sigRow);

if nargin < 4 || isempty(targetNumSamples)
    targetNumSamples = N;
end

timeUniform = (0:targetNumSamples - 1) / targetFs;

if isempty(sourceTimestampsSec)
    % No real per-frame timestamps available (VIPL-HR source2's
    % documented limitation -- see this function's header). Pure
    % relabel: same values, new uniform time axis. Requires
    % targetNumSamples == N (relabeling changes labels, not the number
    % of physical frames captured).
    if targetNumSamples ~= N
        error('resampleSource2CubicSpline:relabelSizeMismatch', ...
            ['No real sourceTimestampsSec given (relabel-only mode), so targetNumSamples must equal ' ...
             'numel(sig) (%d) -- cannot fabricate additional samples without real timing data to interpolate from.'], N);
    end
    sigResampled = sigRow;
    return
end

sourceTimestampsRow = sourceTimestampsSec(:)';
if numel(sourceTimestampsRow) ~= N
    error('resampleSource2CubicSpline:sizeMismatch', 'sig and sourceTimestampsSec must have the same number of elements.');
end

% Real per-frame timestamps available: genuine cubic-spline resample
% (Chen/Lin/Jeong's own method comparison: cubic spline is most robust
% but costs more compute than linear -- implemented here since this is
% offline MATLAB analysis, not the real-time Android path).
sigResampled = interp1(sourceTimestampsRow, sigRow, timeUniform, 'spline');

end
