# Segment 6 Task O: Detrend-Order Sweep and Adaptive Narrow-Band Refinement

Both actions in this task are additive per the constraint: `filtering/detrendSignal.m`'s
new `polyOrder` argument defaults to the exact pre-existing hardcoded value, and
`filtering/bandpassClean.m` is untouched — the two-stage refinement lives in a brand
new file, `filtering/adaptiveNarrowRefine.m`. Both batch runs reused the already-
extracted `data/processed/VIPL_p*_v1_source*_rgb_traces.mat` cached R/G/B traces and
`results/metrics/segment4_hr_summary_vipl.csv`'s `HR_groundtruth` column for the
existing 107-subject VIPL-HR v1 pool — no video was re-decoded and no ROI re-extraction
ran for this task.

## Action 1 — Detrend-order sweep

### Code change

`filtering/detrendSignal.m` gained an optional second argument, `polyOrder`, defaulting
to 3 — confirmed by inspection to be the exact value that was previously hardcoded
inside the function (`detrendOrder = 3;`, unconditionally). No other file was touched.

### Regression check

`scripts/run_segment6_task_o_detrend_sweep.m` Part 1 ran, on the first 3 subjects of
the pool (`VIPL_p1_v1_source1`, `VIPL_p2_v1_source1`, `VIPL_p3_v1_source1`), three
comparisons per subject:

1. `detrendSignal(R)` (new default) vs. `detrendSignal(R, 3)` (new explicit order)
2. `detrendSignal(R)` (new default) vs. `detrend(R, 3)` (MATLAB's own built-in, i.e.
   exactly what the old hardcoded line computed)
3. the `detrendOrder` return value itself, confirmed `== 3` in both cases

All three subjects passed all three checks via `isequal` (bit-for-bit, not
tolerance-based):

| Subject | default vs explicit-order-3 | default vs `detrend(R,3)` built-in | `detrendOrder` returned |
|---|---|---|---|
| VIPL_p1_v1_source1 | byte-identical | byte-identical | 3 |
| VIPL_p2_v1_source1 | byte-identical | byte-identical | 3 |
| VIPL_p3_v1_source1 | byte-identical | byte-identical | 3 |

**Result: default call reproduces byte-identical output. Confirmed, not assumed** — the
script hard-stops (`error(...)`) before running the sweep if any of these checks fail,
so a clean run of the sweep below is itself further evidence the regression check
passed (it did — see the log line `Regression check across 3 subjects: all
byte-identical = 1`).

### 4-order comparison (polyOrder = 2, 3, 4, 5)

Ran on all 107 subjects, 0 failures at every order. `bandpassClean.m`,
`chromCombine.m`, `posCombine.m`, and `fftHeartRate.m` were called completely
unmodified downstream of the swept `detrendSignal.m` call.

| polyOrder | Method | MAE | RMSE | Pearson r | N |
|---|---|---|---|---|---|
| 2 | CHROM | 9.3458 | 18.3724 | 0.27755 | 107 |
| 2 | POS | 8.9089 | 16.7811 | 0.21745 | 107 |
| 2 | Green | 15.0965 | 19.5177 | 0.03443 | 107 |
| **3 (current default)** | **CHROM** | **9.3458** | **18.3724** | **0.27755** | **107** |
| **3 (current default)** | **POS** | **8.9089** | **16.7811** | **0.21745** | **107** |
| **3 (current default)** | **Green** | **15.0965** | **19.5177** | **0.03443** | **107** |
| 4 | CHROM | 9.3458 | 18.3724 | 0.27755 | 107 |
| 4 | POS | 8.9089 | 16.7811 | 0.21745 | 107 |
| 4 | Green | 15.0965 | 19.5177 | 0.03443 | 107 |
| 5 | CHROM | 9.1321 | 18.2122 | 0.27751 | 107 |
| 5 | POS | 8.9089 | 16.7811 | 0.21745 | 107 |
| 5 | Green | 15.0965 | 19.5177 | 0.03443 | 107 |

### Honest reading

Orders 2, 3, and 4 produce **identical** MAE/RMSE/r for all three methods — not just
close, exactly equal to the displayed precision (and, checking the underlying
`segment6_task_o_detrend_sweep_details.csv`, the per-subject HR values themselves are
identical across orders 2-4 too, not just the pooled metrics). Only order 5 differs
from the rest, and only for CHROM (MAE 9.3458 -> 9.1321, RMSE 18.3724 -> 18.2122, a
small but real improvement; r is essentially flat at 0.2775 -> 0.2775). POS and Green
are completely unaffected by polyOrder across the whole 2-5 range tested.

**Why detrend order barely matters here**: `bandpassClean.m` runs immediately after
`detrendSignal.m` with a 0.7-4 Hz passband. A polynomial detrend of order 2-5 only
removes slow, low-order drift (well below 0.7 Hz); the subsequent bandpass filter
already removes essentially everything below 0.7 Hz regardless of exactly how the
detrend polynomial fit that sub-0.7-Hz drift. The detrend step and the bandpass step
overlap in what they remove, which is why changing the detrend order this modestly
produces no visible effect until CHROM's normalization (which uses the raw, pre-filter
channel means from `RRaw/GRaw/BRaw`) picks up a small amount of residual sensitivity at
order 5.

**Plain answer to "is order 3 the best of the four tested"**: no, order 3 is *tied* for
best with orders 2 and 4 (all three are numerically identical here) and is very
slightly worse than order 5 on CHROM specifically (a 0.21 bpm MAE improvement, 1.2 bpm
RMSE improvement, out of an ~9-10 bpm baseline error — a real but small edge, not
enough on its own to justify moving the whole project's default off order 3, especially
since it doesn't move POS or Green at all). Order 3 was never demonstrably wrong; it
just wasn't uniquely optimal either, and this sweep is the first time that was actually
checked rather than assumed.

## Action 2 — Two-stage adaptive bandpass (`adaptiveNarrowRefine.m`)

### Design

`filtering/adaptiveNarrowRefine.m` is a new function, not a modification to
`bandpassClean.m`. It takes the ALREADY-detrended signal (the same input
`bandpassClean.m` itself receives), a frame rate, and a rough HR estimate (bpm), and:

1. builds a narrow Butterworth bandpass centered on the rough estimate, +/- 15 bpm
   (converted to Hz, so +/- 0.25 Hz), clamped to stay inside `fftHeartRate.m`'s own
   0.7-4 Hz search band (otherwise a rough estimate near the edge of the physiological
   range could produce a narrow band with no overlap with 0.7-4 Hz, which would make
   `fftHeartRate.m` raise `fftHeartRate:emptyBand` on an otherwise-valid signal);
2. applies it with the same `filtfilt` zero-phase approach as `bandpassClean.m`;
3. re-runs `fftHeartRate.m` on the result for the refined estimate.

`scripts/run_segment6_task_o_adaptive_refine.m` ran this once per method per subject —
green refined against its own Pass-1 green estimate, CHROM refined against its own
Pass-1 CHROM estimate, POS refined against its own Pass-1 POS estimate — rather than
refining all three against one shared "best" method's rough estimate, since Task K
already found the single best HR method is scope-dependent (POS wins with v7 in the
pool, CHROM/POS switching wins on v1-only).

### Original vs. refined (107/107 subjects, 0 failures)

| Method | Stage | MAE | RMSE | Pearson r | N |
|---|---|---|---|---|---|
| Green | original | 15.0965 | 19.5177 | 0.03443 | 107 |
| Green | refined | 15.6875 | 20.1210 | 0.02936 | 107 |
| CHROM | original | 9.3458 | 18.3724 | 0.27755 | 107 |
| CHROM | refined | 9.3968 | 18.4324 | 0.27397 | 107 |
| POS | original | 8.9089 | 16.7811 | 0.21745 | 107 |
| POS | refined | 9.0121 | 16.8246 | 0.22386 | 107 |

### Honest reading

The narrow refinement stage does **not** help on this pool — every method is flat or
slightly worse after Pass 2: Green's MAE gets 0.59 bpm worse, CHROM's 0.05 bpm worse,
POS's 0.10 bpm worse (Pearson r moves by less than 0.01 in either direction for all
three, i.e. noise-level). This makes sense mechanically:
`results/metrics/segment6_task_o_adaptive_refine_details.csv` shows the refined
estimate equals the original estimate exactly for the large majority of subjects (Pass
2's narrow band, centered on the Pass-1 peak, usually just reselects the same FFT bin
it started from — there's nothing left to "refine" once the wide 0.7-4 Hz band has
already isolated a single dominant peak). Where Pass 2 *does* move the estimate (e.g.
VIPL_p8, VIPL_p82, VIPL_p91, VIPL_p97, VIPL_p104, VIPL_p105 for Green; VIPL_p87,
VIPL_p105 for POS/CHROM), it moves toward a *secondary* peak that happened to fall
inside the narrow +/-15 bpm window — sometimes closer to ground truth (e.g. p105 CHROM
82.83 -> 88.29 bpm against a GT of 63.95 bpm is actually further away), sometimes
further, with no consistent direction. Net effect across the pool: a wash that trends
slightly negative. **Bottom line for the writeup: the two-stage adaptive bandpass, as
specified (+/-15 bpm re-filter of the already-detrended signal, re-run through the same
FFT peak-picker), is not a win on the current 107-subject VIPL v1 pool** — it neither
meaningfully corrects nor meaningfully degrades most estimates, and the small number of
subjects it does move are a coin flip on direction. It remains available as an
optional, non-default stage (per the additive constraint) rather than being wired into
any batch script's default path.

## Outputs

- `src/filtering/detrendSignal.m` (modified, additive: new optional `polyOrder` arg,
  default unchanged)
- `src/filtering/bandpassClean.m` (untouched)
- `src/filtering/adaptiveNarrowRefine.m` (new)
- `scripts/run_segment6_task_o_detrend_sweep.m` (new)
- `scripts/run_segment6_task_o_adaptive_refine.m` (new)
- `results/metrics/segment6_task_o_detrend_sweep_metrics.csv` (new, 12 rows: 4 orders x
  3 methods)
- `results/metrics/segment6_task_o_detrend_sweep_details.csv` (new, 428 rows: 4 orders
  x 107 subjects)
- `results/metrics/segment6_task_o_adaptive_refine_metrics.csv` (new, 6 rows: 3 methods
  x original/refined)
- `results/metrics/segment6_task_o_adaptive_refine_details.csv` (new, 107 rows)
- `matlab/task_o_run.log` (full run log, both actions, regression check output
  included)
