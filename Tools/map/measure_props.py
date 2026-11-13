"""小物の USDZ の大きさを測って Tools/map/prop_sizes.json に書く(当たり判定の大きさを決めるため).

使い方: python3 -I Tools/map/measure_props.py        (pip install usd-core が要る)
出力: { "TreePine": {"variants": 3, "min": [x,y,z], "max": [x,y,z]} , ... }  座標はゲームの座標(Y 上, 機首 -Z).
一度作った JSON はリポジトリに入れるので, 島のデータを作り直すだけなら usd-core は要らない.
"""
import glob
import json
import os
import re

from pxr import Usd, UsdGeom, Gf

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS = os.path.join(ROOT, "Battlefield", "Resources", "Models")


def measure(path):
    """USDZ の中のメッシュを, 名前の最後の _番号 ごとにまとめて, 範囲(最小・最大)を返す."""
    stage = Usd.Stage.Open(path)
    up = UsdGeom.GetStageUpAxis(stage)
    out = {}
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(prim)
        pts = mesh.GetPointsAttr().Get()
        if not pts:
            continue
        m = UsdGeom.Xformable(prim).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
        # 名前の最後の _番号 (TreePine_2 など) が形の番号. 上の階層の名前も探す.
        name, p = prim.GetName(), prim
        idx = 0
        while p and p.GetPath().pathString != "/":
            mm = re.search(r"_(\d+)$", p.GetName())
            if mm:
                idx = int(mm.group(1))
                break
            p = p.GetParent()
        lo = [1e9] * 3
        hi = [-1e9] * 3
        for q in pts:
            w = m.Transform(Gf.Vec3d(*q))
            x, y, z = (w[0], w[1], w[2])
            if up == "Z":          # Blender 由来で Z 上のまま入っているとき: (x, y, z) → (x, z, -y)
                x, y, z = x, z, -y
            for k, v in enumerate((x, y, z)):
                lo[k] = min(lo[k], v)
                hi[k] = max(hi[k], v)
        cur = out.get(idx)
        if cur:
            lo = [min(a, b) for a, b in zip(lo, cur[0])]
            hi = [max(a, b) for a, b in zip(hi, cur[1])]
        out[idx] = (lo, hi)
    return out


def main():
    result = {}
    for path in sorted(glob.glob(os.path.join(MODELS, "Prop_*.usdz"))):
        name = os.path.basename(path)[5:-5]
        parts = measure(path)
        if not parts:
            continue
        lo = [min(v[0][k] for v in parts.values()) for k in range(3)]
        hi = [max(v[1][k] for v in parts.values()) for k in range(3)]
        result[name] = {"variants": len(parts),
                        "min": [round(v, 2) for v in lo], "max": [round(v, 2) for v in hi]}
        print(name, result[name])
    with open(os.path.join(os.path.dirname(__file__), "prop_sizes.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
