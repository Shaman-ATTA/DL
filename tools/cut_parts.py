"""Cut a character sprite into cutout parts for SkelActor (Phase 5).
Each pixel goes to its nearest bone segment (distance / greed, the same metric the v1.3 skin
weights used). For every joint between a lower part P and a part Q drawn above it, P gets the
area hidden under Q near the joint painted in (nearest-colour fill from P's own pixels, blurred
and slightly shaded like an occlusion shadow), so no gap or ghost limb shows when Q rotates.
The top part gets a 3 px real-pixel feather to close seams.
Outputs assets/parts/<id>/<bone>.png and scripts/part_rects.gd."""
import re, json, sys, os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = {"HERO": ("hero", "hero_body"), "GOBLIN": ("goblin", "goblin"), "LICH": ("boss_lich", "boss_lich")}
txt = open(os.path.join(ROOT, "scripts/rigs.gd")).read()
bone_re = re.compile(r'\["(\w+)", "(\w*)", (-?\d+), (-?\d+), (-?\d+), (-?\d+), ([\d.]+), "(\w*)"\]')
z_re = re.compile(r'"z": \{([^}]*)\}')

def seg_dist(P, a, b):
    ab = b - a; L = max(1.0, (ab ** 2).sum())
    f = np.clip(((P - a) * ab).sum(-1) / L, 0, 1)
    return np.sqrt(((P - (a + ab * f[..., None])) ** 2).sum(-1))

rects = {}
for const, (rid, spr) in SRC.items():
    block = txt.split("const %s :=" % const)[1].split("\nconst ")[0]
    bones = [(m[0], m[1], np.array([float(m[2]), float(m[3])]), np.array([float(m[4]), float(m[5])]), float(m[6]), m[7]) for m in bone_re.findall(block)]
    zm = {}
    zz = z_re.search(block)
    if zz:
        for k, v in re.findall(r'"(\w+)": (-?\d+)', zz.group(1)): zm[k] = int(v)
    im = np.array(Image.open(os.path.join(ROOT, "assets/sprites/%s.png" % spr)).convert("RGBA")).astype(np.float32)
    H, W = im.shape[:2]; A = im[..., 3] > 8
    if rid != "hero":   # opaque white background leftovers between limbs (art defect exposed by moving parts)
        wh = A & (im[..., :3].min(-1) > 222) & (im[..., :3].max(-1) - im[..., :3].min(-1) < 30)
        lb, nb = ndi.label(wh)
        if nb:
            sz = ndi.sum(wh, lb, range(1, nb + 1))
            kill = np.isin(lb, [i + 1 for i, v in enumerate(sz) if v >= 150])
            kill = ndi.binary_dilation(kill, iterations=1) & (im[..., :3].min(-1) > 170)  | kill
            A = A & ~kill; im[kill] = 0
            print(rid, "removed white px", int(kill.sum()))
    yy, xx = np.mgrid[0:H, 0:W]; P = np.stack([xx, yy], -1).astype(np.float32)
    skin = [b for b in bones if "n" not in b[5]]
    D = np.stack([seg_dist(P, b[2], b[3]) / b[4] for b in skin])
    lab = np.argmin(D, 0)
    order = {b[0]: i for i, b in enumerate(bones)}
    key = lambda n: (zm.get(n, 0), order[n])         # draw order: z, then tree order
    thick = ndi.distance_transform_edt(A)
    parts = {}
    for i, b in enumerate(skin):
        core = (lab == i) & A
        # keep only the largest connected blob + anything touching the bone segment area
        lbl, n = ndi.label(core)
        if n > 1:
            sizes = ndi.sum(core, lbl, range(1, n + 1)); keep = np.zeros_like(core)
            for j, s in enumerate(sizes):
                if s > 0.08 * sizes.max(): keep |= lbl == j + 1
            core = keep
        parts[b[0]] = {"core": core, "rgba": np.where(core[..., None], im, 0)}
    # reassign orphan pixels (dropped blobs) to the nearest kept part
    owned = np.zeros_like(A)
    for p in parts.values(): owned |= p["core"]
    orphan = A & ~owned
    if orphan.any():
        names = list(parts); idx = np.full((H, W), -1)
        for k, n in enumerate(names): idx[parts[n]["core"]] = k
        _, (iy, ix) = ndi.distance_transform_edt(idx < 0, return_indices=True)
        near = idx[iy, ix]
        for k, n in enumerate(names):
            m = orphan & (near == k); parts[n]["core"] |= m; parts[n]["rgba"][m] = im[m]
    by = {b[0]: b for b in bones}
    for b in skin:
        n = b[0]; par = b[1]
        if par == "" or par not in parts: continue
        if "j" in b[5] and rid == "boss_lich": continue   # flame/robe tips: no painted fill (it showed as a dark hood)
        j = b[2]; r = max(16.0, float(thick[int(min(H - 1, j[1])), int(min(W - 1, j[0]))]) * 1.1)
        disc = ((xx - j[0]) ** 2 + (yy - j[1]) ** 2) <= r * r
        lo, hi = (par, n) if key(par) < key(n) else (n, par)
        hid = parts[hi]["core"] & disc & A
        L = parts[lo]
        if hid.any() and L["core"].any():
            _, (iy, ix) = ndi.distance_transform_edt(~L["core"], return_indices=True)
            fill = im[iy, ix].copy()
            blur = np.stack([ndi.gaussian_filter(fill[..., c], 4) for c in range(3)], -1)
            dist = ndi.distance_transform_edt(~L["core"])
            shade = 1.0 - 0.5 * np.clip(dist / 10.0, 0, 1)        # occlusion shadow under the top part
            m = hid & ~L["core"]
            L["rgba"][m, :3] = blur[m] * shade[m, None]; L["rgba"][m, 3] = 255
            L["core"] = L["core"] | m
    for n, p in parts.items():   # 3 px feather of real pixels to close seams
        f = ndi.binary_dilation(p["core"], iterations=3) & A & ~p["core"]
        p["rgba"][f] = im[f]; p["core"] = p["core"] | f
    out = os.path.join(ROOT, "assets/parts", rid); os.makedirs(out, exist_ok=True)
    for f in os.listdir(out): os.remove(os.path.join(out, f))
    rects[rid] = {}
    for n, p in parts.items():
        ys, xs = np.nonzero(p["core"])
        if len(xs) < 30: continue
        x0, y0, x1, y1 = max(0, xs.min() - 2), max(0, ys.min() - 2), min(W, xs.max() + 3), min(H, ys.max() + 3)
        Image.fromarray(p["rgba"][y0:y1, x0:x1].clip(0, 255).astype(np.uint8)).save(os.path.join(out, n + ".png"))
        rects[rid][n] = [int(x0), int(y0), int(x1 - x0), int(y1 - y0), zm.get(n, 0)]
    print(rid, W, H, {k: v[2] * v[3] for k, v in rects[rid].items()})
with open(os.path.join(ROOT, "scripts/part_rects.gd"), "w") as f:
    f.write("class_name PartRects\n## Generated by tools/cut_parts.py: rig -> bone -> [x, y, w, h, z] in sprite px.\nconst R := %s\n" % json.dumps(rects))
