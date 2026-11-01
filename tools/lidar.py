#!/usr/bin/env python3
"""Turku as the laser saw it: a reference to hold the game against.

Maanmittauslaitos's airborne laser scans (automaattisesti luokiteltu, CC BY
4.0) are points on everything the plane saw: the ground, roofs, crowns. Two
of Turku's are used: spring 2021 (the trees bare, so roofs and ground show
through) and summer 2023 (in leaf, thinned). Each point gets the colour of
the city's 2022 aerial photo under it (tools/aerial.py), and the cloud is
rendered from any camera, so a street can be seen as it is from where the
game's postcard stands (tools/reference.py --street).

A plane sees roofs, not walls: the points well above the ground that
aren't under a green crown in the photo are roofs, gridded to a metre over
the ground; a picture is traced through that heightfield (walls stand where
a roof's edge is), and the crowns of the summer's scan are drawn over it.

The importer also checks each building's height against the roofs the
scans saw (check_heights): the city model has a few heights over the sea,
not the ground, and some boxes take a block's tallest part.

    # once: the scans to tools/osm_cache/lidar/ (needs `pip install "laspy[lazrs]"`)
    python3 tools/lidar.py --fetch
    python3 tools/lidar.py --prepare

The laser files come from the Kapsi mirror of MML's file service (no key);
both have Turku 2009, 2014, 2021 and 2023 and nothing denser.
"""
import argparse
import math
from pathlib import Path
import sys
import urllib.request
import warnings

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / "osm_cache" / "lidar"
MIRROR = "https://kartat.kapsi.fi/files/laser/automaattinen"
# year: (campaign folder, the 3 x 3 km sheets over the map)
SCANS = {
    "2021": ("2021/20210001_MML_Turku_kevat/1", ["L3324B2", "L3324B4", "L3324D2"]),
    "2023": ("2023/20230108_Leica_Turku_kesa/Harvennettu", ["L3324B1", "L3324B2", "L3324B3", "L3324B4", "L3324D1", "L3324D2"]),
}
ORIGIN = (60.45150, 22.27000)  # tools/osm_import.py's for Turku
# MML's classes: 2 ground; 1 and 3-5 the rest (unclassified, vegetation by
# height; the automatic classification puts roofs there too)
GROUND = 2


def fetch():
    for year, (folder, sheets) in SCANS.items():
        d = CACHE / f"turku-{year}"
        d.mkdir(parents=True, exist_ok=True)
        for s in sheets:
            p = d / f"{s}.laz"
            if p.exists() and p.stat().st_size > 1_000_000:
                continue
            print(f"fetching {year} {s}...", flush=True)
            data = urllib.request.urlopen(f"{MIRROR}/{folder}/{s}.laz", timeout=900).read()
            p.write_bytes(data)


def to_game(E, N):
    """ETRS-TM35FIN (E, N) arrays to game x, z: a quadratic fitted through
    a 9 x 9 grid of exact points over their extent (the map is a few km;
    it's good to a centimetre)."""
    import numpy as np
    sys.path.insert(0, str(ROOT / "tools"))
    import citymodel
    lat0, lon0 = ORIGIN
    kx = 111320 * math.cos(math.radians(lat0))
    e0, e1, n0, n1 = float(E.min()), float(E.max()), float(N.min()), float(N.max())
    ce, cn = (e0 + e1) / 2, (n0 + n1) / 2
    rows, xs, zs = [], [], []
    for e in np.linspace(e0, e1, 9):
        for n in np.linspace(n0, n1, 9):
            # TM35FIN is Gauss-Krüger on 27 E scaled by 0.9996, with its own false easting.
            lat, lon = citymodel.gk_inverse(27e6 + 500000 + (e - 500000) / 0.9996, n / 0.9996, 27)
            u, v = e - ce, n - cn
            rows.append([1, u, v, u * u, u * v, v * v])
            xs.append((lon - lon0) * kx)
            zs.append(-(lat - lat0) * 110574)
    A = np.array(rows)
    cx, cz = np.linalg.lstsq(A, np.array(xs), rcond=None)[0], np.linalg.lstsq(A, np.array(zs), rcond=None)[0]
    u, v = E - ce, N - cn
    terms = [np.ones_like(u), u, v, u * u, u * v, v * v]
    return sum(c * t for c, t in zip(cx, terms)), sum(c * t for c, t in zip(cz, terms))


def prepare():
    """Each sheet to game coordinates: <year>/<sheet>.npz with x, z, y
    (float32 metres) and class (uint8)."""
    import laspy
    import numpy as np
    for year in SCANS:
        for laz in sorted((CACHE / f"turku-{year}").glob("*.laz")):
            out = laz.with_suffix(".npz")
            if out.exists():
                continue
            las = laspy.read(laz)
            E, N = np.asarray(las.x, dtype=np.float64), np.asarray(las.y, dtype=np.float64)
            x, z = to_game(E, N)
            np.savez(out, x=x.astype(np.float32), z=z.astype(np.float32), y=np.asarray(las.z, dtype=np.float32),
                     c=np.asarray(las.classification, dtype=np.uint8))
            print(f"{out}: {len(x)} points", flush=True)


class Cloud:
    """The prepared scans round a point: ground, roofs and crowns, each
    point coloured from the aerial photo."""

    def __init__(self, cx, cz, reach):
        import numpy as np
        import aerial
        self.ground_step = 2.0
        parts = {y: [] for y in SCANS}
        for year in SCANS:
            for f in sorted((CACHE / f"turku-{year}").glob("*.npz")):
                d = np.load(f)
                m = (np.abs(d["x"] - cx) < reach) & (np.abs(d["z"] - cz) < reach)
                if m.any():
                    parts[year].append(np.stack([d["x"][m], d["y"][m], d["z"][m], d["c"][m].astype(np.float32)], axis=1))
        if not any(parts.values()):
            raise SystemExit(f"no laser points near ({cx}, {cz}): run tools/lidar.py --fetch and --prepare")
        p = {y: np.concatenate(v) if v else np.zeros((0, 4), np.float32) for y, v in parts.items()}
        allp = np.concatenate(list(p.values()))
        self._ground_grid(allp[allp[:, 3] == GROUND], cx, cz, reach)
        photo = aerial.Aerial("turku", ORIGIN, (cx - reach, cz - reach, cx + reach, cz + reach))
        self.ground, self.roofs, self.crowns = [], [], []
        self.roofs_of = {}  # year -> its roofs (check_heights goes by the newest that saw a building)
        self.ground_of = {}  # year -> its ground points
        for year, pts in p.items():
            if not len(pts):
                continue
            col = np.nan_to_num(photo.pixels(pts[:, 0], pts[:, 2]), nan=0.5)
            r, g, b = col[:, 0], col[:, 1], col[:, 2]
            green = (g > r * 1.06) & (g > b * 1.03)
            above = pts[:, 1] - self.ground_at(pts[:, 0], pts[:, 2])
            is_ground = pts[:, 3] == GROUND
            high = ~is_ground & (above > 2.5)
            self.ground.append(np.concatenate([pts[is_ground, :3], col[is_ground]], axis=1))
            self.ground_of[year] = self.ground[-1]
            # Crowns from the summer's scan, roofs from both: the spring's
            # sees them through bare trees.
            if year == "2023":
                c = ~is_ground & green & (above > 1.0)
                self.crowns.append(np.concatenate([pts[c, :3], col[c]], axis=1))
            roof = high & ~green
            self.roofs.append(np.concatenate([pts[roof, :3], col[roof]], axis=1))
            self.roofs_of[year] = self.roofs[-1]
        self.ground, self.roofs, self.crowns = (np.concatenate(v) for v in (self.ground, self.roofs, self.crowns))

    def _ground_grid(self, g, cx, cz, reach):
        """The bare ground on a 2 m grid: the lowest ground point in each
        cell, the holes (under buildings) filled from round about."""
        import numpy as np
        s = self.ground_step
        self.gx0, self.gz0 = cx - reach, cz - reach
        n = int(2 * reach / s) + 1
        self.gn = n
        H = np.full(n * n, np.inf, dtype=np.float32)
        i = np.clip(((g[:, 0] - self.gx0) / s).astype(int), 0, n - 1)
        j = np.clip(((g[:, 2] - self.gz0) / s).astype(int), 0, n - 1)
        np.minimum.at(H, j * n + i, g[:, 1])
        H = H.reshape(n, n)
        # Fill: repeatedly take the mean of the known neighbours.
        for _ in range(200):
            hole = ~np.isfinite(H)
            if not hole.any():
                break
            P = np.pad(H, 1, constant_values=np.inf)
            nb = np.stack([P[:-2, 1:-1], P[2:, 1:-1], P[1:-1, :-2], P[1:-1, 2:]])
            ok = np.isfinite(nb)
            mean = np.where(ok, nb, 0).sum(0) / np.maximum(ok.sum(0), 1)
            H = np.where(hole & ok.any(0), mean, H)
        H[~np.isfinite(H)] = np.nanmedian(H[np.isfinite(H)]) if np.isfinite(H).any() else 0
        self.H = H

    def ground_at(self, x, z):
        import numpy as np
        n, s = self.gn, self.ground_step
        i = np.clip(((np.asarray(x) - self.gx0) / s).astype(int), 0, n - 1)
        j = np.clip(((np.asarray(z) - self.gz0) / s).astype(int), 0, n - 1)
        return self.H[j, i]


def available():
    """Are the prepared scans there (tools/lidar.py --fetch --prepare)?"""
    return any((CACHE / f"turku-{y}").glob("*.npz") for y in SCANS)


def ground_in(cloud, x, z, w, d, ang, year=None):
    """How many of the scans' (or one year's) ground points fall inside a box."""
    import numpy as np
    G = getattr(cloud, "ground_of", {}).get(year, cloud.ground)
    rad = math.hypot(w, d) / 2
    m = (np.abs(G[:, 0] - x) < rad) & (np.abs(G[:, 2] - z) < rad)
    P = G[m]
    ca, sa = math.cos(ang), math.sin(ang)
    u = (P[:, 0] - x) * ca + (P[:, 2] - z) * sa
    v = -(P[:, 0] - x) * sa + (P[:, 2] - z) * ca
    return int(((np.abs(u) < w / 2) & (np.abs(v) < d / 2)).sum())


def check_heights(boxes, block=1000, cloud_at=None):
    """The importer's building boxes (x, z, w, d, angle, eave height, kind,
    ..., roof height at [10], over a road at [11]) with the heights the
    laser scans clearly disagree with put right: a box whose roof the
    scans see (a point every 3 m² or more) lowered when even its highest
    tenth is 4 m (and a fifth) below the box's top, raised when three
    quarters of it are that much above it. Churches keep theirs (a spire is a few
    points). Returns (boxes, how many lowered, how many raised).
    cloud_at(cx, cz, reach) gives the scans round a point (Cloud)."""
    import numpy as np
    out = list(boxes)
    lowered = raised = 0
    by_block = {}
    for k, b in enumerate(boxes):
        by_block.setdefault((math.floor(b[0] / block), math.floor(b[1] / block)), []).append(k)
    for (bi, bj), ks in sorted(by_block.items()):
        cx, cz = (bi + 0.5) * block, (bj + 0.5) * block
        try:
            cloud = (cloud_at or Cloud)(cx, cz, block / 2 + 80)
        except SystemExit:
            continue
        cell = 20.0
        years = []  # newest first: (year, roofs sorted by cell, their cells' keys)
        for year in sorted(getattr(cloud, "roofs_of", {"": cloud.roofs}), reverse=True):
            R = getattr(cloud, "roofs_of", {"": cloud.roofs})[year]
            ci = np.floor(R[:, 0] / cell).astype(np.int64)
            cj = np.floor(R[:, 2] / cell).astype(np.int64)
            order = np.lexsort((ci, cj))
            years.append((year, R[order], (cj * 1_000_003 + ci)[order]))
        for k in ks:
            x, z, w, d, ang, h, kind = boxes[k][:7]
            roof_h = boxes[k][10] if len(boxes[k]) > 10 and boxes[k][10] else 0.0
            if kind == "church" or (len(boxes[k]) > 11 and boxes[k][11]):
                continue
            rad = math.hypot(w, d) / 2
            ca, sa = math.cos(ang), math.sin(ang)
            built = boxes[k][9] if len(boxes[k]) > 9 and boxes[k][9] else None
            # The newest scan that saw the roof (a building finished in 2021
            # was half up in that spring's).
            seen = None  # (year, points on the roof) of the newest scan after it was built
            for year, R, keys in years:
                sel = []
                for j in range(math.floor((z - rad) / cell), math.floor((z + rad) / cell) + 1):
                    for i in range(math.floor((x - rad) / cell), math.floor((x + rad) / cell) + 1):
                        key = j * 1_000_003 + i
                        a, b = np.searchsorted(keys, key), np.searchsorted(keys, key, side="right")
                        if b > a:
                            sel.append(R[a:b])
                P = np.concatenate(sel) if sel else np.zeros((0, 6))
                u = (P[:, 0] - x) * ca + (P[:, 2] - z) * sa
                v = -(P[:, 0] - x) * sa + (P[:, 2] - z) * ca
                ins = (np.abs(u) < w / 2 - 0.5) & (np.abs(v) < d / 2 - 0.5)
                after = not (year and built and str(year).isdigit() and built >= int(year))
                if seen is None and after:
                    seen = (year, int(ins.sum()))
                if ins.sum() >= max(3, w * d / 6):
                    break
            else:
                after = seen is not None
            if not after:
                continue  # finished in the scan's year or after: the scan saw a building site
            if ins.sum() < max(3, w * d / 6):
                # A shed or a house the scans see only ground in can't be a
                # tower (the city model gave a few small ones its own
                # height over the sea): a storey or two. (Only by a scan
                # taken once it was up.)
                top = h + (boxes[k][10] or 0 if len(boxes[k]) > 10 else 0)
                if kind in ("shed", "house") and top > 12 and seen and seen[1] == 0 and ground_in(cloud, x, z, w, d, ang, seen[0]) >= max(2, w * d / 8):
                    b = list(boxes[k])
                    b[5] = 3.0 if kind == "shed" else 6.0
                    out[k] = tuple(b)
                    lowered += 1
                continue
            g = float(cloud.ground_at(np.array([x]), np.array([z]))[0])
            tops = P[ins, 1] - g
            p75, p90 = float(np.percentile(tops, 75)), float(np.percentile(tops, 90))
            top = h + roof_h
            slack = max(4.0, 0.2 * top)
            new = None
            if p90 < top - slack:
                new = max(2.5, p90 - roof_h)
                lowered += 1
            elif p75 > top + slack:
                new = p75 - roof_h / 2  # (a pitched roof's upper half is over its eaves by about half its height)
                raised += 1
            if new is not None:
                b = list(boxes[k])
                b[5] = round(new, 1)
                out[k] = tuple(b)
    return out, lowered, raised


WALL = (0.74, 0.71, 0.66)  # a plaster for the walls the plane didn't see
SUN = (0.45, 0.75, -0.48)   # towards the sun at 14: south-west and high (x east, z south)


def unshade(c):
    """The aerial photo's colours with its shadows lifted: in a shadow the
    photo is dark and blue with sky light; this scene has its own light."""
    import numpy as np
    c = c.copy()
    c[:, 2] = np.minimum(c[:, 2], np.maximum(c[:, 0], c[:, 1]) + 0.03)
    lum = c.mean(1, keepdims=True)
    # (a shadow's colour is the sky's, not the surface's: keep less of it the darker it is)
    keep = np.clip((lum - 0.12) / 0.25, 0, 1)
    c = lum + (c - lum) * keep
    lift = np.clip(0.42 / np.maximum(lum, 0.05), 1, 2.6)
    return np.clip(c * lift, 0, 1)


class Heights:
    """The ground and the roofs on a 1 m grid: the laser's highest roof
    point in each cell over the ground under it, a cell's holes (a metre
    the plane missed) closed from its neighbours."""

    def __init__(self, cloud, cx, cz, reach):
        import numpy as np
        self.x0, self.z0, self.n = cx - reach, cz - reach, int(2 * reach)
        n = self.n
        gi = np.arange(n) + 0.5
        X, Z = np.meshgrid(self.x0 + gi, self.z0 + gi)
        self.G = cloud.ground_at(X, Z).astype(np.float32)
        R = cloud.roofs
        i = ((R[:, 0] - self.x0)).astype(int)
        j = ((R[:, 2] - self.z0)).astype(int)
        ok = (i >= 0) & (i < n) & (j >= 0) & (j < n)
        roof = np.full(n * n, -np.inf, dtype=np.float32)
        np.maximum.at(roof, j[ok] * n + i[ok], R[ok, 1])
        rc = np.zeros((n * n, 3), np.float32)
        rc[j[ok] * n + i[ok]] = R[ok, 3:]
        roof, rc = roof.reshape(n, n), rc.reshape(n, n, 3)
        for _ in range(2):  # close holes: a cell most of whose neighbours are roof
            P = np.pad(roof, 1, constant_values=-np.inf)
            nb = np.stack([P[a:a + n, b:b + n] for a in range(3) for b in range(3) if (a, b) != (1, 1)])
            have = np.isfinite(nb)
            fill = ~np.isfinite(roof) & (have.sum(0) >= 5)
            med = np.where(have, nb, np.nan)
            with np.errstate(all="ignore"), warnings.catch_warnings():
                warnings.simplefilter("ignore", RuntimeWarning)  # (all-NaN cells aren't filled anyway)
                roof = np.where(fill, np.nanmedian(med, 0), roof)
            Pc = np.pad(rc, ((1, 1), (1, 1), (0, 0)))
            rc = np.where(fill[..., None], Pc[1:-1, :-2], rc)
        b = np.isfinite(roof) & (roof > self.G + 2.5)
        # Open the mask: anything under ~5 m across (a bare tree in the
        # spring's scan, a lamp, a crane's jib) isn't a building.
        def shrink(m):
            P = np.pad(m, 1)
            return np.logical_and.reduce([P[a:a + n, c:c + n] for a in range(3) for c in range(3)])
        def grow(m):
            P = np.pad(m, 1)
            return np.logical_or.reduce([P[a:a + n, c:c + n] for a in range(3) for c in range(3)])
        o = b
        for _ in range(2): o = shrink(o)
        for _ in range(2): o = grow(o)
        self.building = b & o
        self.D = np.where(self.building, roof, self.G).astype(np.float32)
        self.roof_col = rc

    def cell(self, x, z):
        import numpy as np
        n = self.n
        return np.clip((x - self.x0).astype(int), 0, n - 1), np.clip((z - self.z0).astype(int), 0, n - 1)


def render(cloud, eye, look, fov, size, reach=1000):
    """Turku from `eye` towards `look` (game metres), `fov` degrees across
    the height, as an (h, w, 3) uint8 array: the ground and buildings traced
    through Heights, the crowns as points over them."""
    import numpy as np
    import aerial
    W, Hh = size
    eye, look = np.array(eye, float), np.array(look, float)
    f = look - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0])
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    focal = (Hh / 2) / math.tan(math.radians(fov) / 2)
    hf = Heights(cloud, eye[0], eye[2], reach)
    photo = aerial.Aerial("turku", ORIGIN, (eye[0] - reach, eye[2] - reach, eye[0] + reach, eye[2] + reach))

    # One ray a pixel, marched out in steps growing with the distance, then
    # narrowed down to where it meets the surface.
    px, py = np.meshgrid(np.arange(W) + 0.5, np.arange(Hh) + 0.5)
    d = (f[None, None, :] + r[None, None, :] * ((px - W / 2) / focal)[..., None]
         - u[None, None, :] * ((py - Hh / 2) / focal)[..., None]).reshape(-1, 3)
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    N = len(d)
    hit_t = np.full(N, np.inf)
    active = np.arange(N)
    t_prev = np.zeros(N)
    t = 0.3
    while t < reach * 0.98 and len(active):
        p = eye + d[active] * t
        i, j = hf.cell(p[:, 0], p[:, 2])
        under = p[:, 1] <= hf.D[j, i]
        out = (np.abs(p[:, 0] - eye[0]) > reach - 2) | (np.abs(p[:, 2] - eye[2]) > reach - 2)
        if under.any():
            idx = active[under]
            lo, hi = t_prev[idx], np.full(len(idx), t)
            for _ in range(8):
                mid = (lo + hi) / 2
                q = eye + d[idx] * mid[:, None]
                ii, jj = hf.cell(q[:, 0], q[:, 2])
                below = q[:, 1] <= hf.D[jj, ii]
                hi, lo = np.where(below, mid, hi), np.where(below, lo, mid)
            hit_t[idx] = hi
        t_prev[active] = t
        active = active[~under & ~out]
        t = t + max(0.15, t * 0.015)
    hit = np.isfinite(hit_t)
    P = eye + d * np.where(hit, hit_t, 0)[:, None]
    i, j = hf.cell(P[:, 0], P[:, 2])
    on_building = hf.building[j, i]
    top = hf.D[j, i]
    is_wall = on_building & (P[:, 1] < top - 0.4)
    # The surface's slope from the heights round the hit, for the light.
    i1, j1 = np.clip(i + 1, 0, hf.n - 1), np.clip(j + 1, 0, hf.n - 1)
    i0, j0 = np.clip(i - 1, 0, hf.n - 1), np.clip(j - 1, 0, hf.n - 1)
    gx = (hf.D[j, i1] - hf.D[j, i0]) / 2
    gz = (hf.D[j1, i] - hf.D[j0, i]) / 2
    n_ground = np.stack([-gx, np.ones_like(gx), -gz], 1)
    n_ground /= np.linalg.norm(n_ground, axis=1, keepdims=True)
    # A wall faces the way the ray came in from, along the axis it crossed.
    wall_n = np.where(np.abs(d[:, [0]]) > np.abs(d[:, [2]]), np.stack([-np.sign(d[:, 0]), 0 * d[:, 0], 0 * d[:, 0]], 1),
                      np.stack([0 * d[:, 0], 0 * d[:, 0], -np.sign(d[:, 2])], 1))
    n = np.where(is_wall[:, None], wall_n, n_ground)
    sun = np.array(SUN) / np.linalg.norm(SUN)
    light = 0.55 + 0.6 * np.clip(n @ sun, 0, 1)
    col = unshade(np.nan_to_num(photo.pixels(P[:, 0], P[:, 2]), nan=0.5))
    roof_c = unshade(hf.roof_col[j, i])
    col = np.where((on_building & ~is_wall)[:, None], np.where(roof_c.sum(1, keepdims=True) > 0, roof_c, col), col)
    col = np.where(is_wall[:, None], np.array(WALL)[None, :], col)
    col = col * light[:, None]
    depth = np.where(hit, hit_t, np.inf)
    # Haze with distance.
    haze = np.clip(depth / 2500, 0, 0.6)[:, None]
    sky = np.linspace([0.45, 0.62, 0.86], [0.75, 0.83, 0.92], Hh)[:, None, :].repeat(W, 1).reshape(-1, 3)
    img = np.where(hit[:, None], col * (1 - haze) + sky * haze, sky)

    # The crowns: points of the summer's scan, each a leafy blob ~1.8 m
    # across, in front of whatever the trace found there.
    C = cloud.crowns
    rel = C[:, :3] - eye
    zc = rel @ f
    m = (zc > 1.0) & (zc < reach)
    rel, zc, cc = rel[m], zc[m], C[m, 3:]
    sx = (rel @ r) / zc * focal + W / 2
    sy = -(rel @ u) / zc * focal + Hh / 2
    k = np.clip(np.round(focal * 1.8 / zc), 1, 40).astype(int)
    pix_l, z_l, c_l = [], [], []
    for kk in np.unique(k):
        sel = k == kk
        offs = np.arange(kk) - (kk - 1) / 2
        for oy in offs:
            for ox in offs:
                if ox * ox + oy * oy > (kk / 2) ** 2 + 0.25:
                    continue
                x = (sx[sel] + ox).astype(int)
                y = (sy[sel] + oy).astype(int)
                ok = (x >= 0) & (x < W) & (y >= 0) & (y < Hh)
                pix_l.append(y[ok] * W + x[ok]); z_l.append(zc[sel][ok]); c_l.append(cc[sel][ok] * (0.8 + 0.25 * (oy < 0)))
    if pix_l:
        pix, zz, cl = np.concatenate(pix_l), np.concatenate(z_l), np.concatenate(c_l)
        # depth along the ray vs along the view axis: compare like with like
        zray = zz / np.clip(d[pix] @ f, 0.2, 1)
        front = zray < depth[pix]
        pix, zray, cl = pix[front], zray[front], cl[front]
        order = np.lexsort((zray, pix))
        pix, zray, cl = pix[order], zray[order], cl[order]
        first = np.ones(len(pix), bool)
        first[1:] = pix[1:] != pix[:-1]
        hz = np.clip(zray[first] / 2500, 0, 0.6)[:, None]
        img[pix[first]] = cl[first] * (1 - hz) + sky[pix[first]] * hz
    return (np.clip(img.reshape(Hh, W, 3), 0, 1) * 255).astype(np.uint8)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fetch", action="store_true", help="download the scans")
    ap.add_argument("--prepare", action="store_true", help="the scans to game coordinates (needs laspy)")
    args = ap.parse_args(argv)
    if args.fetch:
        fetch()
    if args.prepare:
        prepare()
    if not (args.fetch or args.prepare):
        ap.print_help()


if __name__ == "__main__":
    main()
