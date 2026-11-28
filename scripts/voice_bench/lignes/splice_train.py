import numpy as np, json, sys
from scipy.io import wavfile
rng=np.random.default_rng(int(sys.argv[1]) if len(sys.argv)>1 else 0)
x=np.fromfile("clean.f32",dtype=np.float32); R=16000
t=np.load("t.npy"); g=np.load("g.npy")
# runs de fenêtres consécutives (pas 0.25) du même groupe, ≥ 12 fenêtres ; on garde le cœur (retire 2 fenêtres de chaque bord)
runs=[]; i=0
while i<len(g):
    j=i
    while j+1<len(g) and g[j+1]==g[i] and abs(t[j+1]-t[j]-0.25)<0.01: j+=1
    if g[i]>=0 and j-i+1>=12: runs.append((int(g[i]),float(t[i]+0.76)+0.5, float(t[j]+0.76)-0.5, i, j))   # centre des fenêtres → plage parole sûre
    i=j+1
print("runs sûrs:",len(runs)," par groupe:",{k:sum(r[0]==k for r in runs) for k in sorted(set(r[0] for r in runs))})
groups=sorted(set(r[0] for r in runs))
# enrôlement : runs pairs ; test : runs impairs (par groupe)
enroll=[];test=[]
cnt={}
for r in runs:
    n=cnt.get(r[0],0); cnt[r[0]]=n+1
    (enroll if n%2==0 else test).append(r)
# splice : segments courts tirés des runs de test
segs=[];lab=[];wav=[np.zeros(int(0.3*R),np.float32)]; cur=0.3
prev=-1
N=int(sys.argv[2]) if len(sys.argv)>2 else 120
tg=[r for r in enroll if r[0] in groups]
for _ in range(N):
    cand=tg if (prev<0 or rng.random()<0.75) else tg
    pick=[r for r in cand if r[0]!=prev] if rng.random()<0.75 else cand
    r=pick[rng.integers(len(pick))]
    d=rng.uniform(0.7,1.6)
    if r[2]-r[1]<d: d=r[2]-r[1]
    s=rng.uniform(r[1],r[2]-d)
    a=int(s*R); b=int((s+d)*R)
    seg=x[a:b].copy(); n=len(seg); f=int(0.01*R); seg[:f]*=np.linspace(0,1,f); seg[-f:]*=np.linspace(1,0,f)
    gap=rng.uniform(0.15,0.4)
    wav.append(seg); segs.append([cur,cur+d]); lab.append(r[0]); cur+=d
    wav.append(np.zeros(int(gap*R),np.float32)+rng.normal(0,1e-4,int(gap*R)).astype(np.float32)); cur+=gap; prev=r[0]
y=np.concatenate(wav); wavfile.write("train.wav",R,(np.clip(y,-1,1)*32767).astype(np.int16))
json.dump(segs,open("train_ranges.json","w")); json.dump(lab,open("train_lab.json","w"))
json.dump([[r[3],r[4],r[0]] for r in enroll],open("enroll.json","w"))
print("segments:",len(segs),"durée moyenne %.2f s"%np.mean([b-a for a,b in segs]),"durée totale %.0f s"%cur)
