# Segment 6 Refinement Notes

This note documents a follow-up pass on Segment 6 (validation) that fixed a
thin/broken ground-truth gap in the pooled HR numbers and investigated the
negative Pearson r in the pooled SpO2 LOSO result, rather than just
re-reporting it. It supplements, not replaces, `Segment6_Team_README.md`
and `Segment6_LineByLine_Explanation.md`.

**Path note:** the task brief that requested this refinement referred to
`matlab/docs/Segment6_Refinement_Notes.md`. This project's actual
convention (confirmed against `README.md` and every existing doc —
`DATA_FORMAT.md`, `VIPL_DATA_FORMAT.md`, `HOFFMAN_DATA_FORMAT.md`) is
`docs/` as a sibling of `matlab/`, not nested inside it. This file is
placed at `spandan/docs/Segment6_Refinement_Notes.md` accordingly.

## What was found broken/thin

1. **`segment4_hr_summary.csv` had `HR_groundtruth = NaN` for all 3 UBFC
   rows** (`5-gt`, `6-gt`, `7-gt`). This CSV predates
   `io/loadGroundTruth.m`'s real implementation — at the time those rows
   were written, `loadGroundTruth.m` was still a Segment-4-era stub, so the
   batch script's try/catch recorded NaN for every UBFC subject. Because
   `run_segment6_validation.m` filters out NaN-ground-truth rows before
   computing pooled HR metrics, the previous "pooled" HR table
   (`segment6_hr_pooled_metrics.csv`) was **UBFC: N=0** for every method —
   the "pooled" numbers were silently 100% VIPL (N=3), not a real
   UBFC+VIPL pool, exactly as the task brief suspected.
2. **The pooled SpO2 LOSO result (N=8) showed Pearson r = -0.7554**
   between predicted and true SpO2 — the wrong sign for a working
   calibration. This was investigated rather than re-reported (see below).

## Task A — `loadGroundTruth.m` for DATASET_2's HR format

**Verdict: it already works correctly. No code change was made.**

`loadGroundTruth.m` already contained a `'dataset2'` branch (added in an
earlier session, presumably staged ahead of this need but never actually
exercised end-to-end, since `data/raw/UBFC-rPPG/DATASET_2/` does not exist
locally — see Task C). Before trusting it, it was verified against two real
`ground_truth.txt` files extracted from the authoritative
`ubfc-rppg-dataset.zip` (subject1: 1547 columns/frame-samples, subject9:
2016 columns/frame-samples — only the two small text files were extracted
for this check, not the videos; see Task C for why the full 33.5GB archive
was not touched):

- `readmatrix(gtPath, 'FileType', 'text')` parses the 3-line
  whitespace-delimited format cleanly with no errors, for files with
  different lengths (1547 vs 2016 fields), confirming the parser does not
  assume a fixed frame count.
- `gt.ppg`, `gt.hr`, `gt.timestamp` all come back as `1 x N` doubles with
  matching lengths, `gt.spo2` comes back empty (`[]`) as documented (no
  SpO2 field in DATASET_2) — matches the header comment's contract exactly.
- `gt.timestamp` starts at 0 and increases with **irregular** spacing
  (e.g. subject1: 0, 0.011, 0.055, 0.067, 0.109, 0.120, 0.162 …) — real
  frame-capture jitter, not synthetic uniform resampling — consistent with
  `docs/DATA_FORMAT.md`'s claim that this file is already one-value-per-
  video-frame (index-aligned), unlike DATASET_1's asynchronous ~62 Hz
  oximeter stream which genuinely needs timestamp-based alignment.
- Sanity numbers: subject9 mean HR = 108.19 bpm (line 2's raw values sit
  right around 107 in the first several dozen samples — consistent);
  subject1 spans 1547 samples ending at timestamp 68.26s, in the same
  range as DATASET_2's documented ~68s clip durations.

**Caveat carried forward, not resolved here:** the index-alignment
assumption (`gt.hr(i)` ↔ video frame `i`) is confirmed against the GT
file's own internal structure and `docs/DATA_FORMAT.md`'s prior
verification, but has not been re-confirmed against an actual DATASET_2
video's frame count in this session, because no DATASET_2 video has been
extracted (Task C). This should be spot-checked the first time a real
DATASET_2 subject is run through Segment 2–4.

## Task B — Backfilled HR ground truth (in place, no duplicate rows)

For `5-gt`, `6-gt`, `7-gt` (the only subjects with an existing
`hr_estimates.mat` but `HR_groundtruth = NaN`): re-ran the ground-truth
lookup using the now-verified `loadGroundTruth.m` against each subject's
real `gtdump.xmp`, recomputed the three abs-error columns, overwrote each
subject's `data/processed/<id>_hr_estimates.mat`, and **replaced the
matching row in `results/metrics/segment4_hr_summary.csv` in place** (read
all lines, matched on the `subjectID` field, rewrote just that line) —
no duplicate rows were created; this was verified by reading the CSV back
afterward. This was done via a one-off scratch script (not committed to
the repo), following the same precedent already used in the Segment 5
session for extending DATASET_1 processing without editing the shared
team batch script's logic.

Result: all three subjects now have real ground truth, and the recovered
HR errors are small (CHROM/POS within 1–3 bpm of ground truth), matching
what an earlier session had already verified manually outside the pipeline
before `loadGroundTruth.m` was implemented.

## Task C — Growing N

**DATASET_1 (zero-cost, done):** `12-gt` and `after-exercise` already had
Segment 2/3 output (`_rgb_traces.mat`, `_filtered_traces.mat`) sitting in
`data/processed/` from a prior session, but had never been run through
Segment 4. Ran them through the exact same Segment 4 logic
(`chromCombine`/`posCombine`/`fftHeartRate`/`loadGroundTruth`, all called
unmodified) via a scratch driver script, and appended two genuinely new
rows to `segment4_hr_summary.csv` plus their `_hr_estimates.mat` and
sanity PNGs. This was not explicitly listed in the task brief's Task C
(which named DATASET_2 specifically) but follows the exact same
"already-extracted, zero re-download/re-extraction cost" reasoning the
brief itself used to justify Task C — noted here explicitly rather than
done silently.

**DATASET_2 (not done, and not attempted):** `data/raw/UBFC-rPPG/DATASET_2/`
does not exist locally — confirmed by directory listing. The only source
for DATASET_2 is the single 33.5GB `ubfc-rppg-dataset.zip` (outside the
repo, at `H:\...\UBFC dataset\`), which has never been extracted. The task
brief's own Task C instructions are explicit: *"Do not re-download or
re-extract anything — only process what's already sitting in
`.../DATASET_2/`."* Since nothing is sitting there, **0 of 42 DATASET_2
subjects were processed**, and none were extracted to change that,
per that explicit constraint. (H: had ~56GB free at the time of this
session, so a partial extraction would be feasible disk-space-wise in a
future session if the user authorizes it — each subject's video is
~1.4–1.9GB uncompressed — but that is a deliberate decision for the user
to make given the time/disk cost, not something to do silently.) Two tiny
`ground_truth.txt` files (KBs, not videos) were extracted from the same
zip purely to verify Task A's parsing against real data; this is not video
extraction and does not conflict with the "do not re-extract" instruction.

**Net effect on HR pool:** 3 → 8 usable subjects (5 UBFC + 3 VIPL), all
from data already on disk before this session.

## Task D — Investigating the negative pooled SpO2 Pearson r

### 1. The new `segment6_R_vs_SpO2_by_dataset.png` plot

Raw ratio-of-ratios `R` (x-axis, pre-calibration) vs. true SpO2 (y-axis),
by dataset:

| Dataset | R range | SpO2_true range |
|---|---|---|
| UBFC (5 subjects) | 0.520 – 0.864 | 95.99% – 98.89% |
| VIPL (3 subjects) | 0.823 – 1.378 | 96.00% – 97.58% |

**This shows a real cross-dataset offset, not just noise.** Both datasets'
true SpO2 values sit in essentially the same narrow near-normal band
(~96–99%), but VIPL's R values run substantially higher for that same
SpO2 range — VIPL's minimum R (0.823) is already near UBFC's maximum
(0.864), and two of VIPL's three points (R = 1.25, 1.38) sit far outside
UBFC's entire range. A model that pools both datasets and fits one global
line has no way to tell "R is higher because SpO2 differs" apart from "R
is higher because this is a different camera/sensor/skin-tone/lighting
setup" — and with true SpO2 barely varying at all across all 8 subjects,
there is very little physiological signal for R to explain in the first
place, so the between-dataset offset dominates whatever real physiological
trend exists. This directly matches the pattern already documented in
Segment 5's Hoffman sanity check (per-subject R offsets diluting a pooled
fit) — see `segment5_spo2/Segment5_LineByLine_Explanation.md` — except here
the offset is between whole *datasets*, not just subjects.

### 2. Trivial baseline comparison (`runLOSO.m` extended, non-breaking)

`validation/runLOSO.m` now also computes, per held-out fold, a baseline
prediction equal to the mean true SpO2 of that fold's training subjects
(R ignored entirely) — added as two **new** struct fields
(`SpO2_predicted_baseline`, `abs_error_baseline`) alongside the existing
six, so nothing that already reads `results(i).SpO2_predicted` etc. is
affected. `segment6_spo2_loso_pooled.csv` gained the same two columns, and
a companion `segment6_spo2_loso_baseline_metrics.csv` reports the
baseline's own MAE/RMSE/Pearson r pooled and per-dataset, computed through
the same unmodified `computeMetrics.m`.

| | Real calibration | Trivial baseline |
|---|---|---|
| Pooled MAE | 1.2296 | **1.0231** |
| Pooled RMSE | 1.3486 | **1.1430** |
| Pooled Pearson r | -0.7554 | -1.0000 |

**Finding, stated plainly: the real R-based calibration does not beat the
trivial "guess the training mean" baseline on pooled MAE or RMSE, at the
current N=8.** This holds per-dataset too (UBFC baseline MAE 1.10 vs real
1.22; VIPL baseline MAE 0.89 vs real 1.24).

**Important caveat on the baseline's r = -1.0000 (exactly, in every
scope):** this is a mathematical artifact of the leave-one-out
construction, not a real finding about SpO2 or R. For LOSO,
`baseline_predicted(i) = (sum(SpO2_true) - SpO2_true(i)) / (N-1)`, which is
an exact negative-affine function of `SpO2_true(i)` by algebra alone —
it is guaranteed to produce Pearson r = -1 regardless of any real
relationship, for any dataset, any N. It is reported here for
transparency (it is what the same `computeMetrics.m` call produces), but
**the MAE/RMSE comparison above is the meaningful part of this baseline
check, not its correlation.**

### 3. Read: thin data, cross-device offset, or both?

**Both — not a reassuring "just needs more data" story.** Two distinct
problems are visible together:

- **Cross-device R offset (structural, visible in the plot):** VIPL and
  UBFC occupy largely non-overlapping R ranges for the same SpO2 range.
  Pooling them into one linear fit conflates device/camera differences
  with the physiological R→SpO2 relationship the model is supposed to be
  learning.
- **Near-zero true-SpO2 variance (a ceiling on what more same-type data
  can fix):** all 8 subjects currently in the pool are resting,
  near-normal SpO2 (96–99%, a 3-point spread). There is very little
  physiological signal in the ground truth for R to explain in the first
  place — adding more *resting* VIPL or UBFC subjects narrows confidence
  intervals but does not by itself give R more physiological range to
  track, and will not by itself fix the sign of the correlation if the
  cross-dataset R offset dominates.

Adding more VIPL subjects from the existing 107-subject pool (thin-data
fix) is worth doing and cheap, but should not be expected to flip the
correlation's sign on its own — the R-vs-SpO2 plot's between-dataset
separation is a structural issue a bigger N of the same kind of data does
not resolve. What would more directly address it: (a) subjects spanning
actual desaturation, not just resting SpO2 — the Hoffman finger-camera
dataset already sitting in `data/raw/Hoffman/` has FiO2-controlled
desaturation down to ~65% and would give R something real to track; and/or
(b) a per-dataset R correction (e.g. z-scoring or an offset term per
dataset) before pooling, mirroring the per-subject z-scoring fix already
documented for the Hoffman sanity check in Segment 5.

## Before / after numbers

### HR (`segment6_hr_pooled_metrics.csv`)

| Method | Scope | Before N | Before MAE / RMSE / r | After N | After MAE / RMSE / r |
|---|---|---|---|---|---|
| CHROM | pooled | 3 | 3.937 / 4.484 / 0.9954 | 8 | 3.834 / 5.587 / 0.9572 |
| CHROM | UBFC | 0 | NaN / NaN / NaN | 5 | 3.772 / 6.154 / 0.9402 |
| CHROM | VIPL | 3 | 3.937 / 4.484 / 0.9954 | 3 | 3.937 / 4.484 / 0.9954 (unchanged) |
| POS | pooled | 3 | 3.937 / 4.484 / 0.9954 | 8 | 3.834 / 5.587 / 0.9572 |
| POS | UBFC | 0 | NaN / NaN / NaN | 5 | 3.772 / 6.154 / 0.9402 |
| POS | VIPL | 3 | 3.937 / 4.484 / 0.9954 | 3 | 3.937 / 4.484 / 0.9954 (unchanged) |
| Green | pooled | 3 | 16.916 / 18.992 / -0.2548 | 8 | 14.193 / 18.921 / 0.3454 |
| Green | UBFC | 0 | NaN / NaN / NaN | 5 | 12.559 / 18.878 / 0.2944 |
| Green | VIPL | 3 | 16.916 / 18.992 / -0.2548 | 3 | 16.916 / 18.992 / -0.2548 (unchanged) |

(Note: CHROM and POS produce numerically identical HR values for every
subject in this project's data — a pre-existing property of this
implementation from before this session, not something introduced or
changed here.)

The previous "pooled" HR row was actually VIPL-only (UBFC contributed 0
usable rows). The real UBFC+VIPL pool is now N=8, and CHROM/POS still
strongly beat green-only (MAE 3.8 bpm vs 14.2 bpm pooled).

### SpO2 (`segment6_spo2_loso_metrics.csv` / new `segment6_spo2_loso_baseline_metrics.csv`)

| Scope | N | Real calib. MAE/RMSE/r | Baseline MAE/RMSE/r |
|---|---|---|---|
| Pooled | 8 | 1.230 / 1.349 / -0.755 | 1.023 / 1.143 / -1.000* |
| UBFC | 5 | 1.225 / 1.389 / -0.863 | 1.103 / 1.265 / -1.000* |
| VIPL | 3 | 1.238 / 1.278 / -0.708 | 0.890 / 0.903 / -1.000* |

(*baseline r is a LOSO arithmetic artifact — see Task D §2 above, not a
real correlation.)

**SpO2 numbers are unchanged from before this session** (verified: the old
`segment6_spo2_loso_metrics.csv` had the exact same pooled/UBFC/VIPL
MAE/RMSE/r as the new run) — this is expected and correct, not a bug: the
SpO2 pool is built from `segment5_dataset1_calibration.csv` /
`segment5_vipl_calibration.csv`, a completely different subject/CSV scope
from the HR pool this session backfilled. HR backfill (Task B) grows the
HR pool; it does not and should not change the SpO2 pool's N or numbers.

## Verdict: should the current SpO2 calibration be trusted for the report yet?

**No — it should still be flagged as unresolved, not reported as a working
result.** The pooled LOSO SpO2 calibration currently has the wrong-sign
correlation with true SpO2, and — more damning than the sign flip alone —
does not beat a trivial "always guess the training-set mean" baseline on
either MAE or RMSE, in the pool overall or in either dataset alone. The
new by-dataset R-vs-SpO2 plot shows why: UBFC and VIPL occupy visibly
different R ranges for essentially the same narrow, near-normal SpO2
range, which is consistent with a device-level R offset overwhelming
whatever physiological R→SpO2 relationship exists in this data, compounded
by there being very little true SpO2 variance in the pool to begin with.
This is a real, structural limitation — not a rounding error or a
labeling bug — and the report should present it as an open problem (with
the plot and baseline comparison as evidence), not as a validated
calibration. HR, by contrast, is now a real UBFC+VIPL pool (N=8, up from
an effectively VIPL-only N=3) and CHROM/POS's ~3.8 bpm pooled MAE with
Pearson r=0.96 is a legitimately strong, trustworthy result for the report.

## Task E — Follow-up: is the cross-dataset R offset fixable with per-dataset centering?

This is a follow-up investigation on top of Task D, done in a later
session, and deliberately scoped to NOT touch `spo2/ratioOfRatios.m` or
`spo2/calibrateSpO2.m` — both remain exactly as Segment 5 left them. The
question: Task D's plot shows UBFC and VIPL sitting at different R levels
for a similar SpO2 range. Is that a simple *offset* between the two
datasets (fixable by centering each dataset's R on its own mean), or is
the R→SpO2 *relationship itself* different in shape between the two
cameras (not fixable by centering, and a more serious problem)?

### 1. Diagnostic: per-dataset slope, not just the offset

Before writing any fix, a separate simple linear regression (`SpO2_true`
vs. raw `R`, i.e. exactly the relationship
`spo2/calibrateSpO2.m` fits) was run independently within each dataset's
existing pooled points — this is a diagnostic on N=5 (UBFC) and N=3
(VIPL), far too few points to trust the fitted numbers as models in their
own right, but enough to compare direction and rough scale:

| Dataset | N | Slope (SpO2 per unit R) | Pearson r (within dataset) |
|---|---|---|---|
| UBFC | 5 | +2.81 | +0.339 |
| VIPL | 3 | +1.18 | +0.397 |
| Pooled (both, uncentered) | 8 | +0.036 | +0.009 |

**Both within-dataset slopes are positive, and both within-dataset r
values are positive and of comparable, modest size (+0.34 and +0.40) —**
the two datasets agree on the *direction* of the R→SpO2 relationship, and
their magnitudes are not wildly apart given how few points each has. This
is the "slopes are reasonably similar" case the diagnostic was checking
for, so centering (Step 2) was judged appropriate to try rather than
ruled out. It is also worth being explicit about what this diagnostic
does NOT clear up: the pooled, uncentered slope collapses to essentially
zero (+0.036, r≈0.01) even though both datasets individually show a
positive slope — a textbook Simpson's-paradox-shaped symptom, where
UBFC's higher mean SpO2 (97.17%) sits at a *lower* mean R (0.759) than
VIPL's lower mean SpO2 (96.59%) at a *higher* mean R (1.149). The
between-dataset offset in R is large enough, relative to each dataset's
own within-dataset R spread, that pooling the raw values cancels out the
positive relationship each dataset shows on its own. This is exactly what
per-dataset centering is meant to correct.

**Caveat carried forward, not hidden:** the sign of these slopes
(SpO2 rising as R rises) also runs opposite to the physiological
direction `calibrateSpO2.m`'s own doc comment describes ("SpO2 falls as R
rises", hence `SpO2 = A - B*R`). At N=5 and N=3, resting near-normal
subjects with only a 3-percentage-point SpO2 spread, this is not strong
enough evidence to say the underlying physiology is backwards in this
data — it is at least as likely to be noise from too few points and too
little true SpO2 variance for R to have anything real to track (the same
point Task D's §3 already made). It is flagged here rather than
investigated further because chasing it would mean touching
`ratioOfRatios.m` or `calibrateSpO2.m`, which is explicitly out of scope
for this follow-up.

### 2. `validation/centerRPerDataset.m` (new file, Segment 6 only)

New file, not a Segment 5 change: `matlab/src/validation/centerRPerDataset.m`.
For each LOSO fold, it subtracts each dataset's own mean R — computed
using ONLY that fold's training subjects (the held-out subject excluded)
— from every pooled R value, before handing the result to the unmodified
`calibrateSpO2.m`. The per-fold, training-only recomputation matters for
the same reason LOSO itself matters: if the held-out subject's own R
value were allowed to contribute to its dataset's mean, the centered R
fed to `calibrateSpO2.m` for that subject would already carry information
about the very subject being predicted. The function's own header comment
documents this reasoning in full.

### 3. Wired into `runLOSO.m` as a new, separate output — nothing removed

`validation/runLOSO.m` now computes a THIRD parallel prediction per fold
(`SpO2_predicted_centered` / `abs_error_centered`), alongside the
existing raw pooled prediction and the existing trivial baseline. All
three still come from the same single leave-one-out loop; the centered
path just calls `centerRPerDataset.m` before calling the same unmodified
`calibrateSpO2.m` a second time per fold. The original
`SpO2_predicted`/`abs_error` fields are untouched.
`scripts/run_segment6_validation.m` now also writes
`results/metrics/segment6_spo2_loso_centered_metrics.csv` (same
scope/N/MAE/RMSE/Pearson_r shape as the existing raw and baseline metrics
CSVs) and prints all three side by side in its summary section.
`results/metrics/segment6_spo2_loso_pooled.csv` gained
`SpO2_predicted_centered` / `abs_error_centered` columns alongside the
existing raw and baseline columns, so all three predictions are visible
per subject in one table.

### 4. Three-way result (raw pooled vs. centered vs. trivial baseline, N=8)

| | Raw pooled (uncentered) | Per-dataset centered | Trivial baseline |
|---|---|---|---|
| Pooled MAE | 1.2296 | **1.0947** | 1.0231 |
| Pooled RMSE | 1.3486 | **1.2538** | 1.1430 |
| Pooled Pearson r | -0.7554 | **-0.2771** | -1.0000* |

(*baseline r is a LOSO arithmetic artifact — see Task D §2 above, not a
real correlation; ignore it for the MAE/RMSE comparison.)

Per-dataset breakdown:

| Scope | Raw MAE | Centered MAE | Baseline MAE | Raw r | Centered r |
|---|---|---|---|---|---|
| UBFC (N=5) | 1.2247 | 1.1842 | 1.1028 | -0.8632 | -0.6947 |
| VIPL (N=3) | 1.2377 | 0.9455 | 0.8903 | -0.7075 | -0.0123 |

### 5. Verdict: does centering fix it?

**Partially, but not enough — and this should be reported plainly as
"improved, still not a working calibration," not as "fixed."**

- Centering is a genuine, unambiguous improvement over the raw pooled fit
  on every metric checked: pooled MAE drops from 1.2296 to 1.0947, pooled
  RMSE drops from 1.3486 to 1.2538, and the correlation sign problem
  shrinks sharply (r goes from -0.7554, a strong wrong-sign correlation,
  to -0.2771, a weak one). This is consistent with the diagnostic in §1:
  removing the between-dataset R offset does let each dataset's own
  (weak but same-sign) within-dataset relationship show through more than
  the raw pooled fit allowed.
- **But the centered calibration still does not beat the trivial
  training-mean baseline** (MAE 1.0947 vs. baseline 1.0231; RMSE 1.2538
  vs. baseline 1.1430) — the same bar Task D's raw-pooled comparison
  already failed. It closes roughly half the gap to the baseline (raw was
  0.21 MAE-points worse than baseline; centered is 0.07 MAE-points
  worse), but does not cross it, either pooled or in UBFC alone. VIPL's
  centered MAE (0.9455) does come close to VIPL's own baseline (0.8903),
  but still does not beat it, and N=3 for VIPL is too thin to read much
  into how close that gap is.
- **Honest read:** the cross-dataset R offset documented in Task D was a
  real, fixable-in-part contributor to the pooled model's failure —
  centering measurably helps. It was not, however, the *only* problem.
  Task D's other diagnosis (near-zero true-SpO2 variance across all 8
  subjects, leaving very little physiological signal for R to explain in
  the first place) is still fully in force and centering does nothing
  about it. **The SpO2 calibration should still be flagged as unresolved
  for the report** — now with a somewhat smaller gap to the trivial
  baseline than before this follow-up, and with cross-dataset offset and
  thin/low-variance data identified as two separable problems rather than
  one, but not with a passing result to point to.

### 6. Forward risk for defense day (flagging only, not solving now)

This whole exercise — a real, measurable R offset between two datasets
recorded on different cameras/sensors under different conditions — is a
direct preview of a risk for the live demo. The demo phone is a **third
camera**, never seen by either UBFC or VIPL during calibration fitting.
If UBFC vs. VIPL alone can produce an offset this size in R for
similar true SpO2, there is no reason to assume the demo phone's camera
will land inside either dataset's R range, let alone whichever one ends
up dominating the pooled/centered calibration fit. This is not something
to try to solve before Segment 7 — the right fix (if this data shape
holds) is likely the same kind of per-source centering or z-scoring
already used here, applied with the self-collected test set as its own
third "dataset" — but it is worth deliberately testing for, not assuming
away, once the Segment 7 self-collected clips exist: specifically, check
where the demo phone's own raw R values fall relative to UBFC's and
VIPL's ranges in `segment6_R_vs_SpO2_by_dataset.png`-style plot before
trusting any calibrated SpO2 number shown live.

## Task F -- Growing the VIPL subject pool (2026-08-08 session)

This is a data-extraction and batch-execution pass only, done in a later
session. No Segment 2-5 algorithm file, either VIPL loader, `runLOSO.m`,
`centerRPerDataset.m`, `computeMetrics.m`, or `blandAltman.m` was touched.
The only files changed were the `subjectTriples` list at the top of
`scripts/run_vipl_integration_batch.m` (rows added, none removed or
reordered) and this doc.

### 1. Disk space check (do not assume the prior ~56GB figure still holds)

Actual free space at the start of this session: H: had 55.43 GB free
(checked with `Get-PSDrive`, not assumed from the prior session's ~56GB
note) -- essentially unchanged from the figure recorded when VIPL-HR
integration was first built. Using the three already-extracted `v1/source1`
triples as a reference (`p1`=20MB, `p2`=9.9MB, `p3`=17MB -- `p1` also has
extra `v1/source2-4` from an earlier validation pass, not counted here
since those are additional sources of an already-done subject, not new
N), the average size of one new-subject `v1/source1` triple is ~15.6MB.

Finding: disk space is not actually the binding constraint for this kind
of growth. At ~15.6MB/subject, even a generous 50MB/subject estimate
would allow 800+ new-subject triples before eating into a 15GB safety
margin on a 55GB-free disk -- the entire remaining 94-subject pool (94 x
~16MB = ~1.5GB) would barely register. The original "~56GB free, be
careful" caution from the first integration session was really about not
unzipping whole archives (each of the 21 VIPL-HR zips is compressed
multi-GB; unzipping several in full could exhaust the disk), not about the
cost of targeted per-entry extraction of individual (subject, scenario,
source) triples, which is small enough not to be disk-bound in practice.
The real limiting factor for how many subjects to add in one pass is
processing time (MATLAB startup + per-video ROI/filtering/FFT time), not
disk space.

### 2. New subjects extracted

10 new subjects: p4-p13, `v1/source1` only (one triple each, matching the
same webcam/stable-scenario pattern already used for `p2`/`p3` -- NOT
extra sources of `p1`, per the task's own constraint against inflating N
with same-subject recordings). Checked `Missing_data.txt` first for each:
none of `p4-p13`'s `v1/source1` entries are listed as missing. Extracted
with the same targeted per-zip-entry PowerShell method documented in
`VIPL_Team_README.md` (from `p1-5.zip`, `p6-10.zip`, `p11-15.zip` --
already-downloaded archives, no new download). All 10 landed at
`spandan/data/raw/VIPL-HR/pN/v1/source1/` with the full expected file set
(`video.avi`, `time.txt`, `gt_HR.csv`, `gt_SpO2.csv`, `wave.csv`) --
verified per-subject, not assumed. `gt_SpO2.csv` was present and non-empty
for all 10 (31-36 lines each), so the "SpO2 present in every video checked
so far" pattern from `VIPL_DATA_FORMAT.md` continues to hold, but this was
re-checked rather than assumed. Total extracted size: 130MB for the 10
subjects, trivial against the 55GB free.

No same-subject-only extraction was needed (no corrupted archive was hit
for `p4-p13`), so there is nothing to flag under the "don't count as new N"
caveat this time -- all 10 new triples are genuinely independent people.

### 3. Batch run: `run_vipl_integration_batch.m`, unmodified logic

Updated the `subjectTriples` matrix (the script's existing, documented
per-team-member configuration mechanism -- no restructuring) to list all
13 triples (`p1`-`p13`, `v1`, `source1`). Because the script always
appends to `segment4_hr_summary_vipl.csv`/`segment5_vipl_calibration.csv`
with no dedup logic, and `p1`-`p3`'s rows already existed in those files,
running the full 13-row list unmodified would have duplicated those three
rows. Backed up both CSVs (`*.bak_before10new`) and deleted the live
copies before running, so the unmodified script regenerated both files
from scratch with exactly 13 rows, no duplicates, no code change needed to
add dedup logic that doesn't already exist. Verified afterward: `p1`-`p3`'s
HR values (`HR_chrom`/`HR_pos`/`HR_green`) are bit-identical to the
pre-run backup -- the ROI/filtering/FFT pipeline is deterministic, as
expected. `p1`-`p3`'s SpO2 `SpO2_predicted`/`abs_error` values ARE
different from the backup (e.g. `p1`: 98.0705/1.8761 before vs
97.7999/1.6054 after) -- this is expected and correct, not a bug: those
come from the leave-one-out calibration, whose training fold for `p1` now
includes 12 other subjects instead of 2, so the fitted `A`/`B` per fold
necessarily change as the pool grows.

Result: 13/13 subjects succeeded, 0 failures. Face-tracking drop counts
varied per subject (0 for most; `p7` had 98/750 frames reused-bbox, ~13%;
`p3`/`p4`/`p8` had a handful; `p10` had 2) -- notably, the two subjects
with the largest HR errors this batch (`p5`: 13.2bpm chrom error; `p12`:
27.2bpm chrom/pos error) had zero dropped frames, so their error is not
explained by face-tracking dropout -- it looks like a genuine
pulse-signal-quality limitation for those subjects/lighting/motion
conditions, worth a closer look (sanity PNGs) before the report if time
allows, not a tracking bug.

### 4. Segment 6 re-run: auto-discovery confirmed working

Ran `scripts/run_segment6_validation.m` unmodified. Confirmed (not
assumed) that it auto-discovered the larger pool from the CSV files
directly -- log shows "Loaded 13 VIPL HR rows" and pooled "N=18 total
rows" without any script edit, exactly as its existing design should
behave.

### 5. Before / after numbers

HR (`segment6_hr_pooled_metrics.csv`):

| Method | Scope | Before N | Before MAE/RMSE/r | After N | After MAE/RMSE/r |
|---|---|---|---|---|---|
| CHROM | pooled | 8 | 3.834 / 5.587 / 0.9572 | 18 | 5.887 / 8.940 / 0.8241 |
| CHROM | UBFC | 5 | 3.772 / 6.154 / 0.9402 | 5 | 3.772 / 6.154 / 0.9402 (unchanged) |
| CHROM | VIPL | 3 | 3.937 / 4.484 / 0.9954 | 13 | 6.700 / 9.803 / 0.7272 |
| POS | pooled | 8 | 3.834 / 5.587 / 0.9572 | 18 | 7.190 / 12.495 / 0.6636 |
| POS | UBFC | 5 | 3.772 / 6.154 / 0.9402 | 5 | 3.772 / 6.154 / 0.9402 (unchanged) |
| POS | VIPL | 3 | 3.937 / 4.484 / 0.9954 | 13 | 8.505 / 14.198 / 0.5864 |
| Green | pooled | 8 | 14.193 / 18.921 / 0.3454 | 18 | 18.023 / 21.201 / 0.1406 |
| Green | UBFC | 5 | 12.559 / 18.878 / 0.2944 | 5 | 12.559 / 18.878 / 0.2944 (unchanged) |
| Green | VIPL | 3 | 16.916 / 18.992 / -0.2548 | 13 | 20.124 / 22.029 / 0.0292 |

SpO2 (`segment6_spo2_loso_metrics.csv` + baseline + centered):

| | Scope | Before N | Before MAE/RMSE/r | After N | After MAE/RMSE/r |
|---|---|---|---|---|---|
| Real calibration | pooled | 8 | 1.230/1.349/-0.755 | 18 | 1.009/1.205/-0.671 |
| Real calibration | UBFC | 5 | 1.225/1.389/-0.863 | 5 | 1.181/1.271/-0.882 |
| Real calibration | VIPL | 3 | 1.238/1.278/-0.708 | 13 | 0.943/1.178/-0.634 |
| Trivial baseline | pooled | 8 | 1.023/1.143/-1.000* | 18 | 0.970/1.138/-1.000* |
| Trivial baseline | UBFC | 5 | 1.103/1.265/-1.000* | 5 | 1.080/1.152/-1.000* |
| Trivial baseline | VIPL | 3 | 0.890/0.903/-1.000* | 13 | 0.927/1.132/-1.000* |
| Per-dataset centered | pooled | 8 | 1.095/1.254/-0.277 | 18 | 1.044/1.237/-0.657 |
| Per-dataset centered | UBFC | 5 | 1.184/1.193/-0.695 | 5 | 1.140/1.193/-0.882 |
| Per-dataset centered | VIPL | 3 | 0.946/n-a/-0.012 | 13 | 1.007/1.254/-0.654 |

(*baseline r is a LOSO arithmetic artifact, not a real correlation -- see
Task D Section 2 above; unchanged reasoning at any N.)

### 6. Did the additional data meaningfully move any open finding?

Yes, in two ways -- one confirms the open finding more strongly, one
complicates the earlier "centering helps" read. Neither flips to a clean
"resolved."

- HR accuracy got measurably worse, not better, once more real subjects
  were added. The old N=8 pooled CHROM/POS numbers (MAE 3.83, r=0.957)
  were flattered by having only 3 VIPL subjects, all apparently easy
  cases. With 13 VIPL subjects, pooled CHROM MAE nearly doubles to 5.89
  (r drops to 0.824) and POS MAE more than doubles to 7.19 (r drops to
  0.664). UBFC's numbers are unchanged (its N didn't grow), so this
  degradation is entirely coming from the newly visible spread in VIPL
  subject difficulty (`p5`, `p10`, `p12` in particular). This is the
  opposite of "just needs more data to look better" -- more N revealed
  that the earlier strong pooled HR number was an artifact of a small,
  easy sample, not a robust result. CHROM/POS still clearly beat
  green-only (5.9-7.2 bpm vs 18.0 bpm pooled), so the core algorithm
  choice is still justified, but the report should no longer cite the old
  "~3.8 bpm pooled MAE" figure as representative.
- CHROM and POS are no longer numerically identical for every subject.
  The prior note's caveat ("a pre-existing property... not something
  introduced or changed") no longer holds at N=13 VIPL -- `p10` alone has
  `HR_chrom=72.99` vs `HR_pos=122.83` bpm (GT 83.66), a 50bpm spread
  between the two methods on the same signal. This confirms that
  equivalence was a coincidence of the earlier small, easy sample, not a
  structural property of the implementation, and POS is measurably less
  robust than CHROM on the harder subjects now visible (POS pooled MAE
  7.19 vs CHROM 5.89).
- SpO2 still loses to the trivial baseline, and the correlation is still
  wrong-signed -- unchanged as a headline finding. Real-calibration pooled
  MAE (1.009) is still worse than the trivial baseline (0.970), and pooled
  r is still negative (-0.671). Growing N did not fix this, as Task D's
  original analysis predicted (thin data was diagnosed as only part of
  the problem, alongside the structural cross-dataset R offset and
  near-zero true-SpO2 variance).
- The per-dataset R-centering fix (Task E) looks noticeably less helpful
  at N=18 than it did at N=8, and this is worth flagging explicitly
  rather than re-citing the old "closes half the gap" verdict. At N=8,
  centering moved pooled r from -0.755 to -0.277 (a large improvement
  toward zero) and MAE from 1.230 to 1.095 (closing roughly half the gap
  to the baseline's 1.023). At N=18, centering barely moves pooled r
  (-0.671 to -0.657) and now makes MAE worse, not better (1.009
  uncentered vs 1.044 centered -- centering is now the worst of the three
  pooled options on MAE, behind both raw and baseline). This suggests the
  earlier "centering helps" verdict was itself partly a small-N artifact
  -- with only 3 VIPL points, subtracting VIPL's mean R had an outsized
  effect; with 13 more varied VIPL points, the per-dataset mean is more
  representative but the residual within-dataset R-SpO2 relationship is
  evidently not strong/consistent enough for centering to still pay off.
  This should be reported as "centering's benefit did not hold up under
  more data," not silently dropped.
- VIPL's true-SpO2 dynamic range widened, but only modestly, and did not
  fix the sign problem. VIPL SpO2_true range grew from 96.00-97.58%
  (N=3, 1.6pp spread) to 94.91-98.83% (N=13, 3.9pp spread) -- a real but
  small widening, still far short of the desaturation range the Hoffman
  dataset would offer (per Task D Section 3's suggestion). The
  cross-dataset R offset documented in Task D is also essentially
  unchanged: VIPL's R range was [0.823, 1.378] at N=3 and is still
  [0.823, 1.378] at N=13 (the same two extreme points happened to already
  be `p1`/`p2`), while UBFC's R range ([0.520, 0.864]) is unchanged since
  its N didn't grow. The two datasets still occupy largely non-overlapping
  R bands for overlapping SpO2 values -- the structural problem Task D
  identified is fully intact at N=18, not softened by the added VIPL
  subjects.

Bottom line for the report: SpO2 calibration should still be flagged
unresolved, now with slightly stronger evidence (still loses to baseline,
still wrong-signed, and the centering mitigation that looked promising at
N=8 did not hold up at N=18). HR should be presented with the new, harder
N=18 numbers (CHROM ~5.9 bpm pooled MAE, r=0.82), not the old N=8 numbers
-- CHROM/POS still clearly beat green-only, but the margin over
green-only and the absolute accuracy are both weaker than the smaller
sample suggested, and POS in particular no longer tracks CHROM closely on
harder subjects.

## Task G -- Full VIPL-HR dataset, all 107 subjects (2026-08-08 session, later same day)

Follow-up to Task F, done later the same session at the user's explicit
request to add all remaining VIPL-HR subjects. Same scope discipline as
Task F: no Segment 2-5 algorithm file, either VIPL loader, `runLOSO.m`,
`centerRPerDataset.m`, `computeMetrics.m`, or `blandAltman.m` was touched.
Only `subjectTriples` in `scripts/run_vipl_integration_batch.m` (94 more
rows added) and this doc changed.

### 1. Extraction: p14-p107 (94 more subjects)

12 of these (`p84`, `p97`-`p107`) are missing `v1/source1` in
`Missing_data.txt`; `v1/source2` (phone, no `time.txt`) was used for those
12 instead -- still one independent triple per new subject, still genuine
new N, just a different camera source for the subjects where source1
doesn't exist. The other 82 used `v1/source1` as before. Extracted via the
same targeted per-zip-entry method across all 20 remaining VIPL-HR
archives (`p11-15.zip` through `p101-107.zip`); every target was found (no
`NOT FOUND`/`MISSING ZIP` in the extraction log). All 107 subjects (`p1`
-`p107`) now have a complete file set, `gt_SpO2.csv` present and
non-empty for every one -- re-checked, not assumed. Total dataset size on
disk: 1.5GB. Free space on H: dropped from 55.43GB to 54.10GB over the
whole session (both batches) -- disk was never remotely close to a real
constraint, confirming Task F's disk-math conclusion held at full scale.

### 2. Batch run: 107/107 succeeded, p1-p13 still bit-identical

Same dedup approach as Task F: backed up the 13-subject CSVs
(`*.bak_before107`), cleared the live files, ran
`run_vipl_integration_batch.m` unmodified with all 107 triples listed.
**107/107 subjects succeeded, 0 failures.** `p1`-`p13`'s HR values are
still bit-identical to the Task F backup (pipeline remains deterministic).
Both sibling CSVs now have exactly 108 lines (1 header + 107 rows), no
duplicates.

### 3. Segment 6 re-run: auto-discovery still works, N=112 pooled

`run_segment6_validation.m`, unmodified, confirmed loading "107 VIPL HR
rows" and pooling to N=112 (5 UBFC + 107 VIPL) automatically.

### 4. Two real data-quality findings that only became visible at full scale

These are worth reporting explicitly rather than folding silently into
the before/after table below, because they change how the headline
numbers should be read.

**(a) `p25`'s SpO2 ground truth is a constant, physiologically implausible
44% across all 31 samples in `gt_SpO2.csv` (mean HR for the same subject
is a normal 65-73bpm, so this isn't a wholesale corrupt file -- just the
SpO2 column).** A sustained 44% SpO2 is not compatible with a resting,
conscious subject; this is almost certainly a pulse-oximeter sensor/motion
artifact in VIPL-HR's own original data capture, not a bug in
`loadVIPLGroundTruth.m` (which correctly reports the constant value it
finds) or in this project's pipeline. **This single point dominates the
pooled SpO2 RMSE:** its LOSO abs_error is 52.95pp, and it alone accounts
for **88.8% of the total squared error** across all 112 folds (verified
with a one-off diagnostic script, not a pipeline change: pooled RMSE is
5.3125 with `p25` included vs. **1.7821** excluding it; MAE is far more
robust, 1.8373 vs. 1.3769). **RMSE should not be quoted as a clean summary
statistic for the SpO2 pool at this N without this caveat** -- MAE is the
more trustworthy of the two here. This is flagged, not silently fixed or
excluded from the live CSVs, since removing a subject would be a data
decision for the user/report to make explicitly, not something to do
inside a "just add more subjects and re-run" task.

**(b) A handful of VIPL subjects also produce extreme ratio-of-ratios `R`
values** -- `p96`: R=4.2054 (vs. the previously-seen VIPL range of
~0.82-1.38), `p50`: R=2.7083, `p41`: R=1.9344 -- pulling the pooled R
range from `[0.823, 1.378]` (N=13, Task F) out to **`[0.487, 4.205]`**
(N=107). `spo2/ratioOfRatios.m` was not touched (out of scope), so this is
reported as an observation, not investigated further: the AC/DC
ratio-of-ratios computation appears numerically unstable for a small
number of subjects, worth a closer look in a future session focused on
Segment 5 itself.

**A hypothesis was formed and explicitly checked, not just asserted:**
initial suspicion was that the worst HR-error subjects (`p48`: 101.6bpm
CHROM error, `p22`: 65.5bpm, `p96`: 28.1bpm, etc.) shared the low-fps
signature also seen in `p50`/`p96` (`loadVIPLVideo` derives ~16.1fps from
`time.txt` vs. the 25fps container claim, a ~35% disagreement -- notably
larger than the ~19-24% disagreement range seen in Task F's smaller
sample). **This turned out to affect a genuine majority of the dataset --
62 of 107 subjects (58%) have a real fps below 20** (not a rare edge
case), so it was worth checking whether this cluster is where the worst
HR errors concentrate. **Checked directly, and the hypothesis does NOT
hold up:** mean CHROM abs error for the low-fps (<20fps) cluster is
9.00bpm vs. 9.82bpm for the higher-fps (>=20fps) cluster -- essentially
the same, low-fps subjects are not systematically worse. The worst-error
subjects are a real, scattered spread of hard cases (motion, lighting,
skin tone, or genuine algorithm limits), not explained by this one
variable. Reported here specifically so this spurious-looking pattern
isn't re-investigated or mis-cited as a finding in a future session.

**(c) Pool imbalance changes what "UBFC only" LOSO metrics even measure.**
At N=112 (107 VIPL vs. 5 UBFC), every UBFC subject's leave-one-out
training fold is ~96% VIPL data (roughly 106 VIPL + 4 UBFC). The "UBFC
only" row in the tables below is no longer a UBFC-specific validation in
any meaningful sense -- it now mostly reflects how a VIPL-dominated fit
happens to perform when applied to UBFC's 5 subjects. This likely explains
why UBFC's real-calibration Pearson r flipped from strongly negative
(-0.882 at N=18, Task F) to weakly positive (+0.054 at N=112) -- **this
is not evidence the calibration got better for UBFC; it is a pool-
composition artifact of one dataset now vastly outnumbering the other,
and should not be cited as an improvement.** The "VIPL only" row is more
trustworthy at this N (its own training folds are ~99% VIPL, i.e. close to
what they were before), and it still shows the same negative-r, thin-
signal pattern as before (r=-0.383).

### 5. Before / after numbers (N=18 from Task F vs. N=112 full pool)

HR (`segment6_hr_pooled_metrics.csv`):

| Method | Scope | N=18 (Task F) MAE/RMSE/r | N=112 (full pool) MAE/RMSE/r |
|---|---|---|---|
| CHROM | pooled | 5.887 / 8.940 / 0.824 | 9.097 / 18.005 / 0.314 |
| CHROM | UBFC | 3.772 / 6.154 / 0.940 | 3.772 / 6.154 / 0.940 (unchanged) |
| CHROM | VIPL | 6.700 / 9.803 / 0.727 | 9.346 / 18.372 / 0.278 |
| POS | pooled | 7.190 / 12.495 / 0.664 | 8.680 / 16.454 / 0.281 |
| POS | UBFC | 3.772 / 6.154 / 0.940 | 3.772 / 6.154 / 0.940 (unchanged) |
| POS | VIPL | 8.505 / 14.198 / 0.586 | 8.909 / 16.781 / 0.217 |
| Green | pooled | 18.023 / 21.201 / 0.141 | 14.983 / 19.490 / 0.087 |
| Green | UBFC | 12.559 / 18.878 / 0.294 | 12.559 / 18.878 / 0.294 (unchanged) |
| Green | VIPL | 20.124 / 22.029 / 0.029 | 15.097 / 19.518 / 0.034 |

SpO2 (`segment6_spo2_loso_metrics.csv` + baseline + centered; RMSE at
N=112 is skewed by the `p25` outlier, see Section 4a -- MAE is the more
trustworthy column here):

| | Scope | N=18 (Task F) MAE/RMSE/r | N=112 MAE/RMSE/r | N=112 MAE/RMSE excl. `p25` |
|---|---|---|---|---|
| Real calibration | pooled | 1.009/1.205/-0.671 | 1.852/5.313/-0.381 | 1.377/1.782/n-a |
| Real calibration | UBFC | 1.181/1.271/-0.882 | 0.917/1.342/+0.054 | n-a (p25 is VIPL) |
| Real calibration | VIPL | 0.943/1.178/-0.634 | 1.896/5.427/-0.383 | n-a |
| Trivial baseline | pooled | 0.970/1.138/-1.000* | 1.837/5.309/-1.000* | n-a |
| Trivial baseline | UBFC | 1.080/1.152/-1.000* | 0.906/1.298/-1.000* | n-a |
| Trivial baseline | VIPL | 0.927/1.132/-1.000* | 1.881/5.424/-1.000* | n-a |
| Per-dataset centered | pooled | 1.044/1.237/-0.657 | 1.851/5.312/-0.302 | n-a |
| Per-dataset centered | UBFC | 1.140/1.193/-0.882 | 0.880/1.281/+0.183 | n-a |
| Per-dataset centered | VIPL | 1.007/1.254/-0.654 | 1.896/5.428/-0.304 | n-a |

(*baseline r is a LOSO arithmetic artifact, not a real correlation -- see
Task D Section 2; unchanged reasoning at any N.)

### 6. Did the full dataset meaningfully move any open finding?

**Yes -- and the honest read is "more complicated, not more resolved."**
Growing to the complete 107-subject VIPL pool did three different things
at once: it gave real HR-accuracy visibility into a much wider range of
subject difficulty (good, if sobering), it widened SpO2's true dynamic
range substantially (good, directly addresses the earlier "narrow range"
caveat), and it surfaced at least one clear data-quality outlier plus a
structural LOSO pool-imbalance problem (both new caveats that now need to
be carried forward).

- **HR: the N=18 numbers already looked worse than the original N=8
  numbers (Task F), and the full pool looks worse again.** Pooled CHROM
  MAE keeps climbing (3.83 -> 5.89 -> 9.10bpm as N went 8 -> 18 -> 112);
  RMSE climbs even faster (5.59 -> 8.94 -> 18.00) because a handful of
  genuinely bad estimates (`p48`, `p106`, `p22`, `p21`, `p35`, all with
  30-100bpm+ errors) are now in the pool. This is not a new kind of
  finding, just a continuation of Task F's "the original small-N pooled
  number was flattering, not representative" verdict, now with much more
  data behind it. The low-fps hypothesis was checked and ruled out (see
  Section 4b) -- these are just hard subjects for CHROM/POS/green-only as
  currently implemented, not explained by one identifiable video property.
  CHROM/POS still clearly beat green-only in relative terms, but neither
  should be described as "~4-6bpm accurate" in the report any more --
  9-9.5bpm pooled MAE (and use-with-caution RMSE) is the honest number now.
- **SpO2 still loses to the trivial baseline on MAE (1.852 vs 1.837
  pooled) -- unchanged headline finding, now backed by 112 subjects
  instead of 18.** The gap is much smaller in relative terms than before
  (1.5 hundredths vs. baseline, vs. a clearer ~4% gap at N=18), but it's
  still on the wrong side, and RMSE should not be used to argue otherwise
  given Section 4a's outlier finding.
- **The per-dataset centering fix is now essentially inert** (pooled MAE
  1.851 centered vs. 1.852 raw vs. 1.837 baseline -- all three are within
  0.02 of each other). This continues Task F's trend: centering helped a
  lot at N=8, helped much less at N=18, and now makes almost no
  difference at N=112. With VIPL now 107 subjects against UBFC's fixed 5,
  the pooled fit is so VIPL-dominated that "removing the cross-dataset
  offset" barely changes anything, because the dataset-level distinction
  is nearly drowned out by within-VIPL variation itself. **Centering
  should not be presented as a working fix at this scale.**
- **VIPL's SpO2 dynamic range and R range both widened dramatically**
  (SpO2_true 94.9-98.8% at N=13 -> 44-99% at N=107; R 0.82-1.38 at N=13
  -> 0.49-4.21 at N=107) -- but this widening is now confirmed to be
  partly a data-quality artifact (the `p25` point) rather than purely
  "more real physiological range," so it should not be cited uncritically
  as "the dynamic-range problem is fixed." The genuine widening (excluding
  `p25`) is real but more modest than the raw min/max suggests.
- **New finding not visible at any earlier N: the UBFC/VIPL pool
  imbalance itself is now a methodological caveat**, per Section 4c --
  "UBFC only" LOSO numbers at N=112 measure something different from what
  they measured at N=8/18, and the apparent sign flip in UBFC's r should
  not be reported as an improvement.

**Bottom line for the report:** SpO2 calibration remains unresolved --
if anything, more clearly unresolved, since it still loses to the trivial
baseline at 8x the data, and two new caveats (the `p25` outlier and the
UBFC/VIPL imbalance) now need to be disclosed alongside the original
cross-dataset-offset and thin-range findings. HR should be reported with
the full-pool numbers (CHROM ~9.1bpm pooled MAE, r=0.31) rather than any
earlier smaller-N figure -- the algorithm choice (CHROM/POS over
green-only) is still justified in relative terms, but the absolute
accuracy claim for the report needs to come down significantly from the
early small-sample numbers. If the report wants a defensible, less noisy
absolute-accuracy claim, USE MAE, not RMSE, and consider explicitly
disclosing the `p25` SpO2 ground-truth anomaly rather than letting it
silently inflate RMSE.

## Task H -- Worst-error diagnosis, documented p25 exclusion, and
stratified SpO2 LOSO (2026-08-08 session, follow-up to Task G)

Three follow-ups on top of Task G's full-107-subject-VIPL pool (N=112),
done without touching any Segment 2-5 algorithm file, either VIPL loader,
or the existing behavior of `runLOSO.m`/`centerRPerDataset.m`/
`computeMetrics.m`/`blandAltman.m`. New files only: `matlab/src/
validation/runLOSOStratified.m`, `matlab/scripts/run_segment6_task_h.m`
(a new driver, calls the existing unmodified `runLOSO.m`/`computeMetrics.m`
plus the new stratified function), `results/metrics/
segment6_spo2_with_p25.csv`, `results/metrics/
segment6_spo2_excluding_p25.csv`, `results/metrics/
segment6_spo2_stratified_metrics.csv`, and this section.

### H1. Worst-5 HR-error subjects, confirmed against the real N=112 pool

Sorted the real, current pooled HR data (`segment4_hr_summary.csv` +
`segment4_hr_summary_vipl.csv`, all 112 valid-ground-truth rows) by
`abs_error_chrom` descending. **The real top 5 confirms Task G's own
passing mention exactly -- no correction needed:**

| Rank | Subject | Scenario/source | CHROM abs error | HR_chrom | HR_groundtruth |
|---|---|---|---|---|---|
| 1 | `p48` | v1/source1 | 101.58 bpm | 182.55 | 80.97 |
| 2 | `p106` | v1/source2 | 74.23 bpm | 150.32 | 76.09 |
| 3 | `p22` | v1/source1 | 65.53 bpm | 112.53 | 47.00 |
| 4 | `p21` | v1/source1 | 59.20 bpm | 127.20 | 68.00 |
| 5 | `p35` | v1/source1 | 55.83 bpm | 133.51 | 77.68 |

All five are `v1` ("Stable: seated naturally, 1m from camera, ceiling
lamp on" per `VIPL_DATA_FORMAT.md` Section 2 / the ReadMe's own scenario
table) -- these are not the harder motion/dark/exercise scenarios, they
are supposedly the *easiest* condition, which makes the size of these
errors more notable, not less. Only `p106` is one of the 12 subjects
(`p84`, `p97`-`p107`) that fell back to `v1/source2` (phone camera, no
`time.txt`) because `v1/source1` is listed missing in `Missing_data.txt`
(confirmed: `p106/v1/source1` is on line 94 of that file); the other four
(`p48`, `p22`, `p21`, `p35`) all used the normal `v1/source1` webcam path.

**Per-subject diagnosis (face+ROI overlay + FFT spectrum PNGs, viewed
directly):**

- **`p48`** (`results/figures/VIPL_p48_v1_source1_roi_sanity.png` /
  `..._heartrate_sanity.png`): ROI overlay is correct -- clean forehead
  skin crop, no hair or background pixels inside the green box. The FFT
  spectrum is the problem: broad, scattered energy across ~0.7-3.5Hz with
  no single clean dominant peak, and CHROM locks onto a spurious peak
  near 3.05Hz (182.6bpm) while the true rate (80.97bpm = 1.35Hz) is
  buried in the noise floor, not a visible local maximum. Green-only
  (which usually performs far worse than CHROM/POS pooled) happens to
  land close to the true peak here (83.3bpm) by what looks like luck
  given how noisy its own spectrum is too -- this is a signal-quality
  failure, not an ROI-placement failure.
- **`p106`** (`VIPL_p106_v1_source2_*`): ROI overlay is mostly correct --
  forehead box sits on skin, glasses excluded below the box -- with a
  minor amount of hairline included at the very top edge of the green
  box, not severe. FFT spectrum is scattered with no clean peak; CHROM
  picks ~2.49Hz (150.3bpm) against a true rate of 76.09bpm (1.27Hz).
  Being the phone-camera fallback source (no `time.txt`, fps taken as-is
  from the container per `VIPL_DATA_FORMAT.md` Section 4 Finding 2) is a
  plausible contributing factor here specifically, but the ROI crop
  itself is not visibly at fault.
- **`p22`** (`VIPL_p22_v1_source1_*`): ROI overlay is correct, box sits on
  forehead skin above the glasses. FFT spectrum is scattered with several
  comparable-height peaks; CHROM/POS both lock onto ~1.87Hz (112.5bpm).
  Worth flagging separately: the ground-truth rate itself (47bpm) is
  unusually low for a seated, awake subject in a "stable" scenario --
  this doesn't excuse the pipeline's 65.5bpm error, but an atypical true
  HR sitting at the edge of the algorithm's effective range is a
  plausible secondary contributor alongside the noisy spectrum.
- **`p21`** (`VIPL_p21_v1_source1_*`): ROI overlay is correct, clean
  forehead crop. **This one is informative rather than a plain failure:**
  POS actually lands almost exactly on the true rate (68.84 vs GT 68bpm)
  from the same pixel data, while CHROM locks onto a different peak at
  2.13Hz (127.2bpm) -- roughly double POS's/the true ~1.15Hz peak, i.e. a
  harmonic-confusion pattern, not a face/ROI problem. This shows the two
  combination methods can diverge sharply on the same signal even when
  the crop is clean.
- **`p35`** (`VIPL_p35_v1_source1_*`): ROI overlay is correct with the
  same minor hairline-at-the-top-edge pattern seen in `p106`, not severe.
  FFT spectrum scattered, no clean single peak; CHROM and POS both lock
  onto the same spurious ~2.22Hz peak (133.5bpm) this time (unlike `p21`,
  where they disagreed), while green-only finds yet another, different
  wrong peak (~1.02Hz, 61.3bpm). None of the three methods find the true
  peak (77.68bpm = 1.30Hz) as the dominant spectral feature.

**Overall pattern across the 5:** every ROI overlay is a genuinely
correct forehead skin crop -- **this is a pulse-signal/FFT-peak-selection
problem in all five cases, not a face-detection or ROI-placement bug.**
The FFT spectra are consistently scattered/ambiguous (broad energy across
the whole physiological band, not one clean dominant peak at the correct
frequency), and CHROM in particular keeps locking onto a plausible-looking
but wrong peak rather than the true one. `p21` additionally shows CHROM
and POS can disagree substantially on which peak is "the" peak even for
one identical, well-cropped signal.

**Source2-cluster check:** of the 12 `v1/source2` fallback subjects
(11.2% of the 107-subject VIPL pool), exactly **1 of 5** worst-error
subjects (`p106`) is in that cluster -- 20% vs. an 11.2% base rate.
**This does not look like a real pattern.** With only 5 worst-case
subjects to look at, seeing at least 1 source2 subject by pure chance
already has close to even odds (a binomial draw of 5 subjects from a pool
where 11.2% are source2 has a ~45% chance of including at least one
source2 subject even with no relationship at all between source and
error). One out of five is exactly what "no disproportionate
representation" looks like at this sample size, not evidence the source2
fallback path is worse -- it would take many more worst-case subjects
before a count like this could be read as a real signal either way.

### H2. `p25` SpO2 outlier -- documented exclusion, both numbers reported

**Exclusion justification (stated explicitly, not just "it was an
outlier"):** `p25`'s `gt_SpO2.csv`
(`spandan/data/raw/VIPL-HR/p25/v1/source1/gt_SpO2.csv`) contains a
constant value of **44% across all 31 samples** (verified directly --
`sort | uniq -c` on the real file gives exactly one distinct data value,
44, for all 31 rows). A sustained SpO2 of 44% is not a plausible
physiological reading for a resting, conscious, seated subject -- SpO2 in
that range is associated with severe, typically unsurvivable-without-
intervention hypoxemia, and the fact that it is *exactly* constant across
every single one of 31 samples (real pulse oximeters show sample-to-sample
jitter even in a stable subject) is itself inconsistent with a working
sensor tracking a real physiological signal. This is far more consistent
with a **sensor/contact fault during that specific recording** (e.g. the
oximeter probe not properly seated, or the device outputting a fixed
error/fallback code that happens to look like a plausible-shaped number)
than with a real, if extreme, SpO2 event -- this is the reasoning for
flagging it, not merely that it is numerically far from the rest of the
pool.

Recomputed the pooled SpO2 metrics (raw, baseline, centered -- all three
existing `runLOSO.m` output paths) twice, via the new `run_segment6_task_h.m`
driver calling the unmodified `runLOSO.m`/`computeMetrics.m`, saved side
by side rather than silently dropping `p25` from the main results:

**With `p25` included** (`segment6_spo2_with_p25.csv` -- matches the
existing, unmodified `segment6_spo2_loso_metrics.csv`/`_baseline_/
_centered_` numbers exactly, confirming this is genuinely the same
pipeline, not a new computation):

| Metric type | Scope | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|---|
| raw | pooled | 112 | 1.8519 | 5.3125 | -0.3812 |
| raw | UBFC | 5 | 0.9165 | 1.3424 | +0.0542 |
| raw | VIPL | 107 | 1.8956 | 5.4274 | -0.3833 |
| baseline | pooled | 112 | 1.8373 | 5.3085 | -1.0000* |
| centered | pooled | 112 | 1.8511 | 5.3124 | -0.3016 |

**With `p25` excluded** (`segment6_spo2_excluding_p25.csv`, N drops by
exactly 1 in the pooled/VIPL rows, UBFC unaffected since `p25` is VIPL):

| Metric type | Scope | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|---|
| raw | pooled | 111 | 1.2782 | 1.7350 | -0.1774 |
| raw | UBFC | 5 | 0.9793 | 1.1224 | -0.9354 |
| raw | VIPL | 106 | 1.2923 | 1.7586 | -0.1768 |
| baseline | pooled | 111 | 1.2605 | 1.7172 | -1.0000* |
| centered | pooled | 111 | 1.2781 | 1.7344 | -0.1842 |

(*baseline r is the same LOSO arithmetic artifact documented in Task D
Section 2 -- not a real correlation, at either N.)

**Reading both together:** RMSE is the metric `p25` dominates, exactly as
Task G Section 4a already found -- pooled RMSE drops from 5.3125 to
1.7350 (a 67% reduction) by removing one subject, confirming RMSE should
never be quoted for this SpO2 pool without this caveat. MAE moves too,
but far less dramatically in relative terms (1.8519 -> 1.2782, still a
real drop since `p25`'s 52.95pp error is large even in absolute terms,
but MAE was never the metric being silently distorted the way RMSE was).
**The real calibration still loses to the trivial baseline either way**
(pooled MAE 1.8519 vs baseline 1.8373 with `p25`; 1.2782 vs 1.2605
without) -- excluding the outlier does not flip this headline finding,
it only removes the RMSE distortion. One more notable shift: UBFC's raw
Pearson r flips from +0.0542 (with `p25`) to -0.9354 (without) -- because
`p25` was part of the shared training pool for every UBFC fold under
pooled LOSO, removing it changes UBFC's fold predictions even though
`p25` itself is a VIPL subject. This is itself a preview of the pool-
contamination issue H3 addresses directly.

### H3. Stratified (within-dataset-only) SpO2 LOSO -- isolates real
within-dataset generalization from the pool-imbalance artifact

**Why this was needed:** Task G Section 4c already flagged that at
N=112 (107 VIPL vs. 5 UBFC), every UBFC LOSO fold trains on ~96% VIPL
data under the existing pooled `runLOSO.m`, so "UBFC only" metrics no
longer measure UBFC-specific generalization -- they mostly measure how a
VIPL-dominated fit happens to perform on UBFC's 5 subjects. New file
`matlab/src/validation/runLOSOStratified.m` fixes this by restricting
each fold's training set to subjects from the SAME dataset only (UBFC
held-out subjects train on the other 4 UBFC subjects; VIPL held-out
subjects train on the other 106 VIPL subjects) -- `runLOSO.m` itself is
untouched, this is a new, separate function reusing the same unmodified
`calibrateSpO2.m`.

Results (`segment6_spo2_stratified_metrics.csv`, full N=112 pool
including `p25`, since `p25` is a VIPL subject and does not affect the
UBFC stratified fold at all):

| Scope | N | MAE | RMSE | Pearson r | Reliability |
|---|---|---|---|---|---|
| UBFC | 5 | 1.9683 | 2.1857 | -0.8415 | **THIN -- trains on only 4 subjects/fold, directional signal only, not a reliable number** |
| VIPL | 107 | 1.9078 | 5.4303 | -0.3333 | thin-data-safe -- trains on ~106 subjects/fold |

**Stratified vs. pooled-cross-contaminated comparison (both from the
full N=112 pool, `p25` included in both):**

| Scope | Pooled (cross-dataset training) MAE / r | Stratified (within-dataset only) MAE / r |
|---|---|---|
| UBFC (N=5) | 0.9165 / **+0.0542** | 1.9683 / **-0.8415** |
| VIPL (N=107) | 1.8956 / -0.3833 | 1.9078 / -0.3333 |

**This confirms Task G Section 4c's suspicion directly, not just as a
hypothesis anymore.** UBFC's pooled number looked deceptively good
(lower MAE, and the only positive Pearson r anywhere in the SpO2 results)
specifically *because* its LOSO folds were borrowing ~106 VIPL training
points; once restricted to genuinely training only on the other 4 UBFC
subjects, UBFC's error roughly doubles (0.92 -> 1.97 MAE) and its
correlation flips back to strongly negative (+0.05 -> -0.84) -- the same
wrong-signed pattern seen everywhere else in this investigation. **UBFC's
+0.054 pooled Pearson r should not be cited as evidence the calibration
works for UBFC; the stratified -0.841 is the more honest (if very thin,
N=5-training-on-4) read.** VIPL's stratified number, by contrast, is
barely different from its pooled number (MAE 1.8956 vs 1.9078, r -0.3833
vs -0.3333) -- expected, since VIPL already dominates its own pooled
folds (~99% VIPL) almost as much as the stratified version (~99% VIPL by
construction), so stratification mostly just removes the small UBFC
contribution VIPL folds had access to. VIPL's stratified number is the
one worth trusting at this N; UBFC's should be reported as directional
only, per the CSV's own `reliability_note` column.

**HR needs no equivalent fix -- stated explicitly so this isn't
mis-read as a gap.** `heartrate/fftHeartRate.m` has no fitted parameter
at all (a direct FFT peak read), so there is nothing for one subject's
data to leak into when estimating another subject's HR, pooled or not.
The existing per-dataset HR breakdown in `segment6_hr_pooled_metrics.csv`
already evaluates each dataset's own subjects directly and independently
-- it was never subject to the training-pool-contamination problem that
motivated this stratified SpO2 fix, and does not need a stratified
counterpart.

### Updated bottom-line paragraph for the report (supersedes Task G's,
folds in H1-H3)

**SpO2 calibration remains unresolved, and the stratified check makes
the case stronger, not weaker.** Every angle checked in Tasks D-H point
the same direction: the real R-based calibration loses to a trivial
"guess the training mean" baseline at every N tried (8, 18, 112, and
both with and without the `p25` outlier); the wrong-sign correlation
persists under raw pooling, per-dataset centering, and now under a true
within-dataset stratified LOSO; and the one scope that looked like an
improvement (UBFC's positive pooled r) turns out to be a pool-imbalance
artifact that reverses to strongly negative once measured honestly. The
`p25` ground-truth anomaly (a constant, implausible 44% SpO2, almost
certainly a sensor/contact fault, not a pipeline bug) inflates RMSE by
~3x and should always be disclosed and reported alongside MAE, which is
far more stable to its presence or absence. HR, separately, is
unaffected by any of this session's findings: `p25` is a SpO2-only
ground-truth field (its HR ground truth, 65-73bpm, is normal), the
stratified fix does not apply to HR at all, and the worst-5 HR-error
diagnosis found a genuine signal-quality/FFT-peak-selection limitation
(scattered spectra, no clean dominant peak) rather than any face
detection, ROI cropping, or data-source (source1 vs. source2) problem --
the source2 fallback cluster is not disproportionately represented among
the worst HR errors at this sample size. For the report: present SpO2 as
an open, well-diagnosed problem (cross-dataset R offset, near-zero true
SpO2 variance, one confirmed ground-truth outlier, and now a confirmed
pool-imbalance artifact in the UBFC breakdown specifically), and present
HR's ~9.1bpm pooled CHROM MAE as a real but imperfect result with
concrete evidence that CHROM/POS's remaining error is dominated by a
handful of ambiguous-spectrum subjects rather than a systematic pipeline
bug.

## Task I -- Is CHROM/POS disagreement a useful low-confidence signal at
the full N=112 pool? (2026-08-08 session, follow-up to Task H1)

Task H1 found one informative anecdote: on `p21`, POS read the true rate
almost exactly (68.84 vs GT 68bpm) while CHROM locked onto a harmonic
(127.20bpm, roughly double). This task tests whether CHROM/POS
disagreement generalizes as a low-confidence signal across the full pool,
not just that one subject. Done without touching any Segment 2-5
algorithm file or recomputing any HR estimate. New files only:
`matlab/src/validation/computeAgreementConfidence.m` (generic per-subject
`abs(HR_chrom - HR_pos) / mean([HR_chrom, HR_pos])`, no hardcoded
threshold), `matlab/scripts/run_segment6_task_i_agreement.m` (driver,
calls the existing unmodified `computeMetrics.m`), `results/metrics/
segment6_hr_agreement_flags.csv`, and this section.

### 1. Distribution and threshold justification

Across all 112 subjects (both datasets), relative disagreement runs
min=0%, median=0%, max=90.08%. Histogram:

| Bucket | Count |
|---|---|
| 0-5% | 83 |
| 5-10% | 9 |
| 10-15% | 3 |
| 15-20% | 4 |
| 20%+ | 13 |

77 of 112 subjects (69%, including all 5 UBFC subjects) have `HR_chrom`
exactly equal to `HR_pos` -- reported as-is from the real data, not
altered by this task. The sorted non-zero disagreement values were
scanned for the largest gaps: the single largest gap (30.53 percentage
points) sits right above 59.54% and isolates only one subject
(`p106`) by itself -- too small a rule (N=1) to generalize a threshold
from. The **second-largest gap (9.69 percentage points) sits right above
29.27%** and is a genuine cluster separator, not a lone-outlier artifact:
below it, disagreement values climb fairly continuously from the 0%
floor up through the 20s; above it, 8 subjects sit isolated in a sparse
tail from 38.96% to 90.08%. **Chosen threshold: 29.27% relative
disagreement**, taken directly from this second-largest-gap boundary, not
picked in advance. This flags 8 of 112 subjects (7.14%) low-confidence.

### 2. Does disagreement actually predict error?

Pearson r between `relative_disagreement` and `abs_error_chrom` across
all 112 subjects: **+0.588** -- a real, moderate positive relationship.
Higher CHROM/POS disagreement genuinely does predict higher CHROM error
at this pool size; it is not noise.

### 3. Worst-5 overlap (Task H1 subjects: `p48`, `p106`, `p22`, `p21`, `p35`)

| Subject | Relative disagreement | Flagged? |
|---|---|---|
| `p48` | 38.96% | **YES** |
| `p106` | 90.08% | **YES** |
| `p22` | 0% | no |
| `p21` | 59.54% | **YES** |
| `p35` | 0% | no |

**Overlap: 3 of 5.** The metric catches every worst-5 subject where CHROM
and POS actually disagree on which peak is "the" peak (`p48`, `p106`,
`p21` -- matching the `p21` pattern that motivated this task). It misses
`p22` and `p35` entirely, because in both of those cases CHROM and POS
**agree with each other on the same wrong peak** (Task H1's own
per-subject FFT diagnosis: `p22` both lock onto ~112.5bpm against a
47bpm true rate; `p35` both lock onto ~133.5bpm against a 77.68bpm true
rate) -- correlated errors that a two-method-agreement signal cannot see
by construction, no matter where the threshold is set.

### 4. Confidence-gated accuracy vs. full-pool accuracy

Excluding the 8 flagged subjects (7.14% of the pool, leaving N=104):

| Method | Scope | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|---|
| CHROM | Full pool | 112 | 9.0969 | 18.0047 | 0.3145 |
| CHROM | Confidence-gated | 104 | 6.5407 | 11.7796 | 0.4951 |
| POS | Full pool | 112 | 8.6795 | 16.4537 | 0.2809 |
| POS | Confidence-gated | 104 | 6.9863 | 12.4336 | 0.4393 |

Excluding a 7.1%-of-pool tail cuts CHROM's MAE by 28% (9.10 -> 6.54) and
RMSE by 35% (18.00 -> 11.78), and pushes Pearson r from a weak 0.31 to a
moderate 0.50. POS improves similarly (MAE 8.68 -> 6.99, r 0.28 -> 0.44).
A real, meaningfully-sized improvement for a modest exclusion cost --
consistent with the correlation in Section 2, not a separate finding.

### 5. Full-pool CHROM vs. POS head-to-head

`segment6_hr_pooled_metrics.csv` only reports each method against ground
truth separately; computed directly here for the first time:

| Comparison | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| CHROM vs. POS (each other) | 112 | 6.1299 | 16.5122 | 0.5471 |
| CHROM vs. ground truth | 112 | 9.0969 | 18.0047 | 0.3145 |
| POS vs. ground truth | 112 | 8.6795 | 16.4537 | 0.2809 |

At the full pool, **POS has the lower MAE/RMSE against ground truth** --
the same direction as the `p21` anecdote, so that specific pattern does
generalize to the pool level, not just that one subject. But Section 4's
confidence-gated numbers add a sharper detail: on the subset where CHROM
and POS mostly agree (the 104 not-flagged subjects), **CHROM actually
beats POS** (MAE 6.54 vs 6.99, r 0.50 vs 0.44) -- it is specifically the
high-disagreement tail that drags CHROM's full-pool numbers below POS's,
not a general POS-over-CHROM superiority. Both readings are true at
once: POS is the safer default across the whole pool, while CHROM is
the (slightly) more accurate one wherever the two methods already agree.

### 6. Verdict: is this signal worth porting to the Android app?

**Yes, as a genuine but partial low-confidence flag -- not as a complete
confidence measure, and that limitation should travel with it.** The
correlation (r=+0.588) and the confidence-gated improvement (Section 4)
are real, not cherry-picked from the `p21` anecdote: they hold across the
full 112-subject pool, at a threshold derived from an actual gap in the
data rather than a round number chosen in advance. The Android app
currently computes POS but only logs/displays CHROM as primary; flagging
the ~7% of readings where the two disagree by more than ~29% would cost
nothing extra to compute (POS is already being run) and would correctly
flag 3 of the 5 worst HR-error cases seen in this dataset. But Section 3
is the caveat that must not get lost in translation: this signal is
structurally blind to the failure mode where CHROM and POS agree on the
same wrong answer (`p22`, `p35` -- a scattered/ambiguous FFT spectrum
both methods lock onto similarly), which is exactly half of the worst-5
cases here. **The `p21` case is representative of one real failure mode,
not the only one** -- CHROM/POS disagreement should be shipped as one
input to a confidence indicator, not sold as "if the app doesn't flag
this reading, it's accurate."

## Task J -- Building and validating a CHROM/POS switching estimator on
Task I's threshold (2026-08-08 session, follow-up to Task I)

Task I established that CHROM/POS relative disagreement predicts CHROM
error and derived a data-driven 29.27% threshold. This task turns that
finding into an actual estimator -- switch to POS when disagreement
crosses the threshold, otherwise keep CHROM -- and validates it. Done
without touching any Segment 2-5 algorithm file or recomputing any HR
estimate. New files only: `matlab/src/validation/
computeSwitchingEstimate.m` (per-subject switch, threshold passed in
explicitly by the caller rather than hardcoded, sourced from Task I's
stored 29.27% value), `matlab/scripts/run_segment6_task_j_switching.m`
(driver, calls the existing unmodified `computeMetrics.m`), `results/
metrics/segment6_hr_switching_metrics.csv`, `docs/
Android_HR_Switching_Port_Spec.md`, and this section.

### 1. Switching estimator

`computeSwitchingEstimate.m` recomputes `relative_disagreement` the same
way `computeAgreementConfidence.m` does (`abs(HR_chrom - HR_pos) /
mean([HR_chrom, HR_pos])`), then per subject: `relative_disagreement <
0.2927` keeps `HR_chrom`, `relative_disagreement >= 0.2927` switches to
`HR_pos`. At the full N=112 pool, the switch fires for **8 of 112
subjects (7.14%)** -- the same 8 subjects Task I's `low_confidence_flag`
already isolated, as expected since both use the same threshold on the
same disagreement values.

### 2. Full-pool validation (same caveat as Task I: not an out-of-sample test)

**This evaluation uses the SAME 112-subject pool the 29.27% threshold
was derived from in Task I. It is not a clean out-of-sample validation
of the switching rule and should be read as "on this pool," not as a
generalizable guarantee.**

| Method | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| CHROM alone | 112 | 9.0969 | 18.0047 | 0.3145 |
| POS alone | 112 | 8.6795 | 16.4537 | 0.2809 |
| **Switched** | 112 | **8.2658** | **16.0007** | **0.3246** |

The switched estimator beats both individual methods on every metric
simultaneously at this pool: MAE improves 9.2% over CHROM alone (9.10 ->
8.27) and 4.8% over POS alone (8.68 -> 8.27); RMSE and Pearson r move
the same direction. This is a real, if pool-bound, improvement -- not
just splitting the difference between the two inputs.

### 3. Failure-mode check: does switching ever make things worse?

Aggregate improvement can hide individual regressions, so every one of
the 8 subjects where the switch fired was checked individually
(`abs_error_chrom` vs. `abs_error_pos` for that specific subject):

| Subject | abs\_error\_chrom | abs\_error\_pos | Outcome |
|---|---|---|---|
| `p10` | 10.6709 | 39.1734 | HURT |
| `p21` | 59.2012 | 0.8383 | HELPED |
| `p29` | 30.9489 | 5.5709 | HELPED |
| `p48` | 101.5832 | 42.0554 | HELPED |
| `p54` | 9.6456 | 25.4204 | HURT |
| `p96` | 28.1271 | 98.3423 | HURT |
| `p98` | 24.2197 | 15.0062 | HELPED |
| `p106` | 74.2255 | 19.1289 | HELPED |

**5 of 8 switched subjects (62.5%) were genuinely helped** (POS error
lower than CHROM error), and **3 of 8 (37.5%) were hurt** (POS error
higher than CHROM error) -- 0 ties. "Disagree -> use POS" is reliably
the better call *on average* at this pool size, not individually correct
every time it fires. The net pool-level MAE/RMSE/r improvement in
Section 2 is real, but it is an average outcome across 8 subjects with 3
individual regressions inside it, not a guarantee for any single
switched reading.

### 4. Verdict

The switching estimator is a genuine, measurable improvement over either
single method at the full pool (Section 2), built directly on Task I's
already-validated disagreement signal, with no new algorithm or
recomputed HR value involved. It inherits Task I's structural blind spot
(cannot catch `p22`/`p35`-style cases where CHROM and POS agree on the
same wrong peak) and adds one more caveat of its own: even within the
subjects it does act on, it helps roughly 5 times out of 8 and hurts the
other 3 (Section 3) -- a net-positive average, not a per-subject
guarantee. See `docs/Android_HR_Switching_Port_Spec.md` for the
self-contained implementation spec, including both caveats stated for a
reader who has not seen this MATLAB analysis.

## Bottom Line -- as of Task J

**HR:** the best current estimator is the Task J switching rule (CHROM
below 29.27% CHROM/POS relative disagreement, POS at/above it), reaching
**MAE 8.27 bpm, RMSE 16.00 bpm, Pearson r 0.32 across the full N=112
pool** -- a real improvement over CHROM alone (9.10 bpm MAE) and POS
alone (8.68 bpm MAE), but measured on the same pool the 29.27% threshold
was derived from, not an independent holdout, and known to help roughly
5 times out of 8 among the subjects it actually switches (3 individual
regressions accepted for the net gain). **SpO2:** no validated
calibration signal exists in any single dataset or split checked so far
(raw pooled, per-dataset centered, stratified-by-dataset LOSO, with and
without the `p25` outlier all tested) -- the real R-based calibration
loses to a trivial "guess the training mean" baseline everywhere it has
been tried, and this thread is now paused pending a real oximeter
ground-truth source rather than continuing to re-slice the existing
thin/noisy data. **Two open threads remain, tracked separately:** (1)
the worst-error HR subjects trace to an FFT-peak-selection/ambiguous-
spectrum issue in `heartrate/fftHeartRate.m`'s peak read, not a face
detection, ROI, or data-source problem -- a candidate for a future
peak-selection refinement, not addressed by the switching rule where the
two methods agree on the wrong peak; (2) the Android app's separately-
reported clustered instability is a distinct investigation from this
MATLAB-side analysis and is not resolved by anything in Tasks G-J. This
paragraph is written to be quoted directly into the project report.
