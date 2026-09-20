# Segment 24 — Held-out validation of the Segment 23 read-out candidate

One-shot run per `PREREGISTRATION.md` (committed as `7ffc964` before any read-out was computed). Nothing was tuned, re-run or re-defined after seeing results. 0 processing failures; parity gate passed (0.000039 bpm vs Segment 8's wavelet numbers, i.e. CSV rounding).

## Verdict (project vocabulary, per the pre-declared rules; PRIMARY only)

| candidate (b) as tested in Segment 23 | (b) beats (a)? | band-matched (c) beats (a)? | verdict |
|---|---|---|---|
| **Windowed peak** (0.5–2.0 Hz), CHROM | **No** (person-MAE 11.94→11.47, gain 0.47, Holm p = 1.0) | **Yes** (→9.21, gain 2.73, Holm p = 0.0019) | **(b) EVALUATED, NOT ADOPTED as tested.** Not "CANDIDATE, HELD-OUT VALIDATED": (b) failed. |
| Windowed peak, POS | **No** (11.79→11.54, gain 0.24, p = 1.0) | **Yes** (→8.64, gain 3.14, Holm p = 3e-5) | same |
| **State tracker** (grid 0.7–3.0 Hz), CHROM / POS | No (−0.04 / −0.06 bpm, p = 1.0) | No (+0.08 / +0.72, p = 1.0 / 0.19) | **EVALUATED, NOT ADOPTED** |

**What this means, plainly.**
1. The Segment 23 candidate **did not validate as tested.** On the held-out PRIMARY set the windowed read-out with its ≤120 bpm band is not better than production overall, and the tracker is not better at all. The tracker's Segment 23 gain (1.3–1.5 bpm on MAIN_112) does **not** reproduce; it is a pool-specific result.
2. The "gain was just the narrower band" hypothesis is **the wrong way round for the windowed read-out**: the narrow band is a *liability*. Widening it to production's 0.7–4.0 Hz (c) is what produces the clear win (2.7–3.1 bpm). The windowing + median mechanism carries the gain; the ≤120 cap gives some of it back on elevated heart rates (below).
3. **Caution on (c):** the band-matched windowed read-out was a pre-registered *control condition*, never a candidate selected on MAIN_112 and never run there. It is therefore a **new positive signal seen once, not a validated candidate.** It needs (i) a run on MAIN_112 and (ii) a fresh set, before it can carry any claim. No production change.
4. The held-out claim is **by video/scenario, not by subject** (all 107 VIPL people are in MAIN_112; there are no unused VIPL subjects — verified). The read-outs have no per-subject fitted parameters, but the caveat stands.

## PRIMARY — held out by video/scenario (VIPL source1 webcam; 281 videos, 96 people)

MAE / RMSE / Pearson r, clip HR vs ground-truth HR (`results/s24_metrics_by_stratum.csv`). Severe-error counts in the CSV.

**CHROM**

| stratum (n, mean GT) | (a) fftHR | (bW) windowed 0.5–2 | (cW) windowed 0.7–4 | (bT) tracker 0.7–3 | (cT) tracker 0.7–4 |
|---|---|---|---|---|---|
| v4 bright (96, 75.8) | 8.38 / 15.79 / 0.38 | 4.63 / 7.22 / 0.77 | 4.48 / 6.76 / 0.75 | 6.62 / 13.63 / 0.39 | 6.55 / 11.17 / 0.46 |
| v6 1.5 m (94, 77.9) | 8.56 / 12.86 / 0.40 | 7.40 / 10.67 / 0.47 | 7.91 / 12.23 / 0.42 | 9.27 / 14.36 / 0.43 | 8.43 / 11.48 / 0.46 |
| v7 after exercise (91, 98.0) | 19.49 / 26.61 / 0.24 | 23.52 / 29.10 / −0.08 | 15.93 / 21.74 / 0.33 | 21.16 / 27.61 / 0.25 | 21.74 / 29.67 / 0.23 |
| **all PRIMARY (281)** | 12.04 / 19.23 / 0.34 | 11.68 / 18.17 / 0.33 | **9.34 / 14.79 / 0.51** | 12.21 / 19.48 / 0.35 | 12.10 / 19.28 / 0.36 |

**POS**

| stratum | (a) | (bW) | (cW) | (bT) | (cT) |
|---|---|---|---|---|---|
| v4 | 7.30 / 14.65 / 0.46 | 4.31 / 6.74 / 0.78 | 4.31 / 7.30 / 0.72 | 5.55 / 12.81 / 0.45 | 5.55 / 12.67 / 0.45 |
| v6 | 9.73 / 14.64 / 0.34 | 7.90 / 11.52 / 0.40 | 7.59 / 11.67 / 0.40 | 11.60 / 21.12 / 0.19 | 9.22 / 12.75 / 0.28 |
| v7 | 18.85 / 24.91 / 0.36 | 23.59 / 29.57 / −0.03 | 14.68 / 20.13 / 0.45 | 19.45 / 26.02 / 0.38 | 19.41 / 26.31 / 0.31 |
| **all PRIMARY** | 11.85 / 18.60 / 0.44 | 11.75 / 18.52 / 0.30 | **8.77 / 13.96 / 0.59** | 12.08 / 20.60 / 0.36 | 11.27 / 18.26 / 0.40 |

### Pre-declared test (person-level paired Wilcoxon, 8 tests, Holm α = 0.05; `results/s24_primary_verdict_tests.csv`)

N = 96 people. Person-level mean |error| in bpm; "better/worse" = number of people.

| mech | comb | cond | (a) | candidate | gain | better/worse | p raw | p Holm | clearly beats |
|---|---|---|---|---|---|---|---|---|---|
| W | CHROM | b | 11.94 | 11.47 | 0.47 | 47/49 | 1.000 | 1.000 | no |
| W | CHROM | c | 11.94 | 9.21 | 2.73 | 60/36 | 2.8e-4 | 0.0019 | **yes** |
| W | POS | b | 11.79 | 11.54 | 0.24 | 51/45 | 0.696 | 1.000 | no |
| W | POS | c | 11.79 | 8.64 | 3.14 | 64/32 | 3.9e-6 | 3.1e-5 | **yes** |
| T | CHROM | b | 11.94 | 11.98 | −0.04 | 50/46 | 0.784 | 1.000 | no |
| T | CHROM | c | 11.94 | 11.86 | 0.08 | 48/48 | 0.962 | 1.000 | no |
| T | POS | b | 11.79 | 11.85 | −0.06 | 52/44 | 0.363 | 1.000 | no |
| T | POS | c | 11.79 | 11.06 | 0.72 | 54/42 | 0.188 | 1.000 | no |

N = 96 people, not 107: only people with a source1 clip in at least one of v4/v6/v7 exist in PRIMARY (source1 is absent for p97–p107 in every scenario); each contributes the mean over the (up to three) clips they have.

## Post-hoc, NOT pre-registered (interpretation only, no claim rests on it)

* **Where the (bW) loss lives — the ≤120 cap on elevated HR.** v7 has 8 clips with GT > 120 bpm (23 with GT > 110; max 132). CHROM, v7, GT > 110 (n = 23): (a) 34.5 bpm MAE, (bW) 46.1, (cW) 29.9. GT ≤ 110 (n = 68): (a) 14.4, (bW) 15.9, (cW) 11.2. So even below 110 bpm (bW) is no better on after-exercise clips (near-cap windows and harmonic pull), and above it the cap is clearly harmful; widening the band fixes both.
* **Resting-HR clips only (v4 + v6, n = 190).** CHROM MAE (a) 8.47 → (bW) 6.00, (cW) 6.18, (bT) 7.93, (cT) 7.48. POS (a) 8.50 → (bW) 6.08, (cW) 5.93, (bT) 8.55, (cT) 7.37. On resting data the windowed read-out helps regardless of band, consistent with Segment 23's MAIN_112 gain (~1.1–1.5 bpm there; larger here because baseline error is higher on these scenarios). The tracker helps a little on v4 (descriptive p ≈ 0.02–0.09) and not on v6.
* The verdict's outcome is driven by the v7 (after-exercise) stratum, which the pre-registration deliberately included as the fair test of the band confound; the resting strata alone would have shown (b) helping. Both statements are true; the pre-declared rule decides the verdict.

## EXPLORATORY — phone source2 (descriptive only; cannot drive the verdict)

Cached container `fs` used as-is (known mislabelling for source2). CHROM / POS MAE, `(a) → bW / cW / bT / cT`:
v1 not-in-MAIN (95): 13.99 → 12.94 / 12.44 / 11.95 / 11.98 · 15.37 → 12.81 / 11.66 / 11.59 / 11.63.
v8 (106): 14.58 → 12.39 / 10.70 / 12.84 / 12.58 · 14.02 → 12.21 / 11.82 / 12.04 / 11.79.
v9 (105): 15.22 → 14.62 / 11.62 / 13.44 / 13.03 · 15.70 → 14.33 / 11.27 / 14.12 / 13.31.
v7 phone (15, mean GT 101): 29.46 → 26.96 / 23.12 / 26.06 / 25.90 · 29.35 → 29.31 / 25.72 / 25.79 / 28.26.
All phone (321): CHROM 15.31 → 13.96 / **12.10** / 13.39 / 13.17; POS 15.69 → 13.88 / **12.24** / 13.23 / 13.01. Every candidate is at or below (a) here, and (cW) is best or near-best in most strata (exceptions: v1-not-in-MAIN, where the trackers edge it) — the same direction as PRIMARY, on noisier data.

## SECONDARY — UBFC-D2 (second-look, NOT held-out: prior use Segment 14; descriptive, no verdict)

N = 42 (33 Segment-14-valid + 9 excluded; HR-only scoring does not need the waveform timestamps). D2 GT HR max is 119 bpm, so the ≤120 cap never binds. CHROM MAE / RMSE / r:

| split | (a) | (bW) | (cW) | (bT) | (cT) |
|---|---|---|---|---|---|
| all 42 (mean GT 95.3) | 7.42 / 15.72 / 0.57 | 6.26 / 12.35 / 0.70 | **6.00 / 12.58 / 0.68** | 7.08 / 14.38 / 0.61 | 7.18 / 14.63 / 0.60 |
| Seg-14-valid 33 | 7.67 / 17.02 / 0.48 | 7.11 / 13.71 / 0.63 | 6.35 / 13.69 / 0.61 | 8.28 / 16.10 / 0.52 | 8.41 / 16.38 / 0.50 |
| excluded 9 | 6.53 / 9.54 / 0.87 | 3.16 / 4.75 / 0.97 | 4.70 / 7.18 / 0.92 | 2.67 / 3.76 / 0.98 | 2.67 / 3.76 / 0.98 |

POS all 42: (a) 7.45 / 14.96 / 0.59, (bW) 6.94 / 13.01 / 0.68, (cW) **5.75** / 11.80 / 0.72, (bT) 7.15 / 14.40 / 0.61, (cT) 7.51 / 14.98 / 0.58.

**PRIMARY vs SECONDARY agreement.** Direction agrees for the windowed read-out (D2: (bW) and (cW) both below (a), (cW) best, as on PRIMARY) and for the tracker (little or no gain). They differ in one place worth stating: on D2 the as-tested (bW) *does* help (7.42→6.26) where on PRIMARY it does not — consistent with the post-hoc reading that (bW) helps at resting HRs and loses on elevated ones (D2 has no clip above 119 bpm), not a contradiction. Descriptive paired p-values on D2-33 (`s24_descriptive_paired_by_stratum.csv`) are all > 0.11; the 33 subjects cannot carry a claim (same small-N caveat as Segment 23's UBFC N = 5). D2 did not drive, and is not used to overrule, the PRIMARY verdict.

## Caveats

* Held out by video/scenario, not by subject; the up-to-three PRIMARY clips per person are handled by person-level pairing but people are shared with MAIN_112.
* v7 (after exercise) is only 1/3 of PRIMARY yet dominates the outcome; MAE levels on PRIMARY (9–12 bpm) are higher than MAIN_112's (6–8), so absolute gains are not comparable to Segment 23's.
* Wilcoxon on 96 people, 8 tests, Holm-adjusted; effect sizes are person-level MAE differences, which weight each person equally.
* Not isolated (out of scope): median-over-windows aggregate; whole-clip FFT restricted to 0.5–2 Hz (band alone).
* Tracker constants untuned by design (Segment 23 pre-declared; unchanged).

## Reusable stored data (so future runs need no redundant work)

* `results/s24_set_manifest.csv` — all 644 videos: id, set, stratum, subject, ground-truth HR, cached-trace path.
* `data/processed/VIPL_p*_v{4,6}_source1_rgb_traces.mat` (190 new caches, same schema as every other VIPL cache) + `results/s24_new_vipl_manifest.csv` (fs, frame counts, dropped frames, ground truth, fault counts). Raw v4/v6 videos remain unzipped on `I:\EEE 3-1\EEE 312\project\dataset\seg24_scratch\VIPL-HR` (2 GB, safe to delete; the caches supersede them).
* `results/s24_hr_per_video.csv` — every read-out for every video × combiner; `s24_metrics_by_stratum.csv`, `s24_primary_verdict_tests.csv`, `s24_descriptive_paired_by_stratum.csv`.
* Scripts: `scripts/s24_extract_new_vipl.m`, `s24_run_readouts.m`, `s24_analyze.m`; `logs/`.

## Closeout

18/18 protected production files byte-identical before vs after (`results/protected_files_verification.txt`); read-out copies in `src/` byte-identical to Segment 23's. Only new files were created (experiment folder, 190 cache `.mat`s in `data/processed`); no production file was edited.
