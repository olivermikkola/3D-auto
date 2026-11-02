#!/usr/bin/env python3
"""Föli's bus lines onto a generated map's streets: game/maps/<area>_bus.lua.

Reads the map tools/osm_import.py wrote (its named junctions and the roads
between them) and Föli's timetable data (GTFS, data.foli.fi, CC BY 4.0), and
for each line and direction takes the route most of its trips run, the part
of it inside the map, and finds the junctions a bus passes on the map's own
streets, one way streets and all. The game drives its buses along them
(systems/traffic, lib/buslines).

    python3 tools/foli_lines.py turku            # tools/osm_cache/foli_gtfs.zip, downloaded if not there
    python3 tools/foli_lines.py turku --fetch    # download it again

A line that doesn't follow its route on the map closely enough (a street the
map hasn't got) is left out, and said so.
"""
import argparse
import collections
import csv
import heapq
import io
import math
from pathlib import Path
import re
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
GTFS_URL = "http://data.foli.fi/gtfs/gtfs.zip"
NEAR = 30        # m: how far off the route a street may be and still be on it
PIECE = 400      # m of route matched at a time (so it can't cut out a loop)
MIN_ON = 0.7     # of the route on the matched streets, or the line is left out
MIN_LEN = 600    # m: a line with less of it inside the map is left out
MAX_LONGER = 1.3 # the matched streets this much longer than the route: a detour; left out
DEBUG = False


# ---- the map ------------------------------------------------------------------------------

def lua_value(s, i):
    """A Lua value in s from i (a string, a number, true/false/nil, or a table
    constructor) and where it ends: enough for the generated map's roads."""
    while s[i] in " \t\n": i += 1
    c = s[i]
    if c == '"':
        j, out = i + 1, []
        while s[j] != '"':
            if s[j] == "\\": out.append(s[j + 1]); j += 2
            else: out.append(s[j]); j += 1
        return "".join(out), j + 1
    if c == "{":
        items, keyed, i = [], {}, i + 1
        while True:
            while s[i] in " \t\n,": i += 1
            if s[i] == "}": return (items, keyed), i + 1
            m = re.compile(r"([A-Za-z_][A-Za-z_0-9]*)\s*=").match(s, i)
            if m:
                v, i = lua_value(s, m.end())
                keyed[m.group(1)] = v
            elif s[i] == "[":
                k, i = lua_value(s, i + 1)
                i = s.index("=", s.index("]", i)) + 1
                keyed[k], i = lua_value(s, i)
            else:
                v, i = lua_value(s, i)
                items.append(v)
    m = re.compile(r"-?[0-9.]+(?:e-?[0-9]+)?|true|false|nil").match(s, i)
    v = m.group(0)
    return ({"true": True, "false": False, "nil": None}.get(v, None) if v in ("true", "false", "nil") else float(v)), m.end()


def block(text, key):
    """The table after `  key = ` at the top level of the map file."""
    m = re.search(r"^  " + key + r" = \{", text, re.M)
    if not m: return None
    v, _ = lua_value(text, m.end() - 1)
    return v


def load_map(path):
    text = path.read_text(encoding="utf-8")
    origin = [float(v) for v in re.search(r"origin = \{([-0-9.]+), ([-0-9.]+)\}", text).groups()]
    bounds = [float(v) for v in re.search(r"bounds = \{([-0-9.]+), ([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\}", text).groups()]
    _, junctions = block(text, "junctions")
    pos = {name: (p[0][0], p[0][1]) for name, p in junctions.items()}
    roads, _ = block(text, "roads")
    edges = []  # (a, b, pts, oneway)
    for items, keyed in roads:
        pts, names = [], []
        for it in items:
            if isinstance(it, str):
                pts.append(pos[it]); names.append(it)
            else:
                pts.append((it[0][0], it[0][1])); names.append(None)
        start = 0
        for i in range(1, len(pts)):
            if names[i] is not None:
                if names[start] is not None:
                    edges.append((names[start], names[i], pts[start:i + 1], bool(keyed.get("oneway"))))
                start = i
    return origin, bounds, pos, edges


# ---- geometry ----------------------------------------------------------------------------------

def seg_dist(p, a, b):
    ax, az, bx, bz = a[0], a[1], b[0], b[1]
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0 if L == 0 else max(0, min(1, ((p[0] - ax) * dx + (p[1] - az) * dz) / L))
    return math.hypot(p[0] - ax - dx * t, p[1] - az - dz * t)


def length(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def densify(pts, step):
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(1, n + 1)]
    return out


class Grid:
    """Polylines' segments by 50 m cell, for 'what's near here'."""
    def __init__(self, cell=50):
        self.cell, self.cells = cell, collections.defaultdict(list)

    def add(self, key, pts):
        c = self.cell
        for a, b in zip(pts, pts[1:]):
            for i in range(int(math.floor(min(a[0], b[0]) / c)), int(math.floor(max(a[0], b[0]) / c)) + 1):
                for j in range(int(math.floor(min(a[1], b[1]) / c)), int(math.floor(max(a[1], b[1]) / c)) + 1):
                    self.cells[(i, j)].append((key, a, b))

    def nearest(self, p):
        """The nearest segment to p within a cell or two: (distance, a, b)."""
        c, best = self.cell, (math.inf, None, None)
        i0, j0 = int(math.floor(p[0] / c)), int(math.floor(p[1] / c))
        for i in range(i0 - 1, i0 + 2):
            for j in range(j0 - 1, j0 + 2):
                for _, a, b in self.cells.get((i, j), ()):
                    d = seg_dist(p, a, b)
                    if d < best[0]: best = (d, a, b)
        return best

    def dist(self, p, key=None):
        """Distance from p to the nearest segment (of `key`, if given) within a cell or two."""
        c, best = self.cell, math.inf
        i0, j0 = int(math.floor(p[0] / c)), int(math.floor(p[1] / c))
        for i in range(i0 - 1, i0 + 2):
            for j in range(j0 - 1, j0 + 2):
                for k, a, b in self.cells.get((i, j), ()):
                    if key is None or k == key:
                        best = min(best, seg_dist(p, a, b))
        return best


# ---- matching ---------------------------------------------------------------------------------

def match(route, pos, out_edges, edge_pts):
    """The junctions a bus passes driving `route` (points) on the map: from
    junction to junction near the route about every PIECE m, the cheapest way
    each time, a street costing its length more the further it strays from
    the route (one too far off isn't taken). Returns the junction names, or
    None."""
    dense = densify(route, 10)
    g = Grid()
    g.add(0, dense)
    near = {}  # junctions within NEAR of the route: name -> where along it (index into dense)
    for name, q in pos.items():
        if out_edges.get(name) and g.dist(q) <= NEAR:
            near[name] = min(range(len(dense)), key=lambda k: math.dist(dense[k], q))
    if not near: return None
    wide = Grid(200)
    wide.add(0, dense)
    stray = {}
    def weight(u, v, far):
        """The street's cost, or None if it strays further than `far` m."""
        if (u, v, far) not in stray:
            pts = edge_pts[(u, v)]
            ds = [min((g if far <= 50 else wide).dist(p), 200) for p in densify(pts, 15)]
            w = None if max(ds) > far else length(pts) * (1 + (sum(ds) / len(ds) / 10) ** 2)
            # Against the route's own way along it (back down the other
            # carriageway, past a junction and back): only if nothing else will do.
            against = 0
            for q, r in zip(pts, pts[1:]):
                d, a, b = g.nearest(((q[0] + r[0]) / 2, (q[1] + r[1]) / 2))
                if a and d < NEAR and (r[0] - q[0]) * (b[0] - a[0]) + (r[1] - q[1]) * (b[1] - a[1]) < 0:
                    against += math.dist(q, r)
            if w is not None and against > length(pts) * 0.3: w *= 20
            stray[(u, v, far)] = w
        return stray[(u, v, far)]
    def search(start, goals, far):
        """The way from start to the nearest of goals: (that goal, prev)."""
        cost, prev, heap, done = {start: 0}, {}, [(0, start)], set()
        while heap:
            c, u = heapq.heappop(heap)
            if u in done: continue
            done.add(u)
            if u in goals and u != start: return u, prev
            for v in out_edges.get(u, ()):
                w = weight(u, v, far)
                if w is not None and c + w < cost.get(v, math.inf):
                    cost[v], prev[v] = c + w, u
                    heapq.heappush(heap, (c + w, v))
        return None, None
    # Waypoints about every PIECE m along: each any junction near that point
    # of the route (a dual carriageway's: the one going the right way).
    step = PIECE // 10
    along = sorted(set(near.values()))
    marks, last = [], -step
    for k in along:
        if k - last >= step:
            marks.append(k); last = k
    if along[-1] > last: marks.append(along[-1])
    def around(k): return {n for n, a in near.items() if abs(a - k) <= 5}
    path = None
    for k in marks:
        goals = around(k)
        if path is None:
            # The first: whichever of them a bus can go on from.
            path = [min(goals, key=lambda n: (near[n], n))]
            for n in sorted(goals):
                if search(n, set(near) - {n}, NEAR * 1.6)[0]: path = [n]; break
            continue
        if path[-1] in goals: continue
        # Near the route; else round a gap in the map's streets (a bus lane,
        # a bus-only link it hasn't got) by the nearest it has.
        goal, prev = search(path[-1], goals, NEAR * 1.6)
        if not goal: goal, prev = search(path[-1], goals, NEAR * 6)
        # Stuck (the way in was a one way street's wrong end): back a few
        # junctions and try from there; at the very start, start again here.
        back = 1
        while not goal and back < min(6, len(path)):
            back += 1
            goal, prev = search(path[-back], goals, NEAR * 1.6)
            if goal: del path[len(path) - back + 1:]
        if not goal: goal, prev = search(path[-1], goals, math.inf)  # any way back to it at all
        if not goal:
            if DEBUG: print("unreached", sorted(goals), "from", path[-1], pos[path[-1]], file=sys.stderr)
            if len(path) == 1: path = [min(goals)]
            continue  # (on to the next)
        way, n = [], goal
        while n != path[-1]:
            way.append(n)
            n = prev[n]
        path += reversed(way)
    # Back where it was (a spur to a waypoint and back, round a block): the
    # way round left out. (Junction i to the one after its second visit is
    # still a street: the second visit left by one.)
    out, seen = [], {}
    for n in path:
        if n in seen:
            for m in out[seen[n] + 1:]: del seen[m]
            del out[seen[n] + 1:]
        else:
            seen[n] = len(out)
            out.append(n)
    return out if len(out) > 1 else None


def on_route(route, path, edge_pts):
    """How much of the route lies within NEAR of the matched streets."""
    g = Grid()
    for a, b in zip(path, path[1:]):
        g.add(0, edge_pts[(a, b)])
    dense = densify(route, 10)
    return sum(1 for p in dense if g.dist(p) <= NEAR) / len(dense)


# ---- GTFS ------------------------------------------------------------------------------------------

def read(z, name):
    with z.open(name) as f:
        yield from csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))


def inside_runs(pts, bounds):
    x0, z0, x1, z1 = bounds
    runs, cur = [], []
    for p in pts:
        if x0 + 50 <= p[0] <= x1 - 50 and z0 + 50 <= p[1] <= z1 - 50:
            cur.append(p)
        else:
            if len(cur) > 1: runs.append(cur)
            cur = []
    if len(cur) > 1: runs.append(cur)
    return runs


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("area", help="the map, e.g. turku (game/maps/<area>_osm.lua)")
    ap.add_argument("--gtfs", type=Path, default=ROOT / "tools" / "osm_cache" / "foli_gtfs.zip")
    ap.add_argument("--fetch", action="store_true", help="download Föli's GTFS again")
    ap.add_argument("--only", help="just this line (prints how it matched)")
    a = ap.parse_args(argv)
    if a.fetch or not a.gtfs.exists():
        print(f"fetching {GTFS_URL}...", file=sys.stderr)
        a.gtfs.write_bytes(urllib.request.urlopen(GTFS_URL, timeout=120).read())
    origin, bounds, pos, edges = load_map(ROOT / "game" / "maps" / f"{a.area}_osm.lua")
    out_edges, edge_pts = collections.defaultdict(list), {}
    for u, v, pts, oneway in edges:
        out_edges[u].append(v); edge_pts[(u, v)] = pts
        if not oneway:
            out_edges[v].append(u); edge_pts[(v, u)] = list(reversed(pts))
    kx = 111320 * math.cos(math.radians(origin[0]))
    def P(lat, lon): return ((lon - origin[1]) * kx, -(lat - origin[0]) * 110574)

    z = zipfile.ZipFile(a.gtfs)
    routes = {r["route_id"]: r for r in read(z, "routes.txt") if r["route_type"] == "3"}
    shape_of = collections.Counter()   # (route, direction, shape) -> trips
    heads = collections.defaultdict(collections.Counter)
    for t in read(z, "trips.txt"):
        if t["route_id"] in routes:
            key = (t["route_id"], t["direction_id"])
            shape_of[key + (t["shape_id"],)] += 1
            heads[key + (t["shape_id"],)][t["trip_headsign"]] += 1
    best = {}  # (route, direction) -> (shape, trips on it, all trips)
    for (r, d, s), n in shape_of.items():
        cur = best.get((r, d))
        total = (cur[2] if cur else 0) + n
        if not cur or n > cur[1]: best[(r, d)] = (s, n, total)
        else: best[(r, d)] = (cur[0], cur[1], total)
    wanted = {s for s, _, _ in best.values()}
    shapes = collections.defaultdict(list)
    for p in read(z, "shapes.txt"):
        if p["shape_id"] in wanted:
            shapes[p["shape_id"]].append((int(p["shape_pt_sequence"]), P(float(p["shape_pt_lat"]), float(p["shape_pt_lon"]))))

    lines, left_out = [], []
    for (r, d), (s, _, trips) in sorted(best.items(), key=lambda kv: (routes[kv[0][0]]["route_short_name"], kv[0][1])):
        name = routes[r]["route_short_name"]
        if a.only and name != a.only: continue
        pts = [p for _, p in sorted(shapes[s])]
        runs = inside_runs(pts, bounds)
        if not runs: continue
        run = max(runs, key=length)
        if length(run) < MIN_LEN: continue
        path = match(run, pos, out_edges, edge_pts)
        share = on_route(run, path, edge_pts) if path else 0
        if a.only:
            print(f"{name} dir {d}: {length(run):.0f} m inside, {len(path or [])} junctions, {share:.0%} on route", file=sys.stderr)
        longer = sum(length(edge_pts[(u, v)]) for u, v in zip(path, path[1:])) / length(run) if path else 0
        if not path or share < MIN_ON or longer > MAX_LONGER:
            left_out.append(f"{name}/{d} ({share:.0%}, x{longer:.2f})")
            continue
        head = heads[(r, d, s)].most_common(1)[0][0]
        color = routes[r]["route_color"] or "ffd200"
        rgb = ", ".join(f"{int(color[k:k + 2], 16) / 255:.2f}" for k in (0, 2, 4))
        lines.append((name, head, rgb, trips, path))
    print(f"{len(lines)} line directions matched; left out: {', '.join(left_out) or 'none'}", file=sys.stderr)
    if a.only: return 0

    dest = ROOT / "game" / "maps" / f"{a.area}_bus.lua"
    L = ["-- GENERATED by tools/foli_lines.py " + a.area + ". Don't edit: run it again.",
         "-- Föli's bus lines (data.foli.fi GTFS, FÖLI Turun seudun joukkoliikenne, CC BY 4.0) on this",
         "-- map's streets: {line, headsign, colour, trips a week or so, the junctions it passes in order}.",
         "return {"]
    for name, head, rgb, trips, path in lines:
        L.append(f"  {{line = {lua_str(name)}, to = {lua_str(head)}, color = {{{rgb}}}, trips = {trips},")
        L.append("   " + ", ".join(lua_str(j) for j in path) + "},")
    L.append("}")
    dest.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"{dest}: {len(lines)} lines, {dest.stat().st_size // 1024} KB", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
