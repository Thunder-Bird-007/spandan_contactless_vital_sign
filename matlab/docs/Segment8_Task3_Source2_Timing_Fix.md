# Segment 8 (Action 3) — Real Timing-Correction Fix for VIPL-HR source2

Continues the Segment 8 source2 FPS investigation
(`results/metrics/segment8_source2_fps_investigation.csv`,
`task_source2_fps_investigation.m`) and its already-tried naive fix
(`scripts/task_source2_fpsfix_reprocess.m`,
`results/metrics/segment4_hr_summary_vipl_source2_fpsfix.csv`: pooled CHROM MAE across
the 12 subjects improves 19.4→13.8bpm, but 5 of 12 subjects get *worse* — p84 5.0→27.6,
p104 15.0→30.8, p107 2.1→18.9, and one more below the originally-flagged three). Per
Chen, Lin & Jeong ("Low-Complexity Timing Correction Methods for Heart Rate Estimation
Using Remote Photoplethysmography," *Sensors* 2025, 25(2):588), a single corrected
constant frame rate only fixes the AVERAGE rate, not irregular per-frame timing within a
clip — their fix is to cubic-spline-resample the raw trace from its REAL per-frame
capture timestamps onto a uniform grid at the corrected rate.

## Critical data-availability finding (established before writing any comparison code)

VIPL-HR source2 (the phone camera) has **no `time.txt`** — confirmed in
`docs/VIPL_DATA_FORMAT.md` Section 3 and `io/loadVIPLVideo.m`'s own header, and
re-confirmed directly against the raw folders for all 12 subjects here. Chen/Lin/Jeong's
cubic-spline method needs REAL per-frame capture timestamps as the interpolation source —
without them, there is nothing to spline *from* except an assumed, fictional grid. Two
things are technically possible when only an average-rate estimate exists (borrowed from a
sibling source's session duration, as `task_source2_fps_investigation.m` already does):

1. **Relabel-only** (what `task_source2_fpsfix_reprocess.m` already did): keep the raw
   per-frame values unchanged, just re-timestamp them uniformly at the corrected average
   rate. No interpolation, no fabricated precision.
2. **"Naive spline"**: treat the WRONG, fictional container-rate timestamps
   ((0:N-1)/25) as if they were real, spline-interpolate through them, and evaluate at the
   corrected-rate grid. This does NOT recover any real timing information — it fabricates
   sub-frame precision from labels that were never real capture instants.

New file `filtering/resampleSource2CubicSpline.m` implements both modes explicitly (mode
selected by whether real timestamps are passed), and is written generally enough to do
the SOUND version of Chen/Lin/Jeong's method on sources that DO have real per-frame
timestamps (VIPL source1/3/4) — not attempted in this task, out of scope, but the
function doesn't hardcode source2's limitation into its API.

**This task tests the "naive spline" condition empirically** (not just argued
algebraically) specifically to check whether fabricating precision from fictional labels
accidentally helps anyway, or is actively counterproductive — per this project's standing
rule to confirm rather than assume.

## Three-way comparison, all 12 subjects (`scripts/run_segment8_task3_source2_timing_fix.m`,
`results/metrics/segment8_task3_source2_timing_comparison.csv`)

| Subject | GT (bpm) | err naive-25fps | err relabel | err naive-spline | relabel==spline HR? |
|---|---|---|---|---|---|
| p84  | 80.71 | 5.00  | 27.65 | **4.72**  | false |
| p97  | 97.29 | 18.91 | **2.68**  | 18.88 | false |
| p98  | 73.06 | 24.22 | **10.44** | 72.39 | false |
| p99  | 72.41 | 17.20 | **1.44**  | 17.21 | false |
| p100 | 91.89 | **6.78**  | 20.08 | 12.96 | false |
| p101 | 79.12 | 17.85 | 4.54  | 4.54  | **true** |
| p102 | 72.60 | 12.20 | **7.34**  | 8.48  | false |
| p103 | 65.00 | 20.56 | 16.01 | **0.53**  | false |
| p104 | 88.82 | **14.95** | 30.84 | 19.25 | false |
| p105 | 63.95 | 18.88 | **12.82** | 32.63 | false |
| p106 | 76.09 | 74.23 | 13.20 | **10.17** | false |
| p107 | 82.94 | **2.13**  | 18.90 | 23.06 | false |

**Pooled MAE across all 12**: naive-25fps = **19.41 bpm**, relabel = **13.83 bpm**,
naive-spline = **18.74 bpm**.

`relabel_vs_naivespline_identical` is `false` for 11/12 subjects (only p101 matches) —
this confirms directly (not just by algebra) that spline-interpolating through fictional
labels genuinely changes the signal values, it is not a no-op equivalent to relabeling.
`maxAbsDiff` between relabel-only and the raw unmodified trace is `0.0000000000` for
every subject (sanity check: relabel-only mode really does leave sample values untouched,
as designed).

### Verdict on the cubic-spline method for source2

**Naive spline does NOT beat the already-tried relabel fix — pooled, it's about as bad as
doing nothing (18.74bpm vs. the uncorrected baseline's 19.41bpm, both far worse than
relabel's 13.83bpm).** It helps a few individual subjects by chance (p84 dramatically:
27.65→4.72; p103: 16.01→0.53) but hurts others badly (p98: 10.44→72.39; p105:
12.82→32.63), with no reliable pattern. **This confirms the theoretical expectation from
the data-availability finding above**: without real per-frame timestamps, "cubic-spline
timing correction" for source2 has no genuine jitter to correct, and forcing it through
fictional labels is actively counterproductive on average, not a free improvement.
**The already-adopted relabel-only fix remains the best of the three methods tried for
source2 specifically** — this task does not supersede it, and does not recommend
replacing `task_source2_fpsfix_reprocess.m`'s output with a spline-based one. The real,
sound version of Chen/Lin/Jeong's method would require source2 to have real per-frame
timestamps, which it structurally does not; a genuine cubic-spline win would need testing
on VIPL source1/3/4 (which DO have `time.txt`) — a different, out-of-scope task.

## Investigating why p84, p100, p104, p107 specifically get worse under relabel

Checked both of the handoff's suggested culprits directly against real files for all 12
subjects, not just the 4 flagged ones:

| Subject | Worse under relabel? | source3 gap: mean/sd/max (ms) | sibling (source3) duration (s) | source2's OWN gt_HR.csv row count (s) | duration mismatch (s) |
|---|---|---|---|---|---|
| p84  | **YES** | 47.28 / 6.33 / 158 | 28.794 | 31 | 2.21 |
| p97  | no | 47.09 / 6.67 / 166 | 30.607 | 34 | 3.39 |
| p98  | no | 46.63 / 5.92 / 140 | 29.701 | 33 | 3.30 |
| p99  | no | 47.18 / 4.58 / 127 | 30.434 | 34 | 3.57 |
| p100 | **YES** | 46.90 / 6.90 / 157 | 32.687 | 37 | 4.31 |
| p101 | no | 47.04 / 7.14 / 189 | 30.574 | 34 | 3.43 |
| p102 | no | 47.34 / 6.15 / 145 | 30.342 | 35 | 4.66 |
| p103 | no | 47.07 / 2.06 / 65  | 36.294 | 30 | -6.29 |
| p104 | **YES** | 46.90 / 1.20 / 62  | 31.045 | 34 | 2.96 |
| p105 | no | 47.29 / 6.02 / 169 | 31.686 | 56 | **24.31** |
| p106 | no | 47.03 / 3.80 / 140 | 33.389 | 33 | -0.39 |
| p107 | **YES** | 45.90 / 3.72 / 64  | 27.171 | 31 | 3.83 |

`source2's OWN gt_HR.csv row count` is an independent real-elapsed-seconds proxy (one
row/second, recorded on source2's own separate timeline per
`docs/VIPL_DATA_FORMAT.md` Section 5c) used here only as a cross-check on whether
source3's borrowed duration is a good stand-in for source2's real session length — never
used to choose or tune `trueFps` itself (that would be circular, same discipline as
`task_source2_fps_investigation.m`).

**Neither culprit cleanly separates the "worse" group from the rest, reported plainly
rather than forced into a tidy story**:

- **Source3's own frame-timing jitter** does not predict the outcome: p104 (one of the
  "worse" subjects) has the CLEANEST source3 timing of all 12 (sd=1.20ms, max gap 62ms —
  essentially no evidence of dropped frames in source3 itself), while p101 (which
  *improved* under relabel) has the JITTERIEST source3 timing of all 12 (sd=7.14ms, max
  gap 189ms). If source3 jitter contaminating the borrowed duration were the driver, this
  pattern would run the other way.
- **Duration mismatch vs. source2's own gt_HR.csv** also doesn't separate the groups: the
  4 "worse" subjects have mismatches of 2.2-4.3s, which overlaps entirely with the
  "improved" group's 3.3-4.7s range (p105's 24.3s outlier — by far the largest mismatch of
  any subject — is in the *improved* group, not the worse one).
- **The naive-spline experiment above adds a third, independent line of evidence against
  a single clean explanation**: switching to an entirely different resampling method
  changes which of the 4 "worse" subjects improve (p84, and partially p100/p104) versus
  stays bad (p107 gets even worse: 18.90→23.06) — a pattern that doesn't track either
  culprit checked above either.

**Best-supported explanation, stated as inference (not proven, since no independent
per-frame ground truth exists for source2 to check directly)**: the residual per-subject
error is most likely driven by genuine per-frame capture jitter **internal to source2's
own recording** (a phone camera, plausibly subject to auto-exposure/autofocus-driven
variable frame timing independent of the other three devices) — not by errors in the
borrowed sibling-duration estimate. Every method tried here (relabel, naive-spline) can
only correct the AVERAGE rate; none has access to source2's real per-frame timing, so
none can be expected to fix a source2-specific subject whose actual capture jitter happens
to be large. This is a genuine, currently unresolvable data limitation for VIPL-HR
source2 specifically — not a defect in any one correction method's implementation.

## Bottom line

- **Adopt**: keep `task_source2_fpsfix_reprocess.m`'s relabel-only fix as the best
  available correction for source2 (pooled MAE 13.8bpm, still the best of the three
  methods tried here).
- **Do not adopt**: cubic-spline resampling for source2 specifically — confirmed
  empirically to perform about as poorly as no correction at all, pooled.
- **Not resolved**: why exactly p84/p100/p104/p107 regress under relabel. Both suggested
  culprits were checked directly and neither explains the pattern; the residual is most
  likely source2's own uncorrectable per-frame jitter, but this is inference from
  elimination, not a proven root cause. A genuine fix would require real per-frame
  timestamps for source2, which do not exist in this dataset.
- **Reusable output for future work**: `filtering/resampleSource2CubicSpline.m` is a
  real, general cubic-spline resampler (not source2-specific) — ready to apply to
  VIPL-HR source1/3/4 (which DO have real `time.txt`) if that's ever investigated, a
  natural, cheap follow-up this task did not attempt.
