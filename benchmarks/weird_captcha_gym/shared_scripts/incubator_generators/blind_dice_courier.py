from __future__ import annotations

import hashlib
import random
from collections import deque
from typing import Any


MECHANIC_ID = "blind_dice_courier"
VARIANT_COUNT = 8_640_000_000
FACE_NAMES = ("top", "bottom", "north", "south", "east", "west")
CANONICAL = {"top": 1, "bottom": 6, "north": 2, "south": 5, "east": 3, "west": 4}


def _seed_int(seed: str, salt: str) -> int:
    digest = hashlib.sha256(f"{seed}|{salt}".encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _roll(orientation: dict[str, int], direction: str) -> dict[str, int]:
    old = dict(orientation)
    if direction == "N":
        return {
            "top": old["south"],
            "bottom": old["north"],
            "north": old["top"],
            "south": old["bottom"],
            "east": old["east"],
            "west": old["west"],
        }
    if direction == "S":
        return {
            "top": old["north"],
            "bottom": old["south"],
            "north": old["bottom"],
            "south": old["top"],
            "east": old["east"],
            "west": old["west"],
        }
    if direction == "E":
        return {
            "top": old["west"],
            "bottom": old["east"],
            "north": old["north"],
            "south": old["south"],
            "east": old["top"],
            "west": old["bottom"],
        }
    if direction == "W":
        return {
            "top": old["east"],
            "bottom": old["west"],
            "north": old["north"],
            "south": old["south"],
            "east": old["bottom"],
            "west": old["top"],
        }
    raise ValueError(f"unknown roll direction {direction!r}")


def _trace(initial: dict[str, int], commands: list[str]) -> list[dict[str, Any]]:
    orientation = dict(initial)
    trace: list[dict[str, Any]] = []
    for index, command in enumerate(commands):
        orientation = _roll(orientation, command)
        trace.append({"step": index + 1, "direction": command, "orientation": dict(orientation)})
    return trace


def _solve_course(
    initial: dict[str, int],
    start: tuple[int, int],
    goal: tuple[int, int],
    open_cells: set[tuple[int, int]],
    gates: list[dict[str, Any]],
) -> list[str]:
    gate_map = {(int(item["x"]), int(item["y"])): int(item["required_top"]) for item in gates}
    initial_faces = tuple(int(initial[name]) for name in FACE_NAMES)
    queue: deque[tuple[tuple[int, int], tuple[int, ...], tuple[str, ...]]] = deque([(start, initial_faces, ())])
    seen = {(start, initial_faces)}
    deltas = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}
    while queue:
        position, faces, path = queue.popleft()
        if position == goal:
            return list(path)
        orientation = dict(zip(FACE_NAMES, faces))
        for direction in ("N", "E", "S", "W"):
            dx, dy = deltas[direction]
            candidate = (position[0] + dx, position[1] + dy)
            if candidate not in open_cells:
                continue
            rolled = _roll(orientation, direction)
            required = gate_map.get(candidate)
            if required is not None and int(rolled["top"]) != required:
                continue
            next_faces = tuple(int(rolled[name]) for name in FACE_NAMES)
            key = (candidate, next_faces)
            if key in seen:
                continue
            seen.add(key)
            queue.append((candidate, next_faces, path + (direction,)))
    raise ValueError("generated dice maze has no orientation-valid delivery route")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(_seed_int(seed, MECHANIC_ID))
    initial = dict(CANONICAL)
    for _ in range(rng.randint(9, 24)):
        initial = _roll(initial, rng.choice(("N", "S", "E", "W")))

    columns, rows = 18, 11
    barrier_columns = (3, 6, 9, 12, 15)
    low_rows = (1, 2)
    high_rows = (8, 9)
    gaps = [rng.choice(low_rows if index % 2 == 0 else high_rows) for index in range(len(barrier_columns))]
    start = (1, rng.choice(high_rows))
    goal = (16, rng.choice(high_rows))
    walls = {
        (column, row)
        for column, gap in zip(barrier_columns, gaps)
        for row in range(1, rows - 1)
        if row != gap
    }
    open_cells = {
        (x, y)
        for y in range(1, rows - 1)
        for x in range(1, columns - 1)
        if (x, y) not in walls
    }
    tones = ("amber", "cyan", "violet", "coral", "lime")
    gate_ids = [f"gate-{tone}" for tone in tones]
    solution_path: list[str] | None = None
    gates: list[dict[str, Any]] = []
    for _attempt in range(80):
        gates = [
            {
                "id": gate_ids[index],
                "x": column,
                "y": gaps[index],
                "required_top": rng.randint(1, 6),
                "tone": tones[index],
            }
            for index, column in enumerate(barrier_columns)
        ]
        try:
            candidate = _solve_course(initial, start, goal, open_cells, gates)
        except ValueError:
            continue
        if 48 <= len(candidate) <= 105:
            solution_path = candidate
            break
    if solution_path is None:
        raise ValueError("could not generate a sufficiently long orientation maze")
    scanners = [
        {"id": f"scanner-{index + 1}", "x": column - 1, "y": max(1, min(rows - 2, gap + (2 if index % 2 == 0 else -2)))}
        for index, (column, gap) in enumerate(zip(barrier_columns[:4], gaps[:4]))
    ]
    board = {
        "columns": columns,
        "rows": rows,
        "start": {"x": start[0], "y": start[1]},
        "goal": {"x": goal[0], "y": goal[1]},
        "open_cells": [{"x": x, "y": y} for x, y in sorted(open_cells, key=lambda item: (item[1], item[0]))],
        "gates": gates,
        "scanners": scanners,
    }
    challenge_id = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "blind_dice_courier_seed_0001@0.1")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "prompt": task.get("natural_language")
        or "Roll the sealed die-crate through all five face gates and deliver it. Sparse scanners reveal its orientation.",
        "generator": {"name": "blind_dice_courier_v2", "variant_count": VARIANT_COUNT},
        "board": board,
        "initial_orientation": initial,
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "board": board,
        "initial_orientation": initial,
        "gate_ids": gate_ids,
        "solution_path": solution_path,
        "solution_trace": _trace(initial, solution_path),
        "variant_count": VARIANT_COUNT,
    }
    assert len(gates) == 5 and len(solution_path) >= 48
    return public_state, ground_truth
