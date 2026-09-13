# Segment 12 Task 2 — Harmonic-Selective Gaussian Filtering vs. the ABPF Comb

Run 2026-09-13. Implements Dominguez-Hernandez, Paez & Padilla's
Harmonic-Selective Gaussian Filtering (Sensors 26(12):3710, 2026,
doi:10.3390/s26123710, PMC13307314 — full text retrieved and read this
session, not paraphrased from the earlier literature-search summary alone)
as a new, gated, off-by-default alternative to
`morphology/adaptiveHarmonicFilter.m`'s hard-edged ABPF comb, and evaluates
it head-to-head on the same 100-subject pool Segment 10 Task 1 audited.

**Headline result, in two parts because the honest answer has two parts**:

1. **At the paper's own literal parameter (alpha=0.5, "a practical
   compromise" in their own words) the Gaussian filter underperforms the
   current ABPF comb on every metric except a small harmonic-confusion
   improvement** — pass rate 20% vs. ABPF's 24%, median waveform
   correlation 0.383 vs. 0.519, with a clear mechanistic explanation (§3):
   at this population's typical heart rate, alpha=0.5 makes adjacent
   harmonics' Gaussian passbands overlap so heavily that the filter is no
   longer meaningfully "harmonic-selective."
2. **A follow-up sensitivity sweep (§4, not in the original brief, run
   because the mechanism in §3 predicted it would matter) finds a tighter
   alpha (~0.15) actually beats ABPF on all three metrics at once** — pass
   rate 31% vs. 24%, median corr 0.523 vs. 0.519, harmonic confusion 3% vs.
   5% — but with substantial per-subject volatility (17/100 subjects show
   a severe notch-confidence regression even as the pool median improves),
   reported honestly rather than only citing the favorable median. **Not
   adopted, but a genuinely promising, previously-unexplored lead for a
   future session.**

New file: `matlab/src/morphology/harmonicSelectiveGaussianFilter.m` —
never wired into `pipeline/estimateVitalsAndMorphology.m` or any other
production call site; `adaptiveHarmonicFilter.m` is called, not modified.
Do-not-touch files confirmed unmodified via `git status`.

---

## Method

### The paper's own formula (read from the primary source, PMC13307314)

```
Per-harmonic Gaussian (Eq. 4):  G_h(f) = exp(-(f-h*f0)^2/sigma^2) + exp(-(f+h*f0)^2/sigma^2)
Composite filter (Eq. 5):       H(f)   = sum_{h=1}^{N} G_h(f)
Bandwidth (Eq. 6):              sigma  = alpha * f0,  the paper's own value: alpha = 1/2
Filtering (Eq. 7):              S_filtered(f) = S(f) .* H(f)
Reconstruction (Eq. 8):         s_filtered(t) = real(ifft(S_filtered))
```

The paper's authors describe alpha=0.5 as "a practical compromise," not a
proven universal optimum, and examined `N` (harmonic count) in {3,4,5} for
morphology preservation, up to 10 with diminishing returns.

### Implementation (`harmonicSelectiveGaussianFilter.m`)

Same call signature as `adaptiveHarmonicFilter.m`
(`sigDetrended, frameRate, numHarmonics, f0HzOverride`), plus an optional
5th `alpha` argument (default 0.5, the paper's own value). `numHarmonics`
defaults to **6**, matching `adaptiveHarmonicFilter.m`'s own default —
deliberately different from the paper's own examined N, so this task's
comparison isolates the Gaussian-vs-rectangular SHAPE question alone,
without also changing the harmonic count. Same f0-estimation/override
convention as the existing function, so the two are drop-in interchangeable.

### Evaluation

For all 100 subjects, Branch 2's pipeline was run with the shared-f0 step
**identical and unchanged from production** (`bandpassMorphology.m`
`'wide'` — Segment 12 Task 1's `'mid'` question is a separate, independent
change, deliberately NOT combined with this one), then the harmonic-filter
step run TWICE: `adaptiveHarmonicFilter.m` (current) and
`harmonicSelectiveGaussianFilter.m` (new), both feeding the same shared f0.
Everything downstream (alignment, waveform correlation, notch detection,
harmonic-confusion detection) is Task 1's own exact method, reproduced
line-for-line in this task's own script for a self-contained, freshly
computed comparison — cross-checked against Task 1's own cached
`notchConfidence_harmonic`/`corr_harmonic` first (**100/100 subjects
match to 1e-6** for both metrics), confirming the reimplementation is
faithful before trusting the new Gaussian numbers built the same way.

---

## Result at the paper's own alpha=0.5

| Metric | ABPF comb (current) | Gaussian (alpha=0.5) |
|---|---|---|
| Pass rate (notch conf > 0.3) | **24%** (24/100) | 20% (20/100) |
| Median notch confidence | **0.058** | 0.041 |
| Median waveform correlation | **0.519** | 0.383 |
| Harmonic confusion rate | 5% | **4%** |

Paired per-subject: notch confidence 41 improved / 57 regressed / 2
unchanged; waveform correlation 35 improved / 65 regressed / 0 unchanged.
**A clear majority of subjects regress on both headline metrics.**

Full per-subject table:
`results/metrics/segment12_task2_gaussian_vs_abpf_comparison.csv`.
Figures: `results/figures/segment12_task2_paired_scatter.png`,
`results/figures/segment12_task2_summary_bars.png`.

---

## 3. Why: adjacent-harmonic overlap at alpha=0.5

A Gaussian's full width at half maximum is `~2.355*sigma`. At
`sigma = alpha*f0 = 0.5*f0`, that is `~1.18*f0` — **wider than the
spacing between adjacent harmonics (f0 itself)**. So at alpha=0.5, each
harmonic's passband already extends past the midpoint to the *next*
harmonic, and the composite filter `H(f)` is not really a selective comb
at all — it is closer to one continuous, ripple-textured wide passband
that admits far more inter-harmonic noise than ABPF's narrow (~1-2 FFT
bin) rectangular windows were designed to reject.

Figure `results/figures/segment12_task2_mask_comparison.png` shows this
directly for this pool's own median f0 (1.20Hz, ~72bpm): ABPF's comb is
six sharp, essentially isolated spikes; the alpha=0.5 Gaussian comb is six
overlapping humps that never fully return to zero between harmonics.

---

## 4. Follow-up: does a tighter alpha fix it?

Since §3's explanation is specifically about *overlap*, the natural next
question — not in the original brief, but the obvious test of the
mechanism just proposed — is whether a smaller alpha (less overlap)
recovers competitiveness with ABPF. Swept alpha ∈ {0.10, 0.15, 0.20, 0.30,
0.50} on the same 100-subject pool
(`matlab/scripts/run_segment12_task2b_gaussian_alpha_sweep.m`, no
production file touched, no new source file needed — `alpha` was already
an exposed parameter).

| alpha | pass rate | median notch conf | median waveform corr | harmonic confusion |
|---|---|---|---|---|
| 0.10 | 24% | 0.052 | **0.544** | 3% |
| **0.15** | **31%** | **0.090** | 0.523 | **3%** |
| 0.20 | **32%** | 0.082 | 0.499 | 3% |
| 0.30 | 22% | 0.050 | 0.470 | 4% |
| 0.50 (paper's own value) | 20% | 0.041 | 0.383 | 4% |
| *ABPF comb (reference)* | *24%* | *0.058* | *0.519* | *5%* |

Full table: `results/metrics/segment12_task2b_gaussian_alpha_sweep.csv`.
Figure: `results/figures/segment12_task2b_alpha_sweep.png`.

**Waveform correlation degrades monotonically as alpha increases** (tighter
is straightforwardly better for this metric, consistent with §3's overlap
explanation). **Pass rate and notch confidence are non-monotonic**, peaking
around alpha=0.15–0.20 and falling off at both extremes — too tight
(alpha=0.10) apparently starts to lose real harmonic content the notch
needs; too loose (alpha≥0.30) reintroduces the overlap problem.

**alpha=0.15 beats the current ABPF comb on all three metrics
simultaneously** in the pool-level numbers: pass rate 31% vs. 24%, median
corr 0.523 vs. 0.519, harmonic confusion 3% vs. 5%.

### The honest caveat that keeps this from being a clean win

Paired per-subject at alpha=0.15 vs. ABPF: notch confidence 53 improved /
47 regressed (roughly balanced counts, net positive because the
improvements are larger on average); waveform correlation 60 improved / 40
regressed (more consistently positive). But **17 of 100 subjects show a
severe notch-confidence regression (a drop of more than 0.3)**, several
falling from a near-perfect confidence (~1.0) down to near zero — e.g.
`12-gt` (1.000→0.002), `VIPL_p23` (1.000→0.019), `VIPL_p50` (1.000→0.009).
The pool median improves specifically BECAUSE the improvements are large
and numerous among previously-low-confidence subjects, not because every
subject gets better. **This is a real trade, not a free lunch** — reported
plainly rather than only citing the favorable median, per this project's
own evaluation-honesty standard.

---

## 5. Recommendation

**Do not adopt at the paper's own literal alpha=0.5** — it underperforms
ABPF on the metrics that matter most (pass rate, waveform correlation),
with a verified mechanistic explanation, not just a bad-luck result on this
pool.

**Do not adopt alpha=0.15 either, despite its favorable pool-level
numbers** — the 17-subject severe-regression tail is a real cost this
task's own evaluation-honesty discipline requires surfacing, and 17
subjects losing badly in exchange for a pool median improvement is not a
trade this project should make silently or by default. `Harmonic
SelectiveGaussianFilter.m` stays exactly what it was built as: a new,
gated, off-by-default function, callable but never called by production
code.

**This is nonetheless the most promising lead in this document.** A future
session could reasonably investigate: (a) *why* the 17 severe-regression
subjects lose so badly at alpha=0.15 — is it tied to a specific f0 range,
HR variability, or something else identifiable and correctable; (b) a
per-subject or per-HR-range ADAPTIVE alpha rather than one fixed value
pool-wide; (c) combining a tighter alpha with a higher harmonic count
(closer to the paper's own examined N=3-5, opposite direction from what
this task tested) to see if that interacts differently. None of these are
attempted here — flagged as open questions for a future explicit decision,
not results.

## Files

- `matlab/src/morphology/harmonicSelectiveGaussianFilter.m`
- `matlab/scripts/run_segment12_task2_gaussian_harmonic_filter_evaluation.m`
- `matlab/scripts/run_segment12_task2b_gaussian_alpha_sweep.m`
- `results/metrics/segment12_task2_gaussian_vs_abpf_comparison.csv`
- `results/metrics/segment12_task2b_gaussian_alpha_sweep.csv`
- `results/figures/segment12_task2_paired_scatter.png`
- `results/figures/segment12_task2_summary_bars.png`
- `results/figures/segment12_task2_mask_comparison.png`
- `results/figures/segment12_task2b_alpha_sweep.png`
