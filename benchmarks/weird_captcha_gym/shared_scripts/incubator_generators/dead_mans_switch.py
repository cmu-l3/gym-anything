from __future__ import annotations

import hashlib
import random
from collections import deque
from typing import Any


MECHANIC_ID = "dead_mans_switch"
VARIANT_COUNT = 18_662_400_000
_DIRECTIONS = (
    ("N", 0, -1),
    ("E", 1, 0),
    ("S", 0, 1),
    ("W", -1, 0),
)


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _shortest_path(
    start: tuple[int, int],
    goal: tuple[int, int],
    walls: set[tuple[int, int]],
    columns: int,
    rows: int,
) -> list[str]:
    queue: deque[tuple[int, int]] = deque([start])
    previous: dict[tuple[int, int], tuple[tuple[int, int], str]] = {}
    seen = {start}
    while queue:
        position = queue.popleft()
        if position == goal:
            break
        for direction, dx, dy in _DIRECTIONS:
            candidate = (position[0] + dx, position[1] + dy)
            if not (0 <= candidate[0] < columns and 0 <= candidate[1] < rows):
                continue
            if candidate in walls or candidate in seen:
                continue
            seen.add(candidate)
            previous[candidate] = (position, direction)
            queue.append(candidate)
    if goal not in seen:
        raise ValueError("generated switch course is not traversable")
    commands: list[str] = []
    cursor = goal
    while cursor != start:
        cursor, direction = previous[cursor]
        commands.append(direction)
    commands.reverse()
    return commands


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    columns = 18
    rows = 10
    barrier_columns = (3, 6, 9, 12, 15)
    gaps = [rng.choice((1, 2)) if index % 2 == 0 else rng.choice((7, 8)) for index in range(len(barrier_columns))]

    start = (1, rng.choice((7, 8)))
    goal = (16, rng.choice((7, 8)))
    walls = {
        (column, row)
        for column, gap in zip(barrier_columns, gaps)
        for row in range(rows)
        if row != gap
    }
    checkpoints = [
        {
            "id": f"checkpoint-{index + 1}",
            "order": index + 1,
            "x": column,
            "y": gap,
        }
        for index, (column, gap) in enumerate(zip(barrier_columns, gaps))
    ]

    waypoints = [(item["x"], item["y"]) for item in checkpoints] + [goal]
    solution_path: list[str] = []
    cursor = start
    for waypoint in waypoints:
        segment = _shortest_path(cursor, waypoint, walls, columns, rows)
        solution_path.extend(segment)
        for direction in segment:
            _, dx, dy = next(item for item in _DIRECTIONS if item[0] == direction)
            cursor = (cursor[0] + dx, cursor[1] + dy)

    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "dead_mans_switch_seed_0001@0.1")
    wall_records = [{"x": x, "y": y} for x, y in sorted(walls, key=lambda item: (item[1], item[0]))]
    board = {
        "columns": columns,
        "rows": rows,
        "start": {"x": start[0], "y": start[1]},
        "goal": {"x": goal[0], "y": goal[1]},
        "walls": wall_records,
        "checkpoints": checkpoints,
    }
    pressure_motion = {
        "period_ms": rng.choice((3_600, 3_800, 4_000)),
        "phase_milliradians": rng.randrange(0, 6_284),
        "x_amplitude_milli": rng.randint(245, 285),
        "y_amplitude_milli": rng.randint(155, 190),
        "hit_x_milli": 185,
        "hit_y_milli": 235,
        "sample_ms": 100,
        "maximum_sample_gap_ms": 360,
        "outside_grace_ms": 310,
        "minimum_hold_ms": 5_200,
    }
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "prompt": task.get("natural_language")
        or "Track the moving pressure plate while steering through every numbered checkpoint to the dock.",
        "generator": {"name": "moving_dead_mans_switch_v2", "variant_count": VARIANT_COUNT},
        "board": board,
        "pressure_motion": pressure_motion,
        "controls": {"movement": ["W", "A", "S", "D", "ARROWS"], "pressure": "pointer_hold"},
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "board": board,
        "checkpoint_ids": [item["id"] for item in checkpoints],
        "solution_path": solution_path,
        "minimum_success_moves": len(solution_path),
        "pressure_motion": pressure_motion,
        "variant_count": VARIANT_COUNT,
    }
    assert len(checkpoints) == 5 and len(solution_path) >= 42
    return public_state, ground_truth
