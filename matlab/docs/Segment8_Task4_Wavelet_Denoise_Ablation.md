# Segment 8 (Action 4) — DWT Wavelet-Shrinkage Denoising Ablation

Per Debnath & Kim (*PLOS ONE* 2026, 21(1):e0340097), tests `filtering/waveletDenoise.m`
(DWT wavelet-shrinkage via Donoho-Johnstone universal soft-thresholding) as an ADDITIVE
optional pre-step ahead of `filtering/detrendSignal.m` + `filtering/bandpassClean.m` in
Branch 1, ablated on the full 112-subject pool (5 UBFC-D1 + 107 VIPL) already validated
in `results/metrics/segment6_hr_pooled_metrics.csv`.

## Method

New file `filtering/waveletDenoise.m`: `wavedec` (db4, 3 levels) → estimate noise sigma
from the finest-level detail coefficients' median absolute deviation (`sigma =
median(abs(d1))/0.6745`) → universal threshold `T = sigma*sqrt(2*log(n))` → soft-threshold
every level's detail coefficients → `waverec`. Confirmed the Wavelet Toolbox is licensed
and `wavedec`/`waverec` round-trip correctly (reconstruction error ~1.45e-12 on a test
signal) before building on it. Smoke-tested on a synthetic 1.2 Hz sinusoid + Gaussian
noise: RMSE-vs-clean dropped from 0.3185 to 0.1968 (38% reduction) — the function
measurably denoises, not a no-op.

`scripts/run_segment8_task4_wavelet_ablation_batch.m`: "without wavelet" values are READ
directly from the already-validated `results/metrics/segment4_hr_summary.csv` /
`segment4_hr_summary_vipl.csv` (not recomputed). "With wavelet" values are freshly
computed — same ROI decode, `waveletDenoise.m` inserted on each raw R/G/B channel before
`detrendSignal.m`/`bandpassClean.m`, everything else in the chain unmodified. **112/112
subjects succeeded, 0 failures** (`results/metrics/segment8_task4_wavelet_ablation.csv`).

## Pooled results (N=112)

| Metric | CHROM without wavelet | CHROM with wavelet | POS without wavelet | POS with wavelet |
|---|---|---|---|---|
| MAE (bpm) | 9.0969 | **7.8344** | 8.6795 | **7.2217** |
| RMSE (bpm) | 18.0047 | **11.8676** | 16.4537 | **10.8493** |
| Pearson r | 0.3145 | **0.5319** | 0.2809 | **0.6234** |

**Every metric improves, for both CHROM and POS** — MAE down ~1.3-1.5bpm, RMSE down
~5.6-6.1bpm (a large drop, meaning fewer/smaller large-error outliers), Pearson r nearly
doubles for both. By dataset: UBFC-only CHROM MAE 3.77→3.26bpm (N=5, thin); VIPL-only
CHROM MAE 9.35→8.05bpm (N=107, the number that matters).

## Per-subject reality check — improvement is real but NOT uniform

39/112 subjects had their CHROM HR changed at all by wavelet denoising (34/112 for POS)
— most subjects are unaffected (denoising a genuinely clean channel has nothing to
remove). Among the subjects that DID change:

- **Large improvements exist**: `VIPL_p48_v1_source1` — CHROM error 42.06→12.29bpm (GT
  80.97, no-wavelet estimate 182.55bpm — a severe pre-existing harmonic-like error;
  with-wavelet estimate 93.26bpm, much closer).
- **Real regressions exist too, reported plainly**: `VIPL_p85_v1_source1` — CHROM error
  0.44→45.81bpm (GT 74.52, no-wavelet estimate 74.96bpm, essentially perfect; with-wavelet
  estimate 120.33bpm, a ~1.6x jump). 7 subjects total regress by more than 10bpm on CHROM
  (`p7`: +36.2, `p8`: +29.0, `p14`: +12.0, `p54`: +21.4, `p57`: +10.6, `p85`: +45.4, `p88`:
  +11.9).

**So this is a net-positive, not a uniformly-positive, result** — pooled MAE/RMSE/r all
improve substantially, but a handful of individual subjects get meaningfully worse. This
is reported as-is rather than only citing the pooled averages.

## Confirming or refuting the "no harmonic-lock risk" expectation

**Confirmed, with one qualification.** The pooled RMSE improvement (18.0→11.9, 16.5→10.9)
is itself strong evidence against a systematic harmonic-lock mechanism: ABPF's own
documented Branch 1 harmonic-lock case (one VIPL subject's CHROM jumping 69.4→140.8bpm,
`docs/Spandan_Final_Pipeline_Report.md`) is a designed-in consequence of needing a
pre-estimated f0 and reinforcing exactly that frequency — if wavelet shrinkage carried
the same risk broadly, RMSE (which punishes large individual errors hardest) would be
expected to get WORSE, not dramatically better, since a systematic mechanism would
produce more, not fewer, severe outliers. It does not: RMSE improves by more, proportionally,
than MAE does, meaning large errors shrank on net.

The qualification: `p85`'s regression (0.44→45.81bpm, landing suspiciously close to a
harmonic ratio) shows wavelet shrinkage is NOT immune to occasionally producing a
harmonic-like error on a specific subject — but the mechanism is different from ABPF's.
There is no f0 estimate anywhere in `waveletDenoise.m`'s computation (it thresholds based
purely on each level's own coefficient statistics), so this can't be a "locked onto the
wrong frequency and reinforced it" failure the way ABPF's is — it's better read as an
occasional side effect of denoising shifting which of two already-close-in-magnitude FFT
peaks wins the argmax for a handful of borderline subjects, not a systematic
frequency-targeting bias. The original expectation (stated in `waveletDenoise.m`'s own
header before this ablation ran) is **confirmed at the pool level, with this one
individual-subject caveat honestly on the record**.

## Bottom line

**Adopt as an available additive option for Branch 1**: DWT wavelet-shrinkage denoising
measurably improves pooled HR accuracy on both CHROM and POS, across MAE, RMSE, and
Pearson r, on the full 112-subject pool — the strongest single-intervention result this
project has produced for Branch 1 HR to date. Not without caveats: it changes ~1/3 of
subjects' estimates, improving most of those but regressing 7 by a meaningful margin
(>10bpm) — a real, if minority, downside worth stating alongside the pooled win, not a
free lunch. `filtering/detrendSignal.m`, `filtering/bandpassClean.m`,
`pulseextraction/chromCombine.m`, `pulseextraction/posCombine.m`, and
`heartrate/fftHeartRate.m` are all unmodified — this stays a callable, additive option, not
a replacement, per the handoff's own framing.
