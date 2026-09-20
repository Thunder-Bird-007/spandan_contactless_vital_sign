# Segment 21 — Literature search: motion-robust pulse-extraction combiners

Search pass run 2026-09-20 (Cowork session, no code changed, nothing run). Follows
directly from Segment 18 (`matlab/docs/Segment18_ColorSpace_Ablation.md`), whose own
20-subject VIPL v2 (large head motion) result showed every single-channel method tested
(green, CIELab a\*, YCbCr Cb, YCbCr Cr) collapsing under motion — a\* best but still only
r=0.11, MAE 14.5 bpm, and green/Cb going *negative* (r=-0.21/-0.39, worse than chance).
Purpose: find real, checkable prior work on rPPG methods specifically designed for
motion robustness, since Segment 18 confirmed motion is a genuine, unaddressed weak
point, not evaluate the CIELab paper any further (that is closed, see Segment 18's own
verdict).

**Important scoping note, checked against Segment 10 Task 2 before starting**: this is
NOT a new lead. `matlab/docs/Segment10_Task2_Solution_Literature_Search.md` §7-8 already
named PBV, LGI and OMIT (via the rPPG-Toolbox assessment) and listed them as **Tier 2,
item 14**: *"PBV / LGI / OMIT as additional classical combiners alongside CHROM/POS,
using rPPG-Toolbox as the reference for correctness"* — flagged 2026-09-13, never
started (Segment 11's own closing note confirms "no other Tier 1/2/3 candidate... has
been started" beyond cPACE and the Gaussian filter). This segment is that item, finally
read in full and evaluated for fit, plus 2SR (not in the original Tier 2 list) and the
VIPL-HR dataset paper itself (checked for its own motion-scenario baseline numbers).

Same citation-verification convention as Segment 10 Task 2: **[VERIFIED-FULL]** read in
full this session, **[VERIFIED-INDEX]** existence/metadata confirmed only,
**[BLOCKED]** indexed but a specific link/route failed (recorded, not silently dropped,
route to retry given).

---

## 0. Mechanistic caveat that applies to every candidate below

Kaur, Lakshminarayanan & Saini (2026) — the isochromatic-pulsation paper Segment 10/11
already built cPACE from — states explicitly that the isochromatic contaminant "is
conflated with the chromatic signal by every rPPG method we evaluated, **including
chrominance-based methods (POS, CHROM) and other projection or decomposition methods
(OMIT, LGI, PBV, ICA)**." That means none of the candidates below are expected to fix
Segment 10/11's waveform-morphology/notch-fidelity problem — they were not designed to,
and cPACE (already evaluated, not adopted) is still the only candidate that targets that
axis. This segment is about a **different, separate axis**: gross HR accuracy collapsing
under large head motion (Segment 18's finding), not isochromatic contamination. Keep
these two problems distinct; a future reader should not assume adopting 2SR or LGI would
also fix the notch/PLV problem, or vice versa.

---

## 1. 2SR — Spatial Subspace Rotation

**[VERIFIED-FULL — fetched `https://sstuijk.estue.nl/publications/tbme15-2SR.pdf`]**
Wang, W., Stuijk, S. & de Haan, G. (2016). *A Novel Algorithm for Remote
Photoplethysmography: Spatial Subspace Rotation.* **IEEE Trans. Biomed. Eng. 63(9),
1974–1984.** DOI not directly captured this session, PMID 26685222 (PubMed-indexed,
cross-checked). Reference implementation: `github.com/partofthestars/Spatial-Subspace-Rotation`.

- **Method**: per frame, eigendecompose the 3×3 correlation matrix of skin-pixel RGB
  (C = VᵀV/N) to get an orthonormal skin-pixel subspace. Between frames in a short
  temporal window (stride `l`, default 20 frames at 20fps in the paper), compute the
  rotation matrix between the two frames' subspaces; the off-diagonal (sine-like) terms
  capture the pulse-induced color rotation, largely independent of overall intensity
  changes. Authors state "implementation only requires a few lines of MATLAB code."
- **Why claimed motion-robust**: rotation is measured as a *direction* change relative to
  the subject's own instantaneous skin-color subspace, not against a fixed prior
  (CHROM's fixed skin-tone assumption, PBV's fixed spectral signature) — so it adapts
  per-frame rather than assuming a global constant.
- **Validation** (54 videos / 108,000 frames, three challenge categories): **body-motion
  is where the gain is largest** — correlation improvement +36% over CHROM, +37% over
  PBV, +70% over ICA; SNR +1.66dB vs CHROM, +1.69dB vs PBV. Skin-tone and exercise-recovery
  categories also favor 2SR, by smaller margins.
- **Stated limitation, relevant here**: needs a well-defined skin-pixel mask; degrades
  once non-skin pixels exceed 10-30% of the ROI ("2SR could be worse than ICA, CHROM and
  PBV" in that regime) — worth checking against Spandan's own forehead-box ROI, which is
  a fixed geometric crop, not a segmented skin mask, so some non-skin inclusion (hairline,
  shadow) is expected and its effect on 2SR specifically is untested.
- **Implementation cost for Spandan**: low. No spectral calibration needed (unlike PBV),
  no state-space tracking needed (unlike LGI); a 3×3 eigendecomposition per stride is
  cheap in MATLAB (`eig` on a 3×3 matrix). One tunable parameter (stride `l`) with no
  universally-optimal value stated — would need its own small sweep on Spandan's data,
  the same way `alpha` was swept for the Harmonic-Selective Gaussian filter in Segment 12.

## 2. LGI — Local Group Invariance

**[VERIFIED-FULL — fetched `https://openaccess.thecvf.com/content_cvpr_2018_workshops/papers/w27/Pilz_Local_Group_Invariance_CVPR_2018_paper.pdf`]**
Pilz, C.S., Zaunseder, S., Krajewski, J. & Blazek, V. (2018). *Local Group Invariance for
Heart Rate Estimation from Face Videos in the Wild.* **CVPR Workshops 2018.**

- **Method**: projects RGB features onto a group-invariant subspace via eigenvalue
  decomposition of the pixel covariance, removing motion-induced variance while
  preserving the blood-volume-pulse component, then models HR as a time-varying-frequency
  stochastic process (state-space / Gaussian-mixture approximation) rather than a single
  FFT peak-pick.
- **Why claimed motion-robust**: explicitly targets "in the wild" video — rigid head
  motion, non-rigid expression, and illumination change together, not just one of them.
- **Validation, the single most relevant number found this session** (their own
  benchmark, their own dataset — not yet tested on Spandan's data):

  | Scenario | ICA r/RMSE | 2SR(SSR) r/RMSE | POS r/RMSE | **LGI r/RMSE** |
  |---|---|---|---|---|
  | Resting | 0.97/1.4 | 0.97/2.0 | 0.96/2.1 | 0.96/3.3 |
  | **Head Rotation** | 0.16/10.8 | 0.51/7.6 | 0.56/5.3 | **0.97/2.9** |
  | Gym Exercise | 0.41/16.6 | 0.08/18.6 | 0.09/23.1 | **0.63/13.1** |
  | Urban Conversation | 0.13/23.1 | 0.14/15.4 | 0.30/12.5 | **0.72/4.3** |

  The **Head Rotation** row is the closest published analogue to Segment 18's own VIPL v2
  "large head movement" pool (max rotation 92° roll / 105° pitch / 104° yaw per the
  VIPL-HR paper, §4 below) — LGI is the only method that stays near its resting-scenario
  correlation under rotation in this table, while POS/2SR/ICA all degrade sharply. This
  is the strongest single piece of evidence found for any candidate against Segment 18's
  specific failure mode.
- **Stated limitations, read plainly rather than only citing the favorable table**: LGI is
  slightly *worse* than the others at rest (0.96 vs 0.97); carries a persistent ~4bpm bias
  on their full dataset; confuses pedal cadence with heart rate on some Gym-Exercise
  outliers; their own dataset is small (25 subjects, mostly one ethnicity) and they
  themselves call for "public challenges" due to lack of a shared benchmark — the same
  small-N caution this project applies to its own results applies here too.
- **Implementation cost for Spandan**: higher than 2SR. The projection step is a
  covariance-eigendecomposition, similar cost to 2SR/cPACE; the harder part is the
  state-space HR-frequency tracker (Markov chain over discretized frequency states),
  which is new machinery for this codebase — nothing currently in `matlab/src/` does
  frequency tracking this way (closest existing analogue is
  `pipeline/residualAdaptiveKalmanHR.m`, already built and already rejected on the
  MATLAB side per Segment 13's own note — worth explicit awareness before assuming a new
  state-space tracker will fare differently here). A staged implementation (projection
  first, evaluated with the *existing* `fftHeartRate.m`; state-space tracker only if the
  projection alone doesn't already help) is the lower-risk path.

## 3. PBV — Blood Volume Pulse signature

**[VERIFIED-FULL — fetched `https://pure.tue.nl/ws/files/4007065/446846624760338.pdf`]**
de Haan, G. & van Leest, A. (2014). *Improved motion robustness of remote-PPG by using
the blood volume pulse signature.* **Physiological Measurement 35(9), 1913–1926.**
DOI: 10.1088/0967-3334/35/9/1913. PMID 25159049.

- **Method**: projects onto a fixed, empirically-derived "signature" RGB vector
  representing the known relative amplitude of blood-volume-pulse absorption per channel,
  suppressing anything that doesn't match that spectral signature (motion artifacts are
  typically broadband/non-specific in wavelength, so they get suppressed).
- **Validation**: modest motion gain — 68% vs 60% correct-pulse-rate-detection vs CHROM on
  6 fitness/exercise videos, ~1dB SNR improvement. On stationary subjects it's slightly
  *worse* than CHROM (~1dB SNR loss) — a real accuracy-for-robustness tradeoff, not a
  free win.
- **Practical blocker for this project, not present for 2SR/LGI**: the signature vector
  P_bv requires **camera spectral response characterization** (H_R, H_G, H_B) and an
  assumed skin reflectance model — i.e., calibration specific to the recording camera's
  actual color filters. Spandan's whole design point is "any random video, any camera, no
  calibration" (explicitly restated by Abrar for `run_spandan_interactive.m`, Segment
  17). PBV's own motion-robustness gain is also the smallest of the three combiners found
  here. **Ranked lowest priority of the three combiners for this reason — not because the
  method is weak in general, but because it assumes something Spandan's own project scope
  explicitly rules out.**

## 4. OMIT — Orthogonal Matrix Image Transformation (Face2PPG)

**[VERIFIED-FULL — fetched `arxiv.org/abs/2202.04101` abstract + `arxiv.org/pdf/2202.04101` full text]**
Álvarez-Casado, C. & Bordallo-López, M. (2023). *Face2PPG: An Unsupervised Pipeline for
Blood Volume Pulse Extraction From Faces.* **IEEE J. Biomedical and Health Informatics**,
doi:10.1109/JBHI.2023.3307942. arXiv:2202.04101.

- **Method**: QR-decompose the ROI's RGB pixel matrix (A=QR); project out the dominant
  eigenvector q₁ of Q (which captures the largest, mostly non-pulse variation — lighting,
  motion) via P = I − SSᵀ; extract the BVP estimate from the projected data's second
  component.
- **What it is actually validated for, read carefully — this changes the ranking from
  what the name alone suggests**: OMIT's own stated claim is robustness to **compression
  artifacts**, not motion (best gains are on MAHNOB/COHFACE, heavily-compressed
  datasets). Motion handling in their full pipeline comes from *separate* components —
  rigid face-mesh normalization and dynamic multi-region ROI selection — not from the
  OMIT projection itself.
- **Their own motion-specific numbers (LGI-PPGI dataset, their multi-region pipeline)**:
  Resting 1.8→1.3 MAE, **Rotation 5.2→5.1 (essentially no improvement)**, Talking
  9.5→5.8, Gym 23.2→7.5. **The Rotation scenario — the one closest to Segment 18's own
  failure mode — is where OMIT's own reported gain is smallest of the four scenarios
  tested.** This directly demotes OMIT's priority for Spandan's specific problem, even
  though it is a real, published, positive-result method for other conditions
  (compression, talking, gym).
- **Verdict**: not a good fit for the specific motion problem Segment 18 found. Worth
  keeping on record as a candidate for a *different* future problem (e.g. if Spandan ever
  processes heavily-compressed/re-encoded video, which the Own-Dataset HEVC re-encoding
  work makes newly relevant) rather than pursuing now.

## 5. VIPL-HR dataset paper — checked for its own motion-scenario baseline numbers

**[VERIFIED-FULL — fetched `ar5iv.labs.arxiv.org/html/1810.04927`, the primary
`jdl.link` PDF link is currently BLOCKED, see note below]**
Niu, X., Han, H., Shan, S. & Chen, X. (2018/2019). *VIPL-HR: A Multi-modal Database for
Pulse Estimation from Less-Constrained Face Video.* ACCV 2018 / arXiv:1810.04927.

- Confirms Spandan's own v2 pool is genuinely their "Large Motion" scenario (Situation 2
  in their Table 3, lab environment, 1m distance) with real quantified rotation up to
  **92° roll, 105° pitch, 104° yaw** — a severe rotation range, materially harder than
  LGI's own benchmark scenario is likely to be (their paper doesn't quantify rotation
  angle, but "head rotation" in a lab demo is rarely 90°+). **This is a genuine caution
  against assuming LGI's reported 0.97 head-rotation correlation will transfer directly**
  — Segment 18's v2 pool may simply be a harder motion regime than LGI's own validation.
  Worth measuring, not assuming either way.
- The paper's own Table 4 benchmarks four non-deep methods (Haan2013=CHROM, Wang2017=POS,
  Tulyakov2016, Niu2018's own) but **only pooled across all 9 scenarios, not broken out
  per-scenario** — so it does not answer "how do CHROM/POS themselves do on v2 specifically,"
  which is exactly the gap Segment 18 left open (Segment 18 tested green/a*/Cb/Cr on the
  motion pool but never re-ran production CHROM/POS on it). Their pooled RMSE (Haan2013
  16.9bpm, Wang2017 17.2bpm, Tulyakov2016 21.0bpm, all scenarios combined including dark/
  bright/motion/phone/exercise) is much worse than Spandan's own v1-only pooled numbers
  (CHROM 7.83/POS 7.22 MAE), consistent with v1/source1 being deliberately the easiest,
  most-validated slice and not informative about v2 specifically.
- **[BLOCKED]** The paper's primary PDF host, `https://www.jdl.link/doc/2011/2019110_2018111615545295.pdf`,
  failed this session with an expired-SSL-certificate error on their server (not a
  content-access restriction) — a route to retry later once/if their certificate is
  renewed. Not a dead end: `ar5iv.labs.arxiv.org/html/1810.04927` (the arXiv HTML mirror)
  served the same content successfully and is what this section is based on, so the
  paper's content is not actually missing, only the one specific link.

---

## 6. Ranking for Spandan's specific problem (Segment 18's motion-collapse finding)

Ordered by (expected motion-robustness gain, evidenced above) ÷ (implementation cost +
fit with project constraints):

1. **LGI** — strongest specific evidence for the closest-matching failure mode (head
   rotation), but highest implementation cost (new state-space tracker) and unproven
   transfer to VIPL v2's more extreme rotation range and to Spandan's non-deep-learning,
   MATLAB-native pipeline.
2. **2SR** — cheap, "few lines of MATLAB," real but more modest motion gains in its own
   validation, no calibration or new tracking machinery needed. Lowest-risk first step.
3. **PBV** — real but smaller motion gain, and requires camera spectral calibration that
   conflicts with Spandan's own "any random video, no calibration" design goal. Lowest
   priority of the three combiners.
4. **OMIT** — deprioritized for *this* problem specifically; its own numbers show minimal
   head-rotation gain. Keep on record for a compression-robustness question instead,
   should one arise (relevant given the Own Dataset's HEVC re-encoding work).

**Also identified, not a new algorithm but a real evaluation gap**: production CHROM/POS
(with the wavelet default) have never been run on the VIPL v2 motion pool at all —
Segment 18 only tested green/a\*/Cb/Cr there. Measuring CHROM/POS's own motion-pool
numbers is a near-zero-cost prerequisite before claiming any new combiner "beats
production under motion," since there is currently no production baseline on that pool
to beat.

## Scope note

Nothing in this document has been implemented, run, or validated on Spandan's own data.
It is a search result, exactly like Segment 10 Task 2 was — every candidate above still
has to survive this project's own evaluation standards (small pool first, per-subject
regressions reported honestly, no adoption without an ablation, stratified by skin tone
and motion level rather than one pooled number). See `matlab/docs/Segment22_*` (queued,
not started) for the proposed evaluation plan.

## Related prior work in this repo, checked for overlap

`matlab/docs/Segment10_Task2_Solution_Literature_Search.md` §7 (rPPG-Toolbox assessment)
and §8 Tier 2 item 14 already named PBV/LGI/OMIT as untried candidates on 2026-09-13; this
document is that item actually read and evaluated, plus 2SR (new to this project) and the
VIPL-HR paper's own motion-scenario context (new to this project). Segment 18's own
`matlab/docs/Segment18_ColorSpace_Ablation.md` is the empirical finding that motivated
this search. See `matlab/docs/Literature_Review_Master.md` for the full cross-project
paper index, including everything found in Segment 10 Task 2 alongside this segment's
finds, organized in one place.
