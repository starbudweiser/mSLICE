# Conversion Core ML (fp16, mlprogram) des trois modèles d'essai. Usage : convert.py dinov2|sface|auraface
import sys, warnings, time
warnings.filterwarnings('ignore')
import numpy as np, torch, coremltools as ct
torch.set_grad_enabled(False)
name = sys.argv[1]
out = f'models/coreml/{name}.mlpackage'
import os; os.makedirs('models/coreml', exist_ok=True)

def convert(mod, shape, scale, bias, outputs):
    ex = torch.rand(*shape)
    tr = torch.jit.trace(mod.eval(), ex, strict=False)
    m = ct.convert(tr, inputs=[ct.ImageType(name='image', shape=shape, color_layout=ct.colorlayout.RGB, scale=scale, bias=bias)],
                   outputs=[ct.TensorType(name=o) for o in outputs], convert_to='mlprogram', compute_precision=ct.precision.FLOAT16,
                   minimum_deployment_target=ct.target.macOS14)
    m.save(out); print('écrit', out)

if name == 'dinov2':
    from transformers import Dinov2Model
    net = Dinov2Model.from_pretrained('models/dinov2-small').eval()
    emb = net.embeddings
    _pe = emb.interpolate_pos_encoding(torch.zeros(1, 257, 384), 224, 224).detach().clone()   # grille 16×16 figée (évite l'interpolation dynamique)
    emb.interpolate_pos_encoding = lambda e, h, w: _pe
    class W(torch.nn.Module):
        def __init__(s):
            super().__init__(); s.net = net
            s.register_buffer('mean', torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)); s.register_buffer('std', torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))
        def forward(s, x):                      # x : 0..1 (l'image Core ML est mise à l'échelle 1/255)
            h = s.net(pixel_values=(x - s.mean) / s.std).last_hidden_state
            return h[:, 0], h[:, 1:].mean(dim=1)
    torch.save(None, '/dev/null')
    convert(W(), (1, 3, 224, 224), 1 / 255, [0, 0, 0], ['cls', 'avg'])
else:
    import onnx, onnx2torch
    path = {'sface': 'models/sface/face_recognition_sface_2021dec.onnx', 'auraface': 'models/auraface/glintr100.onnx'}[name]
    net = onnx2torch.convert(onnx.load(path)).eval()
    if name == 'auraface': convert(net, (1, 3, 112, 112), 1 / 127.5, [-1, -1, -1], ['emb'])   # (x − 127,5) / 127,5, RVB
    else: convert(net, (1, 3, 112, 112), 1.0, [0, 0, 0], ['emb'])                              # SFace : RVB brut 0..255
