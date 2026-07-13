from __future__ import annotations

from collections import deque
import hashlib
import random
from typing import Any


MECHANIC_ID = "input_lag_forklift"
WIDTH = 9
HEIGHT = 7
DIRECTIONS: tuple[tuple[str, tuple[int, int]], ...] = (
    ("UP", (0, -1)),
    ("RIGHT", (1, 0)),
    ("DOWN", (0, 1)),
    ("LEFT", (-1, 0)),
)
TRANSFORMS = ("identity", "mirror_x", "mirror_y", "rotate_180")
PALETTES = ("amber", "oxide", "mint", "cobalt")
LAYOUTS: tuple[dict[str, Any], ...] = (
    {"player": (3, 2), "crates": ((4, 1), (4, 4)), "goals": ((7, 3), (6, 1)), "racks": ((4, 2), (5, 3), (7, 5))},
    {"player": (5, 1), "crates": ((6, 2), (6, 3)), "goals": ((2, 3), (1, 3)), "racks": ((2, 2), (3, 3), (4, 3))},
    {"player": (1, 2), "crates": ((6, 4), (2, 2)), "goals": ((1, 5), (7, 2)), "racks": ((1, 1), (2, 3), (3, 5), (4, 5), (6, 1), (7, 3))},
    {"player": (4, 5), "crates": ((6, 2), (2, 3)), "goals": ((7, 5), (5, 3)), "racks": ((1, 3), (2, 5), (4, 1), (4, 2))},
    {"player": (7, 3), "crates": ((6, 2), (2, 3)), "goals": ((1, 5), (5, 1)), "racks": ((1, 3), (3, 1), (5, 5), (7, 2))},
    {"player": (7, 5), "crates": ((6, 3), (2, 3)), "goals": ((3, 2), (4, 4)), "racks": ((1, 1), (2, 1), (2, 2), (4, 3), (6, 4))},
    {"player": (7, 4), "crates": ((4, 2), (3, 2)), "goals": ((5, 2), (7, 1)), "racks": ((1, 4), (4, 1), (6, 1), (6, 4))},
    {"player": (4, 3), "crates": ((3, 5), (3, 4)), "goals": ((7, 5), (7, 2)), "racks": ((1, 3), (3, 3), (4, 2), (5, 2), (5, 3), (6, 2))},
    {"player": (1, 1), "crates": ((6, 2), (6, 4)), "goals": ((1, 3), (2, 5)), "racks": ((1, 5), (2, 2), (4, 3), (7, 1))},
    {"player": (5, 5), "crates": ((2, 3), (4, 2)), "goals": ((2, 1), (7, 4)), "racks": ((1, 1), (2, 4), (5, 2), (6, 3))},
    {"player": (7, 3), "crates": ((2, 3), (2, 4)), "goals": ((3, 5), (4, 1)), "racks": ((1, 1), (2, 1), (3, 1), (3, 3), (6, 2), (6, 5))},
    {"player": (5, 4), "crates": ((1, 4), (2, 3)), "goals": ((1, 3), (6, 5)), "racks": ((3, 3), (4, 4), (5, 3), (7, 2))},
)


def _transform(point: tuple[int, int], variant: str) -> tuple[int, int]:
    x, y = point
    if variant == "mirror_x":
        return WIDTH - 1 - x, y
    if variant == "mirror_y":
        return x, HEIGHT - 1 - y
    if variant == "rotate_180":
        return WIDTH - 1 - x, HEIGHT - 1 - y
    return x, y


def _initial_layout(layout_index: int, variant: str) -> dict[str, Any]:
    outer = {
        (x, y)
        for y in range(HEIGHT)
        for x in range(WIDTH)
        if x in {0, WIDTH - 1} or y in {0, HEIGHT - 1}
    }
    template = LAYOUTS[layout_index]
    walls = outer | set(template["racks"])
    player = template["player"]
    crates = tuple(template["crates"])
    goals = tuple(template["goals"])
    return {
        "width": WIDTH,
        "height": HEIGHT,
        "player": list(_transform(player, variant)),
        "crates": [list(_transform(point, variant)) for point in crates],
        "goals": [list(_transform(point, variant)) for point in goals],
        "walls": [list(point) for point in sorted(_transform(point, variant) for point in walls)],
    }


def _step(
    player: tuple[int, int],
    crates: tuple[tuple[int, int], ...],
    walls: frozenset[tuple[int, int]],
    direction: str,
) -> tuple[tuple[int, int], tuple[tuple[int, int], ...]] | None:
    delta = dict(DIRECTIONS).get(direction)
    if delta is None:
        return None
    target = (player[0] + delta[0], player[1] + delta[1])
    crate_set = set(crates)
    if target in walls:
        return None
    if target not in crate_set:
        return target, crates
    beyond = (target[0] + delta[0], target[1] + delta[1])
    if beyond in walls or beyond in crate_set:
        return None
    crate_set.remove(target)
    crate_set.add(beyond)
    return target, tuple(sorted(crate_set))


def _solve(layout: dict[str, Any]) -> list[str]:
    player = tuple(int(value) for value in layout["player"])
    crates = tuple(sorted(tuple(int(value) for value in point) for point in layout["crates"]))
    walls = frozenset(tuple(int(value) for value in point) for point in layout["walls"])
    goals = frozenset(tuple(int(value) for value in point) for point in layout["goals"])
    start = (player, crates)
    queue: deque[tuple[tuple[int, int], tuple[tuple[int, int], ...], tuple[str, ...]]] = deque(
        [(player, crates, ())]
    )
    visited = {start}
    while queue:
        current_player, current_crates, path = queue.popleft()
        if set(current_crates) == goals:
            return list(path)
        for direction, _delta in DIRECTIONS:
            moved = _step(current_player, current_crates, walls, direction)
            if moved is None:
                continue
            next_player, next_crates = moved
            state = (next_player, next_crates)
            if state in visited:
                continue
            visited.add(state)
            queue.append((next_player, next_crates, path + (direction,)))
    raise ValueError("generated forklift warehouse is not solvable")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    digest = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).digest()
    rng = random.Random(int.from_bytes(digest[:8], "big"))
    layout_index = rng.randrange(len(LAYOUTS))
    transform = TRANSFORMS[rng.randrange(len(TRANSFORMS))]
    palette = PALETTES[rng.randrange(len(PALETTES))]
    layout = _initial_layout(layout_index, transform)
    solution = _solve(layout)
    challenge_id = hashlib.sha256(f"{seed}|input-lag-forklift".encode("utf-8")).hexdigest()[:12]
    task_id = str(task.get("id") or "input_lag_forklift_seed_0001@0.1")
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language") or "Dock both crates. Every direction executes one command late.",
        "submit_label": "CERTIFY LOAD",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "generator": {
            "name": "input_lag_forklift_v2",
            "variant_count": len(LAYOUTS) * len(TRANSFORMS) * len(PALETTES),
        },
        "warehouse": layout,
        "control_lag": 1,
        "palette": palette,
        "rules": {
            "direction": "A direction executes the previously queued direction, then enters the queue.",
            "flush": "EXECUTE QUEUE runs the pending direction without adding another.",
            "reset": "RECALIBRATE restores the warehouse and clears the queue.",
        },
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "initial_state": layout,
        "control_lag": 1,
        "solution": solution,
        "solution_issued_commands": solution + ["FLUSH"],
        "layout_index": layout_index,
        "transform": transform,
        "palette": palette,
        "variant_count": len(LAYOUTS) * len(TRANSFORMS) * len(PALETTES),
    }
    assert 22 <= len(solution) <= 36
    assert len(set(solution)) == 4
    assert len(layout["crates"]) == len(layout["goals"]) == 2
    return public_state, ground_truth
