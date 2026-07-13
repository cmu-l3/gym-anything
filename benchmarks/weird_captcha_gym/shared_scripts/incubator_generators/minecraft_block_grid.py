from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "minecraft_block_grid"
GRID = 5
CANVAS_WIDTH = 900
CANVAS_HEIGHT = 500
TILE_W = 78
TILE_H = 38
CUBE_H = 38


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _rotate(x: int, y: int, orientation: int) -> tuple[int, int]:
    orientation %= 4
    if orientation == 0:
        return x, y
    if orientation == 1:
        return GRID - 1 - y, x
    if orientation == 2:
        return GRID - 1 - x, GRID - 1 - y
    return y, GRID - 1 - x


def _inverse(rx: int, ry: int, orientation: int) -> tuple[int, int]:
    orientation %= 4
    if orientation == 0:
        return rx, ry
    if orientation == 1:
        return ry, GRID - 1 - rx
    if orientation == 2:
        return GRID - 1 - rx, GRID - 1 - ry
    return GRID - 1 - ry, rx


def _neighbor(x: int, y: int, orientation: int, axis: str) -> tuple[int, int]:
    rx, ry = _rotate(x, y, orientation)
    if axis == "x":
        rx += 1
    else:
        ry += 1
    return _inverse(rx, ry, orientation)


def _project(x: int, y: int, z: int, orientation: int) -> tuple[float, float]:
    rx, ry = _rotate(x, y, orientation)
    sx = CANVAS_WIDTH / 2 + (rx - ry) * TILE_W / 2
    sy = 55 + (rx + ry) * TILE_H / 2 + (2 - z) * CUBE_H
    return sx, sy


def _polygon_faces(voxels: dict[str, dict[str, Any]], orientation: int) -> list[dict[str, Any]]:
    occupied = {(int(v["x"]), int(v["y"]), int(v["z"])) for v in voxels.values()}
    ordered = sorted(
        voxels.values(),
        key=lambda voxel: (*(_rotate(int(voxel["x"]), int(voxel["y"]), orientation)), int(voxel["z"])),
    )
    ordered.sort(key=lambda voxel: (
        sum(_rotate(int(voxel["x"]), int(voxel["y"]), orientation)),
        int(voxel["z"]),
        _rotate(int(voxel["x"]), int(voxel["y"]), orientation)[0],
    ))
    faces: list[dict[str, Any]] = []
    for voxel in ordered:
        x, y, z = int(voxel["x"]), int(voxel["y"]), int(voxel["z"])
        sx, sy = _project(x, y, z, orientation)
        nx = _neighbor(x, y, orientation, "x")
        ny = _neighbor(x, y, orientation, "y")
        if (nx[0], nx[1], z) not in occupied:
            faces.append({"voxel_id": voxel["id"], "face": "right", "points": [(sx, sy), (sx + TILE_W / 2, sy + TILE_H / 2), (sx + TILE_W / 2, sy + TILE_H / 2 + CUBE_H), (sx, sy + CUBE_H)]})
        if (ny[0], ny[1], z) not in occupied:
            faces.append({"voxel_id": voxel["id"], "face": "left", "points": [(sx, sy), (sx - TILE_W / 2, sy + TILE_H / 2), (sx - TILE_W / 2, sy + TILE_H / 2 + CUBE_H), (sx, sy + CUBE_H)]})
        if (x, y, z + 1) not in occupied:
            faces.append({"voxel_id": voxel["id"], "face": "top", "points": [(sx, sy), (sx + TILE_W / 2, sy + TILE_H / 2), (sx, sy + TILE_H), (sx - TILE_W / 2, sy + TILE_H / 2)]})
    return faces


def _point_in_polygon(x: float, y: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if ((yi > y) != (yj > y)) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def _raycast(voxels: dict[str, dict[str, Any]], orientation: int, x: float, y: float) -> dict[str, Any] | None:
    for face in reversed(_polygon_faces(voxels, orientation)):
        if _point_in_polygon(x, y, face["points"]):
            return {"voxel_id": face["voxel_id"], "face": face["face"]}
    return None


def _find_point(voxels: dict[str, dict[str, Any]], orientation: int, voxel_id: str) -> tuple[float, float, str] | None:
    faces = [face for face in _polygon_faces(voxels, orientation) if face["voxel_id"] == voxel_id]
    for face in reversed(faces):
        points = face["points"]
        cx = sum(point[0] for point in points) / len(points)
        cy = sum(point[1] for point in points) / len(points)
        samples = [(cx, cy)]
        for px, py in points:
            samples.append(((cx * 3 + px) / 4, (cy * 3 + py) / 4))
        for sx, sy in samples:
            hit = _raycast(voxels, orientation, sx, sy)
            if hit and hit["voxel_id"] == voxel_id:
                return round(sx, 2), round(sy, 2), str(hit["face"])
    return None


def _voxel(voxel_id: str, x: int, y: int, z: int, material: str, role: str = "pile") -> dict[str, Any]:
    return {"id": voxel_id, "x": x, "y": y, "z": z, "material": material, "role": role}


def _build_layout(rng: random.Random, target_count: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]] | None:
    voxels: dict[str, dict[str, Any]] = {}
    reserved_columns: set[tuple[int, int]] = set()
    target_specs: list[dict[str, Any]] = []
    remaining_orientations = [1, 2, 3]
    rng.shuffle(remaining_orientations)
    orientations = [0, *remaining_orientations]
    for target_index in range(target_count):
        target_view = orientations[target_index]
        found = False
        candidates = [(x, y) for x in range(1, 4) for y in range(1, 4)]
        rng.shuffle(candidates)
        for x, y in candidates:
            rx, ry = _rotate(x, y, target_view)
            if rx >= GRID - 1:
                continue
            blocker_x, blocker_y = _inverse(rx + 1, ry, target_view)
            screen_x, screen_y = _inverse(rx, min(GRID - 1, ry + 1), target_view)
            columns = {(x, y), (blocker_x, blocker_y)}
            if target_index == 0:
                columns.add((screen_x, screen_y))
            if any(column in reserved_columns for column in columns) or len(columns) != (3 if target_index == 0 else 2):
                continue
            reserved_columns.update(columns)
            target_id = f"diamond-{target_index}-{rng.randint(100, 999)}"
            blocker_id = f"blocker-{target_index}-{rng.randint(100, 999)}"
            cap_id = f"cap-{target_index}-{rng.randint(100, 999)}"
            voxels[target_id] = _voxel(target_id, x, y, 1, "diamond", "target")
            voxels[blocker_id] = _voxel(blocker_id, blocker_x, blocker_y, 1, "stone", "blocker")
            voxels[cap_id] = _voxel(cap_id, x, y, 2, "stone", "cap")
            if target_index == 0:
                screen_id = f"screen-{rng.randint(100, 999)}"
                voxels[screen_id] = _voxel(screen_id, screen_x, screen_y, 1, "stone", "screen")
            target_specs.append({
                "target_id": target_id,
                "blocker_id": blocker_id,
                "target_view": target_view,
                "blocker_view": (target_view + 1) % 4,
            })
            found = True
            break
        if not found:
            return None

    hazard_columns = [(x, y) for x in range(GRID) for y in range(GRID) if (x, y) not in reserved_columns]
    rng.shuffle(hazard_columns)
    lava_column = hazard_columns.pop()
    support_column = hazard_columns.pop()
    for y in range(GRID):
        for x in range(GRID):
            material = "stone"
            role = "foundation"
            if (x, y) == lava_column:
                material, role = "lava", "hazard"
            elif (x, y) == support_column:
                material, role = "support", "fragile_support"
            voxel_id = f"base-{x}-{y}-{rng.randint(10, 99)}"
            voxels[voxel_id] = _voxel(voxel_id, x, y, 0, material, role)

    simulation = dict(voxels)
    solution_steps: list[dict[str, Any]] = []
    for spec in target_specs:
        blocker_point = _find_point(simulation, spec["blocker_view"], spec["blocker_id"])
        if blocker_point is None:
            return None
        solution_steps.append({
            "kind": "mine",
            "orientation": spec["blocker_view"],
            "voxel_id": spec["blocker_id"],
            "click": [blocker_point[0], blocker_point[1]],
            "face": blocker_point[2],
        })
        del simulation[spec["blocker_id"]]
        target_point = _find_point(simulation, spec["target_view"], spec["target_id"])
        if target_point is None:
            return None
        solution_steps.append({
            "kind": "extract",
            "orientation": spec["target_view"],
            "voxel_id": spec["target_id"],
            "click": [target_point[0], target_point[1]],
            "face": target_point[2],
        })
        del simulation[spec["target_id"]]

    lava_id = next(voxel_id for voxel_id, voxel in voxels.items() if voxel["material"] == "lava")
    lava_point = _find_point(voxels, 0, lava_id)
    if lava_point is None:
        return None
    initial_visible_targets = sum(_find_point(voxels, 0, spec["target_id"]) is not None for spec in target_specs)
    if initial_visible_targets >= target_count:
        return None
    return list(voxels.values()), solution_steps, {
        "orientation": 0,
        "voxel_id": lava_id,
        "click": [lava_point[0], lava_point[1]],
        "face": lava_point[2],
    }


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    base_rng = random.Random(_seed_int(seed, MECHANIC_ID))
    target_count = base_rng.choice((2, 3))
    built = None
    for attempt in range(120):
        rng = random.Random(_seed_int(seed, f"{MECHANIC_ID}|layout|{attempt}"))
        built = _build_layout(rng, target_count)
        if built is not None:
            palette = rng.choice(("cavern", "deep-slate", "ember"))
            break
    if built is None:
        raise RuntimeError("could not generate a ray-solvable voxel extraction mine")
    voxels, solution_steps, edge_case = built
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "")
    durability = target_count * 2 + 2
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Rotate the mine, expose every diamond, and extract it without breaking the support lattice.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "generator": {"name": "isometric_voxel_extraction_mine_v1", "variant_count": 9_000_000_000},
        "palette": palette,
        "grid_size": [GRID, GRID, 3],
        "canvas_size": [CANVAS_WIDTH, CANVAS_HEIGHT],
        "voxels": voxels,
        "starting_orientation": 0,
        "starting_durability": durability,
        "target_count": target_count,
        "submit_label": "EXIT MINE",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "voxels": voxels,
        "diamond_ids": sorted(voxel["id"] for voxel in voxels if voxel["material"] == "diamond"),
        "starting_orientation": 0,
        "starting_durability": durability,
        "solution_steps": solution_steps,
        "edge_case_hit": edge_case,
        "projection": {"width": CANVAS_WIDTH, "height": CANVAS_HEIGHT, "tile_w": TILE_W, "tile_h": TILE_H, "cube_h": CUBE_H},
        "variant_count": 9_000_000_000,
    }
    assert len(ground_truth["diamond_ids"]) == target_count
    assert len(solution_steps) == target_count * 2
    return public_state, ground_truth
