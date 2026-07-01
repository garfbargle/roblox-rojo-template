#!/usr/bin/env python3
"""Generic procedural-model snapshot renderer (engine).

This module is game-agnostic: it turns a parts snapshot (the JSON contract
described in modelsnap/README.md) into a deterministic orthographic PNG, with no
external dependencies beyond the Python 3 standard library and no knowledge of
any particular game's builders.

Use it two ways:
  * Standalone CLI for an existing snapshot:
      python3 render_core.py --snapshot model.json --out model.png
  * Imported by a per-game front-end that knows how to produce snapshots:
      import render_core
      render_core.render(snapshot_dict, out_path, ...)

The renderer mirrors Roblox's real part-shape rules so a preview predicts the
live game: a `Cylinder` extrudes along its local X axis (an un-rotated cylinder
is a sideways slab, not a flat disc) and a `Ball` is a sphere of the smallest
Size axis (non-uniform Size is not an ellipsoid). It does NOT model lighting,
materials, neon glow, lights, or particles.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import zlib
from pathlib import Path


Vec3 = tuple[float, float, float]
Vec2 = tuple[float, float]


class Image:
    def __init__(self, width: int, height: int, background: tuple[int, int, int]):
        self.width = width
        self.height = height
        self.pixels = bytearray(background * (width * height))

    def set(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            i = (y * self.width + x) * 3
            self.pixels[i : i + 3] = bytes(color)

    def get(self, x: int, y: int) -> tuple[int, int, int]:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return (0, 0, 0)
        i = (y * self.width + x) * 3
        return tuple(self.pixels[i : i + 3])

    def blend(self, x: int, y: int, color: tuple[int, int, int], alpha: float) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            self.set(x, y, blend_rgb(self.get(x, y), color, alpha))

    def save_png(self, path: Path) -> None:
        raw = bytearray()
        stride = self.width * 3
        for y in range(self.height):
            raw.append(0)
            raw.extend(self.pixels[y * stride : (y + 1) * stride])

        def chunk(kind: bytes, data: bytes) -> bytes:
            return (
                struct.pack(">I", len(data))
                + kind
                + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
            )

        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        png += chunk(b"IEND", b"")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(png)


def blend_rgb(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(round(a[i] * (1 - t) + b[i] * t)))) for i in range(3))


def shade(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(round(c * factor)))) for c in color)


def mat_vec(m: list[list[float]], v: Vec3) -> Vec3:
    return (
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    )


def add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(v: Vec3, s: float) -> Vec3:
    return (v[0] * s, v[1] * s, v[2] * s)


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot3(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def normalize(v: Vec3) -> Vec3:
    m = math.sqrt(dot3(v, v))
    if m < 1e-9:
        return (0.0, 1.0, 0.0)
    return (v[0] / m, v[1] / m, v[2] / m)


def part_center(part: dict) -> Vec3:
    p = part["cframe"]["position"]
    return (float(p["x"]), float(p["y"]), float(p["z"]))


def part_size(part: dict) -> Vec3:
    s = part["size"]
    return (float(s["x"]), float(s["y"]), float(s["z"]))


def part_rotation(part: dict) -> list[list[float]]:
    return [[float(v) for v in row] for row in part["cframe"]["rotation"]]


def part_color(part: dict) -> tuple[int, int, int]:
    c = part["color"]
    return (int(c["r"]), int(c["g"]), int(c["b"]))


def mat_t_vec(m: list[list[float]], v: Vec3) -> Vec3:
    """Apply the transpose (= inverse, for a rotation) of m to v."""
    return (
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2],
    )


# --- Per-pixel ray/surface intersections for the z-buffer ----------------------
# Each returns the camera-space depth (ray parameter t) of the surface FACING the
# camera -- the greatest valid t -- or None when the ray misses the shape. The
# ray is (origin, direction) already expressed in the shape's local frame for box
# and cylinder; the sphere works in world space since it is rotation-invariant.

def ray_box_depth(origin: Vec3, direction: Vec3, half: Vec3) -> float | None:
    t_near = -math.inf
    t_far = math.inf
    for k in range(3):
        o, d, h = origin[k], direction[k], half[k]
        if abs(d) < 1e-9:
            if o < -h or o > h:
                return None
            continue
        t1 = (-h - o) / d
        t2 = (h - o) / d
        if t1 > t2:
            t1, t2 = t2, t1
        if t1 > t_near:
            t_near = t1
        if t2 < t_far:
            t_far = t2
        if t_near > t_far:
            return None
    return t_far  # camera-facing surface (largest depth) of the slab span


def ray_sphere_depth(origin: Vec3, direction: Vec3, center: Vec3, radius: float) -> float | None:
    oc = sub(origin, center)
    b = 2.0 * (oc[0] * direction[0] + oc[1] * direction[1] + oc[2] * direction[2])
    c = oc[0] * oc[0] + oc[1] * oc[1] + oc[2] * oc[2] - radius * radius
    disc = b * b - 4.0 * c  # a == 1 (direction is unit length)
    if disc < 0:
        return None
    return (-b + math.sqrt(disc)) / 2.0


def ray_cylinder_depth(
    origin: Vec3, direction: Vec3, half_x: float, rey: float, rez: float
) -> float | None:
    # Roblox cylinder: round axis is local X; cross-section is the Y-Z ellipse.
    hits: list[float] = []
    oy, oz = origin[1] / rey, origin[2] / rez
    dy, dz = direction[1] / rey, direction[2] / rez
    a = dy * dy + dz * dz
    if a > 1e-12:
        b = 2.0 * (oy * dy + oz * dz)
        c = oy * oy + oz * oz - 1.0
        disc = b * b - 4.0 * a * c
        if disc >= 0:
            sq = math.sqrt(disc)
            for t in ((-b + sq) / (2.0 * a), (-b - sq) / (2.0 * a)):
                x = origin[0] + t * direction[0]
                if -half_x <= x <= half_x:
                    hits.append(t)
    if abs(direction[0]) > 1e-9:
        for cap in (-half_x, half_x):
            t = (cap - origin[0]) / direction[0]
            y = origin[1] + t * direction[1]
            z = origin[2] + t * direction[2]
            if (y / rey) ** 2 + (z / rez) ** 2 <= 1.0:
                hits.append(t)
    if not hits:
        return None
    return max(hits)


def box_corners(part: dict) -> list[Vec3]:
    center = part_center(part)
    size = part_size(part)
    rot = part_rotation(part)
    corners: list[Vec3] = []
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                local = (size[0] * sx, size[1] * sy, size[2] * sz)
                corners.append(add(center, mat_vec(rot, local)))
    return corners


class Camera:
    def __init__(self, yaw_deg: float, pitch_deg: float):
        self.yaw = math.radians(yaw_deg)
        self.pitch = math.radians(pitch_deg)
        self.cy = math.cos(self.yaw)
        self.sy = math.sin(self.yaw)
        self.cp = math.cos(self.pitch)
        self.sp = math.sin(self.pitch)
        self.scale = 1.0
        self.ox = 0.0
        self.oy = 0.0
        self.center: Vec3 = (0.0, 0.0, 0.0)
        # camera_point applies M @ (p - center) with M = pitch * yaw (orthonormal).
        # Row vectors of M, used to invert the projection back into world space for
        # per-pixel ray casting (the z-buffer rasteriser). camera_point of
        # (center + a*row_x + b*row_y + d*ray) is exactly (a, b, d), so the world
        # ray that lands on a screen pixel is base + t*ray and its parameter t IS
        # the camera-space depth -- which is what the depth test compares.
        self.row_x: Vec3 = (self.cy, 0.0, -self.sy)
        self.row_y: Vec3 = (-self.sp * self.sy, self.cp, -self.sp * self.cy)
        self.ray: Vec3 = (self.cp * self.sy, self.sp, self.cp * self.cy)

    def camera_point(self, p: Vec3) -> Vec3:
        x, y, z = sub(p, self.center)
        x1 = self.cy * x - self.sy * z
        z1 = self.sy * x + self.cy * z
        y2 = self.cp * y - self.sp * z1
        z2 = self.sp * y + self.cp * z1
        return (x1, y2, z2)

    def screen(self, p: Vec3) -> tuple[float, float, float]:
        x, y, z = self.camera_point(p)
        return (self.ox + x * self.scale, self.oy - y * self.scale, z)

    def ray_base(self, sx: float, sy: float) -> Vec3:
        """World-space origin (at depth 0) of the orthographic ray through a
        screen pixel; the ray direction is the shared self.ray. Larger depth =
        nearer the camera, so the nearest visible surface has the GREATEST t."""
        a = (sx - self.ox) / self.scale
        b = (self.oy - sy) / self.scale
        return (
            self.center[0] + a * self.row_x[0] + b * self.row_y[0],
            self.center[1] + a * self.row_x[1] + b * self.row_y[1],
            self.center[2] + a * self.row_x[2] + b * self.row_y[2],
        )


def draw_ellipse(
    img: Image,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    color: tuple[int, int, int],
    alpha: float,
) -> None:
    rx = max(1.0, abs(rx))
    ry = max(1.0, abs(ry))
    min_x = max(0, math.floor(cx - rx))
    max_x = min(img.width - 1, math.ceil(cx + rx))
    min_y = max(0, math.floor(cy - ry))
    max_y = min(img.height - 1, math.ceil(cy + ry))
    for y in range(min_y, max_y + 1):
        ny = (y + 0.5 - cy) / ry
        for x in range(min_x, max_x + 1):
            nx = (x + 0.5 - cx) / rx
            d = nx * nx + ny * ny
            if d <= 1:
                local = 1.0 - d
                img.blend(x, y, shade(color, 0.82 + local * 0.28), alpha)


def fit_camera(
    camera: Camera,
    parts: list[dict],
    width: int,
    height: int,
    padding: int,
    focus: Vec3 | None = None,
    span: float | None = None,
    terrain: dict | None = None,
) -> None:
    corners = [corner for part in parts for corner in box_corners(part)]
    if terrain is not None:
        corners.extend(terrain_bounds_corners(terrain))
    if not corners:
        camera.center = (0, 0, 0)
        camera.scale = 1
        camera.ox = width / 2
        camera.oy = height / 2
        return

    # --focus points the camera at a specific world point (e.g. a room inside a
    # sprawling terrain-embedded build); --span sets how many world units to frame
    # so the auto-fit can't be blown out by far-flung tunnel/approach parts.
    if focus is not None:
        camera.center = focus
        if span is not None:
            camera.scale = (min(width, height) - padding * 2) / max(0.01, span)
            camera.ox = width / 2
            camera.oy = height / 2
            return
    else:
        camera.center = (
            sum(p[0] for p in corners) / len(corners),
            sum(p[1] for p in corners) / len(corners),
            sum(p[2] for p in corners) / len(corners),
        )
    projected = [camera.camera_point(p) for p in corners]
    min_x = min(p[0] for p in projected)
    max_x = max(p[0] for p in projected)
    min_y = min(p[1] for p in projected)
    max_y = max(p[1] for p in projected)
    span_x = max(0.01, max_x - min_x)
    span_y = max(0.01, max_y - min_y)
    camera.scale = min((width - padding * 2) / span_x, (height - padding * 2) / span_y)
    camera.ox = width / 2 - ((min_x + max_x) / 2) * camera.scale
    camera.oy = height / 2 + ((min_y + max_y) / 2) * camera.scale


def part_color_alpha(part: dict) -> tuple[tuple[int, int, int], float]:
    alpha = max(0.0, min(1.0, 1.0 - float(part.get("transparency") or 0)))
    color = part_color(part)
    if "Neon" in part.get("material", ""):
        color = blend_rgb(color, (255, 255, 255), 0.18)
        alpha = min(1.0, alpha + 0.12)
    return color, alpha


def draw_part(
    img: Image, camera: Camera, part: dict, zbuf: list[float], write_depth: bool
) -> None:
    """Rasterise one part through the depth buffer. For every covered pixel we
    cast the orthographic ray, find the camera-facing surface depth, and only
    paint when that surface is at least as near as whatever the buffer already
    holds -- so a part that is geometrically behind (or fully inside) another can
    never paint over it, regardless of where its centre sits."""
    color, alpha = part_color_alpha(part)
    if alpha <= 0.02:
        return
    center = part_center(part)
    size = part_size(part)
    rot = part_rotation(part)
    shape = part.get("shape", "")

    scr = [camera.screen(c) for c in box_corners(part)]
    min_x = max(0, math.floor(min(s[0] for s in scr)))
    max_x = min(img.width - 1, math.ceil(max(s[0] for s in scr)))
    min_y = max(0, math.floor(min(s[1] for s in scr)))
    max_y = min(img.height - 1, math.ceil(max(s[1] for s in scr)))
    if min_x > max_x or min_y > max_y:
        return

    center_depth = camera.screen(center)[2]
    depth_shade = 0.84 + max(-0.12, min(0.14, center_depth * 0.025))
    flat_color = shade(color, depth_shade)
    half = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    is_ball = "Ball" in shape
    is_cyl = (not is_ball) and "Cylinder" in shape
    r_ball = min(size) / 2.0
    rey, rez = size[1] / 2.0, size[2] / 2.0
    # For a ball we keep the old radial fake-shading; precompute screen radius.
    ball_sx, ball_sy = camera.screen(center)[0], camera.screen(center)[1]
    ball_r_screen = max(1.0, r_ball * camera.scale)
    direction = camera.ray
    local_dir = mat_t_vec(rot, direction)  # ray dir in part frame (constant per part)

    for py in range(min_y, max_y + 1):
        for px in range(min_x, max_x + 1):
            base = camera.ray_base(px + 0.5, py + 0.5)
            if is_ball:
                depth = ray_sphere_depth(base, direction, center, r_ball)
            elif is_cyl:
                local_o = mat_t_vec(rot, sub(base, center))
                depth = ray_cylinder_depth(local_o, local_dir, half[0], rey, rez)
            else:
                local_o = mat_t_vec(rot, sub(base, center))
                depth = ray_box_depth(local_o, local_dir, half)
            if depth is None:
                continue
            idx = py * img.width + px
            if depth < zbuf[idx]:
                continue
            if is_ball:
                nx = (px + 0.5 - ball_sx) / ball_r_screen
                ny = (py + 0.5 - ball_sy) / ball_r_screen
                local = max(0.0, 1.0 - (nx * nx + ny * ny))
                pixel = shade(color, 0.82 + local * 0.28)
            else:
                pixel = flat_color
            if alpha >= 0.999:
                img.set(px, py, pixel)
                if write_depth:
                    zbuf[idx] = depth
            else:
                img.blend(px, py, pixel, alpha)


# --- Terrain heightfield --------------------------------------------------
# Optional "terrain" snapshot contract (separate from BaseParts, which never
# model the ground): a regular grid of world-space heights, triangulated here
# into a flat-shaded mesh and rasterised through the SAME per-pixel z-buffer as
# parts, so a structure sitting on a hillside occludes/is-occluded-by the
# ground correctly instead of floating over a flat plane.
#
#   "terrain": {
#     "originX": -50, "originZ": -50, "cellSize": 4, "rows": 26, "cols": 26,
#     "heights": [[y, y, ...], ...],          // rows x cols, row-major (Z, X)
#     "colors":  [[{"r":,"g":,"b":}, ...], ...]   // optional, same shape
#   }
#
# Lighting is a single fixed directional light (fake — there is no real-time
# lighting model here, same caveat as parts); it exists only so slopes read as
# slopes instead of a flat-shaded green plane.
TERRAIN_LIGHT = normalize((0.35, 0.82, 0.45))
TERRAIN_DEFAULT_COLOR = (90, 130, 70)


def terrain_vertex(terrain: dict, row: int, col: int) -> Vec3:
    origin_x = float(terrain["originX"])
    origin_z = float(terrain["originZ"])
    cell = float(terrain["cellSize"])
    h = float(terrain["heights"][row][col])
    return (origin_x + col * cell, h, origin_z + row * cell)


def terrain_vertex_color(terrain: dict, row: int, col: int) -> tuple[int, int, int]:
    colors = terrain.get("colors")
    if colors:
        c = colors[row][col]
        return (int(c["r"]), int(c["g"]), int(c["b"]))
    return TERRAIN_DEFAULT_COLOR


def terrain_triangles(
    terrain: dict,
) -> list[tuple[Vec3, Vec3, Vec3, tuple[int, int, int], tuple[int, int, int], tuple[int, int, int]]]:
    rows = int(terrain["rows"])
    cols = int(terrain["cols"])
    verts = [[terrain_vertex(terrain, r, c) for c in range(cols)] for r in range(rows)]
    cols3 = [[terrain_vertex_color(terrain, r, c) for c in range(cols)] for r in range(rows)]
    tris = []
    for r in range(rows - 1):
        for c in range(cols - 1):
            p00, p10, p01, p11 = verts[r][c], verts[r][c + 1], verts[r + 1][c], verts[r + 1][c + 1]
            c00, c10, c01, c11 = cols3[r][c], cols3[r][c + 1], cols3[r + 1][c], cols3[r + 1][c + 1]
            tris.append((p00, p10, p01, c00, c10, c01))
            tris.append((p10, p11, p01, c10, c11, c01))
    return tris


def terrain_bounds_corners(terrain: dict) -> list[Vec3]:
    rows = int(terrain["rows"])
    cols = int(terrain["cols"])
    heights = terrain["heights"]
    min_h = min(min(row) for row in heights)
    max_h = max(max(row) for row in heights)
    ox, oz, cell = float(terrain["originX"]), float(terrain["originZ"]), float(terrain["cellSize"])
    x0, x1 = ox, ox + (cols - 1) * cell
    z0, z1 = oz, oz + (rows - 1) * cell
    return [(x, y, z) for x in (x0, x1) for z in (z0, z1) for y in (min_h, max_h)]


def triangle_shade(p0: Vec3, p1: Vec3, p2: Vec3, c0, c1, c2) -> tuple[int, int, int]:
    normal = normalize(cross(sub(p1, p0), sub(p2, p0)))
    if normal[1] < 0:
        normal = (-normal[0], -normal[1], -normal[2])
    light = max(0.0, min(1.0, dot3(normal, TERRAIN_LIGHT)))
    factor = 0.55 + light * 0.65
    avg = tuple(round((c0[i] + c1[i] + c2[i]) / 3) for i in range(3))
    return shade(avg, factor)


def edge2(ax: float, ay: float, bx: float, by: float, px: float, py: float) -> float:
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax)


def draw_triangle(
    img: Image,
    camera: Camera,
    p0: Vec3,
    p1: Vec3,
    p2: Vec3,
    color: tuple[int, int, int],
    zbuf: list[float],
) -> None:
    """Rasterise one flat-shaded triangle through the depth buffer. Orthographic
    projection makes screen position AND camera-space depth affine functions of
    world position, so barycentric weights computed in screen space are exact
    for interpolating depth -- no perspective correction needed."""
    s0, s1, s2 = camera.screen(p0), camera.screen(p1), camera.screen(p2)
    min_x = max(0, math.floor(min(s0[0], s1[0], s2[0])))
    max_x = min(img.width - 1, math.ceil(max(s0[0], s1[0], s2[0])))
    min_y = max(0, math.floor(min(s0[1], s1[1], s2[1])))
    max_y = min(img.height - 1, math.ceil(max(s0[1], s1[1], s2[1])))
    if min_x > max_x or min_y > max_y:
        return
    area = edge2(s0[0], s0[1], s1[0], s1[1], s2[0], s2[1])
    if abs(area) < 1e-9:
        return
    inv_area = 1.0 / area
    for py in range(min_y, max_y + 1):
        yc = py + 0.5
        for px in range(min_x, max_x + 1):
            xc = px + 0.5
            w0 = edge2(s1[0], s1[1], s2[0], s2[1], xc, yc) * inv_area
            w1 = edge2(s2[0], s2[1], s0[0], s0[1], xc, yc) * inv_area
            w2 = 1.0 - w0 - w1
            if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                continue
            depth = w0 * s0[2] + w1 * s1[2] + w2 * s2[2]
            idx = py * img.width + px
            if depth < zbuf[idx]:
                continue
            img.set(px, py, color)
            zbuf[idx] = depth


def draw_terrain(img: Image, camera: Camera, terrain: dict, zbuf: list[float]) -> None:
    for p0, p1, p2, c0, c1, c2 in terrain_triangles(terrain):
        color = triangle_shade(p0, p1, p2, c0, c1, c2)
        draw_triangle(img, camera, p0, p1, p2, color, zbuf)


def render(
    snapshot: dict,
    out: Path,
    width: int = 512,
    height: int = 512,
    yaw: float = -25,
    pitch: float = 22,
    padding: int = 54,
    focus: Vec3 | None = None,
    span: float | None = None,
    terrain: dict | None = None,
) -> None:
    parts = [p for p in snapshot.get("parts", []) if float(p.get("transparency") or 0) < 0.98]
    terrain = terrain if terrain is not None else snapshot.get("terrain")
    camera = Camera(yaw, pitch)
    fit_camera(camera, parts, width, height, padding, focus, span, terrain)
    img = Image(width, height, (24, 25, 30))

    # Per-pixel depth buffer (greater depth = nearer the camera). Opaque parts are
    # depth-tested AND depth-written in any order; translucent parts are then
    # painted strictly back-to-front, depth-tested against the opaque surfaces but
    # not writing depth, so glass over glass still blends correctly. This replaces
    # the old whole-part centroid sort, which let a nearer-centred part paint over
    # one it was actually behind (or nested inside).
    zbuf = [-math.inf] * (width * height)
    if terrain is not None:
        draw_terrain(img, camera, terrain, zbuf)
    else:
        # No ground geometry supplied -- keep the old fake contact shadow so
        # parts-only previews don't look like they're floating in a void.
        for radius, alpha in [(78, 0.12), (54, 0.1), (32, 0.08)]:
            draw_ellipse(img, width / 2, height - padding * 0.7, radius, radius * 0.18, (0, 0, 0), alpha)

    opaque = [p for p in parts if float(p.get("transparency") or 0) <= 0.001]
    translucent = [p for p in parts if float(p.get("transparency") or 0) > 0.001]
    for part in opaque:
        draw_part(img, camera, part, zbuf, write_depth=True)
    translucent.sort(key=lambda p: camera.screen(part_center(p))[2])
    for part in translucent:
        draw_part(img, camera, part, zbuf, write_depth=False)
    img.save_png(out)


def parse_focus(text: str | None) -> Vec3 | None:
    if not text:
        return None
    try:
        fx, fy, fz = (float(v) for v in text.split(","))
    except ValueError:
        raise SystemExit('--focus must be "x,y,z", e.g. --focus "54,12,-172".')
    return (fx, fy, fz)


def add_camera_args(parser: argparse.ArgumentParser) -> None:
    """Camera flags shared by this CLI and any per-game front-end."""
    parser.add_argument("--out", type=Path, default=Path("output") / "model_preview.png")
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--yaw", type=float, default=-25)
    parser.add_argument("--pitch", type=float, default=22)
    parser.add_argument("--padding", type=int, default=54)
    parser.add_argument(
        "--focus",
        help='Point the camera at a world position "x,y,z" instead of the model centroid '
        "(use for a room inside a sprawling terrain-embedded build).",
    )
    parser.add_argument(
        "--span",
        type=float,
        help="World units to frame around --focus (zoom). Larger = more pulled back. "
        "Tip: for a room interior use a top-down plan view (--yaw 0 --pitch 88).",
    )
    parser.add_argument(
        "--terrain",
        type=Path,
        help="Optional terrain heightfield JSON (see README) to render as ground, merged "
        "with --snapshot. If the snapshot itself already has a top-level \"terrain\" key, "
        "this flag is not needed.",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a parts snapshot JSON to a PNG.")
    parser.add_argument("--snapshot", required=True, help="JSON snapshot to render.")
    add_camera_args(parser)
    args = parser.parse_args()
    snapshot = json.loads(Path(args.snapshot).read_text())
    terrain = json.loads(args.terrain.read_text()) if args.terrain else None
    render(
        snapshot,
        args.out,
        args.width,
        args.height,
        args.yaw,
        args.pitch,
        args.padding,
        parse_focus(args.focus),
        args.span,
        terrain,
    )
    print(f"Rendered {snapshot.get('label', 'model')} ({snapshot.get('partCount', 0)} parts) to {args.out}")


if __name__ == "__main__":
    main()
