from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "dead_mans_switch"
_MOVES = {
    "N": (0, -1),
    "E": (1, 0),
    "S": (0, 1),
    "W": (-1, 0),
}
_RELEASE_REASONS = {"pointerup", "pointercancel", "pointerleave", "lostcapture", "blur"}


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _point(value: Any) -> tuple[int, int] | None:
    if not isinstance(value, dict):
        return None
    try:
        return int(value["x"]), int(value["y"])
    except (KeyError, TypeError, ValueError):
        return None


def _time(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number) or number < 0 or number > 3_600_000:
        return None
    return number


def _integer(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _normalized_pointer(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, dict):
        return None
    try:
        point = float(value["x"]) / 1000, float(value["y"]) / 1000
    except (KeyError, TypeError, ValueError):
        return None
    if not all(math.isfinite(item) and 0 <= item <= 1 for item in point):
        return None
    return point


def _pressure_contains(pointer: tuple[float, float], t_ms: float, motion: dict[str, Any]) -> bool:
    phase = float(motion["phase_milliradians"]) / 1000
    angle = t_ms / float(motion["period_ms"]) * math.tau + phase
    center_x = .5 + float(motion["x_amplitude_milli"]) / 1000 * math.sin(angle)
    center_y = .5 + float(motion["y_amplitude_milli"]) / 1000 * math.sin(angle * 2 + phase * .63)
    dx = (pointer[0] - center_x) / (float(motion["hit_x_milli"]) / 1000)
    dy = (pointer[1] - center_y) / (float(motion["hit_y_milli"]) / 1000)
    return dx * dx + dy * dy <= 1 + 1e-6


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
        return _failure("public and hidden course geometry disagree")
    motion = ground_truth.get("pressure_motion")
    if not isinstance(motion, dict) or public_state.get("pressure_motion") != motion:
        return _failure("public and hidden pressure motion disagree")

    board = ground_truth.get("board") or {}
    try:
        columns = int(board["columns"])
        rows = int(board["rows"])
    except (KeyError, TypeError, ValueError):
        return _failure("invalid hidden course")
    start = _point(board.get("start"))
    goal = _point(board.get("goal"))
    if start is None or goal is None:
        return _failure("invalid hidden endpoints")
    walls = {_point(item) for item in board.get("walls") or []}
    if None in walls:
        return _failure("invalid hidden wall")
    checkpoints = list(board.get("checkpoints") or [])
    checkpoint_positions = [_point(item) for item in checkpoints]
    checkpoint_ids = [str(item.get("id") or "") for item in checkpoints if isinstance(item, dict)]
    if any(item is None for item in checkpoint_positions) or len(checkpoint_ids) != len(checkpoints):
        return _failure("invalid hidden checkpoints")
    if checkpoint_ids != [str(item) for item in ground_truth.get("checkpoint_ids") or []]:
        return _failure("hidden checkpoint manifest disagrees with course geometry")

    events = payload.get("events")
    if not isinstance(events, list) or not events or len(events) > 800:
        return _failure("missing or oversized interaction transcript")

    position = start
    checkpoint_index = 0
    holding = False
    hold_start_t: float | None = None
    hold_start_seq: int | None = None
    resets = 0
    accepted_since_hold = 0
    last_pressure_sample_t: float | None = None
    pressure_samples = 0
    previous_t = -1.0
    move_directions: list[str] = []

    for index, event in enumerate(events):
        if not isinstance(event, dict):
            return _failure(f"event {index + 1} is not an object")
        try:
            seq = int(event.get("seq"))
        except (TypeError, ValueError):
            return _failure(f"event {index + 1} has no sequence")
        if seq != index + 1:
            return _failure("interaction sequence is not contiguous")
        event_t = _time(event.get("t_ms"))
        if event_t is None or event_t < previous_t:
            return _failure("interaction timestamps are invalid")
        previous_t = event_t
        event_type = str(event.get("type") or "")

        if event_type == "hold_start":
            if holding or position != start or checkpoint_index != 0:
                return _failure("pressure hold began from an invalid course state")
            holding = True
            hold_start_t = event_t
            hold_start_seq = seq
            accepted_since_hold = 0
            if _point(event.get("position")) != position:
                return _failure("hold-start position does not match replay")
            pointer = _normalized_pointer(event.get("pointer"))
            if pointer is None or not _pressure_contains(pointer, event_t, motion):
                return _failure("pressure hold did not begin on the moving plate")
            last_pressure_sample_t = event_t
            continue

        if event_type == "hold_sample":
            if not holding or last_pressure_sample_t is None:
                return _failure("pressure sample occurred outside an active hold")
            if event_t - last_pressure_sample_t > float(motion["maximum_sample_gap_ms"]):
                return _failure("moving pressure tracking has a sampling gap")
            pointer = _normalized_pointer(event.get("pointer"))
            if pointer is None or not _pressure_contains(pointer, event_t, motion):
                return _failure("pressure sample missed the moving plate")
            last_pressure_sample_t = event_t
            pressure_samples += 1
            continue

        if event_type == "hold_end":
            if not holding:
                return _failure("pressure release occurred without an active hold")
            if str(event.get("reason") or "") not in _RELEASE_REASONS:
                return _failure("unknown pressure release reason")
            if _point(event.get("position")) != position:
                return _failure("release position does not match replay")
            holding = False
            hold_start_t = None
            hold_start_seq = None
            position = start
            checkpoint_index = 0
            accepted_since_hold = 0
            last_pressure_sample_t = None
            resets += 1
            continue

        if event_type != "move":
            return _failure(f"unknown interaction event {event_type!r}")
        if not holding:
            return _failure("movement occurred while the pressure plate was released")
        if last_pressure_sample_t is None or event_t - last_pressure_sample_t > float(motion["maximum_sample_gap_ms"]):
            return _failure("vehicle moved without a recent moving-pressure sample")
        direction = str(event.get("direction") or "").upper()
        if direction not in _MOVES:
            return _failure("invalid movement direction")
        move_directions.append(direction)
        if _point(event.get("from")) != position:
            return _failure("reported movement origin does not match replay")
        dx, dy = _MOVES[direction]
        candidate = (position[0] + dx, position[1] + dy)
        accepted = (
            0 <= candidate[0] < columns
            and 0 <= candidate[1] < rows
            and candidate not in walls
        )
        if bool(event.get("accepted")) != accepted:
            return _failure("reported collision result does not match the course")
        if accepted:
            position = candidate
            accepted_since_hold += 1
            if checkpoint_index < len(checkpoint_positions) and position == checkpoint_positions[checkpoint_index]:
                checkpoint_index += 1
        if _point(event.get("to")) != position:
            return _failure("reported movement destination does not match replay")
        try:
            reported_checkpoint = int(event.get("checkpoint_index"))
        except (TypeError, ValueError):
            return _failure("movement is missing checkpoint progress")
        if reported_checkpoint != checkpoint_index:
            return _failure("reported checkpoint progress does not match replay")

    submitted_t = _time(payload.get("submitted_t_ms"))
    reported_duration = _time(payload.get("continuous_hold_duration_ms"))
    if submitted_t is None or reported_duration is None or submitted_t < previous_t:
        return _failure("completion timing is invalid")
    if not holding or hold_start_t is None or hold_start_seq is None:
        return _failure("the successful route was not covered by one continuous hold")
    replay_duration = submitted_t - hold_start_t
    if abs(reported_duration - replay_duration) > 250:
        return _failure("reported hold duration does not match the interaction transcript")
    if replay_duration < previous_t - hold_start_t:
        return _failure("pressure hold ended before the final move")
    if replay_duration < float(motion["minimum_hold_ms"]):
        return _failure("continuous moving-pressure interval was too short")
    if last_pressure_sample_t is None or submitted_t - last_pressure_sample_t > float(motion["maximum_sample_gap_ms"]):
        return _failure("moving pressure trace did not reach submission")
    if position != goal or checkpoint_index != len(checkpoint_positions):
        return _failure("course ended before every checkpoint and the dock")
    if accepted_since_hold < int(ground_truth.get("minimum_success_moves") or 0):
        return _failure("successful hold does not contain a complete traversable route")
    if payload.get("completed") is not True or payload.get("holding") is not True:
        return _failure("completion state was not active at submission")
    if _point(payload.get("final_position")) != position:
        return _failure("final position does not match replay")
    if _integer(payload.get("reset_count")) != resets:
        return _failure("reset count does not match releases")
    if _integer(payload.get("pressure_sample_count")) != pressure_samples:
        return _failure("pressure sample summary does not match replay")
    if _integer(payload.get("successful_hold_start_seq")) != hold_start_seq:
        return _failure("successful hold interval identity does not match replay")
    if [str(item) for item in payload.get("visited_checkpoints") or []] != checkpoint_ids:
        return _failure("checkpoint ledger does not match replay")
    if [str(item).upper() for item in payload.get("path") or []] != move_directions:
        return _failure("movement path does not match the full transcript")

    return {
        "graded": True,
        "passed": True,
        "score": 100,
        "feedback": (
            f"continuous hold covered {accepted_since_hold} accepted moves, "
            f"{len(checkpoint_ids)} checkpoints, and {resets} recoverable resets"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    return {
        "solution_path": list(ground_truth.get("solution_path") or []),
        "checkpoints": list((ground_truth.get("board") or {}).get("checkpoints") or []),
        "minimum_success_moves": int(ground_truth.get("minimum_success_moves") or 0),
    }
