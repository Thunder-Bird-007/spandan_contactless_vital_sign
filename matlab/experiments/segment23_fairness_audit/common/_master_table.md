| method (best-known config) | re-tested native this segment? | verdict changed? | MAIN_112 (UBFC+VIPL v1) MAE / RMSE / r | UBFC (5) | VIPL v1 (107) | VIPL v2 motion (20) |
|---|---|---|---|---|---|---|
| CHROM (production, wavelet, whole-clip FFT) | no (reference; T6 de-tuned it) | unchanged | 7.83 / 11.87 / 0.53 | 3.26 / 5.05 / 0.96 | 8.05 / 12.09 / 0.48 | 8.85 / 12.64 / 0.54 |
| POS (production, wavelet, whole-clip FFT) | no (reference; T6 de-tuned it) | unchanged | 7.22 / 10.85 / 0.62 | 3.77 / 6.15 / 0.94 | 7.38 / 11.02 / 0.58 | 10.56 / 16.06 / 0.31 |
| CHROM, native windowed form (T6 L4) | YES (T6) | No — pooled MAE worse, per-subject n.s. | 10.88 / 21.78 / 0.19 | 3.16 / 4.84 / 0.97 | 11.24 / 22.26 / 0.15 | 9.17 / 14.85 / 0.42 |
| POS, native windowed Algorithm 1 (T6 L4) | YES (T6) | No — pooled MAE worse, per-subject n.s. | 11.45 / 24.85 / 0.08 | 3.16 / 4.84 / 0.97 | 11.84 / 25.41 / 0.01 | 15.42 / 21.40 / 0.16 |
| GREEN | no | unchanged | 14.98 / 19.49 / 0.09 | 12.56 / 18.88 / 0.29 | 15.10 / 19.52 / 0.03 | 21.80 / 24.97 / -0.21 |
| cPACE Stage 1 + CHROM (global q̂, no wavelet) | YES (T1: windowed q̂) | No — windowed q̂ ≈ null | 8.94 / 18.50 / 0.29 | 3.77 / 6.15 / 0.94 | 9.18 / 18.88 / 0.24 | 10.05 / 15.49 / 0.36 |
| cPACE Stage 1 + POS (exact no-op with global q̂) | YES (T1) | No | 8.68 / 16.45 / 0.28 | 3.77 / 6.15 / 0.94 | 8.91 / 16.78 / 0.22 | 9.04 / 14.86 / 0.41 |
| cPACE Full bw 0.30 (no wavelet) | YES (T1: windowed q̂) | No — still loses | 10.91 / 15.29 / 0.45 | 2.44 / 3.66 / 0.98 | 11.30 / 15.62 / 0.35 | 24.95 / 44.16 / -0.18 |
| cPACE Full bw 0.15 (no wavelet) | YES (T1: windowed q̂) | No — still loses | 9.69 / 14.40 / 0.46 | 3.18 / 4.50 / 0.99 | 9.99 / 14.70 / 0.38 | 16.61 / 22.19 / -0.05 |
| CIELab a* — as tested (Seg 18) | baseline for T2 | unchanged | 9.53 / 14.59 / 0.43 | 3.70 / 6.15 / 0.95 | 9.80 / 14.87 / 0.35 | 14.51 / 20.13 / 0.11 |
| YCbCr Cb — as tested | baseline for T2 | unchanged | 14.90 / 19.76 / 0.13 | 17.98 / 22.40 / 0.88 | 14.76 / 19.63 / 0.04 | 22.05 / 25.66 / -0.39 |
| YCbCr Cr — as tested | baseline for T2 | unchanged | 11.92 / 16.59 / 0.32 | 12.15 / 20.47 / 0.40 | 11.91 / 16.39 / 0.28 | 20.52 / 23.27 / -0.23 |
| CIELab a* — NATIVE pipeline (Yang 2016) | YES (T2) | No — worse than as-tested | 16.49 / 26.40 / 0.16 | 18.92 / 23.21 / 0.43 | 16.37 / 26.54 / 0.16 | 21.23 / 25.79 / -0.10 |
| YCbCr Cb — NATIVE | YES (T2) | No | 19.75 / 30.16 / 0.13 | 16.88 / 23.11 / 0.45 | 19.89 / 30.45 / 0.13 | 23.84 / 29.02 / -0.28 |
| YCbCr Cr — NATIVE | YES (T2) | No | 15.68 / 23.67 / 0.17 | 18.92 / 23.21 / 0.43 | 15.53 / 23.69 / 0.15 | 21.44 / 24.70 / 0.23 |
| 2SR — forehead box (Seg 22) | baseline for T3 | unchanged | 9.52 / 14.23 / 0.39 | 3.57 / 6.01 / 0.91 | 9.79 / 14.50 / 0.31 | 21.34 / 26.51 / -0.18 |
| 2SR — skin-masked forehead box | YES (T3) | No | 10.13 / 18.91 / 0.20 | 2.85 / 4.64 / 0.96 | 10.47 / 19.32 / 0.12 | 21.32 / 27.86 / 0.07 |
| 2SR — skin-masked whole face | YES (T3) | No — helps on motion, still loses | 10.34 / 18.32 / 0.31 | 13.80 / 17.17 / 0.59 | 10.18 / 18.37 / 0.24 | 15.39 / 22.12 / -0.10 |
| LGI projection + whole-clip FFT (Seg 22) | baseline for T4 | unchanged | 9.24 / 14.06 / 0.46 | 2.65 / 3.77 / 0.98 | 9.55 / 14.37 / 0.38 | 16.93 / 22.24 / -0.12 |
| LGI + paper read-out (256/90 %, 0.5–2 Hz) | YES (T4/T5) | No — CHROM/POS gain equally | 7.76 / 11.06 / 0.60 | 4.83 / 8.97 / 0.84 | 7.90 / 11.15 / 0.52 | 12.28 / 17.06 / 0.13 |
| LGI + state-space tracker | YES (T4/T5) | No — tracker does not help LGI | 9.48 / 15.62 / 0.38 | 3.77 / 5.72 / 0.94 | 9.74 / 15.93 / 0.30 | 21.57 / 32.62 / -0.06 |
| CHROM + paper windowed read-out | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.38 / 9.10 / 0.64 | 2.64 / 4.82 / 0.97 | 6.55 / 9.25 / 0.56 | 8.25 / 11.47 / 0.53 |
| POS + paper windowed read-out | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.70 / 9.34 / 0.63 | 2.48 / 4.45 / 0.98 | 6.89 / 9.51 / 0.54 | 9.50 / 12.64 / 0.50 |
| CHROM + state-space tracker | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.54 / 8.77 / 0.68 | 3.14 / 4.49 / 0.98 | 6.70 / 8.92 / 0.62 | 9.24 / 12.40 / 0.30 |
| POS + state-space tracker | YES (T4/T5) | CANDIDATE read-out (not promoted) | 6.29 / 8.41 / 0.69 | 2.84 / 4.44 / 0.97 | 6.45 / 8.55 / 0.62 | 9.30 / 14.91 / 0.28 |
| naive windowed HR, CHROM (no smoothing) | YES (T5/T7, wavelet chain) | Still not adopted (beats whole-clip on MAIN_112, not on v2) | 7.59 / 10.32 / 0.55 | 3.19 / 4.40 / 0.99 | 7.79 / 10.52 / 0.48 | 9.56 / 12.08 / 0.31 |
| naive windowed HR, POS | YES (T5/T7) | same | 7.31 / 10.09 / 0.55 | 2.76 / 4.09 / 0.99 | 7.52 / 10.29 / 0.47 | 10.74 / 13.84 / 0.36 |
| RAKF original (division), CHROM | baseline for T7 | unchanged | 10.73 / 17.14 / 0.34 | 9.82 / 14.73 / 0.50 | 10.77 / 17.25 / 0.34 | 10.33 / 15.06 / 0.20 |
| RAKF NATIVE (Eq. 12 exponent, β=1), CHROM | YES (T7) | No — slightly worse than division form | 11.95 / 19.28 / 0.28 | 17.00 / 25.55 / -0.05 | 11.71 / 18.94 / 0.32 | 10.64 / 16.04 / 0.19 |
| RAKF NATIVE, POS | YES (T7) | No | 10.49 / 14.76 / 0.31 | 21.52 / 28.10 / -0.12 | 9.97 / 13.83 / 0.37 | 17.12 / 22.94 / 0.05 |
| whole-clip CHROM, Seg 6 pre-wavelet data (reference for next 3 rows) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 9.35 / 18.37 / 0.28 | n/a |
| gating only (Seg 6 Task P, VIPL-107 only) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 10.38 / 15.66 / 0.32 | n/a |
| gating + window-1 continuity (Task P) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 12.47 / 21.58 / 0.24 | n/a |
| gating + anchored continuity (Task Q) | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | 10.62 / 19.42 / 0.21 | n/a |
