# Segment 6 Task R — Phone (source2) SpO2 Device-Centering

Investigates whether Task L's phone-camera (source2) processing already
produced Segment 5 SpO2 outputs as a byproduct, characterizes phone-vs-webcam
R-value distribution the same way Task D/E characterized UBFC-vs-VIPL, and
fits a real, data-backed source2 centering offset using
`validation/centerRPerDataset.m` completely unmodified. No pipeline file
was touched: `spo2/ratioOfRatios.m`, `spo2/calibrateSpO2.m`,
`validation/centerRPerDataset.m`, `validation/runLOSO.m`, and
`validation/computeMetrics.m` are all used exactly as Segment 5/Task E left
them.

## Action 1 — Does the byproduct data already exist?

**Yes — checked first, not assumed. Segment 5 was NOT skipped for phone
video.** `results/metrics/segment5_vipl_calibration_phone_v1.csv` (107
rows) already exists, written by `scripts/run_vipl_phone_v1_batch.m`
(Task L), which calls `ratioOfRatios.m` and `calibrateSpO2.m` as part of
running the full, unmodified Segment 2-5 pipeline on every extracted
v1/source2 video — exactly the same LOSO calibration loop the webcam
pipeline uses. `results/metrics/segment5_vipl_calibration_phone_v8v9.csv`
(211 rows, v8+v9 pooled) exists too. Task L's own report
(`Segment6_Task_L_Phone_Device_Evaluation.md`) never mentions either file
because it only analyzed the HR side of what its own batch scripts
produced.

**A sanity check on the byproduct data's integrity:** 12 of VIPL's 107
subjects (`p97`-`p107` plus `p84`) had no real source1 (webcam) footage at
all and were already using source2 (phone) footage as their v1 fallback
*before* Task L ever ran, sitting inside the older, nominally-webcam
`segment5_vipl_calibration.csv` under `_v1_source2` subject IDs (see
`docs/VIPL_Scenario_Coverage.md` Section 5). Comparing those 12 subjects'
R values in the old CSV against Task L's freshly-recomputed values for the
same subjects: **12 of 12 matched, 0 mismatches** — confirming both were
built from the same cached extraction through the same unmodified
pipeline, not two different runs quietly diverging.

## Action 2 — source2 (phone) vs source1 (webcam) R-value distribution

Following Task D/E's exact style (R range + SpO2_true range per group),
using the genuine `_v1_source1` rows only (95 of the old CSV's 107 rows —
the 12 fallback rows above are excluded from "source1" here so this
comparison is not contaminated by phone data hiding inside the nominally-
webcam file) against the full Task L v1/source2 pool (107 rows):

| Scope | Device | n | R range | Mean R | SpO2_true range |
|---|---|---|---|---|---|
| Full pool | source1 (webcam) | 95 | [0.517, 4.205] | 1.064 | [44%, 99%]* |
| Full pool | source2 (phone) | 107 | [0.487, 3.682] | 0.857 | [44.06%, 103.79%]* |
| Matched subjects only | source1 (webcam) | 95 | [0.517, 4.205] | 1.064 | — |
| Matched subjects only | source2 (phone) | 95 | [0.492, 3.682] | 0.866 | — |

(*Both ranges are contaminated by known VIPL sensor-fault codes — see the
Action 4 section below for the cleaned range; the R-value comparison
itself is unaffected since R is computed independently of the ground-truth
SpO2 label.)

**Same-subject overlap: all 95 genuine source1 subjects also have a
matching v1/source2 row** — Task L extracted phone v1 for the full
107-subject pool, so this is a true paired, same-subject, same-scenario,
different-camera comparison, not two different populations.

**Mean paired (source2 − source1) R difference: −0.198.** Of the 95
matched source2 R values, **91 fall inside source1's own R range** — the
remaining 4 sit outside it. **Verdict: source2 occupies a real but
noticeably narrower and left-shifted R range relative to source1, not a
wildly disjoint one like UBFC-vs-VIPL was in Task D.** Where Task D found
VIPL's R range barely overlapping UBFC's at all (VIPL min 0.823 already
near UBFC's max 0.864), here 91/95 (96%) of the paired phone R values do
land inside the webcam's own range — this is a milder version of the same
device-offset phenomenon Task L already found for HR (source2 MAE ~2x
source1's), not a categorically different or more severe one on the R
axis specifically.

## Action 3 — Fitting a source2-specific centering offset

Pooled all 95 genuine source1 + 107 source2 subjects (n=202) with dataset
labels `'source1'`/`'source2'` and ran the SAME `runLOSO.m` used for
UBFC/VIPL in Task E — `centerRPerDataset.m` is fully generic (built on
`unique(datasetLabels)`, no dataset names hardcoded), so no code change
was needed to point it at phone vs webcam instead of VIPL vs UBFC.

**Full-pool descriptive offset (not a single LOSO-fold value, since
`centerRPerDataset.m` recomputes per fold from training data only, same
leakage-avoidance discipline as Task E):** mean R = 1.064 (source1), 0.857
(source2) → **source2-minus-source1 offset ≈ −0.207.**

**source2-scope LOSO results, all subjects (n=107, includes 2 known
fault-code subjects — see Action 4):**

| Method | n | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| Raw pooled (uncentered, two-device fit) | 107 | 1.9555 | 5.4544 | -0.177 |
| **Per-device centered (this task's new offset)** | 107 | **1.9390** | **5.4448** | -0.107 |
| Trivial baseline (training-mean guess) | 107 | 1.9327 | 5.4410 | -1.000* |
| Webcam-only fit, applied blind to phone (0 phone subjects in training) | 107 | 1.9826 | 5.4110 | 0.055 |

(*baseline r is the same LOSO arithmetic artifact Task D documented —
ignore the correlation column for the baseline row, MAE/RMSE are the
meaningful comparison.)

**Does source2-specific LOSO accuracy beat an uncentered/webcam-blind
baseline? On this raw (fault-contaminated) pool — yes, narrowly, against
two of three comparisons.** Per-device centering's MAE (1.9390) is lower
than both the raw two-device pooled fit (1.9555) and the webcam-only-blind
fit (1.9826), consistent with Task E's own finding that centering is a
real, if modest, improvement. It does **not**, however, beat the trivial
training-mean baseline (1.9327) — the same shortfall Task E already
reported for UBFC/VIPL centering, now reproduced for source2 specifically.

**A cleaner check, excluding known fault-code subjects (see Action 4),
changes this picture:** with `p25` and `p45` removed, centering's MAE
(1.2609) is essentially a wash against the raw uncentered fit (1.2590) —
no longer even a narrow win — while both remain slightly behind the
trivial baseline (1.2535). **Honest read: the fault-contaminated numbers
above made centering look like a small, real win; the cleaner numbers show
that "win" was partly riding on the same sensor-fault outliers Task D/H
already flagged as data-quality artifacts, not a robust phone-specific
effect.** The offset itself (−0.207) is still a real, measured value
either way — R is computed independently of ground-truth SpO2, so the
fault codes (which are ground-truth SpO2 label errors, not R errors) do
not contaminate the offset's derivation, only the accuracy comparison that
uses it.

## Fault-code check (new finding, not previously documented)

Same physiologically-implausible-value check this project already applies
to `p25` (constant 44% SpO2, `docs/Segment6_Refinement_Notes.md` Task H2):
values outside a 50-100% band are VIPL sensor fault codes, not real SpO2.

| Subject | SpO2_true | Status |
|---|---|---|
| `VIPL_p25_v1_source1` | 44% | Already documented (Task H2) |
| `VIPL_p25_v1_source2` | 44.06% | Already documented, now confirmed present in the phone data too |
| **`VIPL_p45_v1_source2`** | **103.79%** | **NOT previously documented — found here for the first time.** Task L never analyzed the SpO2 side of its own batch output, so this fault code sat unflagged in `segment5_vipl_calibration_phone_v1.csv` since Task L ran. |

Same reporting discipline as the project's existing `p25` precedent
(`segment6_spo2_with_p25.csv` / `segment6_spo2_excluding_p25.csv`): both
numbers are reported above (Action 3's table), not silently dropped.

## Action 4 — Explicit scope statement

**Cleaned (fault-codes excluded) SpO2_true range across both devices:
87.28% – 99%.** This confirms the task brief's expectation directly:
**this task does NOT widen the observed SpO2 range.** It remains the same
narrow-band signal documented throughout this project (Task D's
near-zero-true-variance diagnosis, Task E's follow-up, `p25`'s known
constant-fault ground truth). What this task adds is not more SpO2 range
to learn from — it is a **real, data-backed source2 centering offset
(−0.207 mean R, phone relative to webcam)** in place of what would
otherwise have been an invented, unvalidated session-relative assumption
at demo time. Whether that offset meaningfully improves phone-specific
SpO2 accuracy is genuinely mixed (a narrow win on the raw pool, a wash
once fault-code subjects are excluded) — reported plainly as such above,
not oversold as a fix.

## Outputs

- `matlab/scripts/run_task_r_phone_spo2_centering.m` — Actions 1-4.
- `results/metrics/segment6_task_r_source_R_comparison.csv` — R-value/SpO2_true range stats, full pool and matched-subject scopes, per device.
- `results/metrics/segment6_task_r_source2_spo2_metrics.csv` — source2-scope MAE/RMSE/Pearson r for raw pooled, per-device centered, trivial baseline, webcam-only-blind, and the same four (minus webcam-blind) re-run excluding fault-code subjects.
- No new `.mat` or pipeline files — this task reuses `results/metrics/segment5_vipl_calibration.csv` and `results/metrics/segment5_vipl_calibration_phone_v1.csv`, both pre-existing Task L byproducts.
