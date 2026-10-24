"""Aerial photo colours for tools/osm_import.py: what colour the ground and
the roofs really are, so a block's yard is asphalt where it is asphalt and a
roof is red where it is red tile.

The photo is fetched once per area, a kilometre square at a time at 1 m a
pixel, from a WMS in plain latitude/longitude (EPSG:4326), and cached in
tools/osm_cache/aerial/<area>/. The game never sees the photo, only colours
taken from it: one per roof, and one of a small palette per ground point.

Sources:
  turku  Turun kaupunki, Ilmakuva 2025 (turku.asiointi.fi WMS).

    python3 tools/aerial.py turku --fetch       # fill the cache
    python3 tools/aerial.py turku --sample X Z  # the photo's colour at a point
"""
import io
import math
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / "osm_cache" / "aerial"
TILE_M, TILE_PX = 1000, 1000

SOURCES = {
    "turku": ("https://turku.asiointi.fi/TeklaOGCWeb/WMS.ashx", "Ilmakuva 2025"),
}


def game_colour(c):
    """A photo's colour as the game's: the photo is lit by a real sun (the
    game lights its colours again), so a little darker. A shadow's blue cast
    is taken out first: blue over the red and green mean is mostly sky."""
    r, g, b = c
    b = min(b, max(r, g) + 0.02)
    m = (r + g + b) / 3
    return tuple(max(0.0, min(1.0, (m + (v - m) * 1.1) * 0.85)) for v in (r, g, b))


class Aerial:
    """Colours of the aerial photo at game coordinates (x east, z south of
    `origin`, metres: the importer's projection)."""

    def __init__(self, area, origin, bounds, source=None):
        self.lat0, self.lon0 = origin
        self.kx = 111320 * math.cos(math.radians(self.lat0))
        self.dir = CACHE / area
        self.url, self.layer = SOURCES[source or area]
        self.bounds = bounds
        self.tiles = {}

    def tile_keys(self):
        x0, z0, x1, z1 = self.bounds
        return [(i, j) for j in range(math.floor(z0 / TILE_M), math.floor(z1 / TILE_M) + 1)
                for i in range(math.floor(x0 / TILE_M), math.floor(x1 / TILE_M) + 1)]

    def cached(self):
        return all((self.dir / f"{i}_{j}.jpg").exists() for i, j in self.tile_keys())

    def fetch(self):
        from PIL import Image
        for i, j in self.tile_keys():
            path = self.dir / f"{i}_{j}.jpg"
            if path.exists():
                continue
            x0, z0 = i * TILE_M, j * TILE_M
            lon0, lon1 = self.lon0 + x0 / self.kx, self.lon0 + (x0 + TILE_M) / self.kx
            lat1, lat0 = self.lat0 - z0 / 110574, self.lat0 - (z0 + TILE_M) / 110574
            q = urllib.parse.urlencode({"SERVICE": "WMS", "VERSION": "1.1.1", "REQUEST": "GetMap", "LAYERS": self.layer,
                                        "STYLES": "", "SRS": "EPSG:4326", "BBOX": f"{lon0},{lat0},{lon1},{lat1}",
                                        "WIDTH": TILE_PX, "HEIGHT": TILE_PX, "FORMAT": "image/jpeg"})
            req = urllib.request.Request(f"{self.url}?{q}", headers={"User-Agent": "3d-auto-importer/1.0"})
            img = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=120).read())).convert("RGB")
            self.dir.mkdir(parents=True, exist_ok=True)
            img.save(path, quality=92)
            print(f"aerial: {path.name}", file=sys.stderr)
        print(f"aerial: {len(self.tile_keys())} tiles in {self.dir}", file=sys.stderr)

    def _tile(self, i, j):
        if (i, j) not in self.tiles:
            import numpy as np
            from PIL import Image
            path = self.dir / f"{i}_{j}.jpg"
            self.tiles[i, j] = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255 if path.exists() else None
        return self.tiles[i, j]

    def pixels(self, xs, zs):
        """The photo's rgb (0-1) at arrays of x, z, as an (n, 3) array; NaN off it."""
        import numpy as np
        xs, zs = np.asarray(xs, dtype=np.float64), np.asarray(zs, dtype=np.float64)
        out = np.full((len(xs), 3), np.nan, dtype=np.float32)
        ti, tj = np.floor(xs / TILE_M).astype(int), np.floor(zs / TILE_M).astype(int)
        for i, j in set(zip(ti.tolist(), tj.tolist())):
            img = self._tile(i, j)
            if img is None:
                continue
            m = (ti == i) & (tj == j)
            h, w = img.shape[:2]
            u = np.clip(((xs[m] - i * TILE_M) / TILE_M * w).astype(int), 0, w - 1)
            v = np.clip(((zs[m] - j * TILE_M) / TILE_M * h).astype(int), 0, h - 1)
            out[m] = img[v, u]
        return out

    def robust(self, xs, zs):
        """One colour for a patch: the middle value per channel of the middle
        half by brightness, so a car, a shadow or a skylight doesn't decide
        it. None if the patch is off the photo."""
        import numpy as np
        c = self.pixels(xs, zs)
        c = c[~np.isnan(c[:, 0])]
        if len(c) == 0:
            return None
        c = c[np.argsort(c.sum(axis=1))]
        n = len(c)
        mid = c[n // 4: n - n // 4] if n >= 4 else c
        return game_colour(tuple(float(v) for v in np.median(mid, axis=0)))

    def roof_of_box(self, x, z, w, d, ang):
        """A rotated box's roof colour, from its middle (eaves, walls and the
        shadows beside them kept out)."""
        import numpy as np
        c, s = math.cos(ang), math.sin(ang)
        fu = np.linspace(-0.3, 0.3, max(2, int(w * 0.6 / 1.2)))
        fv = np.linspace(-0.3, 0.3, max(2, int(d * 0.6 / 1.2)))
        U, V = np.meshgrid(fu * w, fv * d)
        return self.robust((x + c * U - s * V).ravel(), (z + s * U + c * V).ravel())

    def roof_of_outline(self, pts):
        """An outline's roof colour: points 1.2 m apart inside it, at least
        2 m from its edges."""
        import numpy as np
        P = np.asarray(pts, dtype=np.float64)
        x0, z0 = P.min(axis=0)
        x1, z1 = P.max(axis=0)
        X, Z = np.meshgrid(np.arange(x0 + 1, x1, 1.2), np.arange(z0 + 1, z1, 1.2))
        X, Z = X.ravel(), Z.ravel()
        inside = np.zeros(len(X), dtype=bool)
        edge = np.full(len(X), np.inf)
        for k in range(len(P)):
            (ax, az), (bx, bz) = P[k], P[(k + 1) % len(P)]
            cross = ((az > Z) != (bz > Z)) & (X < (bx - ax) * (Z - az) / ((bz - az) or 1e-9) + ax)
            inside ^= cross
            dx, dz = bx - ax, bz - az
            t = np.clip(((X - ax) * dx + (Z - az) * dz) / ((dx * dx + dz * dz) or 1e-9), 0, 1)
            edge = np.minimum(edge, np.hypot(X - ax - t * dx, Z - az - t * dz))
        keep = inside & (edge > 2)
        if keep.sum() < 4:
            keep = inside
        return self.robust(X[keep], Z[keep]) if keep.any() else None

    def ground(self, xs, zs, step, n=24, seed=1):
        """The ground under points `step` apart: each point's colour (the
        middle of its cell, 5 x 5 samples) sorted into a palette of `n`.
        Returns (palette as game colours, each point's index into it, or -1
        off the photo)."""
        import numpy as np
        xs, zs = np.asarray(xs, dtype=np.float64), np.asarray(zs, dtype=np.float64)
        offs = (np.arange(5) - 2) * step / 5
        samples = np.stack([self.pixels(xs + dx, zs + dz) for dx in offs for dz in offs], axis=1)
        cols = np.nanmedian(samples, axis=1)
        ok = ~np.isnan(cols[:, 0])
        idx = np.full(len(xs), -1, dtype=int)
        if not ok.any():
            return [], idx
        # k-means from evenly spread starts (deterministic for a given photo)
        data = cols[ok]
        rng = np.random.default_rng(seed)
        centres = data[rng.choice(len(data), size=min(n, len(data)), replace=False)]
        for _ in range(25):
            lab = np.argmin(((data[:, None, :] - centres[None]) ** 2).sum(axis=2), axis=1)
            for k in range(len(centres)):
                if (lab == k).any():
                    centres[k] = data[lab == k].mean(axis=0)
        lab = np.argmin(((data[:, None, :] - centres[None]) ** 2).sum(axis=2), axis=1)
        idx[ok] = lab
        return [game_colour(tuple(float(v) for v in c)) for c in centres], idx


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT / "tools"))
    import osm_import
    area = sys.argv[1]
    cfg = osm_import.AREAS[area]
    lat0, lon0 = cfg["origin"]
    s_, w_, n_, e_ = cfg["bbox"]
    kx = 111320 * math.cos(math.radians(lat0))
    bounds = ((w_ - lon0) * kx, -(n_ - lat0) * 110574, (e_ - lon0) * kx, -(s_ - lat0) * 110574)
    a = Aerial(area, cfg["origin"], bounds, source=cfg.get("aerial"))
    if "--fetch" in sys.argv:
        a.fetch()
    if "--sample" in sys.argv:
        k = sys.argv.index("--sample")
        print(a.pixels([float(sys.argv[k + 1])], [float(sys.argv[k + 2])])[0])
