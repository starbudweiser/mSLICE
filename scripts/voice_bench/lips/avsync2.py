import json, numpy as np
exec(open("lips_lab.py").read().split("# activité des lèvres par piste")[0].split("x=np.fromfile")[0])
exec("x=np.fromfile('clean.f32',dtype=np.float32)")
ft=np.load("ft.npy"); fg=np.load("fg.npy"); fb=np.load("fb.npy")
t=np.load("t.npy"); g=np.load("g.npy"); c=t+0.7575
nF=len(fr)
# activité de chaque voix à la cadence des images
ids=[k for k in sorted(set(g.tolist())) if k>=0]
act=np.zeros((len(ids),nF))
for i in range(len(t)):
    if g[i]<0: continue
    a=int((c[i]-0.125)*fps); b=int((c[i]+0.125)*fps)+1
    act[ids.index(g[i]),max(a,0):min(b,nF)]=1
# visage → groupe (visages à 1 Hz)
def iou(a,b):
    ax,ay,aw,ah=a; bx,by,bw,bh=b
    ix=max(0,min(ax+aw,bx+bw)-max(ax,bx)); iy=max(0,min(ay+ah,by+bh)-max(ay,by)); i=ix*iy
    return i/(aw*ah+bw*bh-i+1e-9)
sec={}
for j in range(len(ft)): sec.setdefault(int(round(ft[j])),[]).append(j)
def group_of(fi,box):
    s=int(round(fr[fi]["t"])); best=-1;bi=0.3
    for ds in (0,-1,1):
        for j in sec.get(s+ds,[]):
            v=iou(box,fb[j]); 
            if v>bi: bi=v;best=int(fg[j])
    return best
# suivi (IoU) puis mouvement normalisé par piste
tracks=[];active=[]
for fi,f in enumerate(fr):
    used=set();new=[]
    for k,face in enumerate(f["f"]):
        best=-1;bi=0.4
        for ti in active:
            tr=tracks[ti]
            if tr["last"]<fi-2 or ti in used: continue
            v=iou(tr["box"],face["b"])
            if v>bi: bi=v;best=ti
        if best>=0: used.add(best); tr=tracks[best]; tr["pts"].append((fi,k)); tr["last"]=fi; tr["box"]=face["b"]; new.append(best)
        else: tracks.append({"pts":[(fi,k)],"last":fi,"box":face["b"]}); new.append(len(tracks)-1); used.add(len(tracks)-1)
    active=[tt for tt in set(active+new) if tracks[tt]["last"]>=fi-2]

groups=sorted(set(fg.tolist())-{-1})
rng=np.random.default_rng(0)
# pré-calcul : pour chaque piste longue, groupe et mouvement normalisé
T=[]
for tr in tracks:
    pts=tr["pts"]
    if len(pts)<int(fps*1.5): continue
    fi=np.array([p[0] for p in pts])
    gid=[group_of(a,fr[a]["f"][b]["b"]) for a,b in pts]; gid=[q for q in gid if q>=0]
    if not gid: continue
    gr=max(set(gid),key=gid.count)
    G=[np.array(fr[a]["f"][b]["g"],dtype=np.float32) for a,b in pts]
    dg=np.zeros(len(pts))
    for i in range(1,len(pts)):
        if len(G[i])==128 and len(G[i-1])==128 and fi[i]-fi[i-1]<=2: dg[i]=np.abs((G[i]-G[i].mean())-(G[i-1]-G[i-1].mean())).mean()
    m=np.convolve(dg,np.ones(5)/5,"same"); m=(m-m.mean())/(m.std()+1e-6)
    T.append((groups.index(gr),fi,m))
def score(actmat):
    num=np.zeros((len(ids),len(groups))); cnt=np.zeros_like(num)
    for gi,fi,m in T:
        for vi in range(len(ids)):
            a=actmat[vi,np.minimum(fi,nF-1)]
            if a.std()<1e-6: continue
            a=(a-a.mean())/a.std(); num[vi,gi]+=float((m*a).sum()); cnt[vi,gi]+=len(fi)
    return num,cnt
num,cnt=score(act); Cm=num/np.maximum(cnt,1)
null=[]
for r in range(60):
    sh=rng.integers(int(8*fps),nF-int(8*fps)); null.append(score(np.roll(act,sh,axis=1))[0]/np.maximum(cnt,1))
null=np.array(null); mu_n=null.mean(0); sd_n=null.std(0)+1e-6
Z=(Cm-mu_n)/sd_n
print("scores z (permutation, décalages ≥ 8 s) — liaisons voix → visage (z ≥ 3, ≥ 60 images)")
for vi,v in enumerate(ids):
    row=[(groups[j],Z[vi,j],Cm[vi,j],int(cnt[vi,j])) for j in range(len(groups)) if cnt[vi,j]>=60]
    row.sort(key=lambda r:-r[1])
    print("voix %d : "%v+", ".join("G%d z=%.1f (r=%+.2f, n=%d)"%r for r in row[:3]))
