# Segment 27 — Branch 2 and SpO2 under wavelet denoising: PREREGISTRATION

Registered 2026-09-20, committed BEFORE any computation. **Nothing in this segment has been run.** (The Segment 27 number is reused: the mechanism-isolation Segment 27 mentioned in SESSION_HANDOFF.md was designed but never run.)

## Why this exists
`pipeline/estimateVitalsAndMorphology.m` now applies `filtering/waveletDenoise.m` (db4, 3-level) before `detrendSignal` by default (commit `87a9b34`). Two consequences were deliberately left unevaluated, not assumed neutral or beneficial:

* **Item A — Branch 2 (notch).** The frozen `results/metrics/segment7_task_b_notch_branch2.csv` was written by `scripts/run_segment7_task_b_branch2_batch.m`, an independent pipeline copy that never had wavelet denoising. It is a valid baseline for that code path. Only Branch 1 was ever validated under wavelet.
* **Item B — SpO2.** The frozen `segment5_dataset1_calibration.csv` / `segment5_vipl_calibration.csv` R values (112/112) are pre-wavelet, and `spo2/calibrateSpO2.m`'s A/B were fit on them. The orchestrator's SpO2 path is therefore pinned to the pre-wavelet chain. Whether wavelet helps or hurts SpO2 is open.

## Item A — Branch 2 notch under wavelet
* **Script:** new `scripts/s27_branch2_wavelet.m` = a copy of `run_segment7_task_b_branch2_batch.m` with exactly one change: `R = waveletDenoise(R); G = ...; B = ...;` inserted immediately before the three `detrendSignal` calls (the same position and in-place reassignment as the orchestrator, so the raw arguments of `chromCombine` are the denoised signal too). The original script and frozen CSV are not modified.
* **Output:** `results/s27_branch2_wavelet.csv` inside this experiment folder, same columns as the frozen CSV. NOT written to `results/metrics/` and never under the frozen name.
* **Subjects/conditions:** the same 5 UBFC ground-truth subjects; conditions `adaptiveHarmonic` and `confidenceGate` (the promoted default). `tiledROI` uses per-tile extraction where the wavelet placement is ambiguous, so it is excluded and reported as such.
* **Metric:** per-subject notch confidence and the "confident" pass count, using the definition already behind the project's "4/5 vs 1/5" figure (Segment7_Task_B_Notch_Quantification.md, ~line 193): confidence ≥ 0.3. The frozen per-subject values are read from the frozen CSV at run time, not retyped. Parity gate first: the copy with the wavelet line disabled must reproduce the frozen CSV row for row at the CSV's own precision, otherwise stop.
* **Decision rules (fixed now):**
  * **Neutral/beneficial:** pass count ≥ the frozen count for `adaptiveHarmonic` AND no subject that passed before falls below 0.3.
  * **Harmful:** pass count drops by ≥ 1, or any previously passing subject falls below 0.3.
  * Otherwise mixed, reported per subject. N = 5, so this is descriptive only; no significance test is claimed.
* **Consequence if harmful:** the orchestrator gains a Branch-2 pin analogous to the SpO2 pin (Branch 2 reads pre-wavelet R/G/B). If neutral/beneficial: the default stands and the docs citing "4/5 vs 1/5" gain a wavelet-conditional note. Either outcome is a separate, explicitly decided commit.

## Item B — SpO2 under wavelet
* **Script:** new `scripts/s27_spo2_wavelet.m`, no new decode: load each of the 112 cached `*_rgb_traces.mat` (5 UBFC + 107 VIPL), compute R values through the orchestrator with the SpO2 pin bypassed (wavelet chain), i.e. R from `waveletDenoise -> detrend -> bandpass -> ratioOfRatios`. Ground-truth SpO2 comes from the frozen calibration CSVs' `SpO2_true` column (already the pooled labels); pre-wavelet R is regenerated to confirm parity with the frozen CSVs first (must match at `num2str` precision, else stop).
* **Evaluation:** the same leave-one-subject-out protocol as `run_segment6_validation.m` (`validation/runLOSO.m`, both datasets pooled per fold), run twice: (1) pre-wavelet R (must reproduce the existing pooled LOSO metrics), (2) wavelet-on R with `calibrateSpO2` **re-fit on the wavelet R values in each fold** (no reuse of pre-wavelet coefficients). Metrics: MAE, RMSE, Pearson r, and the training-mean-only baseline, pooled and per dataset.
* **Decision rules (fixed now), on pooled N = 112 LOSO MAE, paired per-subject |error| with a two-sided Wilcoxon signed-rank test, α = 0.05, one test:**
  * **Wavelet helps:** MAE(wavelet, refit) < MAE(pre-wavelet) by ≥ 0.10 percentage points AND p < 0.05.
  * **Wavelet hurts:** the reverse.
  * Otherwise **no demonstrated difference**: the pin stays (no change of basis without evidence).
* **Caveat carried in:** SpO2's existing verdict is already weak (Segment 7 Task E). Beating a weak baseline is not evidence that SpO2 is good; the report states the wavelet result relative to the trivial baseline as well. The UBFC/VIPL cross-device R offset is a known confound in both arms equally.
* **Consequence:** only if "wavelet helps" would the SpO2 pin be lifted, with a recalibrated `calibrateSpO2` and a new frozen calibration CSV under a new name (old preserved, per the mark-superseded convention). Otherwise nothing changes.

## Guardrails
* Zero changes to production code, frozen CSVs, or the existing scripts as part of this segment; only new files under `matlab/experiments/segment27_branch2_wavelet_evaluation/`.
* Protected-file SHA-256 BEFORE/AFTER, as in Segments 23-26.
* Not run yet. Executing it is a separate decision.
