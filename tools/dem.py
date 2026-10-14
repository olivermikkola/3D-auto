"""Ground heights from Maanmittauslaitos' (National Land Survey of Finland)
10 m elevation model, for tools/osm_import.py.

The model comes in GeoTIFF sheets of 24 x 12 km in ETRS-TM35FIN (EPSG:3067),
heights in N2000 meters. Sheets are cached in tools/osm_cache/dem/; missing
ones are downloaded from MML's open data file service with the key in
~/.config/3d-auto/mml-key (free; register at maanmittauslaitos.fi). The data
is CC BY 4.0: credit Maanmittauslaitos.
"""
import math
import urllib.request
from pathlib import Path

FEED = "https://tiedostopalvelu.maanmittauslaitos.fi/tp/tilauslataus/tuotteet/korkeusmalli/hila_10m/etrs-tm35fin-n2000"
KEY = Path.home() / ".config" / "3d-auto" / "mml-key"


def tm35(lat, lon):
    """WGS84 latitude, longitude to ETRS-TM35FIN easting, northing (meters)."""
    a, f, k0 = 6378137.0, 1 / 298.257222101, 0.9996
    e2, n = f * (2 - f), f / (2 - f)
    A = a / (1 + n) * (1 + n * n / 4 + n ** 4 / 64)
    phi, lam = math.radians(lat), math.radians(lon - 27)
    t = math.sinh(math.atanh(math.sin(phi)) - math.sqrt(e2) * math.atanh(math.sqrt(e2) * math.sin(phi)))
    xi, eta = math.atan2(t, math.cos(lam)), math.atanh(math.sin(lam) / math.sqrt(1 + t * t))
    al = [n / 2 - 2 * n * n / 3 + 5 * n ** 3 / 16, 13 * n * n / 48 - 3 * n ** 3 / 5, 61 * n ** 3 / 240]
    x = xi + sum(al[j] * math.sin(2 * (j + 1) * xi) * math.cosh(2 * (j + 1) * eta) for j in range(3))
    y = eta + sum(al[j] * math.cos(2 * (j + 1) * xi) * math.sinh(2 * (j + 1) * eta) for j in range(3))
    return 500000 + k0 * A * y, k0 * A * x


class Elevation:
    """Heights by easting/northing, bilinear between GeoTIFF pixels.

    The legacy constructor keeps Raisio's cached 10 m sheet behavior.
    Explicit paths use validated source resolution and fail on missing data.
    """
    metadata: list
    strict: bool
    nodata_values: dict

    def __init__(self, sheets, cache):
        from PIL import Image  # only the importer needs Pillow
        self.sheets = []
        cache.mkdir(parents=True, exist_ok=True)
        for name in sheets:
            path = cache / f"{name}.tif"
            if not path.exists():
                fetch(name, path)
            im = Image.open(path)
            tag = im.tag_v2
            sx, sy = tag[33550][:2]
            e0, n0 = tag[33922][3], tag[33922][4]
            self.sheets.append((e0, n0, sx, sy, im.size, im.load()))

    @classmethod
    def from_paths(cls, paths, expected_resolution=2):
        """Load explicit local GeoTIFFs; source resolution is not runtime LOD."""
        from PIL import Image
        obj = cls.__new__(cls)
        obj.sheets, obj.metadata, obj.nodata_values = [], [], {}
        obj.strict = True
        paths = list(paths)
        if not paths:
            raise ValueError("at least one terrain file is required")
        for path in paths:
            path = Path(path)
            with Image.open(path) as im:
                if im.width < 2 or im.height < 2:
                    raise ValueError(f"terrain dimensions must be at least 2 by 2: {path}")
                tag = im.tag_v2
                if any(key not in tag for key in (33550, 33922, 34735)):
                    raise ValueError(f"terrain georeferencing is missing: {path}")
                sx, sy = tag[33550][:2]
                if not all(math.isfinite(v) and v > 0 and
                           math.isclose(v, expected_resolution, abs_tol=1e-6) for v in (sx, sy)):
                    raise ValueError(f"terrain resolution must be {expected_resolution} m: {path}")
                keys = tag.get(34735, ())
                geokeys = {keys[i]: tuple(keys[i + 1:i + 4]) for i in range(4, len(keys), 4)}
                if geokeys.get(3072) != (0, 1, 3067):
                    raise ValueError(f"terrain CRS must be EPSG:3067: {path}")
                e0, n0 = tag[33922][3], tag[33922][4]
                # Copy pixels so the caller never retains open source files.
                pixels = im.copy()
                pixel_access = pixels.load()
                obj.sheets.append((e0, n0, sx, sy, im.size, pixel_access))
                nodata = tag.get(42113)
                if nodata is not None:
                    obj.nodata_values[id(pixel_access)] = float(str(nodata).strip("\x00"))
                obj.metadata.append({"path": str(path.resolve()),
                                     "resolution_m": [sx, sy], "crs": "EPSG:3067",
                                     "bounds": [e0, n0 - im.height * sy, e0 + im.width * sx, n0]})
        return obj

    def __call__(self, e, n):
        for e0, n0, sx, sy, (w, h), px in self.sheets:
            # Pixel centers are half a post in from the sheet's corner.
            c, r = (e - e0) / sx - 0.5, (n0 - n) / sy - 0.5
            if -0.5 <= c < w - 0.5 and -0.5 <= r < h - 0.5:
                c, r = min(max(c, 0), w - 1.001), min(max(r, 0), h - 1.001)
                i, j = int(c), int(r)
                fx, fy = c - i, r - j
                v = [px[i, j], px[i + 1, j], px[i, j + 1], px[i + 1, j + 1]]
                nodata = getattr(self, "nodata_values", {}).get(id(px))
                if (min(v) < -100 or not all(math.isfinite(value) for value in v)
                        or (nodata is not None and any(value == nodata for value in v))):
                    if getattr(self, "strict", False):
                        raise ValueError(f"terrain no-data near ({e:.2f}, {n:.2f})")
                    return 0.0
                return (v[0] * (1 - fx) + v[1] * fx) * (1 - fy) + (v[2] * (1 - fx) + v[3] * fx) * fy
        if getattr(self, "strict", False):
            raise ValueError(f"terrain coverage missing at ({e:.2f}, {n:.2f})")
        return 0.0


def fetch(name, path):
    if not KEY.exists():
        raise SystemExit(f"need elevation sheet {name}: put a Maanmittauslaitos open data key in {KEY}")
    url = f"{FEED}/{name[:2]}/{name[:3]}/{name}.tif?api_key={KEY.read_text().strip()}"
    print(f"fetching elevation sheet {name}...")
    data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "3D-auto osm_import"}), timeout=300).read()
    path.write_bytes(data)
