from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "trajectory_catcher"


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _finite(value: Any) -> float | None:
    try: number = float(value)
    except (TypeError, ValueError): return None
    return number if math.isfinite(number) else None


def _close(first: Any, second: Any, tolerance: float = 0.12) -> bool:
    a, b = _finite(first), _finite(second)
    return a is not None and b is not None and abs(a - b) <= tolerance


def _point(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, dict): return None
    x, y = _finite(value.get("x")), _finite(value.get("y"))
    return None if x is None or y is None else (x, y)


def _path(round_data: dict[str, Any], t_ms: float) -> tuple[float, float]:
    duration = float(round_data["duration_ms"])
    u = _clamp(t_ms / duration, 0.0, 1.0)
    travel = u if round_data["direction"] == "ltr" else 1.0 - u
    x = 70.0 + travel * 760.0
    base, amplitude, wobble, phase = (float(round_data[key]) for key in ("base_y", "amplitude", "wobble", "phase"))
    if round_data["family"] == "ballistic_arc":
        y = base + amplitude * (4.0 * u * (1.0 - u) - 0.48) + wobble * math.sin(math.tau * u + phase)
    elif round_data["family"] == "sine_drift":
        y = base + amplitude * math.sin(math.tau * (u + phase)) + wobble * math.sin(6.0 * math.pi * u)
    else:
        centered = 2.0 * u - 1.0
        y = base + amplitude * (centered**3 - 0.34 * centered) + wobble * math.sin(4.0 * math.pi * u + phase)
    return x, y


def _velocity_angle(round_data: dict[str, Any], t_ms: float) -> float:
    before = _path(round_data, max(0.0, t_ms - 6.0))
    after = _path(round_data, min(float(round_data["duration_ms"]), t_ms + 6.0))
    return math.degrees(math.atan2(after[1] - before[1], after[0] - before[0])) % 360.0


def _local(point: tuple[float, float], catcher: dict[str, Any]) -> tuple[float, float]:
    radians = math.radians(float(catcher["angle_deg"]))
    cosine, sine = math.cos(radians), math.sin(radians)
    dx, dy = point[0] - float(catcher["x"]), point[1] - float(catcher["y"])
    return dx * cosine + dy * sine, -dx * sine + dy * cosine


def _angle_error(first: float, second: float) -> float:
    return abs((first - second + 90.0) % 180.0 - 90.0)


def _swept_catch(round_data: dict[str, Any], catcher: dict[str, Any]) -> tuple[bool, float | None]:
    if not catcher.get("armed"): return False, None
    previous_t = float(round_data["wall_exit_ms"])
    previous_local = _local(_path(round_data, previous_t), catcher)
    current_t = previous_t + 10.0
    end = float(round_data["duration_ms"])
    while current_t <= end + 1e-6:
        current_local = _local(_path(round_data, current_t), catcher)
        if previous_local[0] == 0 or current_local[0] == 0 or previous_local[0] * current_local[0] < 0:
            denominator = previous_local[0] - current_local[0]
            amount = 0.0 if abs(denominator) < 1e-9 else _clamp(previous_local[0] / denominator, 0.0, 1.0)
            crossing_t = previous_t + (current_t - previous_t) * amount
            crossing_y = previous_local[1] + (current_local[1] - previous_local[1]) * amount
            clearance = float(catcher["aperture"]) / 2.0 - float(round_data["projectile_radius"])
            if clearance >= 0 and abs(crossing_y) <= clearance + 1e-9 and _angle_error(_velocity_angle(round_data, crossing_t), float(catcher["angle_deg"])) <= float(round_data["alignment_tolerance_deg"]) + 1e-9:
                return True, crossing_t
        previous_t, previous_local = current_t, current_local
        current_t += 10.0
    return False, None


def _catcher(raw: dict[str, Any]) -> dict[str, Any]:
    initial = raw["initial_catcher"]
    return {"x": float(initial["x"]), "y": float(initial["y"]), "angle_deg": int(initial["angle_deg"]) % 180, "aperture": int(initial["aperture"]), "armed": False}


def _state_matches(value: Any, state: dict[str, Any]) -> bool:
    if not isinstance(value, dict): return False
    return _close(value.get("x"), state["x"]) and _close(value.get("y"), state["y"]) and value.get("angle_deg") == state["angle_deg"] and value.get("aperture") == state["aperture"] and bool(value.get("armed")) == bool(state["armed"])


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID: return _failure("mechanic mismatch")
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id or str(public_state.get("task_id") or "") != task_id: return _failure("task identity mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id: return _failure("stale challenge")
    if str(public_state.get("challenge_id") or "") != challenge_id or str(public_state.get("mechanic_id") or "") != MECHANIC_ID: return _failure("public flight log does not match hidden state")
    rounds = ground_truth.get("rounds")
    if not isinstance(rounds, list) or len(rounds) < 3 or public_state.get("rounds") != rounds: return _failure("analytic flight schedule is missing or inconsistent")
    events = payload.get("events")
    if not isinstance(events, list) or not events or len(events) > 1800: return _failure("flight transcript is missing or too long")

    current_index = 0
    expected_attempt = 0
    phase = "await_start"
    context: dict[str, Any] | None = None
    completed: list[str] = []
    replay_used = {str(item["id"]): 0 for item in rounds}
    attempt_counts = {str(item["id"]): 0 for item in rounds}
    replay_count = 0
    catcher_reset_count = 0
    challenge_reset_count = 0
    caught_crossings: list[float] = []
    previous_global = -1.0

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("seq") != sequence: return _failure(f"flight event {sequence} has invalid sequence")
        global_t = _finite(event.get("t_ms"))
        if global_t is None or global_t < previous_global or global_t > 7_200_000: return _failure(f"flight event {sequence} has invalid timestamp")
        previous_global = global_t
        action = str(event.get("type") or "")
        if phase == "final_terminal": return _failure("flight transcript continues after terminal catch")

        if action == "challenge_reset":
            if phase not in {"terminal_miss", "terminal_caught"}: return _failure("challenge reset occurred during an active flight")
            current_index, expected_attempt, phase, context = 0, 0, "await_start", None
            completed = []
            replay_used = {str(item["id"]): 0 for item in rounds}
            challenge_reset_count += 1
            if event.get("next_round_id") != rounds[0]["id"]: return _failure("challenge reset points at the wrong flight")
            continue

        if action == "replay":
            if phase != "terminal_miss" or context is None: return _failure("round replay occurred without a physical miss")
            round_data = rounds[current_index]
            round_id = str(round_data["id"])
            if event.get("round_id") != round_id or event.get("attempt_before") != expected_attempt or replay_used[round_id] >= int(round_data["replay_limit"]): return _failure("round replay exceeds its budget or replays the wrong attempt")
            replay_used[round_id] += 1
            replay_count += 1
            expected_attempt += 1
            phase, context = "await_start", None
            continue

        if action == "advance":
            if phase != "terminal_caught" or current_index >= len(rounds) - 1: return _failure("round advance occurred without a completed non-final catch")
            if event.get("from_round_id") != rounds[current_index]["id"] or event.get("to_round_id") != rounds[current_index + 1]["id"]: return _failure("round advance targets the wrong flight")
            current_index += 1
            expected_attempt = 0
            phase, context = "await_start", None
            continue

        if action == "round_start":
            if phase != "await_start": return _failure("round starts in an impossible order")
            round_data = rounds[current_index]
            if event.get("round_id") != round_data["id"] or event.get("attempt") != expected_attempt or event.get("round_t_ms") != 0: return _failure("round start identity disagrees with replay")
            context = {
                "catcher": _catcher(round_data), "last_round_t": 0.0, "observations": [], "dragging": False,
                "drag_offset": (0.0, 0.0), "last_pointer": None, "drag_moves": 0, "rotations": 0, "resizes": 0,
                "global_start": global_t,
            }
            attempt_counts[str(round_data["id"])] += 1
            phase = "running"
            continue

        if phase != "running" or context is None: return _failure(f"flight action {action!r} occurs outside a running round")
        round_data = rounds[current_index]
        if event.get("round_id") != round_data["id"] or event.get("attempt") != expected_attempt: return _failure(f"flight event {sequence} is bound to the wrong round")
        round_t = _finite(event.get("round_t_ms"))
        if round_t is None or round_t < context["last_round_t"] or round_t > float(round_data["duration_ms"]) + 500: return _failure(f"flight event {sequence} has impossible round time")
        if abs(round_t - (global_t - context["global_start"])) > 90: return _failure(f"flight event {sequence} compresses or dilates real elapsed time")
        context["last_round_t"] = round_t
        hidden_start = float(round_data["wall_enter_ms"])
        commit_deadline = float(round_data["wall_exit_ms"]) - float(round_data["commit_margin_ms"])
        in_commit_window = hidden_start <= round_t <= commit_deadline

        if action == "observe_sample":
            position = _point(event.get("position"))
            expected = _path(round_data, round_t)
            if round_t > hidden_start or position is None or not _close(position[0], expected[0]) or not _close(position[1], expected[1]): return _failure(f"observation sample {sequence} exposes or misreports the hidden flight")
            context["observations"].append(round_t)
            continue
        if action == "catcher_drag_start":
            point = _point(event.get("pointer"))
            state = context["catcher"]
            if not in_commit_window or state["armed"] or context["dragging"] or point is None or math.hypot(point[0] - state["x"], point[1] - state["y"]) > 42: return _failure(f"catcher drag {sequence} starts outside the hidden physical handle")
            context["drag_offset"] = (point[0] - state["x"], point[1] - state["y"])
            context["last_pointer"] = point
            context["dragging"] = True
            if not _state_matches(event.get("catcher_before"), state): return _failure(f"catcher drag {sequence} reports stale state")
            continue
        if action == "catcher_drag_move":
            point = _point(event.get("pointer"))
            before = _point(event.get("from"))
            after = _point(event.get("to"))
            state = context["catcher"]
            if not in_commit_window or not context["dragging"] or state["armed"] or point is None or before is None or after is None: return _failure(f"catcher drag move {sequence} occurs outside a valid drag")
            if math.hypot(point[0] - context["last_pointer"][0], point[1] - context["last_pointer"][1]) > 150: return _failure(f"catcher drag move {sequence} teleports")
            if not _close(before[0], state["x"]) or not _close(before[1], state["y"]): return _failure(f"catcher drag move {sequence} has a stale origin")
            expected_x = round(_clamp(point[0] - context["drag_offset"][0], 34, 866), 2)
            expected_y = round(_clamp(point[1] - context["drag_offset"][1], 34, 446), 2)
            if not _close(after[0], expected_x) or not _close(after[1], expected_y): return _failure(f"catcher drag move {sequence} reports a false destination")
            state["x"], state["y"] = expected_x, expected_y
            context["last_pointer"] = point
            context["drag_moves"] += 1
            continue
        if action == "catcher_drag_end":
            point = _point(event.get("pointer"))
            # Releasing after the commit horn changes no geometry and must not
            # poison a later replay; only drag starts/moves are commit-gated.
            if not context["dragging"] or point is None or not _state_matches(event.get("catcher_after"), context["catcher"]): return _failure(f"catcher drag end {sequence} is malformed")
            context["dragging"] = False
            continue
        if action == "catcher_rotate":
            state = context["catcher"]
            delta = event.get("delta_deg")
            if not in_commit_window or state["armed"] or context["dragging"] or delta not in {-15, 15} or event.get("angle_before") != state["angle_deg"]: return _failure(f"catcher rotation {sequence} is malformed")
            state["angle_deg"] = (state["angle_deg"] + int(delta)) % 180
            if event.get("angle_after") != state["angle_deg"]: return _failure(f"catcher rotation {sequence} lies about orientation")
            context["rotations"] += 1
            continue
        if action == "catcher_resize":
            state = context["catcher"]
            delta = event.get("delta")
            if not in_commit_window or state["armed"] or context["dragging"] or delta not in {-10, 10} or event.get("aperture_before") != state["aperture"]: return _failure(f"catcher resize {sequence} is malformed")
            next_aperture = state["aperture"] + int(delta)
            if not int(round_data["aperture_min"]) <= next_aperture <= int(round_data["aperture_max"]): return _failure("catcher resize exceeds physical stops")
            state["aperture"] = next_aperture
            if event.get("aperture_after") != state["aperture"]: return _failure(f"catcher resize {sequence} lies about aperture")
            context["resizes"] += 1
            continue
        if action == "catcher_reset":
            if not in_commit_window or context["catcher"]["armed"] or context["dragging"]: return _failure("catcher reset occurred outside the hidden setup interval")
            context["catcher"] = _catcher(round_data)
            context["drag_moves"] = 0
            context["rotations"] = 0
            context["resizes"] = 0
            catcher_reset_count += 1
            if not _state_matches(event.get("catcher_after"), context["catcher"]): return _failure("catcher reset does not restore its stops")
            continue
        if action == "arm":
            state = context["catcher"]
            if not in_commit_window or state["armed"] or context["dragging"]: return _failure("catcher was armed outside the pre-emergence commitment window")
            state["armed"] = True
            if not _state_matches(event.get("catcher"), state): return _failure("arm event reports a false catcher transform")
            continue
        if action == "round_result":
            if round_t < float(round_data["duration_ms"]) - 80 or context["dragging"]: return _failure("round terminated before its analytic flight completed")
            observations = context["observations"]
            if len(observations) < 8 or max(observations) - min(observations) < float(round_data["minimum_observation_ms"]): return _failure("round lacks genuine visible observation duration")
            caught, crossing = _swept_catch(round_data, context["catcher"])
            if bool(event.get("caught")) != caught or not _state_matches(event.get("catcher"), context["catcher"]): return _failure("round result disagrees with swept catcher geometry")
            if caught:
                if context["drag_moves"] < 2 or context["rotations"] < 1 or context["resizes"] < 1: return _failure("successful catch lacks physical placement, rotation, or sizing")
                if not _close(event.get("crossing_ms"), crossing, 0.15): return _failure("reported crossing time disagrees with swept replay")
                completed.append(str(round_data["id"]))
                caught_crossings.append(float(crossing))
                phase = "final_terminal" if current_index == len(rounds) - 1 else "terminal_caught"
            else:
                if event.get("crossing_ms") is not None: return _failure("miss reports a fabricated crossing")
                phase = "terminal_miss"
            continue
        return _failure(f"flight event {sequence} has invalid action {action!r}")

    expected_final = {
        "completed_round_ids": completed,
        "replay_count": replay_count,
        "catcher_reset_count": catcher_reset_count,
        "challenge_reset_count": challenge_reset_count,
        "round_attempt_counts": [{"round_id": str(item["id"]), "attempts": attempt_counts[str(item["id"])]} for item in rounds],
    }
    if payload.get("final_state") != expected_final: return _failure("claimed final flight state does not match transcript replay")
    passed = phase == "final_terminal" and completed == [str(item["id"]) for item in rounds] and len(caught_crossings) == len(rounds)
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": f"replayed {len(completed)}/{len(rounds)} swept catches; replays {replay_count}; catcher resets {catcher_reset_count}; challenge resets {challenge_reset_count}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"solutions": ground_truth.get("solutions") or [], "answers": []}
