import pandas as pd, numpy as np
POOLS=['UBFC','VIPL_v1','MAIN_112','VIPL_v2_motion']
def full(df, key='method', pools=POOLS, extra_filter=None):
    """markdown: one row per method, per pool: MAE / RMSE / r / n>10bpm"""
    out=[]
    hdr='| '+key+' | '+' | '.join(f'{p} MAE / RMSE / r / severe' for p in pools)+' |'
    out.append(hdr); out.append('|'+'---|'*(len(pools)+1))
    for m in df[key].drop_duplicates():
        row=[str(m)]
        for p in pools:
            r=df[(df[key]==m)&(df.pool==p)]
            if r.empty: row.append('n/a'); continue
            r=r.iloc[0]; n=int(r.n)
            row.append(f"{r.MAE:.2f} / {r.RMSE:.2f} / {r.pearsonR:.2f} / {int(r.severeGT10)}/{n}")
        out.append('| '+' | '.join(row)+' |')
    return '\n'.join(out)
