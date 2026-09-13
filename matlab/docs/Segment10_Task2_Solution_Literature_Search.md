# Segment 10 Task 2 — Solution Literature Search (for Task 1's six findings)

Search pass run 2026-09-13 (Cowork planning session, no code changed, nothing run).
Purpose: for each of the six findings in
`docs/Segment10_Task1_Waveform_Fidelity_Audit.md`, find real, checkable prior work
worth trying — papers, open-source implementations, or established techniques from
adjacent fields — rather than inventing fixes from first principles.

> **REVISION 2, same day (2026-09-13).** Revision 1 was written before three papers in
> `H:\EEE 312 project\Contactless Vital Sign\Research Paper\` had been read. Two of
> them change the priority order materially, so this revision restructures rather than
> appends. **Nothing from Revision 1 was deleted** — the ceiling argument that opened
> Revision 1 is still here, demoted from "the finding that reframes everything" to "one
> of two competing explanations," because a second, more mechanical explanation for the
> same numbers has since turned up (§0). Also added: the GitHub-toolbox assessment that
> Revision 1 listed as "not yet assessed," and a consolidated candidate list (§8).

## Citation-verification status (this project's own standing discipline)

- **[VERIFIED-FULL]** — read this session (publisher page or the PDF on disk).
- **[VERIFIED-INDEX]** — existence/authors/venue/DOI confirmed via publisher or PubMed
  index page; full text NOT read.
- **[BLOCKED]** — indexed but unreadable this session. Listed so it isn't silently
  dropped.

---

## 0. The mechanism that explains three of the six findings at once

**[VERIFIED-FULL — read from `Research Paper/d5e15f06-…pdf`]** Kaur, G.,
Lakshminarayanan, V. & Saini, S.S. (2026). *Missed isochromatic cardiac pulsation in
remote photoplethysmography: detection, impact, and removal.* **Biomedical Optics
Express 17(7):3832**, doi:10.1364/BOE.599752 (received 20 Apr 2026, published 24 Jun
2026).

**The claim: the standard rPPG signal model that this entire project is built on is
incomplete.** There are *two* cardiac-frequency signals in skin video, not one:

1. **Chromatic pulsation** — wavelength-dependent haemoglobin absorption. This is what
   CHROM, POS, and every textbook derivation assume is the whole signal.
2. **Isochromatic pulsation** — ballistocardiographic modulation of skin surface
   geometry plus changes in the effective scattering cross-section of the dermal
   vascular bed. It lies along the skin's **mean reflectance direction** q̂, not along
   the haemoglobin absorption axis.

The paper states the isochromatic component "is conflated with the chromatic signal by
every rPPG method we evaluated, including chrominance-based methods (POS, CHROM) and
other projection or decomposition methods (OMIT, LGI, PBV, ICA)," and — critically —
that because both sit at the same cardiac frequency, **"temporal filtering cannot
separate them."** No filter change of any kind fixes this.

### Why this matters so much here: it predicts Task 1's findings

| Task 1 finding | What this paper says |
|---|---|
| **(4)** 40–47% show real phase distortion surviving rigid-lag correction | The two components combine with "a phase offset that varies between subjects and recordings **and even breathing cycles within the same subject**"; the isochromatic envelope swings ~3× over 3–4 s respiratory cycles vs <1.5× for chromatic, so "the phase of the extracted signal wobbles at the respiratory rate **even in the complete absence of motion**." A single rigid lag *cannot* exist for such a signal. |
| **(1)** lag search unreliable on 34–46% of subjects | Same mechanism. If instantaneous phase genuinely wobbles with respiration, the lag search isn't failing — **it is correctly reporting that no single lag exists.** This reframes Task 1's own "single most load-bearing finding" from a methodological weakness into a possible physical measurement. |
| **(5)** mismatch energy concentrated in fundamental / 2nd-harmonic bands | Their Fig. 1(d): the chromatic signal has "sharp, well-defined peaks at the cardiac frequency and its second harmonic with rapid spectral roll-off"; the isochromatic signal has a broader, lower-Q peak and **"does not have a discernible second harmonic."** A chromatic/isochromatic mixture therefore mis-states energy at exactly the fundamental and 2nd harmonic — precisely where Task 1 found the mismatch. |

### It also independently predicts something Spandan already measured but never explained

POS's basis vectors are orthogonal to [1,1,1] by construction, so its isochromatic
leakage starts near zero and grows with skin-colour angle θ. CHROM's are not, so its
leakage is **0.58 even at θ = 0°**. Fitted across 712 ROIs from three cohorts, theory
matched observation with RMSE 0.023 (POS) and 0.075 (CHROM). **Prediction: POS should
beat CHROM on waveform fidelity.** Spandan's own pooled numbers say exactly that —
POS MAE 7.22 / r 0.62 vs CHROM 7.83 / r 0.53 — a pattern this project has recorded
repeatedly and never had a mechanism for.

### Numbers worth having on record

- Fraction of cardiac-band energy lying along q̂ (i.e. predominantly isochromatic),
  median: **83%** UBFC-Phys, **69%** CMU-rPPG India, **78%** CMU-rPPG Sierra Leone.
  The contaminant is not a small correction; it dominates.
- Skin-colour angle θ to [1,1,1]: ~5–10° lightly pigmented, **30–50° darkly
  pigmented**; haemoglobin absorption axis sits at 76–88°.
- POS's σ-ratio combination assumes the cardiac signal sits ~57° from its first basis
  vector. Measured medians: 96.6 ± 19.0° (UBFC-Phys rest), 109.6 ± 9.6° (speech),
  109.6 ± 6.0° (CMU India), 115.5 ± 11.1° (CMU Sierra Leone). **None match, and above
  90° the σ-ratio combination is destructive** — it cancels the cardiac signal at the
  combination step, after which "it cannot be recovered by any downstream processing."
- cPACE vs POS heart-rate MAE across four cohorts: **1.7 / 3.7 / 1.7 / 1.1 BPM** vs
  **2.8 / 9.5 / 16.8 / 17.8 BPM**. The enormous gains are on the darkly-pigmented
  cohorts.

### The fix, and why it is cheap for this project specifically

cPACE Stage 1 is a **subject-adaptive projector** that deletes the isochromatic
direction before any pulse extraction:

```
q̂ = [R̄, Ḡ, B̄] / ‖[R̄, Ḡ, B̄]‖        (per-channel temporal means, normalised)
P  = I − q̂ q̂ᵀ                         (3×3)
x_c(t) = P · x(t)                       (apply to the raw R/G/B traces)
```

The paper's own framing: unlike the chromatic absorption direction p̂, which must be
estimated, **q̂ "is directly observable as it is the normalized temporal mean of each
color channel"** — no estimation uncertainty, no training, no new data.

**Spandan already computes exactly those three numbers.** The raw per-channel DC means
are already used for CHROM/POS normalisation and again for the SpO2 ratio-of-ratios.
Stage 1 is therefore on the order of five lines of MATLAB inserted between
`extractROISignals.m` and the existing `chromCombine.m`/`posCombine.m` calls — additive,
reversible behind a toggle, and it touches nothing on the do-not-touch list. Stages 2
(phase-optimal eigenvector in the remaining 2-D chrominance plane) and 3 (in-band noise
suppression) are larger and should not be attempted before Stage 1 is measured alone.

### One more gift: a fidelity metric that needs no ground truth

The paper evaluates fidelity using **cross-ROI phase-locking value**, on the grounds
that "ROIs sharing a common arterial supply receive the cardiac pulse with a fixed
phase relationship determined by the pulse transit time within the arterial tree."

This matters because Task 1's every number is gated behind an alignment step that fails
34–46% of the time. A cross-ROI PLV metric **sidesteps ground truth entirely** — and
Spandan already has four-region extraction built and cached from Task N
(forehead / glabella / malar / cheek). This is computable today on existing `.mat`
files with no new extraction.

### Honest caveats before anyone gets excited

- Their comparison uses MediaPipe FaceMesh ROIs; Spandan's own Task H/J work found
  face-mesh ROIs *hurt* on its notch metric. The ROI question and the projection
  question are independent, but the cPACE numbers were not obtained on Spandan's ROI.
- Their cohorts are 35 fps (UBFC-Phys) and 15 fps (CMU-rPPG) — the 15 fps cohort is
  close to VIPL's real rates, which is encouraging for transfer.
- The headline gains are largest where skin is darkly pigmented. VIPL is a Chinese
  cohort, UBFC predominantly European; **neither is a good proxy for the Bangladeshi
  subjects in this project's own planned self-collected set (pipeline stage 7).** If
  this paper is right, that set will sit at a higher θ than either public dataset and
  should be expected to perform *worse* under the current pipeline — which is worth
  knowing before collecting it, not after.

---

## 0b. The competing explanation, kept from Revision 1: the information-theoretic ceiling

**[VERIFIED-FULL]** Ben Ahmed, A. — *Template Collapse and Information-Theoretic Limits
in Camera rPPG Pulse Morphology Restoration*, arXiv:2606.03802. (Metadata caution: the
rendered venue string may have been mangled in extraction; the arXiv ID and content are
confirmed. Same paper Task K already checked for a *different* claim.)

Its untested second claim: a **ground-truth waveform-correlation ceiling of r ≈ 0.601**,
and a sampling argument that the dicrotic notch, at ~50–100 ms, "falls within 1–3 sample
points at 30 fps, placing it at or below the joint temporal resolution and SNR floor of
the measurement."

Task 1's median r of 0.44–0.52 sits just under that stated ceiling.

**How this now relates to §0.** These are two different explanations for the same
numbers — an information floor versus a specific, removable contaminant — and they make
*different predictions*, which is what makes them separable:

- If the **ceiling** explanation dominates, notch confidence should scale with effective
  frame rate, and cPACE Stage 1 should change little.
- If the **isochromatic** explanation dominates, cPACE Stage 1 should improve
  phase-stability and cross-ROI PLV measurably at *unchanged* frame rate.

Both tests are cheap and both use data already on disk, so run both rather than
arguing. Note they are not mutually exclusive — the honest prior is that both are
partly true.

**The zero-new-data ceiling test (unchanged from Revision 1):** correlate Task 1's
existing per-subject notch confidence against the existing per-subject effective-fps
figures already on record from the Segment 8 source2 work (where several VIPL scenarios
run at a real ~16 fps against a claimed 25).

---

## 1. Finding: lag search unreliable 34–46% of the time

**Read §0 first** — part of this may be physical, not methodological. The techniques
below still apply to whatever residual is genuinely algorithmic.

- **[VERIFIED-INDEX]** Qin, Zhang et al. — *Subsample time delay estimation via improved
  GCC-PHAT algorithm*, IEEE Xplore doc/4697676. GCC-PHAT whitens the cross-spectrum
  before the inverse transform, sharpening the correlation peak — the standard fix for
  the broad, ambiguous peaks plain cross-correlation produces on periodic signals.
  **MATLAB ships `gccphat`** (Phased Array System Toolbox) — check with `ver` first, per
  Task D's toolbox-check discipline.
- **[VERIFIED-INDEX]** *Frequency-Sliding Generalized Cross-Correlation: A Sub-band Time
  Delay Estimation Approach*, arXiv:1910.08838. Delay per frequency sub-band rather than
  once broadband, which yields a **per-band consistency check**: a genuine physical delay
  is consistent across bands, a cycle-slip is not. That is a usable *confidence* signal,
  not just a better point estimate — and per §0 it may also distinguish "cycle-slip" from
  "genuinely unstable phase."
- **[VERIFIED-INDEX]** Radjef, L. & Tahar, O. — *A New Algorithm for Measuring Pulse
  Transit Time from ECG and PPG Signals*, SSRN 4354000. The PTT literature removes
  whole-cycle ambiguity by construction, aligning *landmarks* (systolic feet) rather
  than raw waveforms.
- **Cross-ROI PLV (§0)** — the strongest option, because it removes the need to align to
  ground truth at all.

---

## 2. Finding: modest waveform correlation (median r 0.44–0.52), bimodal for Branch 2

- **[VERIFIED-FULL]** **Dominguez-Hernandez, S., Paez, G. & Padilla, M. (2026).
  *Harmonic-Selective Gaussian Filtering for Morphology and Timing Preservation in PPG
  Signals*. Sensors 26(12):3710, doi:10.3390/s26123710.** A structural alternative to
  `morphology/adaptiveHarmonicFilter.m`:
  - Gaussian band-*pass* filters centred on k·f₀ instead of a hard rectangular comb, with
    bandwidth scaling **σ = α·f₀** so it tracks heart rate automatically.
  - Explicitly claims preservation of "systolic peak, diastolic decay, and dicrotic
    notch" timing with phase distortion avoided.
  - States that even forward–backward (zero-phase) IIR filtering "preserve[s] phase but
    fail[s] to maintain waveform morphology" — exactly the gap Task 1 finding (4)
    measured.
  - Max cross-correlation at zero lag; usable reconstruction from 3–5 harmonic bands.
  A hard-edged comb rings in the time domain, which is a textbook cause of the morphology
  damage Task 1 found; a Gaussian-tapered comb is the standard remedy. **Still the best
  substantive filter-side candidate** — though note §0's warning that no filter can fix
  isochromatic contamination, so this should be tested *after* or *alongside* cPACE
  Stage 1, not instead of it.
- **[VERIFIED-INDEX]** *Evaluating RGB channels in remote photoplethysmography: a
  comparative study with contact-based PPG*, Frontiers in Physiology 14:1296277 (2023) —
  methodology reference for the exact comparison Task 1 performs.
- **[VERIFIED-INDEX]** *High-Fidelity rPPG Waveform Reconstruction from Palm Videos Using
  GANs*, Sensors 26(2):563 — **out of scope** (deep learning). Fidelity benchmark only.

---

## 3. Finding: harmonic confusion, 4–5× worse on Branch 2

- **[VERIFIED-FULL]** Dubey, H., Kumaresan, R. & Mankodiya, K. — *Harmonic sum-based
  method for heart rate estimation using PPG signals affected with motion artifacts*,
  J. Ambient Intelligence and Humanized Computing 9:137–150 (2018),
  doi:10.1007/s12652-016-0422-z. MAE 0.7359 bpm (SD 0.8328) on the 2015 IEEE SP Cup set.
  Core idea: **score a candidate fundamental by the summed energy of its harmonic
  series**, not by its own peak height. A 2f₀ impostor scores badly by construction,
  because the f₀/2 energy that would have to exist is absent. **Caveat: their strongest
  result leans on an accelerometer reference to model the artifact's own fundamental,
  which a camera-only pipeline does not have — the scoring idea transfers, that part
  does not.**
  **Second-order note from §0:** the isochromatic component has *no* second harmonic
  while the chromatic component does. Harmonic-sum scoring is therefore doing double
  duty here — it discriminates against harmonic impostors *and* implicitly favours the
  chromatic component over the isochromatic one.
- **[VERIFIED-INDEX]** de Cheveigné, A. & Kawahara, H. — *YIN, a fundamental frequency
  estimator for speech and music*, JASA (2002). The canonical octave-error-resistant
  estimator; halving/doubling errors are structurally disfavoured by design.
- **[VERIFIED-INDEX]** *Harmonic Summation-Based Robust Pitch Estimation in Noisy and
  Reverberant Environments*, arXiv:2509.16480 (2026).

Applies to the **evaluation/diagnostic path only** — `heartrate/fftHeartRate.m` is on the
do-not-touch list. This is the first candidate found that attacks the Field Guide's named
core open problem: a score measuring *correctness* rather than *spectral concentration*.

---

## 4. Finding: 40–47% show genuine phase distortion surviving lag correction

**§0 offers a physical mechanism for this (respiration-rate phase wobble from a
two-component mixture). The filter-side explanations below are complementary, not
competing — both can contribute.**

- **[VERIFIED-FULL]** Lapitan et al. (2024) — *Estimation of phase distortions of the
  photoplethysmographic signal in digital IIR filtering*, Scientific Reports 14,
  doi:10.1038/s41598-024-57297-3 (PDF also on disk at
  `Research Paper/s41598-024-57297-3.pdf`). **This is the SAME paper Android Task H
  already checked** — but Task H only answered the *delay* question (confirming
  `filtfilt` is zero-phase, concern inapplicable by construction). Its morphology
  results were never examined, and they are about *shape* distortion, which zero-phase
  filtering does **not** remove:
  - Tested Butterworth, Bessel, Elliptic, Chebyshev I/II at orders 2/4/6, quantified
    with skewness SQI, Reflection Index and ejection-time-compensated (ETc) — not just
    peak delay.
  - **Upper cutoff is the dominant driver**: systolic peak delay 18.7 ± 5.1 ms
    (0.1–10 Hz) → 51.8 ± 6.8 ms (0.1–5 Hz) → **166.8 ± 13.6 ms (0.1–2 Hz)**.
  - Chebyshev II worst overall (RI deviations 20–40%, ETc 100–150 ms).
  - **Recommendation for morphological PPG analysis: Butterworth, Bessel or Elliptic at
    2nd order.**
  Relevance: Branch 1's `bandpassClean.m` is Butterworth **order 2** (matches) cutting at
  **4 Hz**; Branch 2's `bandpassMorphology.m` is Butterworth **order 3** at 0.5–8 Hz —
  one order above the recommendation, a documented deliberate deviation. **Cheap implied
  check: re-run the synthetic-notch test at order 3 vs order 2.**
- **[VERIFIED-FULL — read from `Research Paper/23b5a1b1-…pdf`]** Goda, M.Á., Charlton,
  P.H. & Behar, J.A. (2024) — *pyPPG: a Python toolbox for comprehensive
  photoplethysmography signal analysis*, Physiol. Meas. **45(4):045001**,
  doi:10.1088/1361-6579/ad33a2. Its preprocessing section makes a directly relevant
  parameter argument:
  - pyPPG bandpasses **0.5–12 Hz** (4th-order Chebyshev II, zero-phase). Rationale
    stated verbatim: *"The 12 Hz low-pass cut-off filter was used to avoid time-shifting
    of fiducial points (particularly pulse onset and dicrotic notch)."*
  - And the warning that matters most for Branch 2: *"whilst fiducial point detection
    can be simpler with lower low-pass cut-off frequencies such as **8 Hz**, the drawback
    of using lower cut-off frequencies is that they **significantly distort the pulse
    wave shape** and reduce the accuracy with which the pulse onset and other fiducial
    points can be identified."*
  - **Branch 2 uses exactly 0.5–8 Hz.** A validated, benchmarked toolbox names that exact
    ceiling as too low for notch work.
  - Benchmarks: F1 88.19% peak detection over 2054 PSG recordings / 91M+ beats; mean
    absolute error <10 ms for all fiducial points against 3000+ manual annotations;
    74 biomarkers; optional SQI via Li & Clifford (2012) template matching.
  - Honest tension to record: pyPPG's chosen Chebyshev II is the family Lapitan et al.
    rank *worst* for morphology. The two are reconcilable (pyPPG runs it zero-phase and
    at a far higher cutoff, where Lapitan's distortion is smallest) but this should be
    stated, not glossed.

### The convergence worth noticing

pyPPG says ≥12 Hz is needed to keep notch timing honest. The template-collapse paper
says the notch spans 1–3 samples at 30 fps. **At 25–30 fps, Nyquist is 12.5–15 Hz, so a
12 Hz passband is not merely hard, it is essentially unavailable** — there is no room
for a transition band, and several VIPL scenarios are worse still at a real ~16 fps
(Nyquist 8 Hz, i.e. *below* even Branch 2's existing 8 Hz ceiling).

Two independent papers, arriving from different directions, both land on **camera frame
rate as the binding constraint on notch morphology.** That makes a higher-fps capture
experiment the highest-information acquisition-side test available — and unlike the
public datasets, the Android app's capture rate is something this project actually
controls.

---

## 5. Finding: mismatch energy concentrated in fundamental / 2nd-harmonic bands

**§0 explains this directly** (isochromatic component lacks a 2nd harmonic; chromatic
has a sharp one). Treat §0 as the primary hypothesis. Secondary options:

- **[VERIFIED-FULL]** Abdulrahaman, L.Q. (2023) — *Two-Stage Motion Artifact Reduction
  Algorithm for rPPG Signals Obtained from Facial Video Recordings*, Arabian J. Science
  and Engineering, doi:10.1007/s13369-023-07845-2. Stage 1: partition into 0.5 s
  segments, mean-shift each, recombine. Stage 2: DWT denoising (Symlet-8, level 5, soft
  threshold, SURE). Reports r 0.5→0.97, RMSE 17.2→3.41 bpm on 129 measurements / 33
  participants. **Read those gains with this project's own scepticism** — far larger
  than anything Spandan has seen at N=112, and this project has been burned by
  small-pool inflation before (HR r=0.824 at N=18 → 0.314 at N=112). Stage 1 is cheap
  and additive and is the part worth testing; Stage 2 overlaps `waveletDenoise.m`
  already adopted — though the **different wavelet config (Symlet-8 / level 5 / SURE vs
  this project's db4 / level 3 / universal)** is a cheap, well-defined ablation on
  infrastructure that already exists.

---

## 6. Finding: notch detector's boolean output useless at scale (100/100 "detected")

- **[VERIFIED-FULL]** pyPPG (full citation in §4). Provides an independent, validated,
  maintained fiducial detector including the notch, benchmarked at <10 ms MAE against
  manual annotation. **A second independent detector is the cleanest way to decide
  whether "100/100 detected" is an IEM-specific artefact or a property of the data.**
  Open source: **github.com/godamartonaron/GODA_pyPPG**, docs at pyppg.readthedocs.io,
  also distributed via physiozoo.com. Python — so this is a cross-language check, and
  the practical route is exporting Task 1's prototype beats to `.csv`/`.mat` and running
  pyPPG over them offline rather than any in-MATLAB integration.
- **[VERIFIED-INDEX]** Elgendi, M. — *Photoplethysmogram second derivative review*. The
  SDPPG a–b–c–d–e landmarks give a mechanically different, **graded rather than boolean**
  notch criterion (the c/d waves persist as inflections even when the notch is too
  shallow to be a true local minimum).
- **[VERIFIED-FULL]** van Putten, L.D., Mathieu, A.J.W. & Wegerif, S. (2025) — *Automated
  Signal Quality Assessment for rPPG: A Pulse-by-Pulse Scoring Method Designed Using
  Human Labelling*, Applied Sciences 15(20):10915, doi:10.3390/app152010915. 2,366
  human-labelled pulses (Vision-MD: 4,036 videos / 1,270 participants), independent
  clinical validation set; binary F₁ = 0.93; usable-signal yield 58% → 95% vs prior
  clustering. Its labelling criteria explicitly include *"diastolic inflection points"* —
  i.e. human raters made exactly the graded notch-plausibility judgement IEM's boolean
  fails to make. Authors state it does not address harmonic locking.
- **[VERIFIED-FULL, negative result — recorded so it isn't re-searched]** Elgendi, M.,
  Martinelli, I. & Menon, C. (2024) — *Optimal signal quality index for remote
  photoplethysmogram sensing*, npj Biosensing 1:5, doi:10.1038/s44328-024-00002-1.
  Recommends NSQI (σ²_signal/σ²_noise, threshold < 0.293). **Explicitly does NOT address
  harmonic-vs-fundamental discrimination** — do not adopt expecting that it will.
- **[VERIFIED-FULL, partial]** Rahbar, S., Ferrero, R., Toscani, S., Ronaghi, S. &
  Pegoraro, P.A. (2024) — *Photoplethysmography Signal Quality Assessment Using
  Instantaneous Harmonic Analysis via Taylor-Fourier Method*, IEEE I2MTC, 1–6. Tracks
  instantaneous per-harmonic amplitude/phase and flags violations of the expected
  constant amplitude-ratio relationship between harmonics — same family as the
  harmonic-sum idea in §3, usable as a per-window confidence signal.

---

## 7. Toolbox / GitHub assessment (was "not yet assessed" in Revision 1)

| Resource | What it actually is | Verdict for this project |
|---|---|---|
| **github.com/ubicomplab/rPPG-Toolbox** (NeurIPS 2023) | Python. Implements **seven unsupervised/classical methods — GREEN, ICA, CHROM, LGI, PBV, POS, OMIT** — plus deep models. Supports 9 datasets incl. **UBFC-rPPG and PURE**. Metrics: MAE, RMSE, MAPE, Pearson, SNR, Bland-Altman. "Responsible AI" licence. No MATLAB version. | **Most useful item here, for one specific purpose: an independent cross-check of this project's own CHROM/POS.** §0 argues CHROM leaks isochromatic energy even at θ=0 — if that is right, Spandan's CHROM/POS are *correctly implemented and still contaminated*, and a reference implementation agreeing with them would confirm the problem is the method, not the code. Note the licence is **not** a standard OSI licence — check its terms before borrowing any code into this MIT-licensed repo; reading it for reference is fine, copying may not be. Also supplies **PBV / LGI / OMIT**, three classical combiners Spandan has never tried. |
| **github.com/zx-pan/Awesome-rPPG** | Curated paper/resource index. Covers classical methods (GREEN, CHROM, 2SR) and deep learning, 16+ datasets, and lists 4 toolboxes (iPhys, pyVHR, rPPG-Toolbox, Remote Bio-Sensing). Limited coverage of signal quality/morphology specifically. Only ~3 commits visible; most recent papers listed are 2024. | **Low priority — a bibliography, not a tool**, and it appears not to have been updated since 2024, so it would have missed everything in §0 and §2. Use for back-references only. |
| **github.com/KegangWangCCNU/open-rppg** | Python, **exclusively deep learning** (PhysMamba, RhythmMamba, PhysFormer, TSCAN, EfficientPhys, PhysNet, FacePhys…). MIT licence for code (pretrained weights under their own terms). Actively maintained (78★, 48 commits, models through 2025). | **Out of scope** — this project is explicitly classical DSP. Nothing to borrow. |
| **pyVHR** | Python rPPG framework (listed in Awesome-rPPG; the GitHub link found earlier resolves to a fork, so treat the canonical location as unconfirmed). | **Not assessed in depth.** Overlaps rPPG-Toolbox's role; if a reference implementation is wanted, use rPPG-Toolbox first. |
| **github.com/godamartonaron/GODA_pyPPG** | Python. Validated PPG fiducial-point + biomarker toolbox (see §4/§6). | **Second-highest value after rPPG-Toolbox**, for the notch-detector cross-check specifically. |

---

## 8. Consolidated candidate list — everything we could try, ranked

Ordered by (information gained) ÷ (effort + risk). Every item is additive; none requires
touching a do-not-touch file.

**Tier 0 — costs almost nothing, decides what else is worth doing**

1. **Ceiling test.** Correlate Task 1's per-subject notch confidence vs. per-subject
   effective fps (both already on disk). Tests §0b.
2. **Cross-ROI phase-locking value.** Compute PLV between Task N's cached
   forehead/glabella/malar/cheek traces. A ground-truth-free fidelity metric that
   sidesteps the 34–46% alignment failure entirely. Tests §0's framework and gives
   every later experiment a cheaper evaluation axis.
3. **Synthetic-notch filter-distortion test.** Push a synthetic PPG waveform with a known
   notch through `bandpassClean.m` (Bw2, 0.7–4 Hz), `bandpassMorphology.m` (Bw3,
   0.5–8 Hz), and Bw2 variants at 8/10/12 Hz ceilings. Isolates how much of finding (4)
   is filter-induced. Tests §4.
4. **σ-ratio / cardiac-angle check.** Measure the actual cardiac angle to POS's first
   basis vector on Spandan's own data, against POS's ~57° design assumption. If
   Spandan's medians also exceed 90° like all four of the paper's cohorts, POS is
   partially cancelling its own signal. Pure measurement, no change.

**Tier 1 — the substantive candidates**

5. **cPACE Stage 1** (`P = I − q̂q̂ᵀ` before CHROM/POS). ~5 lines, toggle-gated, uses DC
   means already computed. Evaluate on HR accuracy *and* on PLV/phase-stability, since
   §0's claimed gains are largely about phase fidelity. **Highest expected value in this
   document.**
6. **Harmonic-Selective Gaussian filtering** as an alternative to
   `adaptiveHarmonicFilter.m`'s hard comb (σ = α·f₀). Ablate on the 5-subject UBFC notch
   pool first.
7. **Harmonic-sum scoring** in the evaluation path; re-run Task 1's harmonic-confusion
   detector and see whether the 4–5× Branch 2 penalty shrinks.
8. **Branch 2 cutoff/order sweep** — 8 vs 10 vs 12 Hz ceiling, order 3 vs order 2 — driven
   by pyPPG's explicit "8 Hz distorts shape" warning and Lapitan's order-2 recommendation.
   Bounded by Nyquist per subject, which is itself the finding.

**Tier 2 — worth doing, more effort or narrower payoff**

9. **GCC-PHAT + sub-band delay consistency** to replace/cross-check
   `estimateLagPolarityByGroundTruth.m`, giving graded confidence instead of a binary flag.
10. **pyPPG cross-check** of the notch gate: export Task 1 prototype beats, run pyPPG's
    detector offline, compare against `notchDetectIEM.m`'s 100/100.
11. **SDPPG (second-derivative) notch criterion** as a graded in-MATLAB alternative to
    IEM's boolean.
12. **Wavelet-config ablation**: Symlet-8 / level 5 / SURE vs the adopted db4 / level 3 /
    universal, on existing `waveletDenoise.m` infrastructure.
13. **Segment-wise mean-shifting** (two-stage paper's Stage 1) as an additive pre-step.
14. **PBV / LGI / OMIT** as additional classical combiners alongside CHROM/POS, using
    rPPG-Toolbox as the reference for correctness (read, don't copy — licence).

**Tier 3 — acquisition-side, for the self-collected set (pipeline stage 7)**

15. **Higher-fps capture experiment** (60 fps on Android where the device supports it).
    Both §0b and §4 converge on frame rate as the binding constraint for notch work;
    this is the only knob on that constraint this project actually controls.
16. **Skin-tone-aware evaluation plan.** §0 predicts Bangladeshi subjects sit at higher θ
    than either public dataset and will therefore perform *worse* under the current
    pipeline. Record the prediction now, before collecting, so the result is a test
    rather than a surprise.

---

## Scope note

Nothing in this document has been implemented, run, or validated. It is a search result,
not a finding. Every candidate above still has to survive this project's own evaluation
standards — small pool first, honest reporting, no adoption without an ablation.

## Still unread

- **[BLOCKED]** Nothing outstanding. Revision 1's three blocked items were all resolved:
  the isochromatic paper and pyPPG were supplied as PDFs in
  `H:\EEE 312 project\Contactless Vital Sign\Research Paper\`, and the Lapitan paper was
  retrieved from nature.com (the PMC mirror was the blocked route, not the paper).

## Related prior work in this repo, checked for overlap

`Research Paper/rPPG_Morphology_Solutions.md` (July 2026, 40 KB) covers the earlier
morphology push — widening the band, deterministic polarity, ensemble averaging, PCHIP
upsampling, ABPF, tiling, landmark ROI — essentially all of which this project has since
implemented and tested. It contains **no** reference to isochromatic pulsation, cPACE,
phase-locking value, harmonic-sum scoring, GCC-PHAT, skin-tone/melanin effects, or the
12 Hz cutoff argument. The material in this document is additive to it, not a
re-derivation of it.
