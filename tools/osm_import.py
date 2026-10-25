#!/usr/bin/env python3
"""Turn OpenStreetMap data into a map file for lib/roadnet.

    tools/osm_import.py raisio            # use tools/osm_cache/raisio.json
    tools/osm_import.py raisio --fetch    # download it first (Overpass API)

Writes game/maps/<name>_osm.lua: real roads as a junction graph (junctions are
named after the streets that meet there, "Nesteentie / Raisiontie"), building
footprints as boxes, and ground cover (water, forest, fields, parking) as
strips. The hand-written map (game/maps/<name>.lua) loads it and adds the game:
places, missions, landmarks.

With a "dem" list for the area it also writes game/maps/<name>_terrain.bin: the
ground's height every 10 m from Maanmittauslaitos' elevation model (tools/dem.py;
needs Pillow and, to download sheets, a free key), with the roads graded into it,
and each point's ground cover class.

Coordinates are meters, x east and z south, from the middle of the area. Data (c)
OpenStreetMap contributors, ODbL: the output carries that. Heights: National Land
Survey of Finland, CC BY 4.0.
"""
import argparse
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

AREAS = {
    "raisio": {
        # The center, Mylly, and Nesteentie down to the harbor; north to
        # Raision sairaala, ABC and Haunisten allas; expanded east through
        # central Turku and Aurajoki, south to Turku harbor.
        "bbox": (60.420, 22.085, 60.5085, 22.310),  # south, west, north, east
        # The game's 0, 0: kept where it was when the map was smaller, so
        # what the hand-written map places doesn't move as the area grows.
        "origin": (60.47050, 22.15000),
        "first": "Nesteentie / Raisiontie",
        # Maanmittauslaitos 10 m elevation sheets covering it (see tools/dem.py).
        "dem": ["L3322", "L3324", "L3411", "L3413"],
    },
    "turku": {
        # First regional slice: harbor/downtown through the public
        # Ylioppilaskyla and Kupittaa comparison districts. This rectangle
        # is not a claim to contain the entire Turku municipality.
        "bbox": (60.425, 22.21, 60.480, 22.325),
        "origin": (60.45150, 22.27000),
        "first": "Aninkaistenkatu / Eerikinkatu",
        # Roof and ground colours from the city's aerial photo (tools/aerial.py).
        "aerial": "turku",
        "coverage_kind": "regional_first_slice",
        "terrain_source": {
            "dataset": "MML Elevation model 2 m",
            "resolution_m": 2,
            "crs": "EPSG:3067",
            "vertical_datum": "N2000",
            "license": "CC BY 4.0",
        },
        # A real terrain input is required before this area can be generated.
        # No flat-terrain fallback or borrowed Raisio sheet list.
        "require_terrain": True,
    },
}

# Overpass servers, tried in turn (OVERPASS_URL first, if set).
OVERPASS = [u for u in (os.environ.get("OVERPASS_URL"), "https://overpass-api.de/api/interpreter",
                        "https://maps.mail.ru/osm/tools/overpass/api/interpreter") if u]
TILE = (0.025, 0.05)  # degrees of latitude, longitude fetched at a time
QUERY = """[out:json][timeout:300][bbox:{s},{w},{n},{e}];
(way["highway"];way["building"];relation["building"];way["natural"];relation["natural"];
 way["waterway"];way["landuse"];relation["landuse"];way["leisure"];way["amenity"];way["railway"];
 way["man_made"];node["man_made"~"^(tower|mast)$"];);
out geom tags;"""
# Named parts of town, fetched on their own (small) into <area>_places.json.
PLACES_QUERY = """[out:json][timeout:60][bbox:{s},{w},{n},{e}];
node["place"~"^(town|suburb|neighbourhood)$"];
out;"""
# Points of interest for missions (docs/MISSION_TEMPLATES.md), fetched on
# their own into <area>_pois.json: anything named that is a shop, amenity,
# leisure, tourism or historic place, as a node or as an area's center, and
# sports pitches named or not (a basketball court seldom has a name).
POIS_QUERY = """[out:json][timeout:120][bbox:{s},{w},{n},{e}];
(nwr["shop"]["name"];nwr["amenity"]["name"];nwr["leisure"]["name"];nwr["tourism"]["name"];
 nwr["historic"]["name"];nwr["leisure"="pitch"];);
out center tags;"""
# The tags a POI keeps: what it is, and what missions ask about it.
POI_TAGS = ("name", "shop", "amenity", "leisure", "tourism", "historic", "brand", "sport", "cuisine", "religion")

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
# Streets that have pavements unless the map data says otherwise; smaller
# ones don't (a suburban street in Finland mostly has none, or a separate
# foot and cycle path, which the map data has as a path of its own).
WALKED = ("primary", "secondary", "tertiary", "primary_link", "secondary_link", "tertiary_link")
STONE = ("paving_stones", "sett", "concrete:plates", "unhewn_cobblestone", "cobblestone", "bricks")


def sidewalks(t):
    """Which sides of a way have a pavement of their own, in the way's
    direction: "both", "left", "right" or "no". A pavement mapped as a
    separate path counts as none: the path is drawn."""
    has = {"yes": True, "no": False, "none": False, "separate": False}
    left = right = None
    s = t.get("sidewalk")
    if s in ("both", "yes"): left = right = True
    elif s in ("no", "none", "separate"): left = right = False
    elif s == "left": left, right = True, False
    elif s == "right": left, right = False, True
    both = has.get(t.get("sidewalk:both"))
    if both is not None: left = right = both
    left = has.get(t.get("sidewalk:left"), left)
    right = has.get(t.get("sidewalk:right"), right)
    if left is None and right is None:
        left = right = t["highway"] in WALKED
    left, right = bool(left), bool(right)
    return "both" if left and right else "left" if left else "right" if right else "no"

ROW = 4.0  # ground cover is rasterized in strips this tall
STEP = 10.0  # terrain heights every this many meters
# A tunnel's cutting (the game roofs it over) is flat out to 6 m past the
# road's edge, then climbs back to the ground over TUNNEL_BLEND meters; the
# hill over it is measured ROOF_REACH meters out from the road's edge.
TUNNEL_BLEND = 8.0
ROOF_REACH = 6 + TUNNEL_BLEND + 2
# Cover classes in the order the game draws them (lib/roadnet.lua's COVER):
# a terrain point takes the last one it's in; 0 is plain land.
DRAW_ORDER = ["field", "forest", "park", "cemetery", "works", "parking", "track", "sand", "court", "pitch", "water"]


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


def is_stand(t, poly):
    """A grandstand, or a stadium building shaped like one: long and narrow
    (a squarer one is a hall, an ice rink or a ball hall)."""
    if t.get("building") == "grandstand": return True
    if t.get("building") != "stadium": return False
    _, _, sw, sd = min_rect(poly)
    return min(sw, sd) < 35 and max(sw, sd) > 2.5 * min(sw, sd)


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


# The rest of the CSS colour names, which OSM's colour tags use ("yellow" on
# 273 of Turku's buildings, "beige" on the university's). Taken as they are,
# they'd be paint-box bright, so they're muted the way the names above are:
# half way to their own grey, and not quite white.
CSS = dict(
    aliceblue="f0f8ff", antiquewhite="faebd7", aqua="00ffff", aquamarine="7fffd4", azure="f0ffff", beige="f5f5dc",
    bisque="ffe4c4", blanchedalmond="ffebcd", blueviolet="8a2be2", burlywood="deb887", cadetblue="5f9ea0",
    chartreuse="7fff00", chocolate="d2691e", coral="ff7f50", cornflowerblue="6495ed", cornsilk="fff8dc",
    crimson="dc143c", cyan="00ffff", darkblue="00008b", darkcyan="008b8b", darkgoldenrod="b8860b",
    darkgreen="006400", darkkhaki="bdb76b", darkmagenta="8b008b", darkolivegreen="556b2f", darkorange="ff8c00",
    darkorchid="9932cc", darkseagreen="8fbc8f", darkslateblue="483d8b", darkslategray="2f4f4f",
    darkslategrey="2f4f4f", darkturquoise="00ced1", darkviolet="9400d3", deeppink="ff1493", deepskyblue="00bfff",
    dodgerblue="1e90ff", firebrick="b22222", floralwhite="fffaf0", forestgreen="228b22", fuchsia="ff00ff",
    gainsboro="dcdcdc", ghostwhite="f8f8ff", gold="ffd700", goldenrod="daa520", greenyellow="adff2f",
    honeydew="f0fff0", hotpink="ff69b4", indianred="cd5c5c", indigo="4b0082", ivory="fffff0", khaki="f0e68c",
    lavender="e6e6fa", lavenderblush="fff0f5", lawngreen="7cfc00", lemonchiffon="fffacd", lightblue="add8e6",
    lightcoral="f08080", lightcyan="e0ffff", lightgoldenrodyellow="fafad2", lightgray="d3d3d3",
    lightgreen="90ee90", lightgrey="d3d3d3", lightpink="ffb6c1", lightsalmon="ffa07a", lightseagreen="20b2aa",
    lightskyblue="87cefa", lightslategray="778899", lightslategrey="778899", lightsteelblue="b0c4de",
    lightyellow="ffffe0", lime="00ff00", limegreen="32cd32", linen="faf0e6", magenta="ff00ff", maroon="800000",
    mediumaquamarine="66cdaa", mediumblue="0000cd", mediumorchid="ba55d3", mediumpurple="9370db",
    mediumseagreen="3cb371", mediumslateblue="7b68ee", mediumspringgreen="00fa9a", mediumturquoise="48d1cc",
    mediumvioletred="c71585", midnightblue="191970", mintcream="f5fffa", mistyrose="ffe4e1", moccasin="ffe4b5",
    navajowhite="ffdead", navy="000080", oldlace="fdf5e6", olive="808000", olivedrab="6b8e23", orangered="ff4500",
    orchid="da70d6", palegoldenrod="eee8aa", palegreen="98fb98", paleturquoise="afeeee", palevioletred="db7093",
    papayawhip="ffefd5", peachpuff="ffdab9", peru="cd853f", pink="ffc0cb", plum="dda0dd", powderblue="b0e0e6",
    purple="800080", rebeccapurple="663399", rosybrown="bc8f8f", royalblue="4169e1", saddlebrown="8b4513",
    salmon="fa8072", sandybrown="f4a460", seagreen="2e8b57", seashell="fff5ee", sienna="a0522d", skyblue="87ceeb",
    slateblue="6a5acd", slategray="708090", slategrey="708090", snow="fffafa", springgreen="00ff7f",
    steelblue="4682b4", tan="d2b48c", teal="008080", thistle="d8bfd8", tomato="ff6347", turquoise="40e0d0",
    violet="ee82ee", wheat="f5deb3", whitesmoke="f5f5f5", yellow="ffff00", yellowgreen="9acd32",
)


def named_colour(c):
    """A colour tag's value as r, g, b: one of the names above, a CSS name or
    #rrggbb; None if it's none of those."""
    c = c.strip().lower()
    if c in COLOURS: return COLOURS[c]
    if re.fullmatch(r"#[0-9a-f]{6}", c): return tuple(round(int(c[i:i + 2], 16) / 255, 2) for i in (1, 3, 5))
    if c in CSS:
        rgb = [int(CSS[c][i:i + 2], 16) / 255 for i in (0, 2, 4)]
        grey = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        return tuple(round(0.88 * (v + grey) / 2, 2) for v in rgb)


def roof_colour(t):
    """A roof:colour as r, g, b; None if untagged."""
    return named_colour(t.get("roof:colour", ""))


def height_of(t, kind, A):
    for key in ("height", "building:height"):
        try: return max(2.5, float(t[key].split()[0]))
        except (KeyError, ValueError): pass
    try: levels = float(t["building:levels"])
    except (KeyError, ValueError): levels = None
    floor = {"house": 2.9, "terrace": 2.9, "shed": 2.6}.get(kind, 3.4)
    if levels is None:
        levels = {"shed": 1, "house": 1 if A < 160 else 2, "terrace": 1, "flats": 3 if A < 900 else 4,
                  "shop": 2, "civic": 2, "church": 3, "works": 2.5, "police": 3, "stand": 2}[kind]
    return max(2.5, levels * floor)


def overpass(q, timeout, tries=4):
    """Run an Overpass query, trying each server a few times."""
    import time
    err = None
    for attempt in range(tries):
        for url in OVERPASS:
            req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(),
                                         headers={"User-Agent": "3D-auto osm_import"})
            try:
                return json.loads(urllib.request.urlopen(req, timeout=timeout).read())
            except (OSError, ValueError) as e:
                err = e
                print(f"  {url}: {e}", file=sys.stderr)
        if attempt + 1 < tries: time.sleep(10 * (attempt + 1))
    raise SystemExit(f"Overpass failed: {err}")


def railways_of(els, P, inside):
    """Railway track on the ground (not on bridges or in tunnels), and platforms."""
    railways, platforms = [], []
    for el in els:
        t = el.get("tags", {})
        rw = t.get("railway")
        if rw in ("rail", "light_rail", "narrow_gauge", "tram"):
            if t.get("tunnel") not in (None, "no") or t.get("bridge") not in (None, "no"): continue
            pts = simplify([P(p["lat"], p["lon"]) for p in el.get("geometry") or []], 0.3)
            pts = [p for p in pts if inside(*p)]
            if len(pts) < 2: continue
            # A main line or a branch line carries trains through; sidings,
            # yard tracks and spurs are the yard's.
            main = t.get("service") not in ("siding", "yard", "spur", "crossover")
            wired = t.get("electrified") in ("contact_line", "yes")
            railways.append((main, wired, pts))
        elif rw == "platform" or t.get("public_transport") == "platform" and t.get("train") == "yes":
            for ring in rings(el):
                poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
                if len(poly) < 3 or not all(inside(*p) for p in poly): continue
                ang, (cx, cz), pl, pw = min_rect(poly)
                if pl < pw: ang, pl, pw = ang + math.pi / 2, pw, pl
                if pl >= 20 and 2 <= pw <= 20 and area(poly) > 0.7 * pl * pw:
                    platforms.append((cx, cz, pl, pw, -ang))
    return railways, platforms


# Real brands on buildings go by the game's parody names (as in the missions).
PARODY = {"Hesburger": "Häsburger", "Sokos Wiklund": "Vicklund"}

MATERIALS = {"brick": (0.55, 0.27, 0.2), "concrete": (0.7, 0.69, 0.66), "plaster": (0.86, 0.83, 0.76),
             "glass": (0.55, 0.65, 0.7), "metal": (0.6, 0.62, 0.64), "wood": (0.62, 0.45, 0.3), "stone": (0.62, 0.6, 0.56)}


def wall_colour(t):
    """building:colour (a name or #rrggbb), else building:material's usual colour; None if neither."""
    return named_colour(t.get("building:colour", "")) or MATERIALS.get(t.get("building:material", "").strip().lower())


def outlines_of(els, P, inside, roof_of=None):
    """Footprints that boxes fit badly (an L, a U, a block round a yard), or
    whose walls have a mapped colour, as their own outlines:
    (height, kind, wall colour or None, points, roof colour or None). The
    game draws these as they are and keeps the boxes only to collide with.
    `roof_of(points)` gives an untagged roof its colour (the aerial photo)."""
    out = []
    for el in els:
        t = el.get("tags", {})
        if "building" not in t or t.get("building") in ("no", "roof", "construction", "ruins"): continue
        for ring in rings(el):
            poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
            if len(poly) < 3 or not all(inside(*p, pad=5) for p in poly): continue
            A = area(poly)
            if A < 150: continue
            kind = "stand" if is_stand(t, poly) else building_kind(t, A)
            if kind in ("house", "terrace", "church", "shed", "stand"): continue
            wall = wall_colour(t)
            if len(boxes_of(poly)) < 2 and not wall: continue
            pts = simplify(poly, 0.3)  # open: the closing side is implied
            if len(pts) >= 3:
                roof = roof_colour(t) or (roof_of and roof_of(pts))
                out.append((height_of(t, kind, A), kind, wall, pts, roof))
    return out


def outline_lines(outlines, f):
    L = ["  -- footprints drawn as they are: {height, kind, wall colour or false, points..., roof = colour}", "  outlines = {"]
    for h, kind, wall, pts, roof in outlines:
        w = "{" + ", ".join(f"{c:.2f}" for c in wall) + "}" if wall else "false"
        r = ", roof = {" + ", ".join(f"{c:.2f}" for c in roof) + "}" if roof else ""
        L.append(f"    {{{f(h)}, \"{kind}\", {w}, " + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts) + r + "},")
    L.append("  },")
    return L


def railway_lines(railways, platforms, f):
    L = ["  -- railway track on the ground: {main line?, electrified?, points...}", "  railways = {"]
    for main, wired, pts in railways:
        L.append(f"    {{{'true' if main else 'false'}, {'true' if wired else 'false'}, "
                 + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts) + "},")
    L.append("  },")
    L.append("  -- railway platforms: {x, z, length, width, yaw}")
    L.append("  platforms = {" + ", ".join(f"{{{f(x)}, {f(z)}, {f(pl)}, {f(pw)}, {a:.3f}}}" for x, z, pl, pw, a in platforms) + "},")
    return L


def pois_of(els, P, inside):
    """Points of interest inside the map: (x, z, {tag: value}), sorted so the
    file doesn't change when Overpass returns them in another order."""
    pois, seen = [], set()
    for el in els:
        t = el.get("tags", {})
        c = el if "lat" in el else el.get("center")
        if not c: continue
        x, z = P(c["lat"], c["lon"])
        if not inside(x, z): continue
        keep = {k: t[k] for k in POI_TAGS if k in t}
        if t.get("highway") == "bus_stop": keep["highway"] = "bus_stop"
        key = (round(x), round(z), tuple(sorted(keep.items())))
        if key in seen: continue  # the same place as a node and as its building
        seen.add(key)
        pois.append((x, z, keep))
    pois.sort(key=lambda p: (p[2].get("name", ""), round(p[0]), round(p[1])))
    return pois


def bus_stops_of(els):
    """Named bus stops from the map's own data (nodes, or platforms drawn as
    areas: their middle), as POIs: where a bus driver stops."""
    out = []
    for el in els:
        t = el.get("tags", {})
        if t.get("highway") != "bus_stop" or "name" not in t: continue
        if "lat" in el:
            out.append(el)
        elif el.get("geometry"):
            g = el["geometry"]
            out.append({"tags": t, "center": {"lat": sum(p["lat"] for p in g) / len(g), "lon": sum(p["lon"] for p in g) / len(g)}})
    return out


def poi_lines(pois, f, q):
    L = ["  -- points of interest (OpenStreetMap tags, for missions): {x, z, {tag = value...}}", "  pois = {"]
    for x, z, t in pois:
        tags = ", ".join(f"{k} = {q(v)}" for k, v in t.items())
        L.append(f"    {{{f(x)}, {f(z)}, {{{tags}}}}},")
    L.append("  },")
    return L


def fetch_pois(cache, cfg, fetch):
    """<area>_pois.json, downloaded if asked to or not there yet."""
    path = cache.with_name(cache.stem + "_pois.json")
    if fetch or not path.exists():
        s, w, n, e = cfg["bbox"]
        print("fetching points of interest from Overpass...", file=sys.stderr)
        path.write_text(json.dumps(overpass(POIS_QUERY.format(s=s, w=w, n=n, e=e), 180)))
    return json.loads(path.read_text())["elements"]


def splice_pois(dest, els, P, f, q):
    """Put points of interest into an already generated map, inside its
    bounds, leaving the rest of it as it was."""
    text = dest.read_text()
    m = re.search(r"\n  bounds = \{(-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\},", text)
    X0, Z0, X1, Z1 = map(float, m.groups())
    def inside(x, z, pad=0): return X0 + pad <= x <= X1 - pad and Z0 + pad <= z <= Z1 - pad
    pois = pois_of(els, P, inside)
    out, skip = [], False
    for line in text.split("\n"):
        if line.startswith("  -- points of interest"): continue
        if line == "  pois = {": skip = True; continue
        if skip:
            if line == "  },": skip = False
            continue
        if line.startswith("  -- named parts of town"):
            out.extend(poi_lines(pois, f, q))
        out.append(line)
    dest.write_text("\n".join(out))
    print(f"{dest}: {len(pois)} points of interest", file=sys.stderr)


def splice_railways(dest, els, P, f):
    """Put railways and platforms into an already generated map, inside its
    bounds, leaving the rest of it as it was."""
    text = dest.read_text()
    m = re.search(r"\n  bounds = \{(-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\},", text)
    X0, Z0, X1, Z1 = map(float, m.groups())
    def inside(x, z, pad=0): return X0 + pad <= x <= X1 - pad and Z0 + pad <= z <= Z1 - pad
    railways, platforms = railways_of(els, P, inside)
    outlines = outlines_of(els, P, inside)
    lines = text.split("\n")
    out, skip = [], False
    for line in lines:
        if line.startswith(("  -- railway track on the ground", "  -- railway platforms", "  -- footprints drawn as they are")): continue
        if line in ("  railways = {", "  outlines = {"): skip = True; continue
        if skip:
            if line == "  },": skip = False
            continue
        if line.startswith("  platforms = {"): continue
        if line.startswith("  -- towers and masts"):
            out.extend(railway_lines(railways, platforms, f))
            out.extend(outline_lines(outlines, f))
        out.append(line)
    dest.write_text("\n".join(out))
    print(f"{dest}: {len(railways)} railway tracks, {len(platforms)} platforms, {len(outlines)} outlines", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("area", choices=sorted(AREAS))
    ap.add_argument("--fetch", action="store_true", help="download fresh data from Overpass first")
    ap.add_argument("--cache", type=Path)
    ap.add_argument("--no-aerial", action="store_true", help="leave the aerial photo's colours out")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--only-railways", action="store_true",
                    help="only put railways, platforms and building outlines into the existing map (no terrain needed)")
    ap.add_argument("--only-pois", action="store_true",
                    help="only put points of interest into the existing map (no terrain or map cache needed)")
    ap.add_argument("--terrain", nargs="+", type=Path,
                    help="explicit local EPSG:3067 GeoTIFF source tiles (2 m for Turku)")
    args = ap.parse_args()
    cfg = AREAS[args.area]
    if cfg.get("require_terrain") and not args.terrain and not args.only_railways and not args.only_pois:
        ap.error(f"{args.area} requires verified 2 m terrain; no flat-map fallback is permitted")
    elevation = None
    if args.terrain:
        for path in args.terrain:
            if not path.is_file():
                ap.error(f"terrain file not found: {path}")
        import dem
        try:
            elevation = dem.Elevation.from_paths(
                args.terrain, expected_resolution=cfg.get("terrain_source", {}).get("resolution_m", 2))
        except (OSError, ValueError, KeyError) as error:
            ap.error(f"invalid terrain input: {error}")
        # Reject incomplete source coverage before fetching or writing OSM data.
        # Sample the full planned box, not only district anchor points.
        import dem
        south, west, north, east = cfg["bbox"]
        try:
            for row in range(17):
                lat = south + (north - south) * row / 16
                for col in range(17):
                    lon = west + (east - west) * col / 16
                    elevation(*dem.tm35(lat, lon))
        except ValueError as error:
            ap.error(f"terrain coverage invalid: {error}")
    cache = args.cache or ROOT / "tools" / "osm_cache" / f"{args.area}.json"
    dest = args.out or ROOT / "game" / "maps" / f"{args.area}_osm.lua"
    s, w, n, e = cfg["bbox"]
    if args.only_pois:
        P = Proj(*(cfg.get("origin") or ((s + n) / 2, (w + e) / 2)))
        els = fetch_pois(cache, cfg, args.fetch)
        # Bus stops come from the map's own data (the POI query has none).
        if cache.exists(): els = els + bus_stops_of(json.loads(cache.read_text())["elements"])
        splice_pois(dest, els, P,
                    lambda v: f"{v:.1f}".rstrip("0").rstrip("."), lambda v: json.dumps(v, ensure_ascii=False))
        return
    if args.fetch:
        cache.parent.mkdir(parents=True, exist_ok=True)
        # In tiles: the servers time out on a whole town at once. A way
        # crossing tiles comes whole with each; it's kept once.
        S, W, N, E = s - 0.003, w - 0.006, n + 0.003, e + 0.006
        rows, cols = math.ceil((N - S) / TILE[0]), math.ceil((E - W) / TILE[1])
        # Each tile is kept as it comes (in <cache>_tiles/), so a run that
        # fails part way carries on from there; one that times out is
        # fetched as four smaller ones instead.
        tiles = cache.with_name(cache.stem + "_tiles")
        tiles.mkdir(exist_ok=True)
        merged, seen, stamp = [], set(), None

        def fetch_tile(ts, tw, tn, te, name, depth=0):
            path = tiles / f"{name}.json"
            if path.exists():
                return [json.loads(path.read_text())]
            print(f"fetching {args.area} from Overpass, tile {name}...", file=sys.stderr)
            try:
                part = overpass(QUERY.format(s=ts, w=tw, n=tn, e=te), 600, tries=1 if depth < 3 else 4)
            except SystemExit:
                if depth >= 3: raise
                ms, mw = (ts + tn) / 2, (tw + te) / 2
                return [p for k, (a, b, c, d) in enumerate(((ts, tw, ms, mw), (ts, mw, ms, te), (ms, tw, tn, mw), (ms, mw, tn, te)))
                        for p in fetch_tile(a, b, c, d, f"{name}{k}", depth + 1)]
            path.write_text(json.dumps(part))
            return [part]
        for i in range(rows):
            for j in range(cols):
                ts, tw = S + i * (N - S) / rows, W + j * (E - W) / cols
                for part in fetch_tile(ts, tw, ts + (N - S) / rows, tw + (E - W) / cols, f"{i}_{j}_"):
                    stamp = stamp or part.get("osm3s")
                    for el in part["elements"]:
                        if (el["type"], el["id"]) not in seen:
                            seen.add((el["type"], el["id"]))
                            merged.append(el)
        cache.write_text(json.dumps({"osm3s": stamp or {}, "elements": merged}))
        import shutil
        shutil.rmtree(tiles)
    places_cache = cache.with_name(cache.stem + "_places.json")
    if args.fetch or not places_cache.exists():
        q = PLACES_QUERY.format(s=s - 0.01, w=w - 0.02, n=n + 0.01, e=e + 0.02)
        print(f"fetching {args.area}'s place names from Overpass...", file=sys.stderr)
        places_cache.write_text(json.dumps(overpass(q, 120)))
    data = json.loads(cache.read_text())
    stamp = data.get("osm3s", {}).get("timestamp_osm_base", "?")
    els = data["elements"]
    # 0, 0 is the area's `origin` if it has one, else its middle (and the
    # area is trimmed to be even round it).
    origin = cfg.get("origin") or ((s + n) / 2, (w + e) / 2)
    P = Proj(*origin)
    X0, Z1 = P(s, w)
    X1, Z0 = P(n, e)
    if cfg.get("origin"):
        X0, Z0, X1, Z1 = math.ceil(X0), math.ceil(Z0), math.floor(X1), math.floor(Z1)
    else:
        X1, Z1 = math.floor(min(-X0, X1)), math.floor(min(-Z0, Z1))
        X0, Z0 = -X1, -Z1
    def inside(x, z, pad=0): return X0 + pad <= x <= X1 - pad and Z0 + pad <= z <= Z1 - pad
    # Colours from an aerial photo (tools/aerial.py), when the area names
    # one: untagged roofs, and the ground no survey class covers.
    aerial = None
    if cfg.get("aerial") and not args.no_aerial:
        import aerial as aerial_mod
        aerial = aerial_mod.Aerial(args.area, origin, (X0, Z0, X1, Z1), source=cfg["aerial"])
        if not aerial.cached():
            print(f"aerial: no photo cached for {args.area}; run tools/aerial.py {args.area} --fetch", file=sys.stderr)
            aerial = None
    if args.only_railways:
        splice_railways(dest, els, P, lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
        return

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
        lanes = t.get("lanes")
        oneway = t.get("oneway") in ("yes", "1", "-1") or hw in ("motorway", "motorway_link") or t.get("junction") == "roundabout"
        if lanes and lanes.isdigit() and int(lanes) >= 1:
            n_lanes = int(lanes)
            lane_w = 3.25
            width = max(6.0, round(n_lanes * lane_w + (1.5 if hw == "motorway" else 0.8), 1))
        else:
            width = w1 if oneway else w2
        name = t.get("name") or t.get("ref")
        bridge = t.get("bridge") not in (None, "no") or t.get("tunnel") not in (None, "no") or t.get("layer", "0") not in ("0",)
        # Up on a bridge, not on the ground. A layer alone isn't one: Nesteentie
        # at Raisiontie is layer 1 only to sit over a tunnel being dug under it.
        deck = t.get("bridge") not in (None, "no")
        # Through a hill, not over it: a tunnel runs straight between its
        # ends, and the ground is cut down to it (the game has no overhangs).
        bored = not deck and t.get("tunnel") not in (None, "no")
        # Of those, a tunnel proper (not a passage through a building) is
        # roofed over in the game.
        roofed = bored and t.get("tunnel") == "yes"
        start = 0
        for k in range(1, len(run)):
            if run[k][0] in is_j or k == len(run) - 1:
                seg = run[start:k + 1]
                lit = (t.get("lit") not in ("no", "none")) if "lit" in t else None
                edges.append({"a": seg[0][0], "b": seg[-1][0], "ids": [p[0] for p in seg], "kind": kind, "width": width,
                              "name": name, "bridge": bridge, "deck": deck, "bored": bored, "roofed": roofed, "hw": hw, "walk": sidewalks(t), "lit": lit, "oneway": oneway})
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
                    lift["bridge"] = lift["deck"] = True

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
        if len(pts) >= 2:
            # How it looks: a foot or cycle path, one mapped as a street's
            # pavement, paving stones.
            look = []
            if hw != "service": look.append("path = true")
            if t.get("footway") == "sidewalk" or t.get("cycleway") == "sidewalk": look.append("sidewalk = true")
            if t.get("surface") in STONE: look.append("stone = true")
            paved.append((PAVED[hw], hw == "service", pts, look))

    # ---- buildings ----
    road_grid = Grid(50)
    for ed in edges:
        for a, b in zip(ed["pts"], ed["pts"][1:]): road_grid.add((ed, a, b), a, b, pad=ed["width"])
    footprints, dropped, trimmed = [], 0, 0
    for el in els:
        t = el.get("tags", {})
        if "building" not in t or t.get("building") in ("no", "roof", "construction", "ruins"): continue
        for ring in rings(el):
            poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
            if not all(inside(*p, pad=5) for p in poly): continue
            A = area(poly)
            if A < 15: continue
            kind = "stand" if is_stand(t, poly) else building_kind(t, A)
            h = height_of(t, kind, A)
            name = (t.get("name") or "").replace("\xad", "") or None  # no soft hyphens
            name = PARODY.get(name, name)
            roof_col = roof_colour(t)
            roof_sh = t.get("roof:shape")
            # Store roof info: [r, g, b, shape] if tagged
            roof_data = list(roof_col) if roof_col else []
            if roof_sh:
                roof_data = (roof_data or [0.5, 0.5, 0.5]) + [roof_sh]
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
                # Keep clear of the (game-width) roads and their pavements:
                # a box that reaches into one gives up a few meters on that
                # side (or two neighbouring sides), or is left out.
                c, s_ = math.cos(ang), math.sin(ang)
                def clear_of_roads(x, z, bw, bd):
                    r = math.hypot(bw, bd) / 2
                    for ed, a, b in road_grid.near(x - r, z - r, x + r, z + r):
                        clear = ed["width"] / 2 + (1.5 if ed["kind"] == "highway" else 3)
                        # Points at most 3 m apart, so no road slips between them.
                        nu, nv = max(4, math.ceil(bw / 3)), max(4, math.ceil(bd / 3))
                        for fu in (k / nu - 0.5 for k in range(nu + 1)):
                            for fv in (k / nv - 0.5 for k in range(nv + 1)):
                                px, pz = x + c * bw * fu - s_ * bd * fv, z + s_ * bw * fu + c * bd * fv
                                if seg_dist((px, pz), a, b) < clear: return False
                    return True
                if not clear_of_roads(x, z, bw, bd):
                    best = None
                    for cut in (1.5, 3, 4.5, 6, 8):
                        for su, sv in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                            nw, nd = bw - cut * abs(su), bd - cut * abs(sv)
                            if nw < max(4, 0.6 * bw) or nd < max(4, 0.6 * bd): continue
                            # Shift away from the cut side so the far walls stay put.
                            nx = x - c * su * cut / 2 + s_ * sv * cut / 2
                            nz = z - s_ * su * cut / 2 - c * sv * cut / 2
                            if clear_of_roads(nx, nz, nw, nd):
                                best = (nx, nz, nw, nd)
                                break
                        if best: break
                    if not best:
                        dropped += 1
                        continue
                    x, z, bw, bd = best
                    trimmed += 1
                roof = roof_colour(t) or (aerial and aerial.roof_of_box(x, z, bw, bd, ang))
                footprints.append((x, z, bw, bd, ang, h, kind, name, roof))
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

    # ---- outdoor swimming pools ----
    pools = []
    for el in els:
        t = el.get("tags", {})
        if t.get("leisure") != "swimming_pool" or t.get("indoor") == "yes" or t.get("location") == "indoor" or "building" in t: continue
        for ring in rings(el):
            poly = [P(p["lat"], p["lon"]) for p in ring[:-1]]
            if len(poly) < 3 or not all(inside(*p) for p in poly): continue
            ang, (cx, cz), pw, pd = min_rect(poly)
            if pw < pd: ang, pw, pd = ang + math.pi / 2, pd, pw
            if pw >= 8 and pd >= 4 and area(poly) > 0.7 * pw * pd:
                pools.append((cx, cz, pw, pd, -ang))

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

    railways, platforms = railways_of(els, P, inside)

    # ---- towers, gantry cranes, piers ----
    towers, cranes, piers = [], [], []
    for el in els:
        t = el.get("tags", {})
        mm = t.get("man_made")
        if mm in ("tower", "mast") and t.get("tower:type") not in ("bell_tower", "lighting"):  # not floodlights
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

    # ---- terrain: real heights, with the roads graded into them ----
    terrain = None
    photo_trees = []
    if elevation is not None or cfg.get("dem"):
        import dem
        Z = elevation or dem.Elevation(cfg["dem"], ROOT / "tools" / "osm_cache" / "dem")
        def ground(x, z):
            return Z(*dem.tm35(origin[0] - z / 110574, origin[1] + x / P.kx))
        # Cover classes, for colors and water.
        cls_grid = {c: Grid(50) for c in DRAW_ORDER}
        for c in DRAW_ORDER:
            for st in strips.get(c, []):
                cls_grid[c].add(st, (st[0], st[1]), (st[2], st[3]))
        def cover_at(x, z):
            for k in range(len(DRAW_ORDER) - 1, -1, -1):
                for st in cls_grid[DRAW_ORDER[k]].near(x, z, x, z):
                    if st[0] <= x <= st[2] and st[1] <= z <= st[3]:
                        return k + 1
            return 0
        water_k = DRAW_ORDER.index("water") + 1
        # Each junction's height: the middle one of the ground there and 5 m
        # round it (one sample down a cutting's side doesn't drag it down),
        # and not the water beside a bridge head (that would sink the end of
        # the street on the quay towards the river).
        def junction_height(x, z):
            hs = sorted(ground(x + dx, z + dz) for dx, dz in ((0, 0), (5, 0), (-5, 0), (0, 5), (0, -5))
                        if cover_at(x + dx, z + dz) != water_k)
            if not hs: return ground(x, z)
            n_ = len(hs)
            return hs[n_ // 2] if n_ % 2 else (hs[n_ // 2 - 1] + hs[n_ // 2]) / 2
        # Then each road's profile: the ground along it smoothed over 40 m
        # (80 m for main roads and highways, built gentler) and bent to meet
        # its junctions. A road on a bridge runs straight between its ends
        # instead.
        jh = {j: junction_height(*pos[j]) for j in {ed_["a"] for ed_ in edges} | {ed_["b"] for ed_ in edges}}
        # A bridge's end stands on its abutment, which the ground model (bare
        # earth: no bridges, no embankments) has dug away: there the ground
        # falls to the river or the road below. Raise it to the streets that
        # lead onto the bridge, 10 and 20 m back from it (straight on the way
        # they leave it: a street there is often several short pieces).
        heads = {j for ed_ in edges if ed_["deck"] for j in (ed_["a"], ed_["b"])}
        for ed_ in edges:
            if ed_["deck"] or ed_.get("bored"): continue
            for j, pts in ((ed_["a"], ed_["pts"]), (ed_["b"], ed_["pts"][::-1])):
                if j not in heads: continue
                (ax, az), (bx, bz) = pts[0], pts[1]
                L_ = math.hypot(bx - ax, bz - az) or 1.0
                for s_ in (10, 20):
                    p = (ax + (bx - ax) * s_ / L_, az + (bz - az) * s_ / L_)
                    if cover_at(*p) != water_k: jh[j] = max(jh[j], ground(*p))
        prof_grid = Grid(50)
        for ed_ in edges:
            pts = ed_["pts"]
            ss, xs = [0.0], [pts[0]]
            for a, b in zip(pts, pts[1:]):
                L_ = math.hypot(b[0] - a[0], b[1] - a[1])
                n = max(1, int(L_ // 5))
                for k in range(1, n + 1):
                    xs.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
                    ss.append(ss[-1] + L_ / n)
            total = ss[-1] or 1.0
            ha, hb = jh[ed_["a"]], jh[ed_["b"]]
            if ed_["deck"] or ed_.get("bored"):
                hs = [ha + (hb - ha) * s_ / total for s_ in ss]
            else:
                raw = [ground(*p) for p in xs]
                reach = 40 if ed_["kind"] in ("main", "highway") else 20
                sm = []
                for k in range(len(raw)):
                    lo, hi = k, k
                    while lo > 0 and ss[k] - ss[lo - 1] <= reach: lo -= 1
                    while hi < len(raw) - 1 and ss[hi + 1] - ss[k] <= reach: hi += 1
                    sm.append(sum(raw[lo:hi + 1]) / (hi - lo + 1))
                hs = [sm[k] + (ha - sm[0]) * (1 - ss[k] / total) + (hb - sm[-1]) * ss[k] / total for k in range(len(sm))]
            ed_["profile"] = list(zip(xs, hs))
            # For the game: heights every 10 m or so along the road, end to end.
            n = max(1, round(total / 10))
            ed_["heights"] = []
            k = 0
            for m in range(n + 1):
                s_ = total * m / n
                while k < len(ss) - 2 and ss[k + 1] < s_: k += 1
                f_ = (s_ - ss[k]) / ((ss[k + 1] - ss[k]) or 1)
                ed_["heights"].append(hs[k] + (hs[k + 1] - hs[k]) * min(1.0, max(0.0, f_)) if len(hs) > 1 else hs[0])
            if ed_.get("roofed"):
                # The hill over a tunnel, for the game's roof: the ground
                # either side of its cutting at each of those heights,
                # left then right (looking from a to b).
                ed_["roof"] = []
                k = 0
                for m in range(n + 1):
                    s_ = total * m / n
                    while k < len(ss) - 2 and ss[k + 1] < s_: k += 1
                    (ax_, az_), (bx_, bz_) = xs[k], xs[min(k + 1, len(xs) - 1)]
                    L_ = math.hypot(bx_ - ax_, bz_ - az_) or 1.0
                    f_ = min(1.0, max(0.0, (s_ - ss[k]) / ((ss[k + 1] - ss[k]) or 1)))
                    cx, cz = ax_ + (bx_ - ax_) * f_, az_ + (bz_ - az_) * f_
                    nx, nz = (bz_ - az_) / L_, -(bx_ - ax_) / L_
                    off = ed_["width"] / 2 + ROOF_REACH
                    ed_["roof"] += [ground(cx - nx * off, cz - nz * off), ground(cx + nx * off, cz + nz * off)]
            if not ed_["deck"]:
                for (a, ya), (b, yb) in zip(ed_["profile"], ed_["profile"][1:]):
                    prof_grid.add((ed_, a, b, ya, yb), a, b, pad=ed_["width"] / 2 + 26)
        # Water lies flat at its own level (the sea at 0, a reservoir higher):
        # each strip at the ground model's height there, the bed below it.
        levels = []
        for st in strips.get("water", []):
            levels.append(round(max(0.0, ground((st[0] + st[2]) / 2, (st[1] + st[3]) / 2)), 1))
        tw, td = int(math.ceil((X1 - X0) / STEP)) + 1, int(math.ceil((Z1 - Z0) / STEP)) + 1
        hgt, cls = [], []
        for j in range(td):
            for i in range(tw):
                x, z = X0 + i * STEP, Z0 + j * STEP
                h = ground(x, z)
                # Graded to the nearest road: flat across it out to its
                # pavements and a few meters more, blending back over 20 m
                # (a tunnel's cutting over TUNNEL_BLEND: steep sides, under
                # a roof no wider than it has to be).
                best = None
                for ed_, a, b, ya, yb in prof_grid.near(x, z, x, z):
                    dx, dz = b[0] - a[0], b[1] - a[1]
                    l2 = dx * dx + dz * dz or 1e-9
                    t_ = max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
                    d = math.hypot(x - a[0] - dx * t_, z - a[1] - dz * t_) - ed_["width"] / 2 - 6
                    if best is None or d < best[0]:
                        best = (d, ya + (yb - ya) * t_, TUNNEL_BLEND if ed_.get("bored") else 20)
                if best and best[0] < best[2]:
                    w_ = 1.0 if best[0] <= 0 else 1 - best[0] / best[2]
                    h = h + (best[1] - h) * w_
                k = cover_at(x, z)
                if k == water_k:
                    h = min(h, ground(x, z) - 1.5)
                hgt.append(max(-327, min(327, h)))
                cls.append(k)
        # Ground no survey class covers takes its colour from the aerial
        # photo: a palette after the classes, each point the nearest colour.
        ground_palette = []
        if aerial:
            land = [n_ for n_, k in enumerate(cls) if k == 0]
            ground_palette, idx = aerial.ground([X0 + (n_ % tw) * STEP for n_ in land], [Z0 + (n_ // tw) * STEP for n_ in land], STEP)
            for n_, k in zip(land, idx.tolist()):
                if k >= 0: cls[n_] = len(DRAW_ORDER) + 1 + k
            print(f"aerial: {len(land)} ground points coloured from the photo, {len(ground_palette)} colours", file=sys.stderr)
            # Trees the photo shows where the survey has no wood (the
            # street trees, the trees in front yards) within 14 m of a street, where
            # they are seen: a 10 m grid (a crown's width), each spot under
            # a crown nudged off the grid by its own hash so rows don't look
            # planted by a robot.
            import random as random_
            # Bare ground, and the grass strips and small parks streets are
            # lined with (the woods get their own forest).
            treeable = {0} | {DRAW_ORDER.index(c) + 1 for c in ("field", "park", "cemetery")}
            def by_a_street(x, z, reach=14):
                for ed, a, b in road_grid.near(x - reach, z - reach, x + reach, z + reach):
                    if seg_dist((x, z), a, b) < ed["width"] / 2 + reach: return True
                return False
            cand = [(x, z) for z in range(int(Z0) + 5, int(Z1) - 5, 10) for x in range(int(X0) + 5, int(X1) - 5, 10)
                    if cover_at(x, z) in treeable and by_a_street(x, z)]
            crown = aerial.canopy([c[0] for c in cand], [c[1] for c in cand])
            rnd = random_.Random(7)
            photo_trees = [(x + rnd.uniform(-1.8, 1.8), z + rnd.uniform(-1.8, 1.8)) for (x, z), t in zip(cand, crown.tolist()) if t]
            print(f"aerial: {len(photo_trees)} trees from the photo", file=sys.stderr)
        terrain = {"w": tw, "d": td, "heights": hgt, "classes": cls, "levels": levels, "palette": ground_palette}
        tdest = dest.with_name(dest.stem.replace("_osm", "") + "_terrain.bin")
        import struct
        tdest.write_bytes(struct.pack(f"<{tw * td}h", *(round(h * 100) for h in hgt)) + bytes(cls))
        terrain["file"] = tdest

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
        if ed["kind"] != "highway" and ed["walk"] != "both": attrs += f", sidewalk = {q(ed['walk'])}"
        if ed.get("lit") is False: attrs += ", lit = false"
        if ed.get("oneway"): attrs += ", oneway = true"
        if ed["bridge"]: attrs += ", bridge = true"
        if ed.get("deck") and terrain: attrs += ", deck = true"
        if ed.get("heights") and not ed.get("deck"):
            attrs += ", heights = {" + ", ".join(f"{h:.2f}".rstrip("0").rstrip(".") for h in ed["heights"]) + "}"
        if ed.get("roof"):
            attrs += ", tunnel = true, roof = {" + ", ".join(f"{h:.1f}".rstrip("0").rstrip(".") for h in ed["roof"]) + "}"
        L.append(f"    {{{attrs}, {', '.join(bits)}}},")
    L.append("  },")
    L.append("  -- {width, service road?, points..., path = a foot or cycle path?, sidewalk = a street's pavement?,")
    L.append("  -- stone = paving stones?}")
    L.append("  paved = {")
    for wd, svc, pts, look in paved:
        L.append(f"    {{{wd}, {'true' if svc else 'false'}, " + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts)
                 + "".join(", " + a for a in look) + "},")
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
    L.append("  -- outdoor swimming pools: {x, z, length, width, yaw}")
    L.append("  pools = {" + ", ".join(f"{{{f(x)}, {f(z)}, {f(pw)}, {f(pd)}, {a:.3f}}}" for x, z, pw, pd, a in pools) + "},")
    L.append("  -- foot and cycle bridges over roads: {width, points...}")
    L.append("  footbridges = {")
    for wd, pts in footbridges:
        L.append(f"    {{{f(wd)}, " + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts) + "},")
    L.append("  },")
    L.extend(railway_lines(railways, platforms, f))
    L.extend(outline_lines(outlines_of(els, P, inside, aerial and aerial.roof_of_outline), f))
    L.append("  -- towers and masts: {x, z, height, \"lattice\" or \"pylon\"}")
    L.append("  towers = {" + ", ".join(f"{{{f(x)}, {f(z)}, {f(h)}, {q(k)}}}" for x, z, h, k in towers) + "},")
    L.append("  -- gantry cranes: the rails' {x, z, length, span, yaw, cranes on them}")
    L.append("  cranes = {" + ", ".join(f"{{{f(x)}, {f(z)}, {f(l)}, {f(w)}, {a:.3f}, {n}}}" for x, z, l, w, a, n in cranes) + "},")
    L.append("  -- piers: {width, points...}")
    L.append("  piers = {")
    for wd, pts in piers:
        L.append(f"    {{{f(wd)}, " + ", ".join(f"{{{f(p[0])}, {f(p[1])}}}" for p in pts) + "},")
    L.append("  },")
    L.extend(poi_lines(pois_of(fetch_pois(cache, cfg, args.fetch), P, inside), f, q))
    L.append("  -- named parts of town: {name, x, z, \"town\", \"suburb\" or \"neighbourhood\"}")
    L.append("  areas = {")
    for name, x, z, kind in areas:
        L.append(f"    {{{q(name)}, {f(x)}, {f(z)}, {q(kind)}}},")
    L.append("  },")
    if photo_trees:
        L.append("  -- trees the aerial photo shows outside parks and woods: x, z, x, z, ...")
        L.append("  photo_trees = {" + ", ".join(f"{f(x)}, {f(z)}" for x, z in photo_trees) + "},")
    if terrain:
        L.append(f"  -- the ground's height every {f(STEP)} m from (x0, z0), in {terrain['file'].name} (Maanmittauslaitos")
        L.append("  -- elevation model, CC BY 4.0): i16 centimeters, then each point's cover class (0 land)")
        L.append(f"  terrain = {{x0 = {X0}, z0 = {Z0}, step = {f(STEP)}, w = {terrain['w']}, d = {terrain['d']}, "
                 f"file = {q('maps/' + terrain['file'].name)}, classes = {{{', '.join(q(c) for c in DRAW_ORDER)}}}"
                 + (", aerial = {" + ", ".join("{" + ", ".join(f"{v:.3f}" for v in c) + "}" for c in terrain["palette"]) + "}"
                    if terrain["palette"] else "") + "},")
        if terrain["palette"]:
            L.append("  -- points past the classes take the aerial colours (Turku's aerial photo, via tools/aerial.py)")
    L.append("  -- {x0, z0, x1, z1} strips; water's have its level too")
    L.append("  cover = {")
    for cls, out in strips.items():
        if cls == "water" and terrain:
            L.append(f"    {cls} = {{" + ", ".join(f"{{{a},{f(b)},{c},{f(d)},{f(y)}}}" for (a, b, c, d), y in zip(out, terrain["levels"])) + "},")
        else:
            L.append(f"    {cls} = {{" + ", ".join(f"{{{a},{f(b)},{c},{f(d)}}}" for a, b, c, d in out) + "},")
    L.append("  },")
    L.append("}")
    dest.write_text("\n".join(L) + "\n")
    njs = len(used)
    print(f"{dest.relative_to(ROOT) if dest.is_relative_to(ROOT) else dest}: {njs} junctions, {len(edges)} roads ({sum(1 for e in edges if e['bridge'])} bridges), "
          f"{len(paved)} paved ways, {len(footprints)} building boxes ({trimmed} trimmed and {dropped} left out clear of the roads), "
          + ", ".join(f"{k} {len(v)}" for k, v in strips.items())
          + f", {len(pitches)} pitches, {len(railways)} railway tracks, {len(platforms)} platforms, {len(footbridges)} footbridges, {len(towers)} towers, {len(cranes)} cranes,"
          f" {len(piers)} piers, {len(areas)} areas; {dest.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
