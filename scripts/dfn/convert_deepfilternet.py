import warnings, sys, numpy as np, torch, torch.nn as nn, coremltools as ct
warnings.filterwarnings("ignore")
from df.enhance import init_df, df_features
torch.set_grad_enabled(False)
model, st, _ = init_df(); model.eval()
T = int(sys.argv[1]) if len(sys.argv) > 1 else 500
K = 8
class SG(nn.Module):                       # GRU à état imposé de l'extérieur
    def __init__(s, g): super().__init__(); s.g = g; s.h0 = None; s.hn = None
    def forward(s, x, h=None):
        y, s.hn = s.g(x[:, K:], s.h0)           # les K premières images ne servent qu'au contexte des convolutions
        return torch.cat([torch.zeros(1, K, y.shape[2]), y], 1), s.hn
sg_enc, sg_erb, sg_df = SG(model.enc.emb_gru.gru), SG(model.erb_dec.emb_gru.gru), SG(model.df_dec.df_gru.gru)
model.enc.emb_gru.gru, model.erb_dec.emb_gru.gru, model.df_dec.df_gru.gru = sg_enc, sg_erb, sg_df
class Net(nn.Module):
    def __init__(s, m): super().__init__(); s.m = m
    def forward(s, feat_erb, feat_spec, h_enc, h_erb, h_df):
        sg_enc.h0, sg_erb.h0, sg_df.h0 = h_enc, h_erb, h_df
        fs = feat_spec.squeeze(1).permute(0, 3, 1, 2)
        e0, e1, e2, e3, emb, c0, lsnr = s.m.enc(feat_erb, fs)
        m = s.m.erb_dec(emb, e3, e2, e1, e0)
        co = s.m.df_out_transform(s.m.df_dec(emb, c0))
        return m, co, sg_enc.hn, sg_erb.hn, sg_df.hn
net = Net(model).eval()
x = np.load("dustin_ref.wav.in.npy")[: 48000*12]
a = torch.nn.functional.pad(torch.from_numpy(x)[None], (0, st.fft_size()))
spec, erb_f, spec_f = df_features(a, st, 96)
pe = torch.nn.functional.pad(erb_f, (0,0,-2,2)); ps = torch.nn.functional.pad(spec_f, (0,0,0,0,-2,2))
z = lambda n: torch.zeros(n, 1, 256)
args = (pe[:, :, :T], ps[:, :, :T], z(1), z(2), z(2))
ref = net(*args)
tr = torch.jit.trace(net, args, check_trace=False)
ml = ct.convert(tr, inputs=[ct.TensorType("feat_erb", shape=(1,1,T,32)), ct.TensorType("feat_spec", shape=(1,1,T,96,2)),
    ct.TensorType("h_enc", shape=(1,1,256)), ct.TensorType("h_erb", shape=(2,1,256)), ct.TensorType("h_df", shape=(2,1,256))],
    outputs=[ct.TensorType("mask"), ct.TensorType("coefs"), ct.TensorType("n_enc"), ct.TensorType("n_erb"), ct.TensorType("n_df")],
    minimum_deployment_target=ct.target.macOS14, compute_precision=ct.precision.FLOAT32, convert_to="mlprogram")
ml.save(f"out/DFN3s_T{T}.mlpackage")
r = ml.predict({"feat_erb": args[0].numpy(), "feat_spec": args[1].numpy(), "h_enc": args[2].numpy(), "h_erb": args[3].numpy(), "h_df": args[4].numpy()})
for k, v in zip(("mask","coefs","n_enc","n_erb","n_df"), ref): print(k, "err", np.abs(r[k]-v.numpy()).max(), "amp", np.abs(v.numpy()).mean())
# validation : chaînage par blocs recouverts de K images
mf = net.__class__.__call__  # (inutilisé)
def run_chunks(fe, fs_, n):
    h = [z(1).numpy(), z(2).numpy(), z(2).numpy()]
    fe = np.pad(fe.numpy(), ((0,0),(0,0),(K,T),(0,0))); fs_ = np.pad(fs_.numpy(), ((0,0),(0,0),(K,T),(0,0),(0,0)))   # K images de contexte nul devant
    M = np.zeros((n, 32), np.float32); C = np.zeros((5, n, 96, 2), np.float32); s0 = 0   # s0 : indice dans le tableau décalé
    while s0 < n:
        r = ml.predict({"feat_erb": fe[:, :, s0:s0+T], "feat_spec": fs_[:, :, s0:s0+T], "h_enc": h[0], "h_erb": h[1], "h_df": h[2]})
        m = min(T - K, n - s0)
        M[s0:s0+m] = r["mask"][0,0,K:K+m]; C[:, s0:s0+m] = r["coefs"][0,:,K:K+m]
        h = [r["n_enc"], r["n_erb"], r["n_df"]]; s0 += T - K
    return M, C
n = pe.shape[2]
Mc, Cc = run_chunks(pe, ps, n)
# référence : torch réseau d'origine, tout le fichier d'un coup
for g in (sg_enc, sg_erb, sg_df): pass
import df.deepfilternet3 as D
model.enc.emb_gru.gru, model.erb_dec.emb_gru.gru, model.df_dec.df_gru.gru = sg_enc.g, sg_erb.g, sg_df.g
mfull = model(spec.clone(), erb_f, spec_f)
print("blocs vs fichier entier : mask", np.abs(Mc - mfull[1][0,0].numpy()).max(), "coefs", np.abs(Cc - mfull[3][0].numpy() if mfull[3].dim()==5 and mfull[3].shape[0]==1 else Cc).max())
e = np.abs(Mc - mfull[1][0,0].numpy()).max(1)
print("n", n, "frames with err>1e-3:", np.where(e > 1e-3)[0][:40], "max", e.max())
