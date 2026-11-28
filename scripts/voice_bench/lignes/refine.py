import numpy as np, json
X=np.load("X.npy"); t=np.load("t.npy"); g0=np.load("g.npy"); L=json.load(open("lines.json")); c=t+0.7575
V=json.load(open("votes_swift.json"))
def unit(v): return v/(np.linalg.norm(v,axis=-1,keepdims=True)+1e-9)
mu=X[g0>=0].mean(0); Z=unit(X-mu)
def profiles(g,ids,minrun=6):
    P=[]
    for k in ids:
        idx=np.where(g==k)[0]
        if len(idx)==0: P.append(np.zeros(512)); continue
        z=Z[idx]; cen=unit(z.mean(0)); s=z@cen
        run=np.zeros(len(idx),bool); st=0
        for i in range(1,len(idx)+1):
            if i==len(idx) or idx[i]!=idx[i-1]+1:
                if i-st>=minrun: run[st:i]=True
                st=i
        keep=run&(s>=np.median(s)); keep=keep if keep.sum()>=minrun else (run if run.sum()>=minrun else np.ones(len(idx),bool))
        P.append(unit(z[keep].mean(0)))
    return np.array(P)
ids=[k for k in sorted(set(g0.tolist())) if k>=0]
def agreement(g):
    n=a=0
    for i,l in enumerate(L):
        r=V[i]
        if not r.get("confident"): continue
        m=(c>=l["s"])&(c<=l["e"]); gs=g[m]; gs=gs[gs>=0]
        if len(gs)==0: continue
        cur=int(np.bincount(gs).argmax()); n+=1; a+= (cur==r["voice"])
    return a,n
print("avant : accord fenêtres/vote par réplique %d/%d"%agreement(g0))
for margin,minsim in ((0.10,0.25),(0.15,0.25),(0.20,0.30)):
    g=g0.copy(); 
    for it in range(4):
        P=profiles(g,ids); S=Z@P.T; o=np.argsort(-S,1); best=o[:,0]; sb=S[np.arange(len(S)),best]; ss=S[np.arange(len(S)),o[:,1]]
        cur=np.array([ids.index(x) if x>=0 else -1 for x in g])
        # une fenêtre change de voix si une autre voix la prend nettement mieux que la sienne
        own=np.where(cur>=0,S[np.arange(len(S)),np.maximum(cur,0)],-1)
        move=(g>=0)&(best!=cur)&(sb>=minsim)&(sb-own>=margin)
        # fenêtres ambiguës (-1) rattachées si très nettes
        grab=(g<0)&(sb>=0.4)&(sb-ss>=0.15)
        g=g.copy(); 
        for i in np.where(move|grab)[0]: g[i]=ids[best[i]]
    print("marge %.2f sim≥%.2f : fenêtres déplacées %d, rattachées %d | accord %d/%d"%(margin,minsim,int(move.sum()),int(grab.sum()),*agreement(g)), "| changements totaux:",int((g!=g0).sum()))
    if margin==0.10: np.save("g_refined.npy",g)
