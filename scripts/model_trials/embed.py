# Empreintes Core ML (ANE) de tous les recadrages + contrôle de fidélité de conversion (ONNX Runtime / PyTorch sur 150 images).
import sys, os, time, json, warnings
warnings.filterwarnings('ignore')
import numpy as np
from PIL import Image
import coremltools as ct
name = sys.argv[1]
ids = sorted(f[:-4] for f in os.listdir('data/full/align112'))
cfg = {'sface': [('align112', 'emb')], 'auraface': [('align112', 'emb')], 'dinov2': [('face224', 'cls'), ('face224', 'avg'), ('person224', 'cls'), ('person224', 'avg')]}[name]
m = ct.models.MLModel(f'models/coreml/{name}.mlpackage', compute_units=ct.ComputeUnit.CPU_AND_NE)
os.makedirs('feats', exist_ok=True)
res = {}; t_tot = 0; n_tot = 0
for kind in sorted(set(k for k, _ in cfg)):
    fl = [i for i in ids if os.path.exists(f'data/full/{kind}/{i}.jpg')]
    outs = {o: [] for k, o in cfg if k == kind}
    for i in fl:
        im = Image.open(f'data/full/{kind}/{i}.jpg').convert('RGB')
        t0 = time.time(); r = m.predict({'image': im}); t_tot += time.time() - t0; n_tot += 1
        for o in outs: outs[o].append(np.asarray(r[o]).reshape(-1))
    for o, v in outs.items():
        np.save(f'feats/{name}_{kind}_{o}.npy', np.stack(v).astype(np.float32)); json.dump(fl, open(f'feats/{kind}_ids.json', 'w'))
print(name, 'images', n_tot, 'ms/image (predict Python, CPU+ANE)', round(t_tot / n_tot * 1000, 2))

# Fidélité : référence en flottants 32 bits
import torch; torch.set_grad_enabled(False)
sub = ids[::max(1, len(ids) // 150)][:150]
if name in ('sface', 'auraface'):
    import onnxruntime as ort
    s = ort.InferenceSession({'sface': 'models/sface/face_recognition_sface_2021dec.onnx', 'auraface': 'models/auraface/glintr100.onnx'}[name], providers=['CPUExecutionProvider'])
    inp = s.get_inputs()[0].name
    R = []
    for i in sub:
        a = np.asarray(Image.open(f'data/full/align112/{i}.jpg').convert('RGB'), dtype=np.float32)
        a = (a - 127.5) / 127.5 if name == 'auraface' else a
        R.append(s.run(None, {inp: a.transpose(2, 0, 1)[None]})[0].reshape(-1))
    R = np.stack(R); C = np.load(f'feats/{name}_align112_emb.npy')[[ids.index(i) for i in sub]]
else:
    from transformers import Dinov2Model
    net = Dinov2Model.from_pretrained('models/dinov2-small').eval()
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1); std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
    R = []
    for i in sub:
        a = torch.from_numpy(np.asarray(Image.open(f'data/full/face224/{i}.jpg').convert('RGB'), dtype=np.float32) / 255).permute(2, 0, 1)[None]
        R.append(net(pixel_values=(a - mean) / std).last_hidden_state[:, 0].reshape(-1).numpy())
    R = np.stack(R); C = np.load('feats/dinov2_face224_cls.npy')[[ids.index(i) for i in sub]]
cos = (R * C).sum(1) / np.linalg.norm(R, axis=1) / np.linalg.norm(C, axis=1)
print(name, 'fidélité Core ML fp16 vs fp32 : cosinus moyen', round(float(cos.mean()), 5), 'min', round(float(cos.min()), 5))
