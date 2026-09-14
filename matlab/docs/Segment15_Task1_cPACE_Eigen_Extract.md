# Segment 15 Task 1 — cPACE Stage 2: Eigenvector-Based Cardiac Extraction

Run 2026-09-13/14. Builds `pulseextraction/cpaceEigenExtract.m`, the second
stage of Kaur, Lakshminarayanan & Saini's cPACE method (Biomed. Opt.
Express 17(7):3832, 2026, doi:10.1364/BOE.599752), on top of Segment 11
Task 1's Stage 1 (`cpaceProjection.m`, unmodified, reused as-is).

**Headline: implemented and verified against the real paper (not just its
Supplement 1 Table S2), one real ambiguity found and resolved empirically,
one factual error in this task's own brief caught and corrected before
writing any code.**

---

## 0. Two corrections made before implementation, not after

This task's brief cited Supplement 1 Table S2 as giving "exact parameters,
no longer ambiguous" and asserted the eigenvector selection rule is
dominant-eigenvalue-only, "no second candidate... isn't in the paper."
Both the main paper PDF and its Supplement 1 PDF are checked into this
project's `Research Paper/` folder — both were read directly before
writing any code, not assumed from the brief's summary.

**Finding 1 (factual correction to the brief):** Section 4.2 of the actual
paper *does* describe a second candidate — a multi-ROI consensus scheme
choosing between "cPACE-v1" (dominant eigenvector, always) and
"cPACE-absorption" (eigenvector with the larger projection onto the
hemoglobin-absorption direction) by whichever gives higher cross-ROI PLV,
per recording. Table S2 alone only lists "Dominant (largest eigenvalue)"
and is silent on the second candidate — Table S2 alone is incomplete on
this point, and the brief's "isn't in the paper" claim is wrong. **Decision
(asked of the user directly, not assumed): implement dominant-eigenvector-
only, as briefed**, both because it is simpler/auditable and because the
consensus step needs multiple simultaneously-recorded ROIs per subject,
which this project has cached for only a 20-subject VIPL pool, not the
full 100-subject evaluation pool. `cpaceEigenExtract.m`'s own header
carries this same caveat so a future session does not describe its output
as "the full cPACE method" without qualification.

**Finding 2 (segment-numbering correction):** this work was originally
briefed as "Segment 14," but `docs/Segment14_Task1_UBFC_D2_Held_Out_
Validation.md`, `docs/Segment14_Task2_Confidence_Gate_Production_
Promotion.md`, and `SESSION_HANDOFF.md` itself (Current State line 99,
Completed Work Archive, and Changelog all already carry a full,
already-logged Segment 14 entry, dated 2026-09-13) show Segment 14 is
already a completed, different, and already-documented body of work —
held-out UBFC DATASET_2 validation and promoting
`harmonicFilterConfidenceGate.m` to Branch 2's production default. Nothing
was missing from `SESSION_HANDOFF.md` here; the brief's own segment number
was simply stale. This work uses **Segment 15** instead, and
`SESSION_HANDOFF.md`'s changelog gets a new Segment 15 entry alongside the
existing Segment 14 one (not a replacement or backfill of it).

---

## 1. Method actually implemented

`cpaceEigenExtract.m` takes `cpaceProjection.m`'s raw output (Rc, Gc, Bc —
already q̂-projected, exactly zero-mean by construction) and:

1. **Cardiac-band preprocessing**: bandpass to 0.7–3.0 Hz, 4th-order
   zero-phase Butterworth (Table S2's own Stage 1 band/order) — its own
   filter, deliberately NOT `filtering/bandpassClean.m` (which is a
   different band/order, 0.7–4.0 Hz order 2, built for CHROM/POS). Calls
   this `x_c(t)`, the paper's own notation. Table S2's "per-channel mean
   division" normalization is deliberately skipped here — Rc/Gc/Bc are
   already exactly zero-mean from `cpaceProjection.m`, so dividing by
   their own mean would divide by numerical zero, the same reasoning
   `cpaceProjection.m`'s own header already documents for callers.
2. **Seed frequency**: green-channel PSD peak within 0.7–3.0 Hz, single
   FFT over the full recording (Table S2's "Seed source"/"Seed estimation
   FFT length" rows).
3. **Eigen-window bandpass**: `x_c(t)` narrowband-filtered to seed ± `bw`
   Hz (default 0.30, Table S2's "Eigen-window half-width"), 2nd-order
   zero-phase Butterworth — this project's general narrowband convention.
   Calls this `X_bp`.
4. **Covariance**: Σ = (1/T) X_bp' X_bp (paper's Eq. 8), 3×3, rank ≤ 2
   since X_bp has no energy along q̂ by construction.
5. **Eigenvector selection**: dominant eigenvalue only (per §0 above) — no
   consensus voting.
6. **Projection**: `s(t) = v1' * X_bp`, **not** `v1' * x_c(t)` — see §2
   below for why this deviates from a first literal reading of the paper.

## 2. One real ambiguity, found and resolved empirically

The paper's own Section 4.3 states the extracted signal is
`s(t) = v1^T x_c(t)` — naming the *wider* (0.7–3.0 Hz) `x_c(t)`, not the
narrower `X_bp` used for the covariance. A first implementation followed
this literally. **Result on Spandan's real 100-subject pool: HR MAE
16.2 BPM at bw=0.30 (vs. production POS/CHROM's ~7.9 BPM) — a severe
regression, not the improvement the paper reports.**

Root cause: `x_c(t)` is 2.3 Hz wide, far from monocomponent, and
`cpaceHomodyneNormalize.m`'s Hilbert transform requires a genuinely
narrowband input for its instantaneous phase to be meaningful — the exact
precondition this project's own `validation/computeCrossROIPLV.m` already
documents in its own header ("Hilbert instantaneous phase is only
meaningful for a signal that is already close to monocomponent"). Feeding
it a 2.3 Hz-wide signal produces a corrupted phase trajectory and,
downstream, wildly wrong reconstructed frequency content.

**Fix**: project `X_bp` (the same narrowband signal v1 was derived from —
a standard dominant-principal-component score, the same idea as POS's own
S1/S2 combination) onto v1 instead. Re-running the full 100-subject pool
after this fix: HR MAE at bw=0.30 dropped from 16.2 to 10.1 BPM — still a
net regression vs. production (see `Segment15_Task4_Evaluation.md`), but a
plausible, comparably-scaled result instead of a clearly-broken one. Table
S2 itself is silent on which signal feeds Stage 5, so this is a resolved
ambiguity, not a knowing deviation from an unambiguous spec — documented
in the function's own header, not silently fixed.

## 3. Sanity checks

- Eigenvalue ratio (λ1/λ2) across the 100-subject pool at bw=0.30: median
  4.81, mean 18.70 (min 1.20, max 315.96) — comparable order of magnitude
  to the paper's own reported single-example ratio (~392 on a favorable
  subject, Fig. 4), though this project's median is far lower, consistent
  with this cohort's low skin-colour angle (per Segment 11's own finding)
  putting it outside the paper's most favorable regime. 12/100 subjects
  have λ1/λ2 < 2 — a genuinely weak/ambiguous cardiac direction for those
  subjects, worth remembering when interpreting their individual results.

## Files

- `matlab/src/pulseextraction/cpaceEigenExtract.m`
- Evaluated together with Task 2 in
  `matlab/scripts/run_segment15_task3_task4_cpace_full_evaluation.m` — see
  `Segment15_Task4_Evaluation.md` for results.
