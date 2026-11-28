import numpy as np, json
X=np.load("X.npy"); t=np.load("t.npy"); g=np.load("g.npy"); L=json.load(open("lines.json")); c=t+0.7575
def unit(v): return v/(np.linalg.norm(v,axis=-1,keepdims=True)+1e-9)
mu=X[g>=0].mean(0); ids=[k for k in sorted(set(g.tolist())) if k>=0]
# noyaux : fenêtres dans des runs ≥ 6 et au-dessus de la médiane de similarité au centre
core={}
for k in ids:
    idx=np.where(g==k)[0]; Z=unit(X[idx]-mu); cen=unit(Z.mean(0)); s=Z@cen
    runs=np.zeros(len(idx),bool); st=0
    for i in range(1,len(idx)+1):
        if i==len(idx) or idx[i]!=idx[i-1]+1:
            if i-st>=6: runs[st:i]=True
            st=i
    keep=runs&(s>=np.median(s)); keep=keep if keep.sum()>=6 else runs
    core[k]=unit(unit(X[idx[keep]]-mu).mean(0))
P=np.array([core[k] for k in ids])
E=json.load(open("emb_lines.json"))
cur=[]; new=[]; sims=[]
for i,l in enumerate(L):
    m=(c>=l["s"])&(c<=l["e"]); gs=g[m]; gs=gs[gs>=0]
    cur.append(int(np.bincount(gs).argmax()) if len(gs) else -1)
    if not E[i]: new.append((-1,0,0)); continue
    V=unit(np.array([w["v"] for w in E[i]])-mu); v=unit(V.mean(0)); s=P@v
    o=np.argsort(-s); new.append((ids[o[0]],float(s[o[0]]),float(s[o[0]]-s[o[1]])))
diff=[(i,cur[i],new[i]) for i in range(len(L)) if new[i][0]!=cur[i]]
print("répliques",len(L),"| changent:",len(diff))
for i,a,(b,s,mg) in diff: print("%3d %6.1fs  avant v%-2d → après v%-2d (sim %.2f, écart %.2f) %s"%(i,L[i]["s"],a,b,s,mg,L[i]["txt"][:42]))
