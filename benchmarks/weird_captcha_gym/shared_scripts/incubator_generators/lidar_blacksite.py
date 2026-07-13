from __future__ import annotations

import copy
import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "lidar_blacksite"
GRID_WIDTH = 15
GRID_HEIGHT = 11
TILE = 1.2
WORLD_WIDTH = GRID_WIDTH * TILE
WORLD_HEIGHT = GRID_HEIGHT * TILE
PLAYER_RADIUS = .22
LAYOUTS = (
    {"route": ((1, 9), (6, 9), (6, 6), (11, 6), (11, 2), (8, 2), (13, 2)), "beacon_index": 5, "scan_indices": (0, 2, 4, 5)},
    {"route": ((13, 9), (9, 9), (9, 5), (4, 5), (4, 2), (7, 2), (1, 2)), "beacon_index": 5, "scan_indices": (0, 2, 4, 5)},
    {"route": ((2, 2), (2, 7), (6, 7), (6, 3), (12, 3), (12, 7), (13, 7), (13, 9)), "beacon_index": 5, "scan_indices": (0, 2, 4, 5)},
    {"route": ((12, 9), (12, 6), (8, 6), (8, 2), (3, 2), (3, 7), (1, 7), (1, 9)), "beacon_index": 5, "scan_indices": (0, 2, 4, 5)},
)
PALETTES = (
    {"name": "phosphor_crypt", "void": "#020708", "panel": "#081615", "point": "#68f5c4", "hot": "#ffcf65", "danger": "#ff625e", "cold": "#66cfff"},
    {"name": "cobalt_morgue", "void": "#02060b", "panel": "#091423", "point": "#7de8ff", "hot": "#ffd36c", "danger": "#ff6f75", "cold": "#7da7ff"},
    {"name": "amber_bunker", "void": "#090603", "panel": "#1a1007", "point": "#ffd06a", "hot": "#78f0c2", "danger": "#ff675c", "cold": "#6ec6ff"},
    {"name": "violet_sonar", "void": "#07040c", "panel": "#171021", "point": "#c38dff", "hot": "#ffcb69", "danger": "#ff6377", "cold": "#6de7e0"},
)
# Core visible construction space. Each of the two chamber occluders chooses
# one of three independent half sizes. Decorative wall height/tone draws are
# deliberately excluded because they do not change the navigable geometry.
VARIANT_COUNT = len(LAYOUTS) * 2 * len(PALETTES) * (3 ** 2)


def _seed_int(seed: str, salt: str) -> int:
    return int.from_bytes(hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).digest()[:8], "big")


def _cells_between(first: tuple[int, int], second: tuple[int, int]) -> list[tuple[int, int]]:
    if first[0] != second[0] and first[1] != second[1]:
        raise ValueError("facility route segment must be axis aligned")
    dx = 0 if first[0] == second[0] else (1 if second[0] > first[0] else -1)
    dy = 0 if first[1] == second[1] else (1 if second[1] > first[1] else -1)
    output = []
    current = first
    while True:
        output.append(current)
        if current == second:
            return output
        current = (current[0] + dx, current[1] + dy)


def _transform_cell(cell: tuple[int, int], mirror: int) -> tuple[int, int]:
    return (GRID_WIDTH - 1 - cell[0], cell[1]) if mirror < 0 else cell


def _center(cell: tuple[int, int]) -> tuple[float, float]:
    return ((cell[0] + .5) * TILE, (cell[1] + .5) * TILE)


def _merge_intervals(values: list[tuple[float, float]]) -> list[tuple[float, float]]:
    output: list[tuple[float, float]] = []
    for start, end in sorted(values):
        if output and abs(output[-1][1] - start) <= 1e-9:
            output[-1] = (output[-1][0], end)
        else:
            output.append((start, end))
    return output


def _walls_from_walkable(walkable: set[tuple[int, int]], rng: random.Random) -> list[dict[str, Any]]:
    horizontal: dict[float, list[tuple[float, float]]] = {}
    vertical: dict[float, list[tuple[float, float]]] = {}
    for column, row in walkable:
        x0, x1, y0, y1 = column * TILE, (column + 1) * TILE, row * TILE, (row + 1) * TILE
        if (column, row - 1) not in walkable:
            horizontal.setdefault(y0, []).append((x0, x1))
        if (column, row + 1) not in walkable:
            horizontal.setdefault(y1, []).append((x0, x1))
        if (column - 1, row) not in walkable:
            vertical.setdefault(x0, []).append((y0, y1))
        if (column + 1, row) not in walkable:
            vertical.setdefault(x1, []).append((y0, y1))
    segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    for y, intervals in horizontal.items():
        segments.extend(((start, y), (end, y)) for start, end in _merge_intervals(intervals))
    for x, intervals in vertical.items():
        segments.extend(((x, start), (x, end)) for start, end in _merge_intervals(intervals))
    walls = []
    for index, (first, second) in enumerate(sorted(segments)):
        walls.append({
            "id": f"wall-{index + 1:02d}",
            "a": [round(first[0], 4), round(first[1], 4)],
            "b": [round(second[0], 4), round(second[1], 4)],
            "height": round(rng.choice((2.7, 3.0, 3.3)), 2),
            "tone": rng.randrange(4),
        })
    return walls


def _cross(first: tuple[float, float], second: tuple[float, float]) -> float:
    return first[0] * second[1] - first[1] * second[0]


def ray_segment(origin: tuple[float, float], direction: tuple[float, float], first: tuple[float, float], second: tuple[float, float]) -> float | None:
    segment = (second[0] - first[0], second[1] - first[1])
    denominator = _cross(direction, segment)
    if abs(denominator) <= 1e-10:
        return None
    offset = (first[0] - origin[0], first[1] - origin[1])
    distance = _cross(offset, segment) / denominator
    amount = _cross(offset, direction) / denominator
    return distance if distance >= 0 and -1e-9 <= amount <= 1 + 1e-9 else None


def ray_aabb(origin: tuple[float, float], direction: tuple[float, float], box: dict[str, Any]) -> float | None:
    minimum = box["min"]
    maximum = box["max"]
    near, far = -math.inf, math.inf
    for axis in range(2):
        if abs(direction[axis]) <= 1e-12:
            if origin[axis] < float(minimum[axis]) or origin[axis] > float(maximum[axis]):
                return None
            continue
        first = (float(minimum[axis]) - origin[axis]) / direction[axis]
        second = (float(maximum[axis]) - origin[axis]) / direction[axis]
        near, far = max(near, min(first, second)), min(far, max(first, second))
        if near > far:
            return None
    if far < 0:
        return None
    return max(0.0, near)


def nearest_hit(origin: tuple[float, float], angle: float, walls: list[dict[str, Any]], occluders: list[dict[str, Any]], objects: list[dict[str, Any]], maximum_range: float) -> dict[str, Any] | None:
    direction = (math.cos(angle), math.sin(angle))
    candidates: list[tuple[float, int, str, str]] = []
    for wall in walls:
        distance = ray_segment(origin, direction, tuple(wall["a"]), tuple(wall["b"]))
        if distance is not None:
            candidates.append((distance, 0, str(wall["id"]), "wall"))
    for item in occluders:
        distance = ray_aabb(origin, direction, item)
        if distance is not None:
            candidates.append((distance, 1, str(item["id"]), "occluder"))
    for item in objects:
        distance = ray_aabb(origin, direction, item)
        if distance is not None:
            candidates.append((distance, 2, str(item["id"]), str(item["kind"])))
    if not candidates:
        return None
    distance, _priority, item_id, kind = min(candidates)
    if distance > maximum_range:
        return None
    return {"id": item_id, "kind": kind, "distance": distance, "x": origin[0] + direction[0] * distance, "y": origin[1] + direction[1] * distance}


def _distance_point_segment(point: tuple[float, float], first: tuple[float, float], second: tuple[float, float]) -> float:
    dx, dy = second[0] - first[0], second[1] - first[1]
    denominator = dx * dx + dy * dy
    amount = 0.0 if denominator <= 1e-12 else max(0.0, min(1.0, ((point[0] - first[0]) * dx + (point[1] - first[1]) * dy) / denominator))
    nearest = (first[0] + dx * amount, first[1] + dy * amount)
    return math.hypot(point[0] - nearest[0], point[1] - nearest[1])


def position_clear(point: tuple[float, float], radius: float, walls: list[dict[str, Any]], occluders: list[dict[str, Any]]) -> bool:
    if point[0] - radius < 0 or point[0] + radius > WORLD_WIDTH or point[1] - radius < 0 or point[1] + radius > WORLD_HEIGHT:
        return False
    if any(_distance_point_segment(point, tuple(wall["a"]), tuple(wall["b"])) < radius - 1e-8 for wall in walls):
        return False
    for item in occluders:
        nearest_x = max(float(item["min"][0]), min(point[0], float(item["max"][0])))
        nearest_y = max(float(item["min"][1]), min(point[1], float(item["max"][1])))
        if math.hypot(point[0] - nearest_x, point[1] - nearest_y) < radius - 1e-8:
            return False
    return True


def line_of_sight(first: tuple[float, float], second: tuple[float, float], walls: list[dict[str, Any]], occluders: list[dict[str, Any]]) -> bool:
    distance = math.dist(first, second)
    if distance <= 1e-9:
        return True
    angle = math.atan2(second[1] - first[1], second[0] - first[0])
    direction = (math.cos(angle), math.sin(angle))
    for wall in walls:
        hit = ray_segment(first, direction, tuple(wall["a"]), tuple(wall["b"]))
        if hit is not None and hit < distance - .04:
            return False
    for item in occluders:
        hit = ray_aabb(first, direction, item)
        if hit is not None and hit < distance - .04:
            return False
    return True


def _route_length(points: list[tuple[float, float]]) -> float:
    return sum(math.dist(first, second) for first, second in zip(points, points[1:]))


def _route_samples(points: list[tuple[float, float]], spacing: float = .08) -> list[tuple[float, float]]:
    samples: list[tuple[float, float]] = []
    for first, second in zip(points, points[1:]):
        steps = max(1, math.ceil(math.dist(first, second) / spacing))
        for index in range(steps + 1):
            amount = index / steps
            samples.append((first[0] + (second[0] - first[0]) * amount, first[1] + (second[1] - first[1]) * amount))
    return samples


def _turn_drift_samples(points: list[tuple[float, float]], drift: float = .12) -> list[tuple[float, float]]:
    samples: list[tuple[float, float]] = []
    for center in points[1:-1]:
        for index in range(16):
            angle = index / 16 * math.tau
            samples.append((center[0] + math.cos(angle) * drift, center[1] + math.sin(angle) * drift))
    return samples


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    task_id = str(task.get("id") or "lidar_blacksite_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}|phosphor-v1".encode("utf-8")).hexdigest()[:14]
    layout_index = rng.randrange(len(LAYOUTS))
    mirror = rng.choice((-1, 1))
    palette = copy.deepcopy(rng.choice(PALETTES))
    layout = LAYOUTS[layout_index]
    cell_route = [_transform_cell(cell, mirror) for cell in layout["route"]]
    walkable: set[tuple[int, int]] = set()
    for first, second in zip(cell_route, cell_route[1:]):
        walkable.update(_cells_between(first, second))
    beacon_cell = cell_route[int(layout["beacon_index"])]
    # Open a real room around the beacon. Two unused corners become occluders;
    # the centerline and its cardinal approaches remain clear.
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            cell = (beacon_cell[0] + dx, beacon_cell[1] + dy)
            if 0 < cell[0] < GRID_WIDTH - 1 and 0 < cell[1] < GRID_HEIGHT - 1:
                walkable.add(cell)
    walls = _walls_from_walkable(walkable, rng)
    route_points = [_center(cell) for cell in cell_route]
    start = route_points[0]
    beacon_center = route_points[int(layout["beacon_index"])]
    exit_center = route_points[-1]
    first_heading = math.atan2(route_points[1][1] - start[1], route_points[1][0] - start[0])
    route_segments = list(zip(route_points, route_points[1:]))
    chamber_candidates = [
        (beacon_center[0] + dx * .82, beacon_center[1] + dy * .82)
        for dx in (-1, 1)
        for dy in (-1, 1)
    ]
    # Keep both crates in corners that are genuinely unused by the full route,
    # including the segment after the beacon. This prevents a mathematically
    # exact waypoint from hiding a too-tight physical turn one tick later.
    ranked_candidates = sorted(
        chamber_candidates,
        key=lambda center: (
            -min(_distance_point_segment(center, first, second) for first, second in route_segments),
            center[0],
            center[1],
        ),
    )
    occluder_centers = ranked_candidates[:2]
    occluders = []
    for index, center in enumerate(occluder_centers, start=1):
        half = .22 + .02 * rng.randrange(3)
        occluders.append({"id": f"crate-{index:02d}", "min": [round(center[0] - half, 4), round(center[1] - half, 4)], "max": [round(center[0] + half, 4), round(center[1] + half, 4)], "height": round(1.2 + .25 * index, 2), "tone": rng.randrange(4)})
    objects = [
        {"id": "verification-beacon", "kind": "beacon", "min": [round(beacon_center[0] - .18, 4), round(beacon_center[1] - .18, 4)], "max": [round(beacon_center[0] + .18, 4), round(beacon_center[1] + .18, 4)], "height": 1.35},
        {"id": "extraction-gate", "kind": "exit", "min": [round(exit_center[0] - .32, 4), round(exit_center[1] - .32, 4)], "max": [round(exit_center[0] + .32, 4), round(exit_center[1] + .32, 4)], "height": 2.3},
    ]
    controls = {
        "tick_ms": 20,
        "move_speed": 1.55,
        "turn_speed_deg": 100.0,
        "player_radius": PLAYER_RADIUS,
        "eye_height": 1.42,
        "scan_range": 8.5,
        "scan_rays": 73,
        "scan_half_angle_deg": 52.0,
        "scan_cooldown_ticks": 7,
        "point_lifetime_ticks": 500,
        "pickup_range": .92,
        "exit_radius": .56,
    }
    requirements = {
        "minimum_scan_count": 4,
        "minimum_scan_stations": 3,
        "station_distance": 2.2,
        "minimum_target_scan_displacement": 5.0,
        "minimum_travel_distance": 12.0,
        "minimum_key_transitions": 14,
        "minimum_session_ticks": 320,
        "maximum_session_ticks": 5000,
        "maximum_event_gap_ticks": 1100,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt": "Map the lightless facility with fading LIDAR returns. Recover the verification beacon hidden beyond occlusion and physically carry it to extraction.",
        "submit_label": "VERIFY EXTRACTION",
        "generator": {"name": "procedural_lidar_blacksite_v1", "variant_count": VARIANT_COUNT, "variant_count_kind": "4 layouts × 2 mirrors × 4 palettes × 3² independent occluder sizes; decorative wall height/tone excluded"},
        "palette": palette,
        "world": {"width": WORLD_WIDTH, "height": WORLD_HEIGHT, "wall_height": 3.0},
        "walls": copy.deepcopy(walls),
        "occluders": copy.deepcopy(occluders),
        "objects": copy.deepcopy(objects),
        "initial_player": {"x": round(start[0], 4), "y": round(start[1], 4), "heading_millirad": round(first_heading * 1000)},
        "controls": controls,
        "requirements": requirements,
        "rules": [
            "Hold W/S to move, A/D to strafe, and the arrow keys or Q/E to turn. Movement uses swept-circle wall collision.",
            "Click the viewport or SCAN PULSE to cast a real fan of nearest-hit rays. Returns stay anchored in world coordinates and fade with time.",
            "The beacon is occluded from intake. Rescan from materially different positions, approach with clear line of sight, and pick it up within range.",
            "Carry the beacon through the physical facility to the extraction gate. Client positions, ray hits, and completion labels are independently replayed.",
        ],
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "palette": copy.deepcopy(palette),
        "world": public_state["world"],
        "walls": copy.deepcopy(walls),
        "occluders": copy.deepcopy(occluders),
        "objects": copy.deepcopy(objects),
        "initial_player": copy.deepcopy(public_state["initial_player"]),
        "controls": controls,
        "requirements": requirements,
        "variant": {"layout": layout_index, "mirror": mirror, "palette": palette["name"]},
        "solution": {
            "route_points": [[round(x, 4), round(y, 4)] for x, y in route_points],
            "beacon_route_index": int(layout["beacon_index"]),
            "scan_route_indices": list(layout["scan_indices"]),
            "beacon_center": [round(beacon_center[0], 4), round(beacon_center[1], 4)],
            "exit_center": [round(exit_center[0], 4), round(exit_center[1], 4)],
        },
        "variant_count": VARIANT_COUNT,
        "browser_boundary": "The browser receives necessary wall, occluder, beacon-volume, and exit-volume geometry for local rendering; it never receives the hidden route or scan stations. The server replays all geometry independently.",
    }
    assert len(walls) >= 12 and len(occluders) == 2
    assert all(position_clear(point, PLAYER_RADIUS, walls, occluders) for point in route_points)
    # The entire centerline has a 0.12-unit human drift reserve beyond the
    # player radius. The turn-ring check makes the guarantee explicit from
    # either incoming direction instead of testing only perfect waypoints.
    assert all(position_clear(point, PLAYER_RADIUS + .12, walls, occluders) for point in _route_samples(route_points))
    assert all(position_clear(point, PLAYER_RADIUS, walls, occluders) for point in _turn_drift_samples(route_points))
    assert not line_of_sight(start, beacon_center, walls, occluders)
    assert math.dist(start, beacon_center) >= 5.5
    assert line_of_sight(route_points[int(layout["beacon_index"]) - 1], beacon_center, walls, occluders)
    assert _route_length(route_points) >= requirements["minimum_travel_distance"] + 2
    return public_state, ground_truth
