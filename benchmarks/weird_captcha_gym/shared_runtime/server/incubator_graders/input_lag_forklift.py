from __future__ import annotations

from typing import Any


MECHANIC_ID = "input_lag_forklift"
DELTAS = {
    "UP": (0, -1),
    "RIGHT": (1, 0),
    "DOWN": (0, 1),
    "LEFT": (-1, 0),
}


def _points(value: Any) -> tuple[tuple[int, int], ...]:
    if not isinstance(value, list):
        raise ValueError("coordinate collection is not a list")
    points: list[tuple[int, int]] = []
    for item in value:
        if not isinstance(item, list) or len(item) != 2:
            raise ValueError("coordinate is malformed")
        x, y = item
        if isinstance(x, bool) or isinstance(y, bool):
            raise ValueError("boolean coordinate is invalid")
        points.append((int(x), int(y)))
    return tuple(sorted(points))


def _initial(ground_truth: dict[str, Any]) -> tuple[tuple[int, int], tuple[tuple[int, int], ...], frozenset[tuple[int, int]], frozenset[tuple[int, int]]]:
    source = ground_truth.get("initial_state")
    if not isinstance(source, dict):
        raise ValueError("missing initial warehouse")
    player_points = _points([source.get("player")])
    if len(player_points) != 1:
        raise ValueError("missing initial forklift")
    return player_points[0], _points(source.get("crates")), frozenset(_points(source.get("walls"))), frozenset(_points(source.get("goals")))


def _snapshot(player: tuple[int, int], crates: tuple[tuple[int, int], ...]) -> dict[str, Any]:
    return {
        "player": [player[0], player[1]],
        "crates": [[point[0], point[1]] for point in sorted(crates)],
    }


def _move(
    player: tuple[int, int],
    crates: tuple[tuple[int, int], ...],
    walls: frozenset[tuple[int, int]],
    direction: str,
) -> tuple[tuple[int, int], tuple[tuple[int, int], ...], str]:
    dx, dy = DELTAS[direction]
    target = (player[0] + dx, player[1] + dy)
    crate_set = set(crates)
    if target in walls:
        return player, crates, "collision_wall"
    if target not in crate_set:
        return target, crates, "move"
    beyond = (target[0] + dx, target[1] + dy)
    if beyond in walls or beyond in crate_set:
        return player, crates, "collision_crate_blocked"
    crate_set.remove(target)
    crate_set.add(beyond)
    return target, tuple(sorted(crate_set)), "push"


def _mismatch(index: int, field: str, expected: Any, actual: Any) -> dict[str, Any]:
    return {
        "graded": True,
        "passed": False,
        "feedback": f"command {index} has inconsistent {field}: expected {expected!r}, got {actual!r}",
    }


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "ground-truth mechanic mismatch"}
    if str(public_state.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "public-state mechanic mismatch"}
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "public-state challenge mismatch"}
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id or str(public_state.get("task_id") or "") != task_id:
        return {"graded": True, "passed": False, "feedback": "task identity mismatch"}
    if public_state.get("warehouse") != ground_truth.get("initial_state"):
        return {"graded": True, "passed": False, "feedback": "public/private warehouse contract skew"}
    if public_state.get("control_lag") != ground_truth.get("control_lag") or ground_truth.get("control_lag") != 1:
        return {"graded": True, "passed": False, "feedback": "public/private delay contract skew"}

    try:
        initial_player, initial_crates, walls, goals = _initial(ground_truth)
    except (TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid warehouse contract: {exc}"}

    events = payload.get("issued_commands")
    if not isinstance(events, list) or not (2 <= len(events) <= 400):
        return {"graded": True, "passed": False, "feedback": "command transcript is missing or outside limits"}

    player = initial_player
    crates = initial_crates
    pending: str | None = None
    collisions = 0
    reset_sequences: list[int] = []
    direction_count = 0
    flush_count = 0
    saw_initial_queue = False

    for index, event in enumerate(events, start=1):
        if not isinstance(event, dict):
            return {"graded": True, "passed": False, "feedback": f"command {index} is not an object"}
        if event.get("sequence") != index:
            return _mismatch(index, "sequence", index, event.get("sequence"))
        issued = str(event.get("issued") or "")
        before = _snapshot(player, crates)
        pending_before = pending
        executed: str | None = None

        if issued in DELTAS:
            direction_count += 1
            if pending is None:
                outcome = "queued"
                saw_initial_queue = True
            else:
                executed = pending
                player, crates, outcome = _move(player, crates, walls, executed)
            pending = issued
            event_type = "direction"
        elif issued == "FLUSH":
            flush_count += 1
            event_type = "flush"
            if pending is None:
                outcome = "flushed_empty"
            else:
                executed = pending
                player, crates, outcome = _move(player, crates, walls, executed)
            pending = None
        elif issued == "RESET":
            event_type = "reset"
            outcome = "recalibrated"
            player = initial_player
            crates = initial_crates
            pending = None
            reset_sequences.append(index)
        else:
            return {"graded": True, "passed": False, "feedback": f"command {index} has invalid issued value"}

        if outcome.startswith("collision_"):
            collisions += 1
        expected_fields = {
            "type": event_type,
            "issued": issued,
            "pending_before": pending_before,
            "executed": executed,
            "outcome": outcome,
            "before": before,
            "after": _snapshot(player, crates),
            "pending_after": pending,
        }
        for field, expected in expected_fields.items():
            if event.get(field) != expected:
                return _mismatch(index, field, expected, event.get(field))

    expected_final = _snapshot(player, crates)
    if payload.get("final_state") != expected_final:
        return {"graded": True, "passed": False, "feedback": "submitted final state does not match replay"}
    if payload.get("pending_command") != pending:
        return {"graded": True, "passed": False, "feedback": "submitted queue does not match replay"}
    if payload.get("collisions") != collisions:
        return {"graded": True, "passed": False, "feedback": "collision count does not match replay"}
    if payload.get("reset_count") != len(reset_sequences):
        return {"graded": True, "passed": False, "feedback": "reset count does not match replay"}
    expected_history = [{"sequence": sequence, "reason": "operator_recalibration"} for sequence in reset_sequences]
    if payload.get("calibration_history") != expected_history:
        return {"graded": True, "passed": False, "feedback": "recalibration history does not match transcript"}

    on_bays = set(crates) == set(goals)
    completed = payload.get("completed") is True
    last_is_flush = bool(events) and events[-1].get("issued") == "FLUSH"
    passed = (
        completed
        and on_bays
        and pending is None
        and last_is_flush
        and direction_count > 0
        and flush_count > 0
        and saw_initial_queue
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"crate bays {len(set(crates) & set(goals))}/{len(goals)}; "
            f"commands {len(events)}; collisions {collisions}; resets {len(reset_sequences)}; "
            f"queue {'empty' if pending is None else 'occupied'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    solution = [str(command) for command in ground_truth.get("solution_issued_commands") or []]
    return {
        "route": solution,
        "instruction": "Issue each direction in order, then EXECUTE QUEUE.",
        "answers": [],
    }
