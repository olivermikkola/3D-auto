#!/usr/bin/env python3
"""Turn OpenStreetMap data into a map file for lib/roadnet.

    tools/osm_import.py raisio            # use tools/osm_cache/raisio.json
    tools/osm_import.py raisio --fetch    # download it first (Overpass API)

Writes game/maps/<name>_osm.lua: real roads as a junction graph (junctions are
named after the streets that meet there, "Nesteentie / Raisiontie"), building
footprints as boxes, and ground cover (water, forest, fields, parking) as
strips. The hand-written map (game/maps/<name>.lua) loads it and adds the game:
places, missions, landmarks.

Coordinates are meters, x east and z south, from the middle of the area. The ground
is flat. Data (c) OpenStreetMap contributors, ODbL: the output carries that.
"""
import argparse
import json
import math
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

AREAS = {
    "raisio": {
        # The center, Mylly, and Nesteentie down to the harbor.
        "bbox": (60.444, 22.085, 60.497, 22.215),  # south, west, north, east
        "first": "Nesteentie / Raisiontie",
    },
}

OVERPASS = os.environ.get("OVERPASS_URL", "https://maps.mail.ru/osm/tools/overpass/api/interpreter")
QUERY = """[out:json][timeout:300][bbox:{s},{w},{n},{e}];
(way["highway"];way["building"];relation["building"];way["natural"];relation["natural"];
 way["waterway"];way["landuse"];relation["landuse"];way["leisure"];way["amenity"];way["railway"];);
out geom tags;"""
# Named parts of town, fetched on their own (small) into <area>_places.json.
PLACES_QUERY = """[out:json][timeout:60][bbox:{s},{w},{n},{e}];
node["place"~"^(town|suburb|neighbourhood)$"];
out;"""

# Drivable classes: the game's kind, and width (two-way, one-way).
ROADS = {
    "motorway": ("highway", 11, 11), "trunk": ("highway", 13, 10), "primary": ("main", 13, 10),
    "secondary": ("main", 12, 9), "tertiary": ("street", 10, 9), "unclassified": ("street", 9, 9),
    "residential": ("street", 9, 9), "living_street": ("street", 9, 9),
    "motorway_link": ("highway", 9, 9), "trunk_link": ("street", 9, 9), "primary_link": ("street", 9, 9),
    "secondary_link": ("street", 9, 9), "tertiary_link": ("street", 9, 9),
}
# Drawn but not driven by the AI: service roads and paved paths.
PAVED = {"service": 5, "footway": 2.5, "cycleway": 3, "path": 2, "pedestrian": 6}

ROW = 4.0  # ground cover is rasterized in strips this tall


# ---- geometry --------------------------------------------------------------------------

class Proj:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320 * math.cos(math.radians(lat0))

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.kx, -(lat - self.lat0) * 110574)


def area(poly):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))) / 2


def hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts
    def cross(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0: hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def min_rect(poly):
    """Smallest box round a polygon: angle of its x axis, center, size."""
    h = hull(poly)
    best = None
    for a, b in zip(h, h[1:] + h[:1]):
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        c, s = math.cos(ang), math.sin(ang)
        us = [p[0] * c + p[1] * s for p in h]
        vs = [-p[0] * s + p[1] * c for p in h]
        A = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or A < best[0]:
            best = (A, ang, min(us), max(us), min(vs), max(vs))
    _, ang, u0, u1, v0, v1 = best
    c, s = math.cos(ang), math.sin(ang)
    uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
    return ang, (uc * c - vc * s, uc * s + vc * c), u1 - u0, v1 - v0


def spans(poly, y):
    """Where the horizontal line z = y is inside the polygon: [(x0, x1)]."""
    xs = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        if (a[1] <= y) != (b[1] <= y):
            xs.append(a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1]))
    xs.sort()
    return list(zip(xs[0::2], xs[1::2]))


def boxes_of(poly):
    """A footprint as boxes: one if it's near enough a rectangle, otherwise
    strips across its long side, merged where they line up. Each box is
    (x, z, w, d, angle of w)."""
    ang, (cx, cz), w, d = min_rect(poly)
    if w < d:
        ang, w, d = ang + math.pi / 2, d, w
    A = area(poly)
    if A >= 0.8 * w * d or A < 150:
        return [(cx, cz, w, d, ang)]
    c, s = math.cos(ang), math.sin(ang)
    local = [((p[0] - cx) * c + (p[1] - cz) * s, -(p[0] - cx) * s + (p[1] - cz) * c) for p in poly]
    # Strips along v (the short side), stepping along u: swap to scan in u.
    swapped = [(v, u) for u, v in local]
    step = max(3.0, w / 12)
    runs = []  # (u0, u1, v0, v1)
    u = -w / 2
    while u < w / 2 - 0.5:
        mid = u + step / 2
        for v0, v1 in spans(swapped, mid):
            if v1 - v0 < 2: continue
            for r in runs:
                if abs(r[1] - u) < 1e-6 and abs(r[2] - v0) < 1.5 and abs(r[3] - v1) < 1.5:
                    r[1] = min(u + step, w / 2)
                    break
            else:
                runs.append([u, min(u + step, w / 2), v0, v1])
        u += step
    out = []
    for u0, u1, v0, v1 in runs[:14]:
        uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
        out.append((cx + uc * c - vc * s, cz + uc * s + vc * c, u1 - u0, v1 - v0, ang))
    return out or [(cx, cz, w, d, ang)]


def simplify(pts, tol):
    """Douglas-Peucker on a polyline of (x, z)."""
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    dx, dz = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dz) or 1e-9
    far, fi = -1, 0
    for i in range(1, len(pts) - 1):
        p = pts[i]
        dd = abs((p[0] - a[0]) * dz - (p[1] - a[1]) * dx) / L
        if dd > far: far, fi = dd, i
    if far <= tol:
        return [a, b]
    return simplify(pts[:fi + 1], tol)[:-1] + simplify(pts[fi:], tol)


def seg_cross(a, b, c, d):
    rx, rz, sx, sz = b[0] - a[0], b[1] - a[1], d[0] - c[0], d[1] - c[1]
    den = rx * sz - rz * sx
    if abs(den) < 1e-9: return False
    t = ((c[0] - a[0]) * sz - (c[1] - a[1]) * sx) / den
    u = ((c[0] - a[0]) * rz - (c[1] - a[1]) * rx) / den
    return 1e-3 < t < 1 - 1e-3 and 1e-3 < u < 1 - 1e-3


def seg_dist(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2)) if l2 else 0
    return math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dz * t)


class Grid:
    """Spatial hash of segments, for near/crossing queries."""
    def __init__(self, cell=50):
        self.cell, self.cells = cell, {}

    def keys(self, x0, z0, x1, z1):
        c = self.cell
        for i in range(int(math.floor(x0 / c)), int(math.floor(x1 / c)) + 1):
            for j in range(int(math.floor(z0 / c)), int(math.floor(z1 / c)) + 1):
                yield i, j

    def add(self, item, a, b, pad=0):
        for k in self.keys(min(a[0], b[0]) - pad, min(a[1], b[1]) - pad, max(a[0], b[0]) + pad, max(a[1], b[1]) + pad):
            self.cells.setdefault(k, []).append(item)

    def near(self, x0, z0, x1, z1):
        seen = set()
        for k in self.keys(x0, z0, x1, z1):
            for it in self.cells.get(k, ()):
                if id(it) not in seen:
                    seen.add(id(it))
                    yield it


# ---- reading ---------------------------------------------------------------------------

def rings(e):
    """Closed outlines of a way or a multipolygon's outer members, as lists of
    {lat, lon}. Open member ways are joined end to end."""
    if e["type"] == "way":
        g = e.get("geometry") or []
        return [g] if len(g) >= 4 and g[0] == g[-1] else []
    parts = [m["geometry"] for m in e.get("members", []) if m.get("role") == "outer" and m.get("geometry")]
    out, open_ = [], []
    for g in parts:
        (out if g[0] == g[-1] else open_).append(list(g))
    while open_:
        cur = open_.pop()
        grew = True
        while grew and cur[0] != cur[-1]:
            grew = False
            for i, g in enumerate(open_):
                if g[0] == cur[-1]: cur += g[1:]
                elif g[-1] == cur[-1]: cur += g[-2::-1]
                elif g[-1] == cur[0]: cur = g[:-1] + cur
                elif g[0] == cur[0]: cur = g[:0:-1] + cur
                else: continue
                open_.pop(i)
                grew = True
                break
        if cur[0] == cur[-1]: out.append(cur)
    return out


HARD = ("asphalt", "concrete", "paved", "acrylic", "tartan", "clay", "paving_stones")


def pitch_kind(t):
    """Sports ground surfaces: turf, sand, or a hard court."""
    if t.get("leisure") != "pitch": return None
    surface, sport = t.get("surface", ""), t.get("sport", "")
    if surface in ("sand", "dirt", "gravel", "fine_gravel") or sport in ("equestrian", "beachvolleyball"): return "sand"
    if surface in HARD or sport in ("tennis", "basketball", "skateboard", "multi", "padel", "volleyball"): return "court"
    return "pitch"


COVER = [  # (class, test on tags), first match wins; the game draws them in its own order
    ("track", lambda t: t.get("leisure") == "track"),
    ("sand", lambda t: pitch_kind(t) == "sand"),
    ("court", lambda t: pitch_kind(t) == "court"),
    ("pitch", lambda t: pitch_kind(t) == "pitch"),
    ("cemetery", lambda t: t.get("amenity") == "grave_yard" or t.get("landuse") == "cemetery"),
    ("water", lambda t: t.get("natural") in ("water", "bay") or t.get("waterway") == "riverbank" or "water" in t and t.get("natural") == "water"),
    ("forest", lambda t: t.get("landuse") == "forest" or t.get("natural") in ("wood", "scrub")),
    ("field", lambda t: t.get("landuse") in ("farmland", "meadow", "grass", "greenfield") or t.get("natural") in ("grassland", "heath")),
    ("park", lambda t: t.get("leisure") in ("park", "pitch", "playground", "garden", "golf_course", "sports_centre") or t.get("landuse") in ("recreation_ground", "cemetery", "village_green", "allotments")),
    ("works", lambda t: t.get("landuse") in ("industrial", "railway", "construction", "brownfield", "port")),
    ("parking", lambda t: t.get("amenity") == "parking" and t.get("parking", "surface") == "surface"),
]


def cover_class(t):
    for name, test in COVER:
        if test(t): return name


def round_of(poly):
    """The nearest and farthest a ring's corners are from its middle."""
    cx, cz = sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly)
    d = [math.hypot(x - cx, z - cz) for x, z in poly]
    return min(d), max(d)


def building_kind(t, A):
    b = t.get("building", "yes")
    if t.get("amenity") == "police": return "police"
    if b in ("garage", "garages", "shed", "carport", "hut", "cabin", "roof", "greenhouse", "service", "kiosk"): return "shed"
    if b in ("house", "detached", "semidetached_house", "bungalow", "farm"): return "house"
    if b == "terrace": return "terrace"
    if b in ("apartments", "dormitory"): return "flats"
    if b in ("industrial", "warehouse", "manufacture", "factory", "storage_tank", "silo", "hangar", "barn", "farm_auxiliary"): return "works"
    if b in ("retail", "commercial", "supermarket", "office"): return "shop"
    if b in ("church", "chapel"): return "church"
    if b in ("school", "public", "civic", "hospital", "kindergarten", "university", "college", "government", "sports_hall", "train_station", "fire_station"): return "civic"
    if b == "residential": return "house" if A < 220 else "flats"
    if A < 40: return "shed"
    if A < 220: return "house"
    if A > 2500: return "works"
    return "flats"


COLOURS = {"red": (0.6, 0.22, 0.17), "darkred": (0.45, 0.15, 0.12), "brown": (0.42, 0.28, 0.2), "darksalmon": (0.72, 0.42, 0.33),
           "orange": (0.75, 0.42, 0.22), "black": (0.16, 0.16, 0.17), "dimgrey": (0.33, 0.33, 0.34), "dimgray": (0.33, 0.33, 0.34),
           "grey": (0.5, 0.5, 0.5), "gray": (0.5, 0.5, 0.5), "darkgrey": (0.4, 0.4, 0.41), "darkgray": (0.4, 0.4, 0.41),
           "silver": (0.7, 0.7, 0.72), "white": (0.88, 0.88, 0.86), "green": (0.25, 0.4, 0.28), "blue": (0.25, 0.32, 0.45)}


def roof_colour(t):
    """A roof:colour as r, g, b: a name or #rrggbb; None if untagged."""
    c = t.get("roof:colour", "").strip().lower()
    if c in COLOURS: return COLOURS[c]
    if len(c) == 7 and c[0] == "#":
        try: return tuple(round(int(c[i:i + 2], 16) / 255, 2) for i in (1, 3, 5))
        except ValueError: return None


def height_of(t, kind, A):
    for key in ("height", "building:height"):
        try: return max(2.5, float(t[key].split()[0]))
        except (KeyError, ValueError): pass
    try: levels = float(t["building:levels"])
    except (KeyError, ValueError): levels = None
    floor = {"house": 2.9, "terrace": 2.9, "shed": 2.6}.get(kind, 3.4)
    if levels is None:
        levels = {"shed": 1, "house": 1 if A < 160 else 2, "terrace": 1, "flats": 3 if A < 900 else 4,
                  "shop": 2, "civic": 2, "church": 3, "works": 2.5, "police": 3}[kind]
    return max(2.5, levels * floor)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("area", choices=sorted(AREAS))
    ap.add_argument("--fetch", action="store_true", help="download fresh data from Overpass first")
    ap.add_argument("--cache", type=Path)
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()
    cfg = AREAS[args.area]
    cache = args.cache or ROOT / "tools" / "osm_cache" / f"{args.area}.json"
    dest = args.out or ROOT / "game" / "maps" / f"{args.area}_osm.lua"
    s, w, n, e = cfg["bbox"]
    if args.fetch:
        cache.parent.mkdir(parents=True, exist_ok=True)
        q = QUERY.format(s=s - 0.003, w=w - 0.006, n=n + 0.003, e=e + 0.006)
        req = urllib.request.Request(OVERPASS, data=urllib.parse.urlencode({"data": q}).encode(),
                                     headers={"User-Agent": "3D-auto osm_import"})
        print(f"fetching {args.area} from Overpass...", file=sys.stderr)
        cache.write_bytes(urllib.request.urlopen(req, timeout=600).read())
    places_cache = cache.with_name(cache.stem + "_places.json")
    if args.fetch or not places_cache.exists():
        q = PLACES_QUERY.format(s=s - 0.01, w=w - 0.02, n=n + 0.01, e=e + 0.02)
        req = urllib.request.Request(OVERPASS, data=urllib.parse.urlencode({"data": q}).encode(),
                                     headers={"User-Agent": "3D-auto osm_import"})
        print(f"fetching {args.area}'s place names from Overpass...", file=sys.stderr)
        places_cache.write_bytes(urllib.request.urlopen(req, timeout=120).read())
    data = json.loads(cache.read_text())
    stamp = data.get("osm3s", {}).get("timestamp_osm_base", "?")
    els = data["elements"]
    # The middle of the area is 0, 0: the game's ground is centered there.
    origin = ((s + n) / 2, (w + e) / 2)
    P = Proj(*origin)
    X0, Z1 = P(s, w)
    X1, Z0 = P(n, e)
    X1, Z1 = math.floor(min(-X0, X1)), math.floor(min(-Z0, Z1))
    X0, Z0 = -X1, -Z1
    def inside(x, z, pad=0): return X0 + pad <= x <= X1 - pad and Z0 + pad <= z <= Z1 - pad

    # ---- roads ----
    ways = []
    for el in els:
        t = el.get("tags", {})
        if el["type"] != "way" or t.get("highway") not in ROADS or t.get("area") == "yes": continue
        if t.get("access") in ("private", "no"): continue
        g = el.get("geometry") or []
        # Without node ids (out geom), a node is its coordinates.
        nodes = el.get("nodes") or [f'{p["lat"]:.7f},{p["lon"]:.7f}' for p in g]
        if len(g) != len(nodes): continue
        # Keep runs of nodes inside the area, each its own way.
        run = []
        for nid, p in zip(nodes, g):
            xz = P(p["lat"], p["lon"])
            if inside(*xz, pad=15): run.append((nid, xz))
            else:
                if len(run) >= 2: ways.append((t, run))
                run = []
        if len(run) >= 2: ways.append((t, run))

    uses = {}
    for t, run in ways:
        for k, (nid, _) in enumerate(run):
            uses[nid] = uses.get(nid, 0) + (1 if 0 < k < len(run) - 1 else 2)
    pos = {nid: xz for _, run in ways for nid, xz in run}
    is_j = {nid for nid, u in uses.items() if u >= 2}

    edges = []  # dicts: a, b, pts, kind, width, name, bridge
    for t, run in ways:
        hw = t["highway"]
        kind, w2, w1 = ROADS[hw]
        oneway = t.get("oneway") in ("yes", "1", "-1") or hw in ("motorway", "motorway_link")
        width = w1 if oneway else w2
        name = t.get("name") or t.get("ref")
        bridge = t.get("bridge") not in (None, "no") or t.get("tunnel") not in (None, "no") or t.get("layer", "0") not in ("0",)
        start = 0
        for k in range(1, len(run)):
            if run[k][0] in is_j or k == len(run) - 1:
                seg = run[start:k + 1]
                edges.append({"a": seg[0][0], "b": seg[-1][0], "ids": [p[0] for p in seg], "kind": kind, "width": width,
                              "name": name, "bridge": bridge, "hw": hw})
                start = k
    # Loops and two roads joining the same pair: make a bend a junction.
    changed = True
    while changed:
        changed = False
        seen = {}
        for ed in edges:
            key = tuple(sorted((ed["a"], ed["b"])))
            if ed["a"] == ed["b"] or key in seen:
                if len(ed["ids"]) < 3:
                    ed["drop"] = True
                    continue
                mid = ed["ids"][len(ed["ids"]) // 2]
                is_j.add(mid)
                k = ed["ids"].index(mid)
                tail = dict(ed, a=mid, ids=ed["ids"][k:])
                ed["b"], ed["ids"] = mid, ed["ids"][:k + 1]
                edges.append(tail)
                changed = True
                break
            seen[key] = ed
        edges = [ed for ed in edges if not ed.get("drop")]
    # Only the network you can reach from the first junction's neighborhood:
    # the largest connected piece.
    adj = {}
    for ed in edges:
        adj.setdefault(ed["a"], []).append(ed["b"])
        adj.setdefault(ed["b"], []).append(ed["a"])
    comp, best = {}, None
    for s0 in adj:
        if s0 in comp: continue
        comp[s0], q = s0, [s0]
        for v in q:
            for nb in adj[v]:
                if nb not in comp: comp[nb] = s0; q.append(nb)
        if best is None or len(q) > best[1]: best = (s0, len(q))
    edges = [ed for ed in edges if comp[ed["a"]] == best[0]]
    for ed in edges:
        ed["pts"] = simplify([pos[i] for i in ed["ids"]], 1.0)

    # Roads that cross with no shared node pass over or under each other.
    G = Grid(60)
    for ed in edges:
        for a, b in zip(ed["pts"], ed["pts"][1:]): G.add((ed, a, b), a, b)
    for ed in edges:
        if ed["bridge"]: continue
        for a, b in zip(ed["pts"], ed["pts"][1:]):
            for other, c, d in G.near(min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])):
                if other is not ed and not other["bridge"] and seg_cross(a, b, c, d):
                    # The bigger road is the bridge.
                    order = list(ROADS)
                    lift = ed if order.index(ed["hw"]) < order.index(other["hw"]) else other
                    lift["bridge"] = True

    # Junction names: the streets that meet there.
    meet = {}
    for ed in edges:
        for j in (ed["a"], ed["b"]):
            if ed["name"]: meet.setdefault(j, set()).add(ed["name"])
    names, taken = {}, {}
    for j in sorted({ed["a"] for ed in edges} | {ed["b"] for ed in edges}):
        streets = sorted(meet.get(j, ()))
        nm = " / ".join(streets) if len(streets) >= 2 else f"n{len(names) + 1}"
        if nm in taken:
            taken[nm] += 1
            nm = f"{nm} {taken[nm]}"
        else:
            taken[nm] = 1
        names[j] = nm
    if cfg["first"] not in names.values():
        near = sorted(v for v in names.values() if "Nesteentie" in v or "Raisiontie" in v)[:8]
        sys.exit(f"no junction named {cfg['first']!r}; near: {near}")

    # ---- paved but not driven: service roads, paths ----
    paved = []
    for el in els:
        t = el.get("tags", {})
        hw = t.get("highway")
        if el["type"] != "way" or hw not in PAVED or t.get("area") == "yes": continue
        if hw in ("path", "footway") and t.get("surface") not in ("asphalt", "paved", "concrete", "paving_stones"): continue
        if hw == "service" and t.get("service") in ("driveway",): continue
        pts = simplify([P(p["lat"], p["lon"]) for p in el.get("geometry") or []], 1.0)
        pts = [p for p in pts if inside(*p)]
        if len(pts) >= 2: paved.append((PAVED[hw], hw == "service", pts))

    # ---- buildings ----
    road_grid = Grid(50)
    for ed in edges:
        for a, b in zip(ed["pts"], ed["pts"][1:]): road_grid.add((ed, a, b), a, b, pad=ed["width"])
    footprints, dropped = [], 0
    for el in els:
        t = el.get("tags", {})
        if "building" not in t or t.get("building") in ("no", "roof", "construction", "ruins"): continue
        for ring in rings(el):
            poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
            if not all(inside(*p, pad=5) for p in poly): continue
            A = area(poly)
            if A < 15: continue
            kind = building_kind(t, A)
            h = height_of(t, kind, A)
            name = (t.get("name") or "").replace("\xad", "") or None  # no soft hyphens
            # A church is one nave under one roof, not strips; a round
            # building (a silo, a tank) is one drum.
            parts = boxes_of(poly)
            r_in, r_out = round_of(poly)
            if len(poly) >= 8 and r_out < 40 and r_in > 0.85 * r_out:
                kind, cx, cz = "round", sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly)
                parts = [(cx, cz, 2 * r_out, 2 * r_out, 0)]
                if "height" not in t and "building:levels" not in t: h = max(h, min(1.2 * r_out, 22))
            elif kind == "church":
                ang, (cx, cz), bw, bd = min_rect(poly)
                parts = [(cx, cz, bw, bd, ang) if bw >= bd else (cx, cz, bd, bw, ang + math.pi / 2)]
            for (x, z, bw, bd, ang) in parts:
                # Keep clear of the (game-width) roads and their pavements.
                r = math.hypot(bw, bd) / 2
                hit = False
                for ed, a, b in road_grid.near(x - r, z - r, x + r, z + r):
                    clear = ed["width"] / 2 + (1.5 if ed["kind"] == "highway" else 3)
                    c, s_ = math.cos(ang), math.sin(ang)
                    for fu in (-0.5, 0, 0.5):
                        for fv in (-0.5, 0, 0.5):
                            px, pz = x + c * bw * fu - s_ * bd * fv, z + s_ * bw * fu + c * bd * fv
                            if seg_dist((px, pz), a, b) < clear: hit = True; break
                        if hit: break
                    if hit: break
                if hit:
                    dropped += 1
                    continue
                footprints.append((x, z, bw, bd, ang, h, kind, name, roof_colour(t)))
                name = None  # the label goes on one box

    # ---- ground cover ----
    cover = {k: [] for k, _ in COVER}
    for el in els:
        cls = cover_class(el.get("tags", {}))
        if not cls: continue
        for ring in rings(el):
            poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
            if area(poly) < 200: continue
            cover[cls].append(poly)
    strips = {}
    for cls, polys in cover.items():
        out = []
        for poly in polys:
            zs = [p[1] for p in poly]
            z = math.floor(max(Z0, min(zs)) / ROW) * ROW
            open_runs = {}
            while z < min(Z1, max(zs)):
                nxt = {}
                for x0, x1 in spans(poly, z + ROW / 2):
                    x0, x1 = max(X0, round(x0)), min(X1, round(x1))
                    if x1 - x0 < 2: continue
                    key = (x0, x1)
                    if key in open_runs: nxt[key] = open_runs.pop(key)
                    else: nxt[key] = [x0, z, x1, z]
                    nxt[key][3] = z + ROW
                out.extend(open_runs.values())
                open_runs = nxt
                z += ROW
            out.extend(open_runs.values())
        strips[cls] = out

    # ---- football pitches (lines and goals) ----
    pitches = []
    for el in els:
        t = el.get("tags", {})
        if pitch_kind(t) != "pitch" or t.get("sport", "soccer") not in ("soccer", "american_football", "rugby", ""): continue
        for ring in rings(el):
            poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
            if not all(inside(*p) for p in poly): continue
            ang, (cx, cz), pw, pd = min_rect(poly)
            if pw < pd: ang, pw, pd = ang + math.pi / 2, pd, pw
            if pw >= 40 and pd >= 25 and area(poly) > 0.85 * pw * pd:
                pitches.append((cx, cz, pw, pd, -ang))

    # ---- footbridges: foot and cycle ways that cross a road on a bridge ----
    footbridges = []
    for el in els:
        t = el.get("tags", {})
        if t.get("highway") not in ("footway", "cycleway", "path", "pedestrian") or t.get("bridge") in (None, "no"): continue
        pts = simplify([P(p["lat"], p["lon"]) for p in el.get("geometry") or []], 0.5)
        if len(pts) < 2 or not all(inside(*p) for p in pts): continue
        over = any(seg_cross(a, b, c, d) for a, b in zip(pts, pts[1:])
                   for _, c, d in G.near(min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])))
        if over: footbridges.append((float(t.get("width", "3").split()[0]) if t.get("width", "3").replace(".", "", 1).isdigit() else 3, pts))

    # ---- towers, gantry cranes, piers ----
    towers, cranes, piers = [], [], []
    for el in els:
        t = el.get("tags", {})
        mm = t.get("man_made")
        if mm in ("tower", "mast") and t.get("tower:type") not in ("bell_tower",):
            g = el.get("geometry") or ([{"lat": el["lat"], "lon": el["lon"]}] if "lat" in el else [])
            if not g: continue
            pts = [P(p["lat"], p["lon"]) for p in g]
            x, z = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
            if not inside(x, z, pad=10): continue
            try: h = float(t.get("height", "").split()[0])
            except (ValueError, IndexError): h = 40
            lattice = t.get("tower:construction") == "lattice" or t.get("tower:type") == "communication" or mm == "mast"
            towers.append((x, z, h, "lattice" if lattice and t.get("tower:type") == "communication" else
                           "pylon" if t.get("tower:type") in ("monument", "advertising") else "lattice"))
        elif mm == "crane" and t.get("crane:type") == "gantry_crane":
            for ring in rings(el):
                poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
                ang, (cx, cz), cl, cw = min_rect(poly)
                if cl < cw: ang, cl, cw = ang + math.pi / 2, cw, cl
                if inside(cx, cz): cranes.append((cx, cz, cl, cw, -ang, int(t.get("count", "1") or 1)))
        elif mm == "pier":
            pts = simplify([P(p["lat"], p["lon"]) for p in el.get("geometry") or []], 0.5)
            if len(pts) >= 2 and all(inside(*p, pad=5) for p in pts):
                closed = len(el.get("geometry") or []) > 3 and el["geometry"][0] == el["geometry"][-1]
                if closed:  # a pier drawn as an area: its long middle line
                    ang, (cx, cz), pl, pw = min_rect(pts)
                    if pl < pw: ang, pl, pw = ang + math.pi / 2, pw, pl
                    c, s_ = math.cos(ang), math.sin(ang)
                    pts = [(cx - c * pl / 2, cz - s_ * pl / 2), (cx + c * pl / 2, cz + s_ * pl / 2)]
                    width = max(2, min(pw, 12))
                else:
                    width = 2.5
                piers.append((width, pts))

    # ---- named areas ----
    areas = []
    for el in json.loads(places_cache.read_text())["elements"]:
        t = el.get("tags", {})
        if t.get("name"):
            x, z = P(el["lat"], el["lon"])
            areas.append((t["name"], x, z, t["place"]))
    areas.sort(key=lambda d: (d[3], d[0]))

    # ---- write ----
    def f(v): return f"{v:.1f}".rstrip("0").rstrip(".")
    def q(s): return json.dumps(s, ensure_ascii=False)
    L = [f"-- GENERATED by tools/osm_import.py {args.area} from OpenStreetMap data of {stamp}. Don't edit:",
         "-- change the importer or the hand-written map and run it again.",
         "-- Map data (c) OpenStreetMap contributors, available under the Open Database License",
         "-- (ODbL 1.0, https://opendatacommons.org/licenses/odbl/). See LICENSE in this folder.",
         "return {",
         f"  origin = {{{origin[0]:.5f}, {origin[1]:.5f}}},",
         f"  bounds = {{{X0}, {Z0}, {X1}, {Z1}}},",
         f"  first = {q(cfg['first'])},",
         "  junctions = {"]
    used = sorted({ed["a"] for ed in edges} | {ed["b"] for ed in edges}, key=lambda j: names[j])
    for j in used:
        L.append(f"    [{q(names[j])}] = {{{f(pos[j][0])}, {f(pos[j][1])}}},")
    L.append("  },")
    L.append("  roads = {")
    for ed in edges:
        bits = [q(names[ed["a"]])] + [f"{{{f(p[0])}, {f(p[1])}}}" for p in ed["pts"][1:-1]] + [q(names[ed["b"]])]
        attrs = f"kind = {q(ed['kind'])}, width = {ed['width']}"
        if ed["name"]: attrs = f"name = {q(ed['name'])}, " + attrs
        if ed["bridge"]: attrs += ", bridge = true"
        L.append(f"    {{{attrs}, {', '.join(bits)}}},")
    L.append("  },")
    L.append("  -- {width, service road?, points...}")
    L.append("  paved = {")
    for wd, svc, pts in paved:
        L.append(f"    {{{wd}, {'true' if svc else 'false'}, " + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts) + "},")
    L.append("  },")
    L.append("  -- {x, z, w, d, yaw, height, kind, name or false, roof color or nil}: yaw turns the box's w side off the x axis")
    L.append("  footprints = {")
    for x, z, bw, bd, ang, h, kind, name, roof in footprints:
        # The engine's yaw turns +z toward +x: a box whose w runs at angle
        # `ang` (from +x toward +z) has yaw = -ang.
        tail = f", {q(name)}" if name else ""
        if roof: tail = (tail or ", false") + ", {" + ", ".join(f(v) for v in roof) + "}"
        L.append(f"    {{{f(x)}, {f(z)}, {f(bw)}, {f(bd)}, {-ang:.3f}, {f(h)}, {q(kind)}{tail}}},")
    L.append("  },")
    L.append("  -- football pitches: {x, z, length, width, yaw}")
    L.append("  pitches = {" + ", ".join(f"{{{f(x)}, {f(z)}, {f(pw)}, {f(pd)}, {a:.3f}}}" for x, z, pw, pd, a in pitches) + "},")
    L.append("  -- foot and cycle bridges over roads: {width, points...}")
    L.append("  footbridges = {")
    for wd, pts in footbridges:
        L.append(f"    {{{f(wd)}, " + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts) + "},")
    L.append("  },")
    L.append("  -- towers and masts: {x, z, height, \"lattice\" or \"pylon\"}")
    L.append("  towers = {" + ", ".join(f"{{{f(x)}, {f(z)}, {f(h)}, {q(k)}}}" for x, z, h, k in towers) + "},")
    L.append("  -- gantry cranes: the rails' {x, z, length, span, yaw, cranes on them}")
    L.append("  cranes = {" + ", ".join(f"{{{f(x)}, {f(z)}, {f(l)}, {f(w)}, {a:.3f}, {n}}}" for x, z, l, w, a, n in cranes) + "},")
    L.append("  -- piers: {width, points...}")
    L.append("  piers = {")
    for wd, pts in piers:
        L.append(f"    {{{f(wd)}, " + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts) + "},")
    L.append("  },")
    L.append("  -- named parts of town: {name, x, z, \"town\", \"suburb\" or \"neighbourhood\"}")
    L.append("  areas = {")
    for name, x, z, kind in areas:
        L.append(f"    {{{q(name)}, {f(x)}, {f(z)}, {q(kind)}}},")
    L.append("  },")
    L.append("  -- {x0, z0, x1, z1} strips")
    L.append("  cover = {")
    for cls, out in strips.items():
        L.append(f"    {cls} = {{" + ", ".join(f"{{{a},{f(b)},{c},{f(d)}}}" for a, b, c, d in out) + "},")
    L.append("  },")
    L.append("}")
    dest.write_text("\n".join(L) + "\n")
    njs = len(used)
    print(f"{dest.relative_to(ROOT)}: {njs} junctions, {len(edges)} roads ({sum(1 for e in edges if e['bridge'])} bridges), "
          f"{len(paved)} paved ways, {len(footprints)} building boxes ({dropped} too close to a road), "
          + ", ".join(f"{k} {len(v)}" for k, v in strips.items())
          + f", {len(pitches)} pitches, {len(footbridges)} footbridges, {len(towers)} towers, {len(cranes)} cranes,"
          f" {len(piers)} piers, {len(areas)} areas; {dest.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
