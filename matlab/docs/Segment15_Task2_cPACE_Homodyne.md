# Segment 15 Task 2 — cPACE Stage 3: Homodyne Amplitude Normalization

Run 2026-09-13/14. Builds `pulseextraction/cpaceHomodyneNormalize.m`, the
third stage of cPACE (Kaur, Lakshminarayanan & Saini, Biomed. Opt. Express
17(7):3832, 2026, doi:10.1364/BOE.599752), consuming
`cpaceEigenExtract.m`'s (Task 1) scalar pulse output.

**Built together with Task 1 and evaluated only as the combined
Stage1+2+3 pipeline** — the paper's own ablation (Section 5.2,
"cPACE-no-homodyne") found Stage 2 alone performs catastrophically worse
than POS, so this project's evaluation (`Segment15_Task4_Evaluation.md`)
never reports Stage 2 alone as if it were a candidate on its own.

## Method

Paper's Eq. 9 (main text):

```
s_clean(t) = (A(t) / A_slow(t)) * cos(phi(t))
```

where `A(t)`/`phi(t)` are the Hilbert-transform instantaneous
envelope/phase of the (re-)bandpass-filtered pulse signal, and `A_slow(t)`
is `A(t)` lowpass-filtered at `fenv` = 0.30 Hz to isolate slow
respiratory/vasomotor amplitude modulation.

**One documented interpretation call**: Supplement 1 Table S2 separately
lists a "Gate exponent κ" parameter (default 2, "Stage 5: Homodyne
envelope," described only as "Exponent applied to envelope magnitude") —
a parameter Eq. 9's own printed form does not show at all. This function
implements the generalized form

```
gate(t)    = (A(t) / A_slow(t)) ^ kappa
s_clean(t) = gate(t) * cos(phi(t))
```

which reduces exactly to Eq. 9 at κ=1 and matches Table S2's own default
(κ=2) — the value the supplement states "produce[s] all results reported
in the main paper." This is the most literal reading of the two source
documents together that is consistent with both; it is an interpretation,
not something either document states outright, and is documented as such
in the function's own header rather than silently assumed.

Steps implemented exactly as specified:

1. Re-bandpass the input to the cardiac band (0.7–3.0 Hz, order-4
   zero-phase — same band/order `cpaceEigenExtract.m` uses), per
   Section 4.3's own described sequence. In practice close to a no-op
   since the input is already a linear combination of already-bandpassed
   channels.
2. Hilbert transform → envelope `A(t)` = |analytic|, phase `φ(t)` =
   angle(analytic).
3. Lowpass `A(t)` at `fenv` (default 0.30 Hz, Table S2) → `A_slow(t)`.
4. `gate(t) = (A(t)/A_slow(t))^kappa` (default κ=2, Table S2);
   `s_clean(t) = gate(t) .* cos(φ(t))`.

A numerical guard floors `A_slow(t)` at `1e-6 * RMS(A(t))` (scaled to the
recording's own amplitude, not a fixed epsilon) to prevent the ratio from
blowing up on near-silent/clipped segments.

## Parameters NOT swept (per this segment's Task 3 brief)

The paper's own sensitivity analysis (Supplement 1 §S.6) found both `fenv`
and κ have negligible effect on HR MAE — 0.03–0.18 BPM swing for `fenv`
over {0.15, 0.30, 0.50, 0.70} Hz, 0.16–0.28 BPM swing for κ over
{1, 2, 4, 8} — dwarfed by the eigen-window `bw` parameter's 0.99–2.88 BPM
swing. Task 3 (`Segment15_Task3_Hyperparameter_Sweep.md`) spends its
evaluation effort on `bw` for this reason; `fenv`/κ are kept at their
Table S2 defaults throughout.

## Files

- `matlab/src/pulseextraction/cpaceHomodyneNormalize.m`
- Evaluated together with Task 1 in
  `matlab/scripts/run_segment15_task3_task4_cpace_full_evaluation.m` — see
  `Segment15_Task4_Evaluation.md` for results.
