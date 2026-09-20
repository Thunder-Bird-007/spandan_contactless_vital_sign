# Segment 23 Task 4 — LGI with its own read-out stage (Pilz et al., CVPR-W 2018)

**Verdict: EVALUATED, NOT ADOPTED — unchanged for LGI. But two things the brief did not anticipate:**
(1) **the LGI paper's own experiments do not use its state-space tracker** — its benchmark read-out is a 256-sample / 90 %-overlap FFT peak-pick; (2) both alternative read-outs
(the paper's and a state-space tracker) improve **CHROM and POS by as much as or more than they improve LGI**, so LGI's rank against CHROM/POS does not change. LGI still loses under every read-out.

**Opening paragraph — light or heavy (asked for explicitly).** Segment 22 did **not** cache the LGI pulse signal. It did cache what produces it: the raw ROI-mean R/G/B (`seg22cov_*.mat`, `*_rgb_traces.mat`),
and `lgiProjection.m` is a 3-row SVD on that trace (milliseconds). So the projection is regenerated with **no video decode → LIGHT**, and the regenerated LGI pulse reproduces Segment 22's HRs
(**max |ΔHR| = 0.0000 bpm on all 132 subjects** for LGI, CHROM and POS).

## What the paper actually specifies (read this session from the CVF PDF — `Pilz_Local_Group_Invariance_CVPR_2018_paper.pdf`)
* **§3 "The Model Space"** (Eq. 23–31): the pulse is a stochastic harmonic oscillator, `dx/dt = F0(θ)x + Le`, `c = H(θ)x`, with latent frequency θ on a **discrete set Ω = {θ₁…θ_S} forming a Markov chain with transition matrix Π** (`P(θᵢ,t | θⱼ,t−1) = Π_ij`); "the solution is given by computing the Gaussian mixture approximation to the joint posterior of the latent variables and states". No numeric grid, Π, noise levels or window is given.
* **§4 Experiments** (the benchmark in the paper's results table): "Each signal … is band-filtered in the range between **0.5 and 2.0 Hz** [2.5 Hz for the ergometer sessions]. All filtered signals are then analyzed by **standard Fourier based spectral method with windows size of 256 samples and overlap of 90 percent. A maximum peak energy criterion** is applied over the spectral traces to determine the heart rate candidates." All methods were read out identically.
* So: the state-space model is the paper's *modelling framework*; its **reported numbers come from an FFT read-out, applied identically to LGI, POS, SSR, ICA.** The brief's premise ("the paper's robustness lives partly in its read-out stage — the tracker") is therefore only partly supported: the read-out that produced the paper's numbers is a windowed FFT peak-pick, and this project's whole-clip `fftHeartRate.m` differs from it (windowed + a 0.5–2.0 Hz band).

## Method
`src/lgiStateSpaceTracker.m` — interacting-multiple-model bank: one Kalman filter per frequency state (0.7–3.0 Hz, 0.025 Hz grid, 93 states) for a discrete stochastic resonator, weights updated by innovation likelihood, re-mixed through Π every 0.5 s (Gaussian-mixture approximation of the joint posterior, Eq. 28–31); HR = argmax of the posterior state probability averaged over time after a 3 s burn-in.
**Every numeric setting is this implementation's own, fixed a priori (the paper gives none) and never tuned on data:** Π_ij ∝ exp(−Δf²/2·0.05²)+1e-3; measurement noise r=0.3 (signal z-scored); process noise 0.005·diag(1,ω²)/sample.
`src/lgiPaperReadout.m` — the paper's §4 read-out: Butterworth-2 0.5–2.0 Hz, 256-sample Hann windows, 90 % overlap, max FFT peak per window, per-clip HR = median of window peaks (the paper reports spectrogram traces, not a scalar); 4× zero-padding is a deviation *in the estimator's favour*.
The **same three read-outs are applied to CHROM and POS** so a read-out gain is not credited to LGI. LGI chain = Segment 22's (wavelet → `lgiProjection` → detrend → bandpass); CHROM/POS = production chain.
Pools: UBFC 5, VIPL v1 107, MAIN_112, VIPL v2 motion 20.

## Results — MAE / RMSE / r / severe (>10 bpm) / n
| pulse · read-out | UBFC (5) | VIPL v1 (107) | MAIN_112 | VIPL v2 motion (20) |
|---|---|---|---|---|
| LGI · whole-clip FFT (Segment 22's) | 2.65 / 3.77 / 0.98 / 0 | 9.55 / 14.37 / 0.38 / 38 | 9.24 / 14.06 / 0.46 / 38 | 16.93 / 22.24 / −0.12 / 11 |
| LGI · **paper's own read-out** | 4.83 / 8.97 / 0.84 / 1 | 7.90 / 11.15 / 0.52 / 33 | 7.76 / 11.06 / 0.60 / 34 | 12.28 / 17.06 / 0.13 / 8 |
| LGI · **state-space tracker** | 3.77 / 5.72 / 0.94 / 1 | 9.74 / 15.93 / 0.30 / 35 | 9.48 / 15.62 / 0.38 / 36 | 21.57 / 32.62 / −0.06 / 12 |
| CHROM · whole-clip FFT (production) | 3.26 / 5.05 / 0.96 / 1 | 8.05 / 12.09 / 0.48 / 31 | 7.83 / 11.87 / 0.53 / 32 | 8.85 / 12.64 / 0.54 / 7 |
| CHROM · paper's read-out | 2.64 / 4.82 / 0.97 / 1 | 6.55 / 9.25 / 0.56 / 24 | 6.38 / 9.10 / 0.64 / 25 | 8.25 / 11.47 / 0.53 / 6 |
| CHROM · state-space tracker | 3.14 / 4.49 / 0.98 / 0 | 6.70 / 8.92 / 0.62 / 30 | 6.54 / 8.77 / 0.68 / 30 | 9.24 / 12.40 / 0.30 / 8 |
| POS · whole-clip FFT (production) | 3.77 / 6.15 / 0.94 / 1 | 7.38 / 11.02 / 0.58 / 29 | 7.22 / 10.85 / 0.62 / 30 | 10.56 / 16.06 / 0.31 / 6 |
| POS · paper's read-out | 2.48 / 4.45 / 0.98 / 0 | 6.89 / 9.51 / 0.54 / 30 | 6.70 / 9.34 / 0.63 / 30 | 9.50 / 12.64 / 0.50 / 7 |
| POS · state-space tracker | 2.84 / 4.44 / 0.97 / 0 | 6.45 / 8.55 / 0.62 / 26 | 6.29 / 8.41 / 0.69 / 26 | 9.30 / 14.91 / 0.28 / 7 |

Paired per-subject (|error| difference; >1 bpm = better/worse; sign-rank p):
* LGI tracker vs LGI whole-clip FFT — MAIN_112 41 better / 45 worse, 11 severe-worse, p=0.96; v2 7 / 10, 4 severe, p=0.46.
* LGI tracker vs CHROM whole-clip — MAIN_112 37 / 45, 12 severe, p=0.52; **v2 3 / 14, 7 severe, p=0.009**. vs POS: MAIN_112 36 / 50, 13, p=0.10; v2 4 / 12, 8, p=0.030.
* LGI paper read-out vs LGI whole-clip — MAIN_112 31 / 34, 8 severe, p=0.79; v2 **11 better / 3 worse**, 1 severe, p=0.062 (borderline, N=20).
* LGI paper read-out vs CHROM whole-clip — MAIN_112 29 / 34, 10 severe, p=0.42; v2 5 / 10, 4 severe, p=0.18.

## Interpretation
* **Is LGI competitive with CHROM/POS once read out properly?** No, on either read-out. Same-read-out comparison, MAIN_112: paper read-out LGI 7.76 vs CHROM 6.38 / POS 6.70; tracker LGI 9.48 vs CHROM 6.54 / POS 6.29. v2 motion: LGI 12.3 (paper read-out) / 21.6 (tracker) vs CHROM 8.25 / 9.24 and POS 9.5 / 9.3. The published head-rotation advantage of LGI (r 0.97) does not appear on Spandan's data under any read-out.
* **The tracker does not help LGI** (MAIN_112 9.24 → 9.48; v2 16.9 → 21.6) — its wrong-frequency cases are wrong in the *signal*, which a tracker cannot repair (a tracker can only smooth what the spectrum contains).
* **The tracker does help CHROM/POS**: MAIN_112 CHROM 7.83 → 6.54 MAE (RMSE 11.87 → 8.77, r 0.53 → 0.68), POS 7.22 → 6.29 (10.85 → 8.41, 0.62 → 0.69). It is *not* broken. But on the v2 motion pool the tracker is worse than whole-clip for CHROM in r (0.54 → 0.30).
* **The paper's simple windowed read-out gives a similar gain to CHROM/POS** (CHROM 7.83 → 6.38 MAE, RMSE 9.10, r 0.64). This is a **material finding about the existing record, not about LGI**: a windowed peak read-out with a 0.5–2.0 Hz band beats the production whole-clip `fftHeartRate.m` on the main pool for both incumbents. Two confounds keep this from being called a production improvement: the 0.5–2.0 Hz cap encodes a ≤120 bpm prior (it costs the 5-clip UBFC LGI row, 2.65 → 4.83, where after-exercise HR is high), and the median-over-windows is an outlier-robust aggregate. **Recorded as a CANDIDATE (read-out stage), not promoted** — no held-out validation was run (UBFC-D2, 33 valid subjects, is available and would be the right next check).
* Caveat: the tracker's three continuous settings were not tuned (tuning them on this pool would be exactly the fishing the segment forbids); a differently parameterised tracker might behave differently, but the CHROM/POS gains above show the implementation is sound.

**Verdict line: LGI (projection + own read-out + state-space tracker) — EVALUATED, NOT ADOPTED. Read-out stage: windowed/tracked read-outs are a CANDIDATE improvement for CHROM/POS (needs held-out validation).**

## Protected-files verification
See `../common/protected_files_verification.txt`: 18/18 protected production files byte-identical before vs after Segment 23 (SHA-256).

## Outputs
`src/lgiStateSpaceTracker.m`, `src/lgiPaperReadout.m`, `scripts/run_task4_lgi_tracker.m`, `results/task4_summary_by_pool.csv`, `results/task4_per_subject.csv`.
