import warnings,sys; warnings.filterwarnings("ignore")
sys.path.insert(0,"3d")
import torch, numpy as np, coremltools as ct
from speakerlab.models.campplus.DTDNN import CAMPPlus
torch.set_grad_enabled(False)

import torch.nn.functional as F
from speakerlab.models.campplus import layers as L
REC=[];TS=None;CALL=0
def seg_pooling(self, x, seg_len=100, stype='avg'):
    # équivalent exact pour une longueur fixe : moyennes par segment (le dernier peut être plus court : ceil_mode) puis répétition
    global CALL
    if REC is not None: REC.append(x.shape[-1]); T=x.shape[-1]
    else: T=TS[CALL]; CALL+=1
    n=(T+seg_len-1)//seg_len   # longueurs fixes relevées une fois
    outs=[]
    for k in range(n):
        seg=x[..., k*seg_len:min((k+1)*seg_len,T)].mean(-1,keepdim=True)
        outs.append(seg.expand(*seg.shape[:-1], min((k+1)*seg_len,T)-k*seg_len))
    return torch.cat(outs,-1)
orig=L.CAMSequential if False else None
net0=CAMPPlus(feat_dim=80,embedding_size=512); net0.load_state_dict(torch.load('campplus_voxceleb.bin',map_location='cpu')); net0.eval(); xx=torch.randn(1,150,80); ref=net0(xx)
L.CAMLayer.seg_pooling=seg_pooling
net=CAMPPlus(feat_dim=80,embedding_size=512); sd=torch.load("campplus_voxceleb.bin",map_location="cpu"); net.load_state_dict(sd); net.eval()
print('patch cos',float(torch.cosine_similarity(ref,net(xx))))
TS=list(REC);REC=None;CALL=0;print('T par couche',sorted(set(TS)),len(TS))
x=xx
CALL=0
tr=torch.jit.trace(net,x,strict=False,check_trace=False)
m=ct.convert(tr,inputs=[ct.TensorType(name="fbank",shape=(1,150,80))],outputs=[ct.TensorType(name="embedding")],convert_to="mlprogram",compute_precision=ct.precision.FLOAT16,minimum_deployment_target=ct.target.macOS14)
CALL=0
m.save("CAMPPlus.mlpackage"); print("écrit")
for T in (150,):
    x=np.random.randn(1,T,80).astype(np.float32); r=net(torch.from_numpy(x)).numpy()[0]; c=m.predict({"fbank":x})["embedding"][0]
    print(T,"cos coreml/torch",float(r@c/np.linalg.norm(r)/np.linalg.norm(c)))
