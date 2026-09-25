# Segment 16 Task 2 — SpO2: Audit + Literature Search

Status as of **2026-09-14**.

## Citation-verification discipline (same as `matlab/docs/Segment10_Task2_Solution_Literature_Search.md`)

- **[VERIFIED-FULL]** — read this session (publisher page, PDF, or full text via the paper-search tool's read-paper passage retrieval).
- **[VERIFIED-INDEX]** — existence/authors/venue/DOI confirmed via a paper index; full text NOT read.
- **[BLOCKED]** — indexed but unreadable this session.

---

## 1. Audit: is SpO2 genuinely live, or is this prompt's premise wrong?

**Confirmed at the code level, not taken on faith.** Read directly, not
assumed:

- `signal/LiveSpo2Estimator.kt` exists, is a real two-stage port (ratio-of-
  ratios per `spo2/ratioOfRatios.m`, then the uncentered production linear
  calibration `A - B*R` per `spo2/calibrateSpO2.m`/`SpO2_Final_Calibration_
  Spec.md`), and is genuinely independent of `RealHeartRateEstimator` (no
  shared state, confirmed by inspection of both classes).
- `MainActivity.kt` instantiates `spo2Estimator` and calls
  `spo2Estimator.update(samples)` every `refreshUi()` tick (200ms cadence),
  writing the result into `spo2Text` (`R.id.spo2Text`, present in
  `activity_main.xml`) via the `spo2_format`/`spo2_placeholder_default`
  string resources.
- `docs/SpO2_Live_Implementation.md` §Action 5 already documents a real,
  crash-free 4.5-minute on-device run (Galaxy A35, 209 SpO2 recomputes,
  range 96.72-96.94%, R range 0.5843-1.1078, clamp never triggered,
  screenshot taken) from the session that added this feature.

**Update, same day — this session's own fresh on-device confirmation.** A
physical device (the same Samsung Galaxy A35, `RFCXC0FFFSN`) became
available partway through this task, so the "fresh run" gap this section
originally flagged was closed for real, not left as a carried-forward
claim:

- `adb devices` confirmed attached; `./gradlew assembleDebug` +
  `adb install -r` + `adb shell am start` — clean install and launch.
- **SpO2 chip visibly live and updating** in a real on-device capture:
  `96.81%` shown alongside `HR: 130 bpm`, both with green "OK"-status
  pills (the capture itself was deleted at the user's request afterward —
  see `Segment16_Task3_UI_UX_Pass.md` §4).
- **`logcat` confirms real computation, not a frozen/fake value** — sample
  line from this session: `R=0.8229 rawSpo2=96.82% clampedSpo2=96.82%
  fs=17.44Hz n=437 PI_red=0.0313 PI_blue=0.0380`. R and SpO2 visibly track
  together tick to tick across the capture (consistent with
  `SpO2_Live_Implementation.md`'s own prior finding), and the clamp (90-100%)
  never fired — every raw value landed naturally in range, same as the
  original verification.
- **Zero crashes**: across every build/install/run in this session's full
  Segment 16 testing (Tasks 1-3 combined), `grep -c "FATAL EXCEPTION"`
  against the captured logs returned `0` every time, and `pidof
  com.spandan.app` stayed constant within each run.
- **Perfusion index now visible in real logs for the first time** (§3's new
  addition): `PI_red`/`PI_blue` values observed this session ranged
  roughly 0.007-0.038 across different lighting/framing moments within one
  short session — real numbers now exist where none did before, though
  still far too few (one subject, one session) to derive a defensible
  graded confidence threshold from; that remains future work, not done
  here.

**What is still NOT re-verified**: a multi-minute (4-5 min) stability run
specifically for SpO2 (this session's device time went to the shorter,
more numerous checks above plus Tasks 1 and 3's own on-device work) — the
4.5-minute crash-free run remains `SpO2_Live_Implementation.md`'s own,
not repeated fresh this session. The code-level claim (§ above) and this
session's own shorter fresh checks are both real; a long-duration re-run
is the one piece still carried forward rather than repeated.

## 2. The real work: literature search, 2023+, RGB/webcam PPG SpO2 specifically

Searched via an academic paper-search tool (PubMed/bioRxiv/medRxiv/arXiv-
spanning index) and a GitHub-indexed developer search, both restricted to
2023 onward, explicitly excluding pulse-oximeter-hardware-only papers.

### Camera/video-based SpO2 estimation — the active research landscape

- **[VERIFIED-INDEX]** Ye, Y., Gu, D. & Wang, W. — *Impact of Different Skin
  Penetration Depths of Red and Green Wavelengths on Camera-based SpO2
  Measurement*, IEEE EMBC 2023, doi:10.1109/EMBC40787.2023.10341163,
  pmid:38082996. Directly relevant to this app's channel choice
  (`ratioOfRatios.m` uses Red/Blue, not Red/Green) — investigates how
  wavelength penetration depth affects camera SpO2 accuracy. An analysis
  paper, not a drop-in replacement formula; see §3 for why this was not
  ported.
- **[VERIFIED-INDEX]** Petersen, A.G., Kjær, M.R. & Sørensen, H.B.D. —
  *Remote Estimation of Peripheral Oxygen Saturation and Pulse Rate From
  Facial Analysis Using a Smartphone Camera*, IEEE EMBC 2023,
  doi:10.1109/EMBC40787.2023.10340995, pmid:38083785. Same modality as this
  app (facial video, smartphone camera) — a directly comparable, recent
  reference point, though no numeric formula/coefficients were retrievable
  from the abstract/index alone this session.
- **[VERIFIED-INDEX]** Casalino, G., Castellano, G. & Zaza, G. — *Evaluating
  the robustness of a contact-less mHealth solution for personal and remote
  monitoring of blood oxygen saturation*, J. Ambient Intelligence and
  Humanized Computing, doi:10.1007/s12652-021-03635-6, pmcid:PMC8758222.
  Facial-video, contactless — relevant population/modality match.
- **[VERIFIED-INDEX]** *CL-SPO2Net: Contrastive Learning Spatiotemporal
  Attention Network for Non-Contact Video-Based SpO2 Estimation*,
  pmcid:PMC10885926. Deep learning — **out of scope** for a Kotlin/on-device
  port without a trained model artifact and independent validation data;
  noted for context only.
- **[VERIFIED-INDEX]** *Contactless Blood Oxygen Saturation Estimation from
  Facial Videos Using Deep Learning*, pmcid:PMC10968547. Same out-of-scope
  reasoning as above.
- **[VERIFIED-FULL]** Tang, J. et al. (incl. McDuff, D.) — *Camera
  Measurement of Blood Oxygen Saturation*, arXiv:2503.01699 (2025). Deep
  learning framework, evaluated against "traditional signal processing
  approaches" per its own abstract — **out of scope for the same reason**
  (needs a trained model + independent validation data this project does
  not have); the traditional-method comparison it references is not itself
  a portable formula.
- **[VERIFIED-INDEX]** *Notch RGB-camera based SpO2 estimation: a clinical
  trial in a neonatal intensive care unit*, pmcid:PMC10783908. Requires a
  physical optical notch filter accessory on the camera — **not applicable**
  to an unmodified phone camera.

### The one genuinely portable, well-supported idea: perfusion index as a quality signal, not a calibration change

- **[VERIFIED-FULL]** Liang, Z. et al. — *Low-Rate Wrist SpO2 Estimation
  under Micro-Perturbations Using Motion-Aware Beat Selection and
  Perfusion-Guided Calibration*, IEEE BSN 2026 (arXiv:2607.08001, read in
  full via passage retrieval this session). Uses the **perfusion index**
  (PI = AC/DC per wavelength — exactly the intermediate quantity
  `ratioOfRatios.m`'s own R formula already divides through by) as a
  **calibration-state/quality indicator**, alongside motion-aware beat
  weighting, to stabilize wrist-based SpO2 estimation. **Their full
  perfusion-*guided calibration*** (Eq. 6-7 in the paper: `R_c = R_win + b0
  + b1*PI_ref`, then a quadratic `R_c → SpO2` fit) uses coefficients
  (`b0,b1,a0,a1,a2`) **trained on their own private wrist IR/red contact-PPG
  dataset (9 subjects, Masimo Rad-G reference)** — a different modality
  (wrist, contact, dual-wavelength IR/red) from this app's (forehead,
  non-contact, RGB visible-light). **These coefficients do not transfer**;
  porting them would mean applying numbers fit on a different sensor,
  wavelength pair, and body site to this app's signal, which is not a
  genuine improvement, just a different unvalidated guess.

  **What IS directly portable and implemented this session**: the concept
  of exposing perfusion index as a quality/confidence signal, using the
  AC/DC terms this app's own `LiveSpo2Estimator.kt` already computes
  internally. This required no new coefficients, no new training data, and
  no modification to the calibration formula itself. See §3.

### Why the search stopped short of a new production calibration

Per this task's own explicit permission to say so: **no genuinely better,
independently-validated calibration formula was found that this segment
could responsibly port and evaluate.** Three compounding constraints, all
real, not excuses:

1. **The root problem is cohort variance, not channel choice.**
   `matlab/docs/SpO2_Final_Report_Section.md`'s own per-subject table
   (N=112) shows predicted SpO2 clustering almost entirely in a narrow
   96.2-96.9% band regardless of true label (which itself only spans
   87.28-99% after excluding a known sensor-fault subject) — the LOSO fit
   is close to a constant function of R because R barely correlates with
   true SpO2 in a cohort of mostly-healthy, resting subjects with almost no
   real desaturation events. A different channel pair (e.g. Ye/Gu/Wang's
   red-vs-green penetration-depth angle) could not fix a training set that
   lacks the physiological variance to fit against in the first place —
   changing the *feature* does not manufacture missing *signal*.
2. **This segment cannot touch `matlab/`** (explicit scope boundary), so no
   new calibration could be refit against this project's own validated
   112-subject pool even if a promising channel/feature idea existed.
3. **No independent reference pulse oximeter is available this session**
   (the same limitation the original `LiveSpo2Estimator.kt` implementation
   had — its own on-device verification checked "sane values, tracks R
   changes, stays in clamp range," never "matches a real oximeter," because
   no reference device existed then either). Any new formula ported from
   literature could be exercised on live data but not genuinely *validated*
   against ground truth on this device, which would make claiming an
   "improvement" dishonest regardless of how the numbers looked.

**Conclusion: the current calibration is not swapped. It is not proven
better than the alternatives found — it is that no alternative found could
be honestly shown to be better within this segment's actual constraints.**
This matches `SpO2_Final_Report_Section.md`'s own standing framing (a data-
variance and cross-camera-offset problem, not a code bug) and does not
contradict it.

## 3. What was implemented: perfusion index exposure (quality signal, not a calibration change)

`LiveSpo2Estimator.kt` now computes and exposes, per successful window:

```kotlin
lastPerfusionIndexRed = acR / dcR   // == the numerator's own AC/DC term
lastPerfusionIndexBlue = acB / dcB  // == the denominator's own AC/DC term
```

These are the exact same `acR`, `dcR`, `acB`, `dcB` values the existing
`ratioOfRatios` computation already used — **no new computation on the
signal path, purely exposing an intermediate value that already existed**.
Logged alongside the existing `Log.d` line (`PI_red=... PI_blue=...`) for
the first time.

**Deliberately NOT used to gate a new numeric confidence threshold this
session.** A defensible cutoff (e.g. "PI below X is low confidence") needs
a real distribution of PI values across varied real conditions (good/poor
lighting, different skin tones, motion) to set responsibly — this session
has no such capture. Real clinical pulse-oximeter PI thresholds (e.g. "poor
perfusion" heuristics under ~1%) do not transfer numerically either: this
app's PI is `std/mean` of raw camera pixel intensity in arbitrary units,
not a calibrated optical transmittance percentage — same units mismatch as
`SpO2_Final_Report_Section.md`'s own caution against over-interpreting this
project's uncalibrated intermediate quantities.

**What this DOES already improve, at zero new risk**: `EstimatorStatus`
(shared with Task 1, see that doc) already promotes the EXISTING hard
near-zero degenerate-DC/AC guard (`dcR==0.0 || dcB==0.0 || acB==0.0`) from a
silent `Log.w` to a named `LOW_SIGNAL_QUALITY` status the UI (Task 3) can
show distinctly. This is the honest, currently-defensible slice of "use
perfusion index for quality" — the graded numeric threshold is flagged as
the concrete next step once real varied-condition capture data exists to
set one from.

## 4. Recommendation

- **Calibration formula: unchanged.** `CALIBRATION_A`/`CALIBRATION_B`,
  the uncentered application, and the 90-100% clamp are all exactly as
  Task R/`SpO2_Live_Implementation.md` left them.
- **New, additive, zero-risk**: per-channel perfusion index now computed,
  logged, and exposed as public properties on `LiveSpo2Estimator`, plus the
  existing degenerate-signal guard is now a named, UI-visible status
  instead of a silent log line.
- **Flagged for a future session with (a) a real device and (b) either
  varied real-condition data or an independent reference oximeter**: derive
  an evidence-based graded PI threshold, and/or revisit whether a
  facial-RGB-specific (not wrist-IR) perfusion-guided calibration exists in
  future literature.

## Files

- `android/app/src/main/java/com/spandan/app/signal/LiveSpo2Estimator.kt` (modified — additive `lastStatus`/`lastPerfusionIndexRed`/`lastPerfusionIndexBlue`, calibration formula unchanged)
- `android/app/src/main/java/com/spandan/app/signal/EstimatorStatus.kt` (new, shared with Task 1/3)
