import hashlib, os, sys, pathlib
root=pathlib.Path(__file__).resolve().parents[3]   # .../matlab
here=pathlib.Path(__file__).resolve().parent
before={}
for line in (here/'protected_files_sha256_BEFORE.txt').read_text().splitlines():
    h,p=line.split('  ',1); before[p.strip()]=h.strip().upper()
lines=[]; bad=0
after=[]
for p,h in before.items():
    f=root.parent/p
    a=hashlib.sha256(f.read_bytes()).hexdigest().upper()
    after.append(f'{a}  {p}')
    ok=(a==h); bad+=0 if ok else 1
    lines.append(f"{'IDENTICAL' if ok else 'CHANGED  '}  {p}")
(here/'protected_files_sha256_AFTER.txt').write_text('\n'.join(after)+'\n')
res=f"{len(before)-bad}/{len(before)} protected production files byte-identical before vs after Segment 23 (SHA-256)."
(here/'protected_files_verification.txt').write_text(res+'\n\n'+'\n'.join(lines)+'\n')
print(res)
