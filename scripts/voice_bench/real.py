import json,sys,numpy as np
from scipy.cluster.hierarchy import linkage,fcluster
E=json.load(open(sys.argv[1]+"/emb.json")); HOP=E["hop"]
X=np.array([r["v"] for r in E["windows"]],dtype=np.float32); X/= (np.linalg.norm(X,axis=1,keepdims=True)+1e-9)
Z=linkage(X,method="average",metric="cosine"); sims=np.sort(1-Z[:,2])[::-1]
print("fenêtres",len(X),"| similarités des 15 dernières fusions :",np.round(sims[-15:],2))
for tau in (0.30,0.38,0.45,0.55):
    lab=fcluster(Z,1-tau,criterion="distance"); sizes=np.sort(np.bincount(lab)[1:])[::-1]*HOP
    print("τ=%.2f : %d groupes, ≥4 s : %d, parole couverte par ces groupes : %.0f %%"%(tau,len(sizes),(sizes>=4).sum(),100*sizes[sizes>=4].sum()/sizes.sum()), "| tailles (s) :",np.round(sizes[:8]).astype(int))
