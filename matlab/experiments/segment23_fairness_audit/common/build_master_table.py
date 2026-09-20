import pandas as pd, numpy as np, pathlib
here = pathlib.Path(__file__).resolve().parent
base = here.parent
repo = base.parents[2]
L = pd.read_csv(base / 'task5_estimator_swap_audit/results/task5_matrix_long.csv')
t6 = pd.read_csv(base / 'task6_chrom_pos_untuned_baseline/results/task6_summary_by_pool.csv')

def cell(method, est, pool):
    r = L[(L.method == method) & (L.estimator == est) & (L.pool == pool)]
    if r.empty: return 'n/a'
    r = r.iloc[0]; return f'{r.MAE:.2f} / {r.RMSE:.2f} / {r.pearsonR:.2f}'

E1 = 'E1 whole-clip fft'; E2 = 'E2 naive windowed'; E3 = 'E3 RAKF native (exp, b=1)'; E4 = 'E4 RAKF original (division)'
E5 = 'E5 LGI-paper readout 256/90%'; E6 = 'E6 state-space tracker'
rows = [
 ('CHROM (production, wavelet, whole-clip FFT)', 'CHROM (prod, wavelet)', E1, 'no (reference; T6 de-tuned it)', 'unchanged'),
 ('POS (production, wavelet, whole-clip FFT)', 'POS (prod, wavelet)', E1, 'no (reference; T6 de-tuned it)', 'unchanged'),
 ('CHROM, native windowed form (T6 L4)', 'T6:CHROM L4 native windowed', None, 'YES (T6)', 'No — pooled MAE worse, per-subject n.s.'),
 ('POS, native windowed Algorithm 1 (T6 L4)', 'T6:POS L4 native windowed', None, 'YES (T6)', 'No — pooled MAE worse, per-subject n.s.'),
 ('GREEN', 'GREEN (Seg4/18 form)', E1, 'no', 'unchanged'),
 ('cPACE Stage 1 + CHROM (global q̂, no wavelet)', 'cPACE Stage1+CHROM (global q)', E1, 'YES (T1: windowed q̂)', 'No — windowed q̂ ≈ null'),
 ('cPACE Stage 1 + POS (exact no-op with global q̂)', 'cPACE Stage1+POS (global q)', E1, 'YES (T1)', 'No'),
 ('cPACE Full bw 0.30 (no wavelet)', 'cPACE Full bw0.30', E1, 'YES (T1: windowed q̂)', 'No — still loses'),
 ('cPACE Full bw 0.15 (no wavelet)', 'cPACE Full bw0.15', E1, 'YES (T1: windowed q̂)', 'No — still loses'),
 ('CIELab a* — as tested (Seg 18)', 'CIELab a* (orig, Seg18)', E1, 'baseline for T2', 'unchanged'),
 ('YCbCr Cb — as tested', 'YCbCr Cb (orig, Seg18)', E1, 'baseline for T2', 'unchanged'),
 ('YCbCr Cr — as tested', 'YCbCr Cr (orig, Seg18)', E1, 'baseline for T2', 'unchanged'),
 ('CIELab a* — NATIVE pipeline (Yang 2016)', 'a* NATIVE (Task2)', E1, 'YES (T2)', 'No — worse than as-tested'),
 ('YCbCr Cb — NATIVE', 'Cb NATIVE (Task2)', E1, 'YES (T2)', 'No'),
 ('YCbCr Cr — NATIVE', 'Cr NATIVE (Task2)', E1, 'YES (T2)', 'No'),
 ('2SR — forehead box (Seg 22)', '2SR (Seg22, forehead box)', E1, 'baseline for T3', 'unchanged'),
 ('2SR — skin-masked forehead box', '2SR skin-masked forehead (Task3)', E1, 'YES (T3)', 'No'),
 ('2SR — skin-masked whole face', '2SR skin-masked face (Task3)', E1, 'YES (T3)', 'No — helps on motion, still loses'),
 ('LGI projection + whole-clip FFT (Seg 22)', 'LGI projection (Seg22)', E1, 'baseline for T4', 'unchanged'),
 ('LGI + paper read-out (256/90 %, 0.5–2 Hz)', 'LGI projection (Seg22)', E5, 'YES (T4/T5)', 'No — CHROM/POS gain equally'),
 ('LGI + state-space tracker', 'LGI projection (Seg22)', E6, 'YES (T4/T5)', 'No — tracker does not help LGI'),
 ('CHROM + paper windowed read-out', 'CHROM (prod, wavelet)', E5, 'YES (T4/T5)', 'CANDIDATE read-out (not promoted)'),
 ('POS + paper windowed read-out', 'POS (prod, wavelet)', E5, 'YES (T4/T5)', 'CANDIDATE read-out (not promoted)'),
 ('CHROM + state-space tracker', 'CHROM (prod, wavelet)', E6, 'YES (T4/T5)', 'CANDIDATE read-out (not promoted)'),
 ('POS + state-space tracker', 'POS (prod, wavelet)', E6, 'YES (T4/T5)', 'CANDIDATE read-out (not promoted)'),
 ('naive windowed HR, CHROM (no smoothing)', 'CHROM (prod, wavelet)', E2, 'YES (T5/T7, wavelet chain)', 'Still not adopted (beats whole-clip on MAIN_112, not on v2)'),
 ('naive windowed HR, POS', 'POS (prod, wavelet)', E2, 'YES (T5/T7)', 'same'),
 ('RAKF original (division), CHROM', 'CHROM (prod, wavelet)', E4, 'baseline for T7', 'unchanged'),
 ('RAKF NATIVE (Eq. 12 exponent, β=1), CHROM', 'CHROM (prod, wavelet)', E3, 'YES (T7)', 'No — slightly worse than division form'),
 ('RAKF NATIVE, POS', 'POS (prod, wavelet)', E3, 'YES (T7)', 'No'),
]
out = ('| method (best-known config) | re-tested native this segment? | verdict changed? | MAIN_112 (UBFC+VIPL v1) MAE / RMSE / r | UBFC (5) | VIPL v1 (107) | VIPL v2 motion (20) |\n|'
       + '---|' * 7 + '\n')
for name, m, e, nat, ch in rows:
    if m.startswith('T6:'):
        mm = m[3:]
        def c(p):
            r = t6[(t6.method == mm) & (t6.pool == p)].iloc[0]; return f'{r.MAE:.2f} / {r.RMSE:.2f} / {r.pearsonR:.2f}'
        cells = [c('MAIN_112'), c('UBFC'), c('VIPL_v1'), c('VIPL_v2_motion')]
    else:
        cells = [cell(m, e, 'MAIN_112'), cell(m, e, 'UBFC'), cell(m, e, 'VIPL_v1'), cell(m, e, 'VIPL_v2_motion')]
    out += f'| {name} | {nat} | {ch} | ' + ' | '.join(cells) + ' |\n'
q = pd.read_csv(repo / 'results/metrics/segment6_task_q_anchored_windowed_hr_summary.csv')
def mt(col):
    e = q[col] - q.HR_groundtruth; r = np.corrcoef(q[col], q.HR_groundtruth)[0, 1]
    return f'{e.abs().mean():.2f} / {np.sqrt((e ** 2).mean()):.2f} / {r:.2f}'
for nm, col in [('whole-clip CHROM, Seg 6 pre-wavelet data (reference for next 3 rows)', 'HR_wholeClip'),
                ('gating only (Seg 6 Task P, VIPL-107 only)', 'HR_gatingOnly'),
                ('gating + window-1 continuity (Task P)', 'HR_gatingPlusWindow1Continuity'),
                ('gating + anchored continuity (Task Q)', 'HR_gatingPlusAnchoredContinuity')]:
    out += f'| {nm} | no (not part of this segment; VIPL-107 only, pre-wavelet) | unchanged | n/a | n/a | {mt(col)} | n/a |\n'
(here / '_master_table.md').write_text(out, encoding='utf-8')
print(out)
