from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "top_face_dice_arithmetic"
DIRECTIONS = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}
OPPOSITE = {"N": "S", "E": "W", "S": "N", "W": "E"}
FACES = ("top", "bottom", "north", "south", "east", "west")


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _point(value: Any) -> tuple[int, int] | None:
    if not isinstance(value, dict):
        return None
    try:
        return int(value["x"]), int(value["y"])
    except (KeyError, TypeError, ValueError):
        return None


def _point_dict(value: tuple[int, int]) -> dict[str, int]:
    return {"x": value[0], "y": value[1]}


def _orientation(value: Any) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    try:
        orientation = {face: int(value[face]) for face in FACES}
    except (KeyError, TypeError, ValueError):
        return None
    if set(orientation.values()) != {1, 2, 3, 4, 5, 6}:
        return None
    if orientation["top"] + orientation["bottom"] != 7:
        return None
    if orientation["north"] + orientation["south"] != 7:
        return None
    if orientation["east"] + orientation["west"] != 7:
        return None
    return orientation


def _roll(orientation: dict[str, int], direction: str) -> dict[str, int]:
    old = dict(orientation)
    if direction == "N":
        return {"top": old["south"], "bottom": old["north"], "north": old["top"], "south": old["bottom"], "east": old["east"], "west": old["west"]}
    if direction == "S":
        return {"top": old["north"], "bottom": old["south"], "north": old["bottom"], "south": old["top"], "east": old["east"], "west": old["west"]}
    if direction == "E":
        return {"top": old["west"], "bottom": old["east"], "north": old["north"], "south": old["south"], "east": old["top"], "west": old["bottom"]}
    if direction == "W":
        return {"top": old["east"], "bottom": old["west"], "north": old["north"], "south": old["south"], "east": old["bottom"], "west": old["top"]}
    raise ValueError(direction)


def _screen_to_world(direction: str, view: int) -> str:
    return direction if view % 4 == 0 else OPPOSITE[direction]


def _time(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and 0 <= number <= 3_600_000 else None


def _settle_profile(delta: int) -> list[int]:
    if delta == 0:
        return [26, -16, 10, -6, 3, -1, 0]
    bias = max(-34, min(34, delta * 6))
    return [bias + 22, bias - 13, bias + 8, bias - 5, bias + 3, bias - 1, bias]


def _visible(die: dict[str, Any]) -> bool:
    return bool(die["initial_reveal"] or die["position"] in die["scanner_cells"] or die["docked"])


def _snapshot(
    order: list[str],
    dice: dict[str, dict[str, Any]],
    view: int,
    selected: str,
    view_rotations: int,
    reset_count: int,
    settled: bool,
    settle_samples: list[int],
) -> dict[str, Any]:
    die_states = []
    for die_id in order:
        die = dice[die_id]
        die_states.append({
            "die_id": die_id,
            "position": _point_dict(die["position"]),
            "orientation": dict(die["orientation"]),
            "accepted_rolls": die["accepted_rolls"],
            "docked": die["docked"],
            "top_visible": _visible(die),
        })
    return {
        "view": view,
        "selected_die_id": selected,
        "view_rotations": view_rotations,
        "reset_count": reset_count,
        "dice": die_states,
        "top_sum": sum(die["orientation"]["top"] for die in dice.values() if die["docked"]),
        "settled": settled,
        "settle_samples": list(settle_samples),
    }


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("mechanic mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return _failure("stale challenge")
    if str(public_state.get("challenge_id") or "") != challenge_id or str(public_state.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("public foundry state does not match the hidden challenge")
    if public_state.get("dice") != ground_truth.get("dice") or public_state.get("board") != ground_truth.get("board"):
        return _failure("public rail manifest disagrees with hidden state")
    try:
        target_sum = int(ground_truth["target_sum"])
    except (KeyError, TypeError, ValueError):
        return _failure("hidden scale target is invalid")
    if public_state.get("target_sum") != target_sum:
        return _failure("public scale target disagrees with hidden state")

    raw_dice = ground_truth.get("dice")
    if not isinstance(raw_dice, list) or len(raw_dice) != 3:
        return _failure("hidden three-die manifest is missing")
    dice: dict[str, dict[str, Any]] = {}
    order: list[str] = []
    for raw in raw_dice:
        if not isinstance(raw, dict):
            return _failure("hidden die manifest is malformed")
        die_id = str(raw.get("id") or "")
        initial = _orientation(raw.get("initial_orientation"))
        start, dock = _point(raw.get("start")), _point(raw.get("dock"))
        open_cells = {_point(item) for item in raw.get("open_cells") or []}
        scanner_cells = {_point(item) for item in raw.get("scanner_cells") or []}
        if not die_id or die_id in dice or initial is None or start is None or dock is None or None in open_cells or None in scanner_cells:
            return _failure("hidden die rail is malformed")
        if start not in open_cells or dock not in open_cells:
            return _failure("die rail omits its start or dock")
        order.append(die_id)
        dice[die_id] = {
            "start": start,
            "dock": dock,
            "open_cells": open_cells,
            "scanner_cells": scanner_cells,
            "initial_orientation": initial,
            "position": start,
            "orientation": dict(initial),
            "accepted_rolls": 0,
            "docked": False,
            "initial_reveal": True,
        }

    starting_view = int(ground_truth.get("starting_view") or 0)
    selected = str(ground_truth.get("initial_selected_die_id") or "")
    if starting_view != 0 or selected not in dice:
        return _failure("hidden table initialization is malformed")
    view = starting_view
    view_rotations = 0
    reset_count = 0
    settled = False
    settling = False
    settle_samples: list[int] = []
    expected_profile: list[int] | None = None
    previous_time = -1.0

    events = payload.get("events")
    if not isinstance(events, list) or not events or len(events) > 500:
        return _failure("foundry interaction transcript is missing or too long")
    for index, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("seq") != index:
            return _failure(f"foundry event {index} has invalid sequence")
        event_time = _time(event.get("t_ms"))
        if event_time is None or event_time < previous_time:
            return _failure(f"foundry event {index} has invalid timing")
        previous_time = event_time
        action = str(event.get("type") or "")
        if settled:
            return _failure("foundry transcript continues after scale settlement")

        if action == "select":
            die_id = str(event.get("die_id") or "")
            if settling or die_id not in dice or event.get("selected_before") != selected:
                return _failure(f"die selection {index} disagrees with replay")
            selected = die_id
            if event.get("selected_after") != selected:
                return _failure(f"die selection {index} has a false result")
            continue

        if action == "view_rotate":
            if settling or event.get("delta") != 2 or event.get("view_before") != view:
                return _failure(f"table rotation {index} is malformed")
            view = (view + 2) % 4
            view_rotations += 1
            if event.get("view_after") != view:
                return _failure(f"table rotation {index} disagrees with replay")
            continue

        if action == "reset":
            if settling:
                return _failure("table reset occurred during settlement")
            for die in dice.values():
                die["position"] = die["start"]
                die["orientation"] = dict(die["initial_orientation"])
                die["accepted_rolls"] = 0
                die["docked"] = False
                die["initial_reveal"] = True
            view = starting_view
            selected = order[0]
            view_rotations = 0
            settle_samples = []
            expected_profile = None
            reset_count += 1
            if event.get("view_after") != view or event.get("selected_after") != selected:
                return _failure("table reset does not match the initial manifest")
            continue

        if action == "roll":
            die_id = str(event.get("die_id") or "")
            screen_direction = str(event.get("input_direction") or "").upper()
            if settling or die_id != selected or die_id not in dice or screen_direction not in DIRECTIONS:
                return _failure(f"die roll {index} is not bound to the selected die")
            die = dice[die_id]
            if event.get("view") != view or _point(event.get("from")) != die["position"]:
                return _failure(f"die roll {index} has stale view or origin")
            world_direction = _screen_to_world(screen_direction, view)
            if event.get("world_direction") != world_direction:
                return _failure(f"die roll {index} uses the wrong table-relative direction")
            dx, dy = DIRECTIONS[world_direction]
            candidate = (die["position"][0] + dx, die["position"][1] + dy)
            accepted = not die["docked"] and candidate in die["open_cells"]
            if accepted:
                die["position"] = candidate
                die["orientation"] = _roll(die["orientation"], world_direction)
                die["accepted_rolls"] += 1
                die["initial_reveal"] = False
                die["docked"] = candidate == die["dock"]
            if bool(event.get("accepted")) != accepted:
                return _failure(f"die roll {index} reports a false rail collision")
            if _point(event.get("to")) != die["position"]:
                return _failure(f"die roll {index} reports a false destination")
            if _orientation(event.get("orientation_after")) != die["orientation"]:
                return _failure(f"die roll {index} reports a false 3D orientation")
            if event.get("accepted_rolls_after") != die["accepted_rolls"] or bool(event.get("docked")) != die["docked"]:
                return _failure(f"die roll {index} disagrees with the dock ledger")
            if bool(event.get("top_visible")) != _visible(die):
                return _failure(f"die roll {index} disagrees with scanner occlusion")
            continue

        if action == "settle_start":
            if settling or settle_samples or not all(die["docked"] for die in dice.values()):
                return _failure("scale settlement began before all dice were docked")
            if view_rotations < 1 or any(die["accepted_rolls"] < 2 for die in dice.values()):
                return _failure("scale settlement lacks meaningful rolls or a table rotation")
            top_sum = sum(die["orientation"]["top"] for die in dice.values())
            expected_profile = _settle_profile(top_sum - target_sum)
            settling = True
            if event.get("sample_count") != len(expected_profile):
                return _failure("scale settlement declares the wrong sample count")
            continue

        if action == "settle_sample":
            if not settling or expected_profile is None:
                return _failure("scale sample occurred outside a settlement")
            sample_index = len(settle_samples)
            if event.get("sample_index") != sample_index + 1 or sample_index >= len(expected_profile):
                return _failure("scale sample sequence is malformed")
            if event.get("deflection") != expected_profile[sample_index]:
                return _failure("scale deflection does not match physical replay")
            settle_samples.append(expected_profile[sample_index])
            continue

        if action == "settle_complete":
            if not settling or expected_profile is None or settle_samples != expected_profile:
                return _failure("scale settlement completed without its full waveform")
            top_sum = sum(die["orientation"]["top"] for die in dice.values())
            balanced = top_sum == target_sum
            if bool(event.get("balanced")) != balanced or event.get("top_sum") != top_sum:
                return _failure("scale completion reports a false balance")
            settling = False
            settled = True
            continue

        return _failure(f"foundry event {index} has invalid action {action!r}")

    final_state = _snapshot(order, dice, view, selected, view_rotations, reset_count, settled, settle_samples)
    if payload.get("final_state") != final_state:
        return _failure("claimed final foundry state does not match transcript replay")
    top_sum = sum(die["orientation"]["top"] for die in dice.values())
    passed = (
        settled
        and not settling
        and all(die["docked"] and die["accepted_rolls"] >= 2 for die in dice.values())
        and view_rotations >= 1
        and top_sum == target_sum
        and settle_samples == _settle_profile(0)
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": f"replayed three docked dice; top sum {top_sum}/{target_sum}; view turns {view_rotations}; settle samples {len(settle_samples)}; resets {reset_count}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "solution_plans": ground_truth.get("solution_plans") or [],
        "target_sum": ground_truth.get("target_sum"),
        "settle_profile": ground_truth.get("settle_profile") or [],
        "answers": [],
    }
