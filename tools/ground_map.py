"""The ground's colours every 2 m for tools/osm_import.py: a map the
terrain's shader paints from (render.rs ground_map), where the terrain's
own points are 10 m apart and their colours blur a yard into a blotch.

From the aerial photo (tools/aerial.py), a kilometre tile at a time:
- the photo's shadows lifted (the game lights its ground itself): a shaded
  pixel takes the sunlit colour round it;
- under a crown outside the woods, a shaded lawn (the game draws the trees);
- the crisp ground of the survey (pitches, courts, tracks, sand) in its own
  colours, as the terrain's points have them;
- sorted into a palette of N colours and smoothed (each point the commonest
  of the 3 x 3 round it), so the ground is flat patches with clean edges,
  as the rest of the game is, and the file packs into runs.

The file (Engine::load_ground_map): "GRND", w and h (u16), x0, z0 and step
(f32), n and n rgb bytes, then the points row by row toward +z as runs of
(length - 1, index).
"""
import math
import struct

N = 32          # palette colours
COPY = 255      # a run's index meaning "as the row above"
SHADE_LAWN = (0.27, 0.42, 0.21)


def _box(a, r):
    """Mean over a (2r+1)^2 box, per channel, edges clamped."""
    import numpy as np
    p = np.pad(a, ((r, r), (r, r)) + ((0, 0),) * (a.ndim - 2), mode="edge")
    c = np.cumsum(np.cumsum(p, 0), 1)
    c = np.pad(c, ((1, 0), (1, 0)) + ((0, 0),) * (a.ndim - 2))
    k = 2 * r + 1
    h, w = a.shape[:2]
    return (c[k:k + h, k:k + w] - c[:h, k:k + w] - c[k:k + h, :w] + c[:h, :w]) / (k * k)


def game_colours(c):
    """aerial.game_colour over an array (..., 3)."""
    import numpy as np
    c = c.copy()
    c[..., 2] = np.minimum(c[..., 2], np.maximum(c[..., 0], c[..., 1]) + 0.02)
    m = c.mean(-1, keepdims=True)
    keep = 0.85 * np.clip((m - 0.12) / 0.2, 0, 1)
    return np.clip((m + (c - m) * keep) * 0.85, 0, 1)


def photo_tile(aerial, i, j, step):
    """Tile (i, j) of the photo as game colours every `step` m (its 1 m
    pixels averaged), shadows lifted, and which points are under a crown.
    None off the photo."""
    import numpy as np
    img = aerial._tile(i, j)
    if img is None:
        return None
    img = np.nan_to_num(img, nan=0.5).astype(np.float32)
    lum = img.mean(-1)
    # Shade: much darker than the sunlit ground round about (the brighter
    # half of a 21 m box); it takes that ground's colour.
    lit = lum > _box(lum[..., None], 10)[..., 0] * 0.8
    w_lit = _box(lit[..., None].astype(np.float32), 10)
    lit_col = _box(img * lit[..., None], 10) / np.maximum(w_lit, 1e-3)
    shade = (lum < 0.33) & ~lit & (w_lit[..., 0] > 0.15)
    img = np.where(shade[..., None], lit_col, img)
    # Crowns: green and lumpy over 7 m (aerial.canopy's test).
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    green = ((g > r * 1.08) & (g > b * 1.05)).astype(np.float32)
    rough = np.sqrt(np.maximum(_box((lum ** 2)[..., None], 3)[..., 0] - _box(lum[..., None], 3)[..., 0] ** 2, 0))
    crown = (_box(green[..., None], 3)[..., 0] > 0.65) & (rough > 0.07)
    s = int(round(step))
    h, w = img.shape[0] // s * s, img.shape[1] // s * s
    col = img[:h, :w].reshape(h // s, s, w // s, s, 3).mean((1, 3))
    under = crown[:h, :w].reshape(h // s, s, w // s, s).mean((1, 3)) > 0.5
    return game_colours(col), under


def build(aerial, x0, z0, w, h, step, cls, class_colours, forest):
    """The ground map over w x h points `step` apart from (x0, z0): (palette
    as 0-255 rgb, indices h x w). cls is the survey's class at each point
    (h x w), class_colours {class: rgb 0-1} the ones drawn in their own
    colour, forest the woods' class (their crowns stay)."""
    import numpy as np
    from aerial import TILE_M
    xs = x0 + np.arange(w) * step
    zs = z0 + np.arange(h) * step
    col = np.full((h, w, 3), 0.42, dtype=np.float32)
    under = np.zeros((h, w), bool)
    tiles = {}
    ti = np.floor(xs / TILE_M).astype(int)
    tj = np.floor(zs / TILE_M).astype(int)
    for j in np.unique(tj):
        rows = np.nonzero(tj == j)[0]
        for i in np.unique(ti):
            cols = np.nonzero(ti == i)[0]
            if (i, j) not in tiles:
                tiles[i, j] = photo_tile(aerial, i, j, step)
            t = tiles[i, j]
            if t is None:
                continue
            c, u = t
            px = np.clip(((xs[cols] - i * TILE_M) / step).astype(int), 0, c.shape[1] - 1)
            pz = np.clip(((zs[rows] - j * TILE_M) / step).astype(int), 0, c.shape[0] - 1)
            col[np.ix_(rows, cols)] = c[np.ix_(pz, px)]
            under[np.ix_(rows, cols)] = u[np.ix_(pz, px)]
        tiles = {k: v for k, v in tiles.items() if k[1] == j}  # (a row of tiles at a time)
    col = np.where((under & (cls != forest))[..., None], np.array(SHADE_LAWN, np.float32), col)
    for k, c in class_colours.items():
        col[cls == k] = c
    # A light blur first: the photo's grain would come out as specks.
    col = _box(col, 1).astype(np.float32)
    # The palette: k-means on a sample, then each point its nearest.
    rng = np.random.default_rng(1)
    flat = col.reshape(-1, 3)
    sample = flat[rng.choice(len(flat), size=min(200_000, len(flat)), replace=False)]
    centres = sample[rng.choice(len(sample), size=N, replace=False)].copy()
    for _ in range(20):
        lab = np.argmin(((sample[:, None, :] - centres[None]) ** 2).sum(-1), axis=1)
        for k in range(N):
            if (lab == k).any():
                centres[k] = sample[lab == k].mean(0)
    centres = np.vstack([centres] + [np.array(c, np.float32)[None] for c in class_colours.values()])  # the crisp colours exactly
    idx = np.empty(len(flat), np.uint8)
    for a in range(0, len(flat), 500_000):
        idx[a:a + 500_000] = np.argmin(((flat[a:a + 500_000, None, :] - centres[None]) ** 2).sum(-1), axis=1)
    idx = idx.reshape(h, w)
    # Smooth: each point the commonest index of the 3 x 3 round it, if
    # five or more share it (a speck of one colour in another's patch goes).
    for r, need in ((1, 5), (2, 9), (2, 9)):
        best = idx.copy()
        most = np.zeros((h, w), np.uint8)
        for k in range(len(centres)):
            P = np.pad((idx == k).astype(np.uint8), r, mode="edge")
            cnt = sum(P[a:a + h, b:b + w] for a in range(2 * r + 1) for b in range(2 * r + 1))
            better = cnt > most
            best[better], most[better] = k, cnt[better]
        idx = np.where(most >= need, best, idx)
    palette = [tuple(int(round(v * 255)) for v in c) for c in centres]
    return palette, idx


def write(path, x0, z0, step, palette, idx):
    """The file Engine::load_ground_map reads. Returns its size in bytes.
    Each run is (length - 1, index), or (length - 1, COPY): that many
    points as in the row above, whichever covers more."""
    import numpy as np
    h, w = idx.shape
    out = bytearray(b"GRND" + struct.pack("<HHfffB", w, h, x0, z0, step, len(palette)))
    for c in palette:
        out += bytes(c)
    same = np.zeros((h, w), bool)
    same[1:] = idx[1:] == idx[:-1]
    # How far each point's "as above" and "as itself" go along its row.
    up = np.zeros((h, w + 1), np.int32)
    run = np.zeros((h, w + 1), np.int32)
    for x in range(w - 1, -1, -1):
        up[:, x] = np.where(same[:, x], up[:, x + 1] + 1, 0)
        run[:, x] = 1 + np.where(x + 1 < w, (idx[:, x] == idx[:, min(x + 1, w - 1)]) * run[:, x + 1], 0)
    runs = bytearray()
    for y in range(h):
        x, row, u, r_ = 0, idx[y], up[y], run[y]
        while x < w:
            if u[x] > r_[x]:
                n, k = min(256, int(u[x])), COPY
            else:
                n, k = min(256, int(r_[x])), int(row[x])
            runs += bytes((n - 1, k))
            x += n
    out += runs
    path.write_bytes(bytes(out))
    return len(out)
