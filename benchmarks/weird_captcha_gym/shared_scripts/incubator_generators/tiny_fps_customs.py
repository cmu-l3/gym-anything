from __future__ import annotations

import hashlib
import json
import math
import random
from collections import deque
from typing import Any


MECHANIC_ID = "tiny_fps_customs"
CREATURE_RADIUS = 0.27
PLAYER_RADIUS = 0.18
MOVE_STEP = 0.25
AMMO = 9

_MAP_ROWS = (
    "#################",
    "#.....#.........#",
    "#.###.#.#####.#.#",
    "#.#...#.....#.#.#",
    "#.#.#####.#.#.#.#",
    "#.#.......#...#.#",
    "#.#####.#######.#",
    "#.....#.......#.#",
    "###.#.###.###.#.#",
    "#...#.....#...#.#",
    "#.#######.#.###.#",
    "#...............#",
    "#################",
)

_SPAWN_CELLS = (
    (14, 1),
    (8, 3),
    (3, 5),
    (13, 5),
    (4, 7),
    (11, 7),
    (2, 9),
    (8, 9),
    (12, 11),
    (15, 11),
)

_PALETTES = (
    ("verdigris", "#43d6b1", "#123f43", "#ffe26c"),
    ("ember", "#ff6b45", "#5a1929", "#ffe9b0"),
    ("ultraviolet", "#a98cff", "#30205f", "#76ffe4"),
    ("brine", "#59b8ff", "#15385f", "#ffb85c"),
    ("lichen", "#b2dc54", "#344b18", "#f8f1cb"),
    ("orchid", "#f06eb7", "#53234b", "#9effee"),
)
_HORNS = ("fork", "spiral", "blade", "antenna")
_MARKS = ("ring", "chevron", "triple-dot", "split-bar")
_STRIPES = ("shoulder", "belly", "none")


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _challenge_id(seed: str) -> str:
    return hashlib.sha256(f"{seed}|{MECHANIC_ID}|v1".encode("utf-8")).hexdigest()[:14]


def _creature_id(seed: str, index: int) -> str:
    return f"traveller-{hashlib.sha256(f'{seed}|creature|{index}'.encode('utf-8')).hexdigest()[:10]}"


def _open_cells(rows: tuple[str, ...]) -> set[tuple[int, int]]:
    return {
        (x, y)
        for y, row in enumerate(rows)
        for x, value in enumerate(row)
        if value == "."
    }


def _layout_variant(
    variant: str,
) -> tuple[tuple[str, ...], tuple[int, int], int, tuple[tuple[int, int], ...]]:
    width = len(_MAP_ROWS[0])
    height = len(_MAP_ROWS)

    def transform_cell(cell: tuple[int, int]) -> tuple[int, int]:
        x, y = cell
        if variant == "mirror_x":
            return width - 1 - x, y
        if variant == "mirror_y":
            return x, height - 1 - y
        if variant == "rotate_180":
            return width - 1 - x, height - 1 - y
        return x, y

    if variant == "mirror_x":
        rows = tuple(row[::-1] for row in _MAP_ROWS)
        angle_mdeg = 180_000
    elif variant == "mirror_y":
        rows = tuple(reversed(_MAP_ROWS))
        angle_mdeg = 0
    elif variant == "rotate_180":
        rows = tuple(row[::-1] for row in reversed(_MAP_ROWS))
        angle_mdeg = 180_000
    else:
        rows = _MAP_ROWS
        angle_mdeg = 0
    return rows, transform_cell((1, 1)), angle_mdeg, tuple(transform_cell(cell) for cell in _SPAWN_CELLS)


def _reachable(start: tuple[int, int], open_cells: set[tuple[int, int]]) -> set[tuple[int, int]]:
    queue: deque[tuple[int, int]] = deque([start])
    visited = {start}
    while queue:
        cell = queue.popleft()
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            candidate = (cell[0] + dx, cell[1] + dy)
            if candidate in open_cells and candidate not in visited:
                visited.add(candidate)
                queue.append(candidate)
    return visited


def _bfs(
    start: tuple[int, int],
    goal: tuple[int, int],
    open_cells: set[tuple[int, int]],
) -> list[tuple[int, int]]:
    queue: deque[tuple[int, int]] = deque([start])
    previous: dict[tuple[int, int], tuple[int, int] | None] = {start: None}
    while queue:
        cell = queue.popleft()
        if cell == goal:
            break
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            candidate = (cell[0] + dx, cell[1] + dy)
            if candidate in open_cells and candidate not in previous:
                previous[candidate] = cell
                queue.append(candidate)
    if goal not in previous:
        raise AssertionError(f"unreachable customs cell {goal}")
    path: list[tuple[int, int]] = []
    cursor: tuple[int, int] | None = goal
    while cursor is not None:
        path.append(cursor)
        cursor = previous[cursor]
    path.reverse()
    return path


def _traits(rng: random.Random, index: int) -> dict[str, Any]:
    palette = _PALETTES[index % len(_PALETTES)]
    return {
        "palette_name": palette[0],
        "body": palette[1],
        "shadow": palette[2],
        "accent": palette[3],
        "horn": _HORNS[(index + rng.randrange(len(_HORNS))) % len(_HORNS)],
        "eyes": 1 + ((index + rng.randrange(3)) % 3),
        "mark": _MARKS[(index * 2 + rng.randrange(len(_MARKS))) % len(_MARKS)],
        "stripe": _STRIPES[(index + rng.randrange(len(_STRIPES))) % len(_STRIPES)],
    }


def _decoy_traits(target: dict[str, Any], pair_index: int) -> dict[str, Any]:
    decoy = dict(target)
    # Each protected traveller is a close visual relative. One prominent trait
    # changes, rather than the palette, so a glance at colour alone is unsafe.
    if pair_index == 0:
        decoy["eyes"] = 1 + (int(target["eyes"]) % 3)
    elif pair_index == 1:
        mark_index = _MARKS.index(str(target["mark"]))
        decoy["mark"] = _MARKS[(mark_index + 1) % len(_MARKS)]
    else:
        horn_index = _HORNS.index(str(target["horn"]))
        decoy["horn"] = _HORNS[(horn_index + 1) % len(_HORNS)]
    return decoy


def _approach_cell(
    target: tuple[int, int],
    open_cells: set[tuple[int, int]],
    occupied: set[tuple[int, int]],
) -> tuple[int, int]:
    for dx, dy in ((-1, 0), (0, -1), (1, 0), (0, 1)):
        candidate = (target[0] + dx, target[1] + dy)
        if candidate in open_cells and candidate not in occupied:
            return candidate
    for dx, dy in ((-1, 0), (0, -1), (1, 0), (0, 1)):
        candidate = (target[0] + dx, target[1] + dy)
        if candidate in open_cells:
            return candidate
    raise AssertionError(f"no firing position for creature at {target}")


def _angle_mdeg(origin: tuple[int, int], target: tuple[int, int]) -> int:
    dx = target[0] - origin[0]
    dy = target[1] - origin[1]
    if (dx, dy) == (1, 0):
        return 0
    if (dx, dy) == (0, 1):
        return 90_000
    if (dx, dy) == (-1, 0):
        return 180_000
    if (dx, dy) == (0, -1):
        return 270_000
    raise AssertionError("solver aim must be cardinal")


def _ray_wall_distance(rows: tuple[str, ...], x: float, y: float, angle_mdeg: int) -> float:
    angle = math.radians(angle_mdeg / 1000)
    dx, dy = math.cos(angle), math.sin(angle)
    map_x, map_y = int(math.floor(x)), int(math.floor(y))
    delta_x = abs(1 / dx) if abs(dx) > 1e-12 else 1e30
    delta_y = abs(1 / dy) if abs(dy) > 1e-12 else 1e30
    if dx < 0:
        step_x, side_x = -1, (x - map_x) * delta_x
    else:
        step_x, side_x = 1, (map_x + 1 - x) * delta_x
    if dy < 0:
        step_y, side_y = -1, (y - map_y) * delta_y
    else:
        step_y, side_y = 1, (map_y + 1 - y) * delta_y
    for _ in range(128):
        if side_x < side_y:
            distance = side_x
            side_x += delta_x
            map_x += step_x
        else:
            distance = side_y
            side_y += delta_y
            map_y += step_y
        if rows[map_y][map_x] == "#":
            return distance
    raise AssertionError("customs ray escaped its bounded map")


def _ray_creature_distance(x: float, y: float, angle_mdeg: int, creature: dict[str, Any]) -> float | None:
    angle = math.radians(angle_mdeg / 1000)
    dx, dy = math.cos(angle), math.sin(angle)
    offset_x = x - float(creature["x"])
    offset_y = y - float(creature["y"])
    b = dx * offset_x + dy * offset_y
    c = offset_x * offset_x + offset_y * offset_y - CREATURE_RADIUS * CREATURE_RADIUS
    discriminant = b * b - c
    if discriminant < 0:
        return None
    distance = -b - math.sqrt(discriminant)
    return distance if distance >= 0.04 else None


def _nearest_hit(
    rows: tuple[str, ...],
    creatures: list[dict[str, Any]],
    alive: set[str],
    x: float,
    y: float,
    angle_mdeg: int,
) -> str | None:
    wall_distance = _ray_wall_distance(rows, x, y, angle_mdeg)
    nearest_id: str | None = None
    nearest_distance = wall_distance
    for creature in creatures:
        creature_id = str(creature["id"])
        if creature_id not in alive:
            continue
        distance = _ray_creature_distance(x, y, angle_mdeg, creature)
        if distance is not None and distance < nearest_distance - 1e-8:
            nearest_distance = distance
            nearest_id = creature_id
    return nearest_id


def _solver_segment(
    current: tuple[int, int],
    creature: dict[str, Any],
    open_cells: set[tuple[int, int]],
    occupied: set[tuple[int, int]],
) -> tuple[dict[str, Any], tuple[int, int]]:
    target = (int(math.floor(float(creature["x"]))), int(math.floor(float(creature["y"]))))
    approach = _approach_cell(target, open_cells, occupied)
    route = _bfs(current, approach, open_cells)
    return ({
        "target_id": creature["id"],
        "route_cells": [{"x": x, "y": y} for x, y in route],
        "approach": {"x": approach[0], "y": approach[1]},
        "aim_mdeg": _angle_mdeg(approach, target),
    }, approach)


def _manifest_digest(rows: tuple[str, ...], initial_pose: dict[str, Any], creatures: list[dict[str, Any]]) -> str:
    encoded = json.dumps(
        {"map": list(rows), "initial_pose": initial_pose, "creatures": creatures, "ammo": AMMO},
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    layout_variant = rng.choice(("identity", "mirror_x", "mirror_y", "rotate_180"))
    rows, start_cell, initial_angle, spawn_cells = _layout_variant(layout_variant)
    open_cells = _open_cells(rows)
    initial_pose = {"x": start_cell[0] + 0.5, "y": start_cell[1] + 0.5, "angle_mdeg": initial_angle}

    selected_cells = list(spawn_cells)
    rng.shuffle(selected_cells)
    selected_cells = selected_cells[:6]
    occupied = set(selected_cells)

    wanted_traits = [_traits(rng, index) for index in range(3)]
    # Repair the extremely unlikely possibility that randomized feature choices
    # create identical warrants.
    for index in range(1, len(wanted_traits)):
        while wanted_traits[index] in wanted_traits[:index]:
            horn_index = _HORNS.index(str(wanted_traits[index]["horn"]))
            wanted_traits[index]["horn"] = _HORNS[(horn_index + 1) % len(_HORNS)]

    creatures: list[dict[str, Any]] = []
    wanted_ids: list[str] = []
    protected_ids: list[str] = []
    for pair_index in range(3):
        wanted_id = _creature_id(seed, pair_index * 2)
        protected_id = _creature_id(seed, pair_index * 2 + 1)
        wanted_cell = selected_cells[pair_index * 2]
        protected_cell = selected_cells[pair_index * 2 + 1]
        creatures.append({
            "id": wanted_id,
            "x": wanted_cell[0] + 0.5,
            "y": wanted_cell[1] + 0.5,
            "traits": dict(wanted_traits[pair_index]),
            "pose": rng.choice(("alert", "stooped", "side-eye")),
        })
        creatures.append({
            "id": protected_id,
            "x": protected_cell[0] + 0.5,
            "y": protected_cell[1] + 0.5,
            "traits": _decoy_traits(wanted_traits[pair_index], pair_index),
            "pose": rng.choice(("alert", "stooped", "side-eye")),
        })
        wanted_ids.append(wanted_id)
        protected_ids.append(protected_id)

    rng.shuffle(creatures)
    posters = [{"warrant": f"W-{index + 1}", "traits": dict(traits)} for index, traits in enumerate(wanted_traits)]
    rng.shuffle(posters)

    by_id = {str(creature["id"]): creature for creature in creatures}
    current = start_cell
    solver_plan: list[dict[str, Any]] = []
    alive = {str(creature["id"]) for creature in creatures}
    for wanted_id in wanted_ids:
        segment, current = _solver_segment(current, by_id[wanted_id], open_cells, occupied)
        solver_plan.append(segment)
        approach = segment["approach"]
        hit_id = _nearest_hit(
            rows,
            creatures,
            alive,
            float(approach["x"]) + 0.5,
            float(approach["y"]) + 0.5,
            int(segment["aim_mdeg"]),
        )
        assert hit_id == wanted_id, f"solver ray reaches {hit_id}, expected {wanted_id}"
        alive.remove(wanted_id)

    protected_plan, _ = _solver_segment(start_cell, by_id[protected_ids[0]], open_cells, occupied)
    protected_approach = protected_plan["approach"]
    assert _nearest_hit(
        rows,
        creatures,
        {str(creature["id"]) for creature in creatures},
        float(protected_approach["x"]) + 0.5,
        float(protected_approach["y"]) + 0.5,
        int(protected_plan["aim_mdeg"]),
    ) == protected_ids[0]

    challenge_id = _challenge_id(seed)
    task_id = str(task.get("id") or "")
    digest = _manifest_digest(rows, initial_pose, creatures)
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Clear the three warrants. Protected travellers must survive.",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "generator": {"name": "tiny_fps_customs_v1", "variant_count": 2_500_000_000},
        "layout_variant": layout_variant,
        "map": list(rows),
        "initial_pose": initial_pose,
        "player_radius": PLAYER_RADIUS,
        "creature_radius": CREATURE_RADIUS,
        "move_step": MOVE_STEP,
        "ammo": AMMO,
        "creatures": creatures,
        "wanted_posters": posters,
        "manifest_digest": digest,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "layout_variant": layout_variant,
        "map": list(rows),
        "initial_pose": initial_pose,
        "player_radius": PLAYER_RADIUS,
        "creature_radius": CREATURE_RADIUS,
        "move_step": MOVE_STEP,
        "ammo": AMMO,
        "creatures": creatures,
        "wanted_ids": wanted_ids,
        "protected_ids": protected_ids,
        "solver_plan": solver_plan,
        "protected_test_plan": protected_plan,
        "manifest_digest": digest,
        "variant_count": 2_500_000_000,
    }

    assert _reachable(start_cell, open_cells) == open_cells
    assert len(creatures) == 6
    assert len(wanted_ids) == len(protected_ids) == 3
    assert not (set(wanted_ids) & set(protected_ids))
    assert all("id" not in poster and "wanted" not in poster for poster in posters)
    assert all(len(segment["route_cells"]) >= 1 for segment in solver_plan)
    return public_state, ground_truth
