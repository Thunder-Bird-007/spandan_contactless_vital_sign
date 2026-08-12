# Segment 6 Task P — Windowed Harmonic Disambiguation + Signal-Quality Gating

Harmonic disambiguation and signal-quality gating share a prerequisite: the
pipeline as it stood before this task computed exactly one whole-clip FFT
per subject (`heartrate/fftHeartRate.m`). Both techniques need the clip
split into shorter windows first, so this task builds that shared
prerequisite once (`heartrate/windowedHeartRate.m`, Action 1) and layers
both mechanisms on top of it as separate, composable functions.

**Known motivating failure case** (not re-diagnosed here, already confirmed
in Task H1/I and recurring in Task N Section 5b): `VIPL_p21`, `v1`,
forehead region — whole-clip CHROM estimated **127.20 bpm** against a true
**68 bpm**, a **1.87x** harmonic-confusion error. Every mechanism below is
checked against this concrete case before being run at pool scale.

`heartrate/fftHeartRate.m` and `filtering/bandpassClean.m` are **unmodified**
by this task. `heartrate/windowedHeartRate.m` is a new, separate entry point
that receives the same filtered pulse signal `fftHeartRate.m` already
receives; the whole-clip function remains callable and unchanged for
anything still depending on it.

## Action 1 — `heartrate/windowedHeartRate.m`

Splits the filtered pulse signal into **10-second windows at 50% overlap
(5-second hop)**, stated explicitly rather than left implicit. 10 seconds
resolves the 0.7–4 Hz cardiac band comfortably at VIPL-HR's ~15–30 fps
(150–300 samples/window) while staying short enough that one bad window
doesn't spoil the whole clip; 50% overlap means every interior second is
covered by two windows, which Action 3's window-to-window continuity check
needs.

For each window, using the exact same FFT/band logic as `fftHeartRate.m`
(0.7–4 Hz band, magnitude spectrum, no changes to that math):

- **(a) top-3 candidate peaks** — local maxima in the in-band magnitude
  spectrum, sorted by magnitude descending, top 3 kept (NaN-padded if fewer
  than 3 local maxima exist).
- **(b) window-quality score** = top peak's magnitude ÷ sum of all in-band
  spectral energy. A clean pulse concentrates energy in one dominant peak
  (score near 1); a noisy window spreads energy across many frequencies
  (score near 0). No threshold is applied inside this function — see Action
  2.

`windowedHeartRate.m` also returns a **naive windowed baseline** (mean of
each window's own tallest peak, no gating, no continuity) purely so later
comparisons have a clean three-way split: whole-clip → naive windowed →
gated/continuity-corrected.

## Action 3 tested first, isolated — `validation/selectHarmonicConsistentHR.m`

Per instructions, harmonic continuity was verified on the known p21 case
**before** touching quality gating or the full pool
(`scripts/run_task_p_p21_isolated_check.m`).

Rule: window 1 keeps the tallest peak (no prior window to constrain
against). Every window after that must choose, from its **own** top-3 (not
borrowed from any other window), whichever candidate is numerically closest
to the *previous window's chosen bpm* — not automatically the tallest peak.

**p21 isolated result (no gating applied):**

| Window | Start (s) | Top-3 candidates (bpm) | Tallest peak | Chosen (continuity) | Override fired |
|---|---|---|---|---|---|
| 1 | 0.0 | 66.15, 132.30, 114.26 | 66.15 | 66.15 | no |
| 2 | 5.0 | 126.29, 66.15, 84.19 | 126.29 | 66.15 | **YES** |
| 3 | 10.0 | 126.29, 150.35, 48.11 | 126.29 | 48.11 | **YES** |
| 4 | 15.1 | 126.29, 72.17, 150.35 | 126.29 | 72.17 | **YES** |
| 5 | 20.1 | 102.24, 150.35, 126.29 | 102.24 | 102.24 | no |
| 6 | 25.1 | 96.22, 72.17, 126.29 | 96.22 | 96.22 | no |
| 7 | 30.1 | 72.17, 120.28, 132.30 | 72.17 | 72.17 | no |

| Method | HR (bpm) | abs. error vs GT (68 bpm) |
|---|---|---|
| Whole-clip single FFT (baseline) | 127.20 | 59.20 |
| Naive windowed (no continuity) | 102.24 | 34.24 |
| **Windowed + harmonic continuity** | **74.74** | **6.74** |

**Verdict: harmonic continuity corrects the known p21 harmonic error.**
127.2 → 74.7 bpm against a true 68 bpm — the 1.87x harmonic-confusion error
is gone, and the result also beats the naive (no-continuity) windowed
baseline, so this is attributable to continuity specifically, not just to
windowing. Continuity overrode the tallest peak on 3 of 7 windows (window 1
can never fire, by definition).

## Action 2 — Quality gating

`validation/computeWindowQualityThreshold.m` derives the cutoff from the
**pooled** distribution of quality scores across every window of every
subject in the batch — a single clip's handful of windows is too few points
to find a reliable knee in, so this mirrors Task I's own reasoning
(`run_segment6_task_i_agreement.m`'s 29.27% threshold) applied to a pooled
population, not a single clip. Same largest-gap-vs-second-largest-gap
discipline: take the largest gap in the sorted pooled scores as the natural
knee, unless it isolates only a lone outlier at one end, in which case fall
back to the second-largest gap.

`validation/aggregateGatedWindowHR.m` **excludes** (does not downweight)
windows below the threshold, then averages the survivors. Exclusion, not
downweighting, was chosen because a low-quality window's HR reading is
treated as close to arbitrary noise, not a fainter-but-still-partially-valid
reading of the true rate — downweighting still lets that near-arbitrary
value pull a weighted average away from the true rate every time it
disagrees with the clean windows, while hard exclusion keeps the estimate
built only from windows whose own spectrum found an actual dominant pulse
frequency. If every window in a clip falls below threshold, the function
falls back to averaging all windows (never returns NaN) and flags this so
it's visible per-subject.

## Action 4 — Full 107-subject v1 VIPL pool

Ran gating + continuity together on the same 107-subject pool used in every
prior HR comparison (`results/metrics/segment4_hr_summary_vipl.csv`),
loading already-cached `_rgb_traces.mat` / `_filtered_traces.mat` — no video
was reprocessed. All 107 subjects were usable (0 failures).

**Pooled quality threshold, derived once from all 547 windows across all
107 subjects:** min = 0.0531, median = 0.0973, max = 0.2289. The single
largest gap (0.0112, sitting just above 0.2177) isolated only the very top
of the distribution — a lone-outlier split, same failure mode Task I
guarded against — so the **second-largest gap** was used instead, landing
the threshold at **0.2119**.

**Comparison table (N=107, MAE/RMSE in bpm):**

| Method | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| Whole-clip single FFT (current baseline) | 107 | 9.346 | 18.372 | 0.278 |
| Naive windowed (no gating, no continuity) | 107 | 10.338 | 15.643 | 0.316 |
| Gating only | 107 | 10.383 | 15.663 | 0.317 |
| **Gating + harmonic continuity** | 107 | 12.466 | 21.575 | 0.237 |

**Isolating which mechanism does the work (both required by Action 4):**

- **Harmonic continuity fired and changed a subject's final HR for 60 of
  107 subjects** (`gatingPlusContinuity` vs `gatingOnly`, same gating,
  same windows, both sides — so this count is attributable to continuity
  alone).
- **Quality gating alone changed a subject's final HR for only 2 of 107
  subjects** (`naiveWindowed` vs `gatingOnly`, no continuity either side).

**Why gating barely moved anything, read directly off the data:** the
pooled quality-score distribution (min 0.053, median 0.097, max 0.229) is
dense and continuous through its middle, with the only real "gap" sitting
right at the extreme top. The gap-based threshold (0.2119) therefore ended
up so close to the maximum observed score that **103 of 107 subjects had
every one of their windows fall below it**, tripping the
all-windows-excluded fallback (average of all windows — identical to the
naive windowed baseline for that subject). This is reported as-is, not
patched: hardcoding a lower threshold to make gating "do more" would
violate the same no-hardcoded-threshold discipline used everywhere else in
this project. The honest reading is that this particular quality metric's
distribution, at this pool's scale, does not contain a knee usable for
meaningful exclusion — a different quality signal, or a per-subject rather
than pooled threshold, would be needed to make Action 2 bite.

**Why continuity helps p21 specifically but hurts the pool on net:**
continuity fixed the one motivating case it was built for (p21:
127.2 → 74.7 bpm, error cut from 59.2 to 6.7 bpm) but, at full-pool scale,
raised MAE from 10.34 (naive windowed) to 12.47 and dropped Pearson r from
0.32 to 0.24. The mechanism is real and fires often (60/107 subjects), but
propagating one window's choice into the next means an early wrong choice
(e.g. window 1's tallest peak already being a harmonic, since window 1 has
no predecessor to correct it) can chain forward and lock in an error the
naive per-window tallest-peak approach would not have made consistently.
This is not a subtle effect — it is the dominant driver of the pool-level
regression, since gating alone barely moves the numbers (see above) while
continuity alone is responsible for the 60-subject change count and the
full MAE/RMSE/r shift between `gatingOnly` and `gatingPlusContinuity`.

## Bottom line

Windowing (Action 1) is a real, working prerequisite: it already improves
RMSE and Pearson r over the whole-clip baseline even naively
(15.64 vs 18.37 RMSE, 0.316 vs 0.278 r), likely because averaging several
independent per-window FFTs is itself a noise-reduction step. Harmonic
continuity (Action 3) does exactly what it was designed to do on the
specific case that motivated it — p21's 1.87x harmonic error is corrected
— but generalizes poorly across the full pool because a bad first-window
choice propagates forward uncorrected; it is a targeted fix for a specific
failure mode, not a general accuracy improvement. Quality gating (Action 2),
as derived from this pooled quality-score distribution, functions as a
near-no-op at this pool's scale because the natural knee sits in the
extreme tail rather than separating a meaningful low-quality cluster.

## Outputs

- `matlab/src/heartrate/windowedHeartRate.m` — Action 1.
- `matlab/src/validation/selectHarmonicConsistentHR.m` — Action 3.
- `matlab/src/validation/computeWindowQualityThreshold.m` — Action 2 (threshold derivation).
- `matlab/src/validation/aggregateGatedWindowHR.m` — Action 2 (exclusion + aggregation).
- `matlab/scripts/run_task_p_p21_isolated_check.m` — Action 3 isolated verification.
- `matlab/scripts/run_task_p_windowed_batch.m` — Action 4 full-pool batch.
- `results/metrics/segment6_task_p_windowed_hr_summary.csv` — per-subject, all four methods + ground truth + window counts + continuity-override count + changed-by-continuity flag + fallback flag.
- `results/metrics/segment6_task_p_windowed_metrics.csv` — pooled MAE/RMSE/Pearson r per method.
