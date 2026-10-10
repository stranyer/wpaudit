# Uso: python relief.py depth_anything_v2.onnx assets/art/zombies/<tipo>.webp salida/<tipo>
# Modelo: onnx-community/depth-anything-v2-base (Hugging Face). Requiere numpy, scipy, pillow, onnxruntime.
# Mapas de relieve para las criaturas: profundidad (Depth Anything V2) →
# normales → capas de luz (borde izq., borde der., luz frontal) + profundidad.
import sys, numpy as np, onnxruntime as ort
from PIL import Image, ImageFilter
from scipy import ndimage

model, src, out_prefix = sys.argv[1], sys.argv[2], sys.argv[3]
im = Image.open(src).convert('RGBA')
W, H = im.size
alpha = np.asarray(im)[..., 3].astype(np.float32) / 255.0

# Fondo gris neutro para que el modelo no "vea" el negro como pared.
bg = Image.new('RGBA', im.size, (118, 118, 118, 255)); bg.alpha_composite(im)
rgb = bg.convert('RGB')
ih = 14 * round(980 / 14); iw = 14 * max(1, round(ih * W / H / 14))
x = np.asarray(rgb.resize((iw, ih), Image.BICUBIC)).astype(np.float32) / 255.0
x = (x - np.array([0.485, 0.456, 0.406], np.float32)) / np.array([0.229, 0.224, 0.225], np.float32)
x = x.transpose(2, 0, 1)[None]
sess = ort.InferenceSession(model, providers=['CPUExecutionProvider'])
d = sess.run(None, {sess.get_inputs()[0].name: x})[0]
d = np.squeeze(d).astype(np.float32)
d = np.asarray(Image.fromarray(d).resize((W, H), Image.BICUBIC))

# Normalizar dentro de la silueta (cerca = 1).
m = alpha > 0.5
lo, hi = np.percentile(d[m], 2), np.percentile(d[m], 99.5)
dn = np.clip((d - lo) / (hi - lo + 1e-6), 0, 1)

# Forma: profundidad del modelo (gran escala) + "inflado" circular desde el
# borde de la silueta + un poco de relieve fino tomado de la pintura.
dist = ndimage.distance_transform_edt(m)
R = 0.075 * W
t = np.clip(dist / R, 0, 1)
inflate = np.sqrt(1 - (1 - t) ** 2)
lum = np.asarray(im.convert('L')).astype(np.float32) / 255.0
detail = lum - ndimage.gaussian_filter(lum, 6)
height = (0.55 * ndimage.gaussian_filter(dn, 3) + 0.45 * inflate + 0.035 * detail) * m
depth_s = ndimage.gaussian_filter(height, 1.2)
depth = depth_s

# Normales desde el gradiente (escala relativa al ancho).
k = 0.2 * W
gy, gx = np.gradient(depth_s * k)
nx, ny, nz = -gx, -gy, np.ones_like(gx)
n = np.sqrt(nx * nx + ny * ny + nz * nz); nx /= n; ny /= n; nz /= n
fres = np.clip(1 - nz, 0, 1)

def light(lx, ly, lz):
    l = np.array([lx, ly, lz], np.float32); l /= np.linalg.norm(l)
    return np.clip(nx * l[0] + ny * l[1] + nz * l[2], 0, 1)

# Borde: luz rasante desde atrás de cada costado + fresnel; se recorta al borde.
edge = np.clip(1 - dist / (0.05 * W), 0, 1) ** 1.6
rimL = np.clip(light(-1, -0.25, -0.15) ** 1.3 * (0.55 + 0.9 * fres) + edge * np.clip(-nx, 0, 1) * 0.8, 0, 1)
rimR = np.clip(light(1, -0.25, -0.15) ** 1.3 * (0.55 + 0.9 * fres) + edge * np.clip(nx, 0, 1) * 0.8, 0, 1)
key = light(-0.25, -0.45, 0.85) ** 1.5
# Oclusión (cavidades): cuánto más hundido está el punto que su vecindad.
cav = np.clip((ndimage.gaussian_filter(depth, 10) - depth) * 9, 0, 1) * m
a = alpha
lum = np.asarray(im.convert('L')).astype(np.float32) / 255.0
# Las capas aditivas se apoyan en la luminancia para no lavar las sombras.
mod = 0.35 + 0.65 * np.clip(lum * 1.8, 0, 1)
layers = np.stack([rimL * mod * a, rimR * mod * a, key * mod * a], -1)
Image.fromarray((np.clip(layers, 0, 1) * 255).astype(np.uint8), 'RGB').save(out_prefix + '_light.webp', quality=86, method=6)
# Profundidad y oclusión en chico (para la malla y para sombrear).
dsmall = Image.fromarray((np.clip(np.stack([depth_s, cav, a], -1), 0, 1) * 255).astype(np.uint8), 'RGB').resize((W // 4, H // 4), Image.BILINEAR)
dsmall.save(out_prefix + '_depth.webp', quality=92, method=6)
# Vista previa.
prev = np.concatenate([np.stack([depth_s] * 3, -1), np.stack([rimL * a] * 3, -1), np.stack([rimR * a] * 3, -1), np.stack([key * a] * 3, -1), np.stack([cav] * 3, -1)], 1)
Image.fromarray((np.clip(prev, 0, 1) * 255).astype(np.uint8)).resize((prev.shape[1] // 3, prev.shape[0] // 3)).save(out_prefix + '_prev.png')
print('ok', out_prefix, W, H)
