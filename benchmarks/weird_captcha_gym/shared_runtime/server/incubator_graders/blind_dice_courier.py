from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "blind_dice_courier"
_MOVES = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}
_FACES = ("top", "bottom", "north", "south", "east", "west")


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _point(value: Any) -> tuple[int, int] | None:
    if not isinstance(value, dict):
        return None
    try:
        return int(value["x"]), int(value["y"])
    except (KeyError, TypeError, ValueError):
        return None


def _orientation(value: Any) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    try:
        result = {face: int(value[face]) for face in _FACES}
    except (KeyError, TypeError, ValueError):
        return None
    if set(result.values()) != {1, 2, 3, 4, 5, 6}:
        return None
    return result


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


def _time(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and 0 <= number <= 3_600_000 else None


def _integer(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("mechanic mismatch")
    if str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("hidden mechanic mismatch")
    if str(public_state.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("public mechanic mismatch")
    if str(payload.get("challenge_id") or "") != str(ground_truth.get("challenge_id") or ""):
        return _failure("stale challenge")
    if str(public_state.get("challenge_id") or "") != str(ground_truth.get("challenge_id") or ""):
        return _failure("public and hidden challenge state disagree")
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id or str(public_state.get("task_id") or "") != task_id:
        return _failure("task identity mismatch")
    if public_state.get("board") != ground_truth.get("board"):
        return _failure("public and hidden courier geometry disagree")
    if public_state.get("initial_orientation") != ground_truth.get("initial_orientation"):
        return _failure("public and hidden initial orientation disagree")

    board = ground_truth.get("board") or {}
    start = _point(board.get("start"))
    goal = _point(board.get("goal"))
    initial = _orientation(ground_truth.get("initial_orientation"))
    if start is None or goal is None or initial is None:
        return _failure("invalid hidden courier state")
    open_cells = {_point(item) for item in board.get("open_cells") or []}
    if None in open_cells or start not in open_cells or goal not in open_cells:
        return _failure("invalid hidden courier floor plan")
    gates_by_position: dict[tuple[int, int], dict[str, Any]] = {}
    for gate in board.get("gates") or []:
        position = _point(gate)
        if position is None:
            return _failure("invalid hidden gate")
        gates_by_position[position] = gate
    expected_gate_ids = [str(item) for item in ground_truth.get("gate_ids") or []]

    actions = payload.get("actions")
    if not isinstance(actions, list) or not actions or len(actions) > 1200:
        return _failure("missing or oversized roll transcript")
    position = start
    orientation = dict(initial)
    crossings: list[str] = []
    previous_t = -1.0
    path: list[str] = []
    resets = 0

    for index, action in enumerate(actions):
        if not isinstance(action, dict):
            return _failure(f"action {index + 1} is not an object")
        try:
            seq = int(action.get("seq"))
        except (TypeError, ValueError):
            return _failure("roll transcript has no sequence")
        if seq != index + 1:
            return _failure("roll transcript sequence is not contiguous")
        action_t = _time(action.get("t_ms"))
        if action_t is None or action_t < previous_t:
            return _failure("roll transcript timestamps are invalid")
        previous_t = action_t
        action_type = str(action.get("type") or "")
        if action_type == "reset":
            position = start
            orientation = dict(initial)
            crossings = []
            resets += 1
            if _point(action.get("position")) != start or _orientation(action.get("orientation")) != initial:
                return _failure("reset state does not match the manifest")
            continue
        if action_type != "move":
            return _failure(f"unknown roll action {action_type!r}")
        direction = str(action.get("direction") or "").upper()
        if direction not in _MOVES:
            return _failure("invalid roll direction")
        path.append(direction)
        if _point(action.get("from")) != position:
            return _failure("reported roll origin does not match replay")
        dx, dy = _MOVES[direction]
        candidate = (position[0] + dx, position[1] + dy)
        accepted = candidate in open_cells
        tentative = _roll(orientation, direction) if accepted else dict(orientation)
        gate = gates_by_position.get(candidate) if accepted else None
        if gate is not None and int(tentative["top"]) != int(gate.get("required_top")):
            accepted = False
            tentative = dict(orientation)
        if accepted:
            position = candidate
            orientation = tentative
            if gate is not None:
                gate_id = str(gate.get("id") or "")
                if gate_id not in crossings:
                    crossings.append(gate_id)
        if bool(action.get("accepted")) != accepted:
            return _failure("reported gate or wall collision does not match replay")
        if _point(action.get("to")) != position:
            return _failure("reported roll destination does not match replay")
        if _orientation(action.get("orientation_after")) != orientation:
            return _failure("reported die orientation does not match replay")
        reported_gate = action.get("gate_id")
        replay_gate = str(gate.get("id")) if gate is not None else None
        if (str(reported_gate) if reported_gate is not None else None) != replay_gate:
            return _failure("reported gate encounter does not match replay")

    if position != goal or crossings != expected_gate_ids:
        return _failure(f"courier did not cross all {len(expected_gate_ids)} gates in order and reach dispatch")
    if payload.get("completed") is not True:
        return _failure("delivery was not completed")
    if _point(payload.get("final_position")) != position:
        return _failure("final courier position does not match replay")
    if _orientation(payload.get("final_orientation")) != orientation:
        return _failure("final die orientation does not match replay")
    if [str(item) for item in payload.get("gate_crossings") or []] != crossings:
        return _failure("gate crossing ledger does not match replay")
    if [str(item).upper() for item in payload.get("path") or []] != path:
        return _failure("submitted path does not match full roll transcript")
    if _integer(payload.get("reset_count")) != resets:
        return _failure("reset count does not match replay")

    return {
        "graded": True,
        "passed": True,
        "score": 100,
        "feedback": f"replayed {len(path)} rolls through {len(crossings)} face gates after {resets} resets",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    return {
        "solution_path": list(ground_truth.get("solution_path") or []),
        "solution_trace": list(ground_truth.get("solution_trace") or []),
        "gate_ids": list(ground_truth.get("gate_ids") or []),
    }
