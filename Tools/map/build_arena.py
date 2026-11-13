"""島 1 つぶんのデータを作る(numpy と Pillow だけ. Blender は使わない).

使い方:
    python3 Tools/map/build_arena.py            # 島のデータを作る(1 分以内)
    python3 Tools/map/build_arena.py --check    # 作らずに, 今あるファイルの中身だけ確かめる

できるもの(`Battlefield/Resources/` の下):
    Maps/island.height          高さ. "PPHF" 形式(Airplane と同じ). 257 × 257, 2 m 間隔,
                                originX = -256, originZ = +256(行 r は z = 256 - 2r, 列 c は x = -256 + 2c)
    Maps/island.json            `MapData`(小物・当たり判定・出発点・ひろうものの置き場・名所)
    Ground/island_0..3.jpg      地面の絵. 1 枚が 256 m 四方 1024 px.
                                0 = 西北(x: -256〜0, z: 0〜256), 1 = 東北, 2 = 西南, 3 = 東南. 絵の上が z の大きい方.
    Ground/island_minimap.jpg   ミニマップ 512 px. 絵の上が **-Z(前)**, 右が +X, 1 px = 1 m.

同じ種(SEED)からは, 何回作っても同じ結果になる.
座標の約束: Y が上, 単位 m, -Z が前. 小物の向き(yaw)は Y まわりで, 箱の向きと同じ式
(ローカル (lx, lz) → 世界 (cos·lx + sin·lz, -sin·lx + cos·lz)).

当たり判定の大きさは `COLLIDERS`(Tools/map/prop_sizes.json で測った USDZ の大きさから決めた).
木は幹だけ(葉は弾が通る), 茂みと草は当たり判定なし.
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
import time

import numpy as np
from PIL import Image

SEED = 20261113
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "Battlefield", "Resources")
MAP_DIR = os.path.join(RES, "Maps")
GROUND_DIR = os.path.join(RES, "Ground")

COLS = ROWS = 257
CELL = 2.0
ORIGIN_X, ORIGIN_Z = -256.0, 256.0
TILE = 256.0          # 地面の絵 1 枚が覆う長さ(m)
TILE_PX = 1024
MINIMAP_PX = 512
WATER_Y = 0.0
POI_RADIUS = 60.0

# 名所: (名前, x, z). たがいに 120 m 以上はなす.
POIS = [("村", -80.0, 40.0), ("製材所", 70.0, 60.0), ("岩場", 80.0, -70.0), ("森の広場", -50.0, -90.0)]
# 名所どうしを結ぶ道.
ROADS = [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2)]


# ---------------------------------------------------------------------------
# ノイズ
# ---------------------------------------------------------------------------

class Noise:
    """格子に乱数を置いて, なめらかにつなぐ値ノイズ."""

    def __init__(self, seed: int):
        self.t = np.random.default_rng(seed).random((256, 256))

    def value(self, x, y):
        x = np.asarray(x, dtype=np.float64)
        y = np.asarray(y, dtype=np.float64)
        xi = np.floor(x).astype(np.int64)
        yi = np.floor(y).astype(np.int64)
        fx, fy = x - xi, y - yi
        u, v = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        t = self.t
        a = t[xi & 255, yi & 255]
        b = t[(xi + 1) & 255, yi & 255]
        c = t[xi & 255, (yi + 1) & 255]
        d = t[(xi + 1) & 255, (yi + 1) & 255]
        return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v

    def fbm(self, x, y, octaves: int = 4):
        """-1〜1 に近い値."""
        total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
        for o in range(octaves):
            total = total + amp * (self.value(x * freq + 17.3 * o, y * freq + 9.1 * o) * 2 - 1)
            norm += amp
            amp *= 0.5
            freq *= 2.0
        return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


N_SHORE, N_HILL, N_BIG, N_FLAT, N_PAINT, N_FOREST = (Noise(SEED + i) for i in range(6))


# ---------------------------------------------------------------------------
# 高さ
# ---------------------------------------------------------------------------

def base_height(x, z):
    """島の形と丘(名所をならす前)."""
    r = np.hypot(x, z)
    theta = np.arctan2(z, x)
    shore_r = 198 + 10 * N_SHORE.fbm(np.cos(theta) * 1.7 + 5, np.sin(theta) * 1.7 + 5, 3)
    t = np.clip((r - (shore_r - 55)) / 75, 0, 1)
    edge = 1 - smoothstep(0, 1, t)                       # 内陸 1, 海 0
    hills = 6.0 + 7.5 * (N_HILL.fbm(x / 70, z / 70, 4) * 0.5 + 0.5)
    hills += 4.0 * np.maximum(0, N_BIG.fbm(x / 150 + 10, z / 150, 2))
    return -7 + edge * (7 + hills)


def build_heights():
    xs = ORIGIN_X + np.arange(COLS) * CELL
    zs = ORIGIN_Z - np.arange(ROWS) * CELL
    X, Z = np.meshgrid(xs, zs)                            # 行 = z, 列 = x
    H = base_height(X, Z)
    for (_, px, pz) in POIS:
        base = float(base_height(np.array(px), np.array(pz)))
        d = np.hypot(X - px, Z - pz)
        w = 1 - smoothstep(48, 72, d)
        flat = base + 0.4 * N_FLAT.fbm(X / 9, Z / 9, 2)
        H = H * (1 - w) + flat * w
    return H.astype(np.float32)


def sample_height(H, x, z):
    """高さマップを双一次補間で読む(ゲームの `Heightfield.height` と同じ)."""
    fx = np.clip((np.asarray(x) - ORIGIN_X) / CELL, 0, COLS - 1)
    fz = np.clip((ORIGIN_Z - np.asarray(z)) / CELL, 0, ROWS - 1)
    c0 = np.minimum(np.floor(fx).astype(int), COLS - 2)
    r0 = np.minimum(np.floor(fz).astype(int), ROWS - 2)
    tx, tz = fx - c0, fz - r0
    h00, h10 = H[r0, c0], H[r0, c0 + 1]
    h01, h11 = H[r0 + 1, c0], H[r0 + 1, c0 + 1]
    return (h00 * (1 - tx) + h10 * tx) * (1 - tz) + (h01 * (1 - tx) + h11 * tx) * tz


def normal_y(H, x, z, e=CELL):
    dhdx = (sample_height(H, x + e, z) - sample_height(H, x - e, z)) / (2 * e)
    dhdz = (sample_height(H, x, z + e) - sample_height(H, x, z - e)) / (2 * e)
    return 1.0 / np.sqrt(dhdx ** 2 + dhdz ** 2 + 1.0)


def write_height(path, H):
    lo, hi = float(H.min()), float(H.max())
    q = np.round((H - lo) / (hi - lo) * 65535).astype("<u2")
    with open(path, "wb") as f:
        f.write(b"PPHF")
        f.write(struct.pack("<III", 1, COLS, ROWS))
        f.write(struct.pack("<fffff", ORIGIN_X, ORIGIN_Z, CELL, lo, hi))
        f.write(q.tobytes())


# ---------------------------------------------------------------------------
# 当たり判定
# ---------------------------------------------------------------------------

def cyl(x, y, z, r, h):
    return {"shape": "cyl", "p": [round(x, 2), round(y, 2), round(z, 2)], "r": round(r, 2), "h": round(h, 2)}


def box(x, y, z, hx, hy, hz, yaw):
    return {"shape": "box", "p": [round(x, 2), round(y, 2), round(z, 2)],
            "half": [round(hx, 2), round(hy, 2), round(hz, 2)], "yaw": round(yaw, 3)}


def colliders(name, x, y, z, yaw, s):
    """小物 1 つの当たり判定(なければ空)."""
    c, sn = math.cos(yaw), math.sin(yaw)
    if name in ("TreePine", "TreePineSnow"):
        return [cyl(x, y, z, 0.5 * s, 6 * s)]
    if name in ("TreeRound", "TreeSakura"):
        return [cyl(x, y, z, 0.6 * s, 5 * s)]
    if name == "House":
        return [box(x, y + 3.9 * s, z, 4.4 * s, 3.9 * s, 4.0 * s, yaw)]
    if name == "Chalet":
        return [box(x, y + 5.0 * s, z, 6.4 * s, 5.0 * s, 6.4 * s, yaw)]
    if name in ("RockA", "RockB", "RockSavanna"):
        return [cyl(x, y, z, 1.5 * s, 1.3 * s)]
    if name == "Log":
        return [box(x, y + 0.45 * s, z, 1.15 * s, 0.45 * s, 0.45 * s, yaw)]
    if name == "LogPile":
        return [box(x, y + 0.65 * s, z, 1.5 * s, 0.65 * s, 0.75 * s, yaw)]
    if name == "StoneArch":
        out = []
        for side in (-1, 1):
            lx = 4.6 * side * s
            out.append(box(x + c * lx, y + 4.0 * s, z - sn * lx, 1.25 * s, 4.0 * s, 0.95 * s, yaw))
        return out
    return []


def footprint_radius(name, s):
    return {"House": 6.0, "Chalet": 9.0, "LogPile": 2.0, "Log": 1.4, "StoneArch": 7.0, "RockA": 1.8, "RockB": 1.8,
            "RockSavanna": 1.8, "TreePine": 1.2, "TreeRound": 1.2, "TreeSakura": 1.2, "Bush": 1.2,
            "GrassTuft": 0.4}.get(name, 1.0) * s


def obstacle_clear(obstacles, x, z, radius):
    """(x, z) を中心とする半径 radius の円が, 当たり判定と重ならないか(上から見た形で調べる)."""
    for o in obstacles:
        px, pz = o["p"][0], o["p"][2]
        if o["shape"] == "cyl":
            if math.hypot(x - px, z - pz) < o["r"] + radius:
                return False
        else:
            yaw = o["yaw"]
            dx, dz = x - px, z - pz
            lx = math.cos(yaw) * dx - math.sin(yaw) * dz
            lz = math.sin(yaw) * dx + math.cos(yaw) * dz
            hx, _, hz = o["half"]
            ex, ez = max(abs(lx) - hx, 0), max(abs(lz) - hz, 0)
            if ex * ex + ez * ez < radius * radius:
                return False
    return True


# ---------------------------------------------------------------------------
# 小物の配置
# ---------------------------------------------------------------------------

class Placer:
    def __init__(self, H, rng):
        self.H, self.rng = H, rng
        self.props = []              # [名前, 番号, x, y, z, 向き, s, s, s]
        self.obstacles = []
        self.blocked = []            # (x, z, 半径): 新しい物を置かない円

    def free(self, x, z, radius):
        return all(math.hypot(x - bx, z - bz) >= br + radius for bx, bz, br in self.blocked)

    def add(self, name, x, z, yaw=None, s=1.0, variant=None, check=True, margin=0.5):
        rng = self.rng
        yaw = rng.uniform(0, 2 * math.pi) if yaw is None else yaw
        variant = int(rng.integers(0, 4)) if variant is None else variant
        r = footprint_radius(name, s)
        if check and not self.free(x, z, r + margin):
            return False
        y = float(sample_height(self.H, x, z))
        if y < 1.2:
            return False
        self.props.append([name, variant, round(x, 2), round(y, 2), round(z, 2), round(yaw, 3), round(s, 3), round(s, 3),
                           round(s, 3)])
        self.obstacles += colliders(name, x, y, z, yaw, s)
        self.blocked.append((x, z, r))
        return True


def road_distance(x, z, pois):
    """道(名所どうしを結ぶ線)までの距離(配列)."""
    best = np.full(np.shape(x), 1e9)
    for a, b in ROADS:
        ax, az, bx, bz = pois[a][1], pois[a][2], pois[b][1], pois[b][2]
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        t = np.clip(((x - ax) * dx + (z - az) * dz) / L2, 0, 1)
        best = np.minimum(best, np.hypot(x - (ax + t * dx), z - (az + t * dz)))
    return best


def place_all(H, rng):
    P = Placer(H, rng)
    pois = POIS
    # 道の上と名所の中心には何も置かない.
    def on_road(x, z):
        return float(road_distance(np.array(x), np.array(z), pois)) < 4.5

    def put(name, cx, cz, dx, dz, **kw):
        x, z = cx + dx, cz + dz
        if on_road(x, z) and name not in ("GrassTuft",):
            return False
        return P.add(name, x, z, **kw)

    # --- 村: 家 5 軒・山小屋 2 軒・丸太
    vx, vz = pois[0][1], pois[0][2]
    for dx, dz, yaw in [(-28, -20, 0.1), (26, -24, -0.3), (-30, 24, 3.0), (30, 26, 2.6), (0, -40, 0.0)]:
        put("House", vx, vz, dx, dz, yaw=yaw, s=1.0, check=False)
    for dx, dz, yaw in [(-4, 32, 3.14), (46, 0, -1.57)]:
        put("Chalet", vx, vz, dx, dz, yaw=yaw, s=1.0, check=False)
    for dx, dz in [(-12, -6), (14, 8), (4, 10)]:
        put("LogPile", vx, vz, dx, dz, s=1.0)
    for dx, dz in [(-16, 12), (18, -12), (-6, -26)]:
        put("Log", vx, vz, dx, dz, s=2.2)
    for dx, dz in [(10, -14), (-20, 2)]:
        put("RockA", vx, vz, dx, dz, s=1.3)

    # --- 製材所: 大きな小屋・家・丸太の山と丸太がたくさん
    sx, sz = pois[1][1], pois[1][2]
    put("Chalet", sx, sz, -20, -10, yaw=0.3, s=1.0, check=False)
    put("House", sx, sz, 24, -26, yaw=-0.5, s=1.0, check=False)
    for i in range(7):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(14, 44)
        put("LogPile", sx, sz, d * math.cos(a), d * math.sin(a), s=rng.uniform(0.9, 1.3))
    for i in range(10):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(8, 48)
        put("Log", sx, sz, d * math.cos(a), d * math.sin(a), s=rng.uniform(1.8, 2.6))

    # --- 岩場: 大きな岩 16 個と石のアーチ 2 つ
    rx, rz = pois[2][1], pois[2][2]
    put("StoneArch", rx, rz, -15, 5, yaw=0.4, s=1.0, check=False)
    put("StoneArch", rx, rz, 22, -18, yaw=1.9, s=1.0, check=False)
    kinds = ["RockA", "RockB", "RockSavanna"]
    for i in range(16):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(8, 52)
        put(kinds[i % 3], rx, rz, d * math.cos(a), d * math.sin(a), s=rng.uniform(1.2, 2.2))

    # --- 森の広場: 外側にぎっしり木, 中は岩と丸太
    fx, fz = pois[3][1], pois[3][2]
    for i in range(46):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(26, 62)
        put(["TreePine", "TreeRound", "TreePine"][i % 3], fx, fz, d * math.cos(a), d * math.sin(a), s=rng.uniform(0.9, 1.3))
    for i in range(6):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(6, 24)
        put(kinds[i % 3], fx, fz, d * math.cos(a), d * math.sin(a), s=rng.uniform(1.0, 1.8))
    for i in range(5):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(6, 24)
        put("Log", fx, fz, d * math.cos(a), d * math.sin(a), s=rng.uniform(1.8, 2.4))
    for dx, dz in [(-10, 8), (12, -6)]:
        put("LogPile", fx, fz, dx, dz, s=1.0)

    # --- 島じゅうの木・茂み・岩・草(間かくをばらして, 森の濃さで数を変える)
    step = 11.0
    gx = np.arange(-200, 200, step)
    for x0 in gx:
        for z0 in gx:
            x = x0 + rng.uniform(-4.5, 4.5)
            z = z0 + rng.uniform(-4.5, 4.5)
            if math.hypot(x, z) > 195:
                continue
            h = float(sample_height(H, x, z))
            if h < 2.2 or float(normal_y(H, np.array(x), np.array(z))) < 0.82 or on_road(x, z):
                continue
            if any(math.hypot(x - p[1], z - p[2]) < 40 for p in pois):
                continue
            forest = float(N_FOREST.fbm(x / 60, z / 60, 3)) * 0.5 + 0.5          # 0〜1
            roll = rng.random()
            if roll < 0.15 + 0.7 * forest:
                kind = rng.choice(["TreePine", "TreePine", "TreeRound", "TreeRound", "TreeSakura"])
                P.add(str(kind), x, z, s=rng.uniform(0.85, 1.35))
            elif roll < 0.15 + 0.7 * forest + 0.07:
                P.add("Bush", x, z, s=rng.uniform(0.8, 1.2))
            elif roll < 0.15 + 0.7 * forest + 0.11:
                P.add(str(rng.choice(kinds)), x, z, s=rng.uniform(0.8, 1.6))
    # 草(当たり判定なし. 見た目だけ)
    for _ in range(900):
        a = rng.uniform(0, 2 * math.pi)
        d = 190 * math.sqrt(rng.random())
        x, z = d * math.cos(a), d * math.sin(a)
        if float(sample_height(H, x, z)) < 2.4:
            continue
        P.add("GrassTuft", x, z, s=rng.uniform(0.9, 1.6), check=False)
    return P


# ---------------------------------------------------------------------------
# 出発点・ひろうものの置き場
# ---------------------------------------------------------------------------

def make_spawns(H, obstacles):
    """島のふち近く(半径 約 170 m)の 16 か所. 地面が水平に近く, 固いものから離れた所."""
    out = []
    for i in range(16):
        base = 2 * math.pi * i / 16
        found = None
        for dr in (0, -6, 6, -12, 12, -18, -24, -30):
            for da in (0, 0.03, -0.03, 0.06, -0.06):
                a = base + da
                r = 170 + dr
                x, z = r * math.cos(a), r * math.sin(a)
                if (float(sample_height(H, x, z)) > 1.5 and float(normal_y(H, np.array(x), np.array(z))) > 0.9
                        and obstacle_clear(obstacles, x, z, 1.6)):
                    found = [round(x, 1), round(z, 1)]
                    break
            if found:
                break
        if not found:
            raise SystemExit(f"出発点 {i} が見つかりません")
        out.append(found)
    return out


def make_loot(H, obstacles, rng):
    """各名所に 8 か所(中心から 8〜48 m), 名所のあいだの道ぞいに 12 か所."""
    loot = []

    def try_add(x, z):
        if float(sample_height(H, x, z)) < 2.0 or float(normal_y(H, np.array(x), np.array(z))) < 0.85:
            return False
        if not obstacle_clear(obstacles, x, z, 1.4):
            return False
        if any(math.hypot(x - l[0], z - l[2]) < 6 for l in loot):
            return False
        loot.append([round(x, 2), round(float(sample_height(H, x, z)) + 0.5, 2), round(z, 2)])
        return True

    for _, px, pz in POIS:
        n, tries = 0, 0
        while n < 8 and tries < 400:
            tries += 1
            a = rng.uniform(0, 2 * math.pi)
            d = rng.uniform(8, 48)
            n += try_add(px + d * math.cos(a), pz + d * math.sin(a))
        if n < 8:
            raise SystemExit("名所のひろうものが 8 か所に届きません")
    n, tries = 0, 0
    while n < 12 and tries < 2000:
        tries += 1
        a, b = ROADS[int(rng.integers(0, len(ROADS)))]
        t = rng.uniform(0.25, 0.75)
        x = POIS[a][1] + (POIS[b][1] - POIS[a][1]) * t + rng.uniform(-14, 14)
        z = POIS[a][2] + (POIS[b][2] - POIS[a][2]) * t + rng.uniform(-14, 14)
        if all(math.hypot(x - p[1], z - p[2]) > 60 for p in POIS):
            n += try_add(x, z)
    return loot


# ---------------------------------------------------------------------------
# 地面の絵
# ---------------------------------------------------------------------------

C = {
    "grassA": np.array([0.33, 0.58, 0.23]), "grassB": np.array([0.44, 0.68, 0.27]), "dry": np.array([0.60, 0.64, 0.32]),
    "sand": np.array([0.87, 0.80, 0.59]), "wet": np.array([0.68, 0.60, 0.44]), "seabed": np.array([0.42, 0.56, 0.56]),
    "rock": np.array([0.56, 0.52, 0.47]), "dirt": np.array([0.56, 0.43, 0.29]), "stone": np.array([0.70, 0.66, 0.60]),
    "dark": np.array([0.20, 0.42, 0.20]),
}


def mix(a, b, t):
    t = np.asarray(t)[..., None]
    return a * (1 - t) + b * t


def paint(H, X, Z, trees, pixel):
    """座標 X, Z(同じ形の配列)の地面の色 (…, 3)."""
    h = sample_height(H, X, Z)
    ny = normal_y(H, X, Z)
    n1 = N_PAINT.fbm(X / 6, Z / 6, 3) * 0.5 + 0.5
    n2 = N_PAINT.fbm(X / 1.3 + 40, Z / 1.3 + 40, 2) * 0.5 + 0.5
    col = mix(C["grassA"], C["grassB"], smoothstep(0.3, 0.7, n1))
    col = mix(col, C["dry"], smoothstep(0.55, 0.9, N_PAINT.fbm(X / 25 + 90, Z / 25, 2) * 0.5 + 0.5) * 0.7)
    col = col * (0.93 + 0.14 * n2[..., None])
    # 森の濃さで少し暗い緑.
    forest = N_FOREST.fbm(X / 60, Z / 60, 3) * 0.5 + 0.5
    col = mix(col, C["dark"], 0.35 * smoothstep(0.55, 0.85, forest))
    # 砂浜と海の底.
    col = mix(col, C["sand"], smoothstep(2.8, 1.0, h))
    col = mix(col, C["wet"], smoothstep(0.9, 0.0, h))
    col = mix(col, C["seabed"], smoothstep(0.1, -2.5, h))
    # 急な所は岩の色.
    col = mix(col, C["rock"], smoothstep(0.92, 0.78, ny) * smoothstep(1.0, 2.0, h))
    # 名所の地面と道.
    for idx, (_, px, pz) in enumerate(POIS):
        d = np.hypot(X - px, Z - pz)
        kind = ["stone", "dirt", "rock", "grassB"][idx]
        r = [22, 26, 40, 18][idx]
        col = mix(col, C[kind], 0.85 * (1 - smoothstep(r - 6, r + 8, d)) * (1.0 if idx != 3 else 0.5))
    rd = road_distance(X, Z, POIS)
    col = mix(col, C["dirt"], 0.9 * (1 - smoothstep(2.0, 3.4, rd)) * smoothstep(0.5, 2.0, h))
    # 木の影(太陽と反対がわへ).
    for (tx, tz, tr) in trees:
        if X.min() - 8 < tx < X.max() + 8 and Z.min() - 8 < tz < Z.max() + 8:
            sx, sz = tx - 1.6 * tr, tz - 1.4 * tr
            d2 = ((X - sx) ** 2 + (Z - sz) ** 2) / (2.2 * tr) ** 2
            col = col * (1 - 0.30 * np.exp(-d2))[..., None]
    return np.clip(col, 0, 1)


def to_image(col):
    return Image.fromarray((col * 255 + 0.5).astype(np.uint8), "RGB")


def build_ground(H, props):
    trees = [(p[2], p[4], 1.4 * p[6]) for p in props if p[0].startswith("Tree")]
    px = TILE / TILE_PX
    for idx in range(4):
        col, row = idx % 2, idx // 2
        x0 = -256 + col * TILE
        z_top = 256 - row * TILE
        us = x0 + (np.arange(TILE_PX) + 0.5) * px
        vs = z_top - (np.arange(TILE_PX) + 0.5) * px
        X, Z = np.meshgrid(us, vs)
        img = to_image(paint(H, X, Z, trees, px))
        img.save(os.path.join(GROUND_DIR, f"island_{idx}.jpg"), quality=88)


def build_minimap(H):
    px = 512 / MINIMAP_PX
    us = -256 + (np.arange(MINIMAP_PX) + 0.5) * (512 / MINIMAP_PX)
    vs = -256 + (np.arange(MINIMAP_PX) + 0.5) * (512 / MINIMAP_PX)      # 上が -Z
    X, Z = np.meshgrid(us, vs)
    h = sample_height(H, X, Z)
    ny = normal_y(H, X, Z)
    col = mix(C["grassB"] * 1.05, C["dry"], smoothstep(4, 14, h))
    forest = N_FOREST.fbm(X / 60, Z / 60, 3) * 0.5 + 0.5
    col = mix(col, C["dark"], 0.7 * smoothstep(0.5, 0.8, forest))
    col = mix(col, C["sand"], smoothstep(2.6, 1.0, h))
    col = mix(col, C["rock"], smoothstep(0.92, 0.78, ny) * 0.9)
    for idx, (_, px_, pz_) in enumerate(POIS):
        d = np.hypot(X - px_, Z - pz_)
        kind = ["stone", "dirt", "rock", "grassA"][idx]
        col = mix(col, C[kind], 0.85 * (1 - smoothstep(26, 32, d)))
    rd = road_distance(X, Z, POIS)
    col = mix(col, C["dirt"], 0.95 * (1 - smoothstep(1.5, 3.0, rd)) * smoothstep(0.5, 2.0, h))
    sea = np.array([0.22, 0.45, 0.72])
    col = mix(col, mix(sea, np.array([0.10, 0.25, 0.50]), smoothstep(0, -6, h)), smoothstep(0.4, -0.2, h))
    # 日なた・日かげ(立体に見えるよう).
    dhdx = (sample_height(H, X + 2, Z) - sample_height(H, X - 2, Z)) / 4
    dhdz = (sample_height(H, X, Z + 2) - sample_height(H, X, Z - 2)) / 4
    shade = np.clip(0.95 + 1.6 * (-dhdx * 0.6 - dhdz * 0.6), 0.75, 1.2)
    col = np.where((h > 0.3)[..., None], col * shade[..., None], col)
    to_image(np.clip(col, 0, 1)).save(os.path.join(GROUND_DIR, "island_minimap.jpg"), quality=90)


# ---------------------------------------------------------------------------
# 確かめ
# ---------------------------------------------------------------------------

def visibility_report(obstacles, H):
    """名所の中心から見て, 半径 55 m の中の何割が, 背の高い物(目の高さより上)で見通せないか."""
    rng = np.random.default_rng(1)
    tall = [o for o in obstacles if (o["p"][1] + (o["half"][1] if o["shape"] == "box" else o["h"])) - (
        o["p"][1] - (o["half"][1] if o["shape"] == "box" else 0)) > 1.7]
    result = []
    for name, cx, cz in POIS:
        hidden, total = 0, 300
        for _ in range(total):
            a, d = rng.uniform(0, 2 * math.pi), 55 * math.sqrt(rng.random())
            tx, tz = cx + d * math.cos(a), cz + d * math.sin(a)
            blocked = False
            for o in tall:
                ox, oz = o["p"][0], o["p"][2]
                rad = o["r"] if o["shape"] == "cyl" else max(o["half"][0], o["half"][2])
                # 線分 (cx,cz)-(tx,tz) と円(箱は外接円)の距離
                dx, dz = tx - cx, tz - cz
                L2 = dx * dx + dz * dz
                if L2 < 1e-6:
                    continue
                t = max(0, min(1, ((ox - cx) * dx + (oz - cz) * dz) / L2))
                if math.hypot(ox - (cx + t * dx), oz - (cz + t * dz)) < rad * (0.8 if o["shape"] == "box" else 1.0):
                    blocked = True
                    break
            hidden += blocked
        result.append((name, hidden / total))
    return result


def verify(m, H):
    pois = m["pois"]
    for i in range(len(pois)):
        for j in range(i + 1, len(pois)):
            d = math.hypot(pois[i]["p"][0] - pois[j]["p"][0], pois[i]["p"][1] - pois[j]["p"][1])
            assert d >= 120, f"名所 {pois[i]['name']} と {pois[j]['name']} が近すぎる({d:.0f} m)"
    obs = m["obstacles"]
    for p in pois:
        cx, cz = p["p"]
        near = [o for o in obs if math.hypot(o["p"][0] - cx, o["p"][2] - cz) < p["r"]
                and ((o["shape"] == "box") or o["h"] * 1 >= 1.2)]
        loot = [l for l in m["loot"] if math.hypot(l[0] - cx, l[2] - cz) < p["r"]]
        assert len(near) >= 8, f"{p['name']} にかくれる物が {len(near)} 個しかない"
        assert len(loot) >= 6, f"{p['name']} のひろうものが {len(loot)} か所しかない"
    assert len(m["spawns"]) == 16
    for s in m["spawns"]:
        assert float(sample_height(H, s[0], s[1])) > 1.0
        assert obstacle_clear(obs, s[0], s[1], 1.0)
    for l in m["loot"]:
        assert obstacle_clear(obs, l[0], l[2], 1.0)
        assert float(sample_height(H, l[0], l[2])) > 1.0


def main():
    t0 = time.time()
    os.makedirs(MAP_DIR, exist_ok=True)
    os.makedirs(GROUND_DIR, exist_ok=True)
    rng = np.random.default_rng(SEED)
    H = build_heights()
    print(f"高さ: {H.min():.1f}〜{H.max():.1f} m  陸の広さ {(H > 0.3).mean() * 100:.0f}%  ({time.time() - t0:.1f} 秒)")
    if "--check" in sys.argv:
        with open(os.path.join(MAP_DIR, "island.json"), encoding="utf-8") as f:
            verify(json.load(f), H)
        print("OK")
        return
    write_height(os.path.join(MAP_DIR, "island.height"), H)
    P = place_all(H, rng)
    spawns = make_spawns(H, P.obstacles)
    loot = make_loot(H, P.obstacles, rng)
    m = {
        "id": "island", "name": "はじまりの島", "waterY": WATER_Y,
        "sun": {"direction": [0.4, 0.8, 0.45], "color": [1.0, 0.96, 0.9], "intensity": 9000},
        "ambient": 1.0, "sky": "Sky_island",
        "fog": {"color": [0.78, 0.86, 0.95], "start": 150, "end": 700},
        "props": P.props, "obstacles": P.obstacles,
        "spawns": spawns, "loot": loot,
        "pois": [{"name": n, "p": [x, z], "r": POI_RADIUS} for n, x, z in POIS],
    }
    verify(m, H)
    with open(os.path.join(MAP_DIR, "island.json"), "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, separators=(",", ":"))
    print(f"小物 {len(P.props)} 個 / 当たり判定 {len(P.obstacles)} 個 / 出発点 {len(spawns)} / ひろうもの {len(loot)}  ({time.time() - t0:.1f} 秒)")
    for name, frac in visibility_report(P.obstacles, H):
        print(f"  {name}: 中心から見通せない所 {frac * 100:.0f}%")
    build_ground(H, P.props)
    build_minimap(H)
    print(f"絵を書き出しました ({time.time() - t0:.1f} 秒)")


if __name__ == "__main__":
    main()
