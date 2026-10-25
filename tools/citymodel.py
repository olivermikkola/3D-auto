"""Building heights and ages from a city's 3D model, for tools/osm_import.py.

Turku publishes its city model (Turun kaupunkitietomalli, CC BY 4.0) through
a WFS as CityGML. Each building there has a point inside it, a measured
height, its storeys and the year it was finished. The importer gives an OSM
building the height of the model's buildings inside it, so a five-storey
block from 1890 is as tall as it is, not as tall as a guess.

Fetched once per area in 500 m squares (EPSG:3877) and cached as small JSON
in tools/osm_cache/citymodel/<area>/; only those few numbers are kept.

    python3 tools/citymodel.py turku --fetch
"""
import json
import math
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / "osm_cache" / "citymodel"
TILE = 500

SOURCES = {
    # Turun kaupunki, Turun kaupunkitietomalli, CC BY 4.0 (avoindata.fi).
    "turku": ("https://turku.asiointi.fi/TeklaOGCWeb/WFS.ashx", "bldg:Building_LOD1", 23),
}


def _consts():
    a, f = 6378137.0, 1 / 298.257222101
    e2, n = f * (2 - f), f / (2 - f)
    A = a / (1 + n) * (1 + n * n / 4 + n ** 4 / 64)
    return e2, n, A


def gk(lat, lon, lon0):
    """WGS84 to Gauss-Krüger (ETRS-GKn, EPSG:38xx): easting, northing."""
    e2, n, A = _consts()
    phi, lam = math.radians(lat), math.radians(lon - lon0)
    t = math.sinh(math.atanh(math.sin(phi)) - math.sqrt(e2) * math.atanh(math.sqrt(e2) * math.sin(phi)))
    xi, eta = math.atan2(t, math.cos(lam)), math.atanh(math.sin(lam) / math.sqrt(1 + t * t))
    al = [n / 2 - 2 * n * n / 3 + 5 * n ** 3 / 16, 13 * n * n / 48 - 3 * n ** 3 / 5, 61 * n ** 3 / 240]
    x = xi + sum(al[j] * math.sin(2 * (j + 1) * xi) * math.cosh(2 * (j + 1) * eta) for j in range(3))
    y = eta + sum(al[j] * math.cos(2 * (j + 1) * xi) * math.sinh(2 * (j + 1) * eta) for j in range(3))
    return lon0 * 1e6 + 500000 + A * y, A * x


def gk_inverse(E, N, lon0):
    """Gauss-Krüger back to WGS84 latitude, longitude (Newton on gk)."""
    lat, lon = N / 111320.0, lon0 + (E - lon0 * 1e6 - 500000) / 55000.0
    for _ in range(6):
        e0, n0 = gk(lat, lon, lon0)
        d = 1e-5
        e1, n1 = gk(lat + d, lon, lon0)
        e2_, n2 = gk(lat, lon + d, lon0)
        J = [[(e1 - e0) / d, (e2_ - e0) / d], [(n1 - n0) / d, (n2 - n0) / d]]
        det = J[0][0] * J[1][1] - J[0][1] * J[1][0]
        de, dn = E - e0, N - n0
        lat += (J[1][1] * de - J[0][1] * dn) / det
        lon += (-J[1][0] * de + J[0][0] * dn) / det
    return lat, lon


def parse(xml):
    """The buildings in a GetFeature answer: dicts of E, N, height, storeys, year."""
    out = []
    for b in xml.split("<bldg:Building gml:id")[1:]:
        attr = dict(re.findall(r'name="(\w+)">\s*<gen:value>([^<]*)', b))
        h = re.search(r"<bldg:measuredHeight[^>]*>([\d.]+)<", b)
        st = re.search(r"<bldg:storeysAboveGround>(\d+)<", b)
        yr = re.search(r"<bldg:yearOfConstruction>(\d{4})", b) or re.search(r"\d\d\.\d\d\.(\d{4})", attr.get("valmistunut", ""))
        try:
            E, N = float(attr["y"]), float(attr["x"])  # the model names northing x
        except (KeyError, ValueError):
            continue
        out.append({"E": E, "N": N, "h": float(h.group(1)) if h else None,
                    "storeys": int(st.group(1)) if st else None, "year": int(yr.group(1)) if yr else None})
    return out


class CityModel:
    """The model's buildings in game coordinates (the importer's projection)."""

    def __init__(self, area, origin, bounds, source=None):
        self.url, self.layer, self.lon0 = SOURCES[source or area]
        self.lat0, self.lon00 = origin
        self.kx = 111320 * math.cos(math.radians(self.lat0))
        self.dir = CACHE / area
        self.bounds = bounds

    def _tiles(self):
        x0, z0, x1, z1 = self.bounds
        corners = [(self.lat0 - z / 110574, self.lon00 + x / self.kx) for x in (x0, x1) for z in (z0, z1)]
        pts = [gk(la, lo, self.lon0) for la, lo in corners]
        E0, E1 = min(p[0] for p in pts), max(p[0] for p in pts)
        N0, N1 = min(p[1] for p in pts), max(p[1] for p in pts)
        return [(i, j) for j in range(math.floor(N0 / TILE), math.floor(N1 / TILE) + 1)
                for i in range(math.floor(E0 / TILE), math.floor(E1 / TILE) + 1)]

    def cached(self):
        return all((self.dir / f"{i}_{j}.json").exists() for i, j in self._tiles())

    def fetch(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        tiles = self._tiles()
        for k, (i, j) in enumerate(tiles):
            path = self.dir / f"{i}_{j}.json"
            if path.exists():
                continue
            q = urllib.parse.urlencode({"service": "WFS", "version": "1.1.0", "request": "GetFeature", "typeName": self.layer,
                                        "bbox": f"{i * TILE},{j * TILE},{(i + 1) * TILE},{(j + 1) * TILE}"})
            req = urllib.request.Request(f"{self.url}?{q}", headers={"User-Agent": "3d-auto-importer/1.0"})
            xml = urllib.request.urlopen(req, timeout=600).read().decode("utf-8-sig")
            path.write_text(json.dumps(parse(xml)))
            print(f"citymodel: {k + 1}/{len(tiles)} {path.name}", file=sys.stderr)
            time.sleep(0.5)  # a city's own server: one request at a time, with a pause

    def buildings(self):
        """(x, z, height or None, storeys or None, year or None) in game coordinates."""
        out = []
        for i, j in self._tiles():
            path = self.dir / f"{i}_{j}.json"
            if not path.exists():
                continue
            for b in json.loads(path.read_text()):
                if not (i * TILE <= b["E"] < (i + 1) * TILE and j * TILE <= b["N"] < (j + 1) * TILE):
                    continue  # a building on a tile's edge comes back in both
                lat, lon = gk_inverse(b["E"], b["N"], self.lon0)
                out.append(((lon - self.lon00) * self.kx, -(lat - self.lat0) * 110574, b["h"], b["storeys"], b["year"]))
        return out


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT / "tools"))
    import osm_import
    area = sys.argv[1]
    cfg = osm_import.AREAS[area]
    lat0, lon0 = cfg["origin"]
    s_, w_, n_, e_ = cfg["bbox"]
    kx = 111320 * math.cos(math.radians(lat0))
    bounds = ((w_ - lon0) * kx, -(n_ - lat0) * 110574, (e_ - lon0) * kx, -(s_ - lat0) * 110574)
    m = CityModel(area, cfg["origin"], bounds, source=cfg.get("citymodel"))
    if "--fetch" in sys.argv:
        m.fetch()
    bs = m.buildings()
    hs = [b[2] for b in bs if b[2]]
    print(f"citymodel: {len(bs)} buildings, {len(hs)} with a height, {len(m._tiles())} tiles")
