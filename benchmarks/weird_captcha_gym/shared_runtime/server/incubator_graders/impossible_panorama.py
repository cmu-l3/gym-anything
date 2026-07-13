from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "impossible_panorama"


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def _point(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, dict):
        return None
    x, y = _number(value.get("x")), _number(value.get("y"))
    return (x, y) if x is not None and y is not None else None


def _close(first: Any, second: Any, tolerance: float = 0.08) -> bool:
    first_number, second_number = _number(first), _number(second)
    return first_number is not None and second_number is not None and abs(first_number - second_number) <= tolerance


def _same_point(claimed: Any, expected: tuple[float, float], tolerance: float = 0.08) -> bool:
    point = _point(claimed)
    return point is not None and _close(point[0], expected[0], tolerance) and _close(point[1], expected[1], tolerance)


def _round(value: float) -> float:
    return round(float(value) + 1e-12, 2)


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _time(value: Any) -> float | None:
    result = _number(value)
    return result if result is not None and 0 <= result <= 600_000 else None


def _target_contract(challenge_id: str, objects: list[dict[str, Any]], camera: dict[str, Any]) -> dict[str, Any]:
    cx, cy = float(camera["x"]), float(camera["y"])
    far_indices = [
        index
        for index, item in enumerate(objects)
        if abs(float(item["x"]) - cx) > 1080 or abs(float(item["y"]) - cy) > 670
    ]
    if not far_indices:
        raise ValueError("no off-screen event candidates")
    target_index = far_indices[int(challenge_id[:6], 16) % len(far_indices)]
    period_ms = 5880 + (int(challenge_id[6:8], 16) % 7) * 140
    return {
        "target_index": target_index,
        "target_id": str(objects[target_index]["id"]),
        "period_ms": period_ms,
        "window_ms": 1980,
        "offset_ms": int(challenge_id[8:12], 16) % period_ms,
    }


def _camera_bounds(world: dict[str, Any], viewport: dict[str, Any], zoom: float) -> tuple[float, float, float, float]:
    half_width = float(viewport["width"]) / (2 * zoom)
    half_height = float(viewport["height"]) / (2 * zoom)
    return half_width, float(world["width"]) - half_width, half_height, float(world["height"]) - half_height


def _clamp_camera(camera: tuple[float, float], world: dict[str, Any], viewport: dict[str, Any], zoom: float) -> tuple[float, float]:
    minimum_x, maximum_x, minimum_y, maximum_y = _camera_bounds(world, viewport, zoom)
    return _round(_clamp(camera[0], minimum_x, maximum_x)), _round(_clamp(camera[1], minimum_y, maximum_y))


def _sector(camera: tuple[float, float], world: dict[str, Any]) -> str:
    columns, rows = int(world["sector_columns"]), int(world["sector_rows"])
    column = min(columns - 1, max(0, int(camera[0] / (float(world["width"]) / columns))))
    row = min(rows - 1, max(0, int(camera[1] / (float(world["height"]) / rows))))
    return f"{column}:{row}"


def _target_position(item: dict[str, Any], time_ms: float) -> tuple[float, float]:
    angle = (time_ms / float(item["motion_period_ms"]) + float(item["motion_phase"])) * math.tau
    return (
        float(item["x"]) + math.cos(angle) * float(item["amp_x"]),
        float(item["y"]) + math.sin(angle * 1.17) * float(item["amp_y"]),
    )


def _phase_active(contract: dict[str, Any], time_ms: float) -> bool:
    return (time_ms + float(contract["offset_ms"])) % float(contract["period_ms"]) < float(contract["window_ms"])


def _qualified(
    time_ms: float,
    camera: tuple[float, float],
    zoom: float,
    focus: float,
    target: dict[str, Any],
    contract: dict[str, Any],
    viewport: dict[str, Any],
    qualification: dict[str, Any],
) -> bool:
    target_x, target_y = _target_position(target, time_ms)
    projection_x = float(viewport["width"]) / 2 + (target_x - camera[0]) * zoom
    projection_y = float(viewport["height"]) / 2 + (target_y - camera[1]) * zoom
    reticle_distance = math.hypot(projection_x - float(viewport["width"]) / 2, projection_y - float(viewport["height"]) / 2)
    return (
        _phase_active(contract, time_ms)
        and float(qualification["minimum_zoom"]) <= zoom <= float(qualification["maximum_zoom"])
        and abs(focus - float(target["depth"])) <= float(qualification["focus_tolerance"])
        and reticle_distance <= float(qualification["reticle_radius"])
    )


def _camera_claim(value: Any, camera: tuple[float, float], zoom: float, focus: float) -> bool:
    if not isinstance(value, dict):
        return False
    return _close(value.get("x"), camera[0]) and _close(value.get("y"), camera[1]) and _close(value.get("zoom"), zoom) and _close(value.get("focus"), focus)


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    task_id = str(ground_truth.get("task_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("mechanic mismatch")
    if str(payload.get("task_id") or "") != task_id:
        return _failure("task mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return _failure("stale challenge")
    if str(public_state.get("mechanic_id") or "") != MECHANIC_ID or str(public_state.get("challenge_id") or "") != challenge_id or str(public_state.get("task_id") or "") != task_id:
        return _failure("public panorama identity mismatch")

    objects = ground_truth.get("objects")
    world = ground_truth.get("world")
    viewport = ground_truth.get("viewport")
    initial = ground_truth.get("initial_camera")
    controls = ground_truth.get("controls")
    qualification = ground_truth.get("qualification")
    expected_objects = int(world.get("sector_columns", 0)) * int(world.get("sector_rows", 0)) if isinstance(world, dict) else 0
    if not isinstance(objects, list) or len(objects) != expected_objects or expected_objects < 24 or not all(isinstance(value, dict) for value in (world, viewport, initial, controls, qualification)):
        return _failure("hidden panorama manifest is malformed")
    if public_state.get("objects") != objects or public_state.get("world") != world or public_state.get("viewport") != viewport or public_state.get("initial_camera") != initial or public_state.get("controls") != controls or public_state.get("qualification") != qualification:
        return _failure("public panorama geometry disagrees with hidden state")
    object_ids = [str(item.get("id") or "") for item in objects]
    if "" in object_ids or len(set(object_ids)) != len(object_ids):
        return _failure("panorama specimen identities are malformed")
    try:
        contract = _target_contract(challenge_id, objects, initial)
    except (KeyError, TypeError, ValueError):
        return _failure("challenge event derivation failed")
    hidden_contract = ground_truth.get("event_contract") or {}
    if str(ground_truth.get("target_id") or "") != contract["target_id"] or any(not _close(hidden_contract.get(key), contract[key], 1e-9) for key in ("period_ms", "window_ms", "offset_ms")):
        return _failure("hidden event does not match challenge derivation")
    target = objects[int(contract["target_index"])]

    try:
        camera = (float(initial["x"]), float(initial["y"]))
        zoom, focus = float(initial["zoom"]), float(initial["focus"])
        view_width, view_height = float(viewport["width"]), float(viewport["height"])
    except (KeyError, TypeError, ValueError):
        return _failure("initial optic state is malformed")
    events = payload.get("events")
    if not isinstance(events, list) or not events or len(events) > 1200:
        return _failure("panorama transcript is missing or too long")

    panning = False
    holding = False
    terminal = False
    pointer = (0.0, 0.0)
    visited = [_sector(camera, world)]
    pan_moves = 0
    pan_travel = 0.0
    zoom_changes = 0
    focus_changes = 0
    reset_count = 0
    shutter_attempts = 0
    valid_holds = 0
    hold_start_time = 0.0
    hold_camera = camera
    hold_zoom = zoom
    hold_focus = focus
    hold_samples: list[float] = []
    previous_time = -1.0

    for sequence, event in enumerate(events, start=1):
        if terminal:
            return _failure(f"event {sequence} occurs after terminal verification")
        if not isinstance(event, dict) or event.get("seq") != sequence:
            return _failure(f"event {sequence} has invalid sequence")
        event_time = _time(event.get("t_ms"))
        if event_time is None or event_time < previous_time:
            return _failure(f"event {sequence} has invalid timestamp")
        previous_time = event_time
        action = str(event.get("type") or "")

        if action == "pan_start":
            raw_pointer = _point(event.get("pointer"))
            if panning or holding or raw_pointer is None or not (-12 <= raw_pointer[0] <= view_width + 12 and -12 <= raw_pointer[1] <= view_height + 12):
                return _failure(f"pan start {sequence} is physically impossible")
            if not _camera_claim(event.get("camera"), camera, zoom, focus):
                return _failure(f"pan start {sequence} reports stale optics")
            pointer = raw_pointer
            panning = True
            continue

        if action == "pan_move":
            raw_pointer = _point(event.get("pointer"))
            claimed_from = _point(event.get("from"))
            claimed_to = _point(event.get("to"))
            if not panning or holding or raw_pointer is None or claimed_from is None or claimed_to is None:
                return _failure(f"pan move {sequence} occurs outside a drag")
            screen_delta = math.hypot(raw_pointer[0] - pointer[0], raw_pointer[1] - pointer[1])
            if screen_delta > 225:
                return _failure(f"pan move {sequence} teleports across the viewport")
            if not _close(claimed_from[0], camera[0]) or not _close(claimed_from[1], camera[1]):
                return _failure(f"pan move {sequence} has a stale origin")
            expected = _clamp_camera((camera[0] - (raw_pointer[0] - pointer[0]) / zoom, camera[1] - (raw_pointer[1] - pointer[1]) / zoom), world, viewport, zoom)
            if not _close(claimed_to[0], expected[0]) or not _close(claimed_to[1], expected[1]):
                return _failure(f"pan move {sequence} reports false geometry")
            pan_travel += math.hypot(expected[0] - camera[0], expected[1] - camera[1])
            camera = expected
            pointer = raw_pointer
            pan_moves += 1
            sector = _sector(camera, world)
            if sector not in visited:
                visited.append(sector)
            continue

        if action == "pan_end":
            raw_pointer = _point(event.get("pointer"))
            if not panning or holding or raw_pointer is None or not _camera_claim(event.get("camera"), camera, zoom, focus):
                return _failure(f"pan end {sequence} is malformed")
            panning = False
            pointer = raw_pointer
            continue

        if action == "pan_nudge":
            direction = str(event.get("direction") or "")
            claimed_from = _point(event.get("from"))
            claimed_to = _point(event.get("to"))
            if panning or holding or direction not in {"left", "right", "up", "down"} or claimed_from is None or claimed_to is None:
                return _failure(f"pan nudge {sequence} has impossible ordering")
            if not _close(claimed_from[0], camera[0]) or not _close(claimed_from[1], camera[1]):
                return _failure(f"pan nudge {sequence} has a stale origin")
            distance = float(controls["pan_nudge_px"]) / zoom
            dx = (-distance if direction == "left" else distance if direction == "right" else 0.0)
            dy = (-distance if direction == "up" else distance if direction == "down" else 0.0)
            expected = _clamp_camera((camera[0] + dx, camera[1] + dy), world, viewport, zoom)
            if not _close(claimed_to[0], expected[0]) or not _close(claimed_to[1], expected[1]):
                return _failure(f"pan nudge {sequence} reports false geometry")
            pan_travel += math.hypot(expected[0] - camera[0], expected[1] - camera[1])
            camera = expected
            pan_moves += 1
            sector = _sector(camera, world)
            if sector not in visited:
                visited.append(sector)
            continue

        if action == "zoom":
            source = str(event.get("source") or "")
            before, after = _number(event.get("from")), _number(event.get("to"))
            if panning or holding or before is None or after is None or not _close(before, zoom):
                return _failure(f"zoom event {sequence} has impossible ordering or origin")
            minimum, maximum, step = float(controls["zoom_min"]), float(controls["zoom_max"]), float(controls["zoom_step"])
            if source == "button_in":
                expected_zoom = _round(_clamp(zoom + step, minimum, maximum))
            elif source == "button_out":
                expected_zoom = _round(_clamp(zoom - step, minimum, maximum))
            elif source == "slider":
                expected_zoom = _round(_clamp(after, minimum, maximum))
                if abs((expected_zoom - minimum) / step - round((expected_zoom - minimum) / step)) > 1e-5:
                    return _failure(f"zoom slider {sequence} is off its physical step")
            else:
                return _failure(f"zoom event {sequence} has unknown control source")
            if not _close(after, expected_zoom):
                return _failure(f"zoom event {sequence} reports false optics")
            zoom = expected_zoom
            camera = _clamp_camera(camera, world, viewport, zoom)
            if not _same_point(event.get("camera_after"), camera):
                return _failure(f"zoom event {sequence} reports a false clamped camera")
            zoom_changes += 1
            continue

        if action == "focus":
            before, after = _number(event.get("from")), _number(event.get("to"))
            if panning or holding or str(event.get("source") or "") != "slider" or before is None or after is None or not _close(before, focus):
                return _failure(f"focus event {sequence} has impossible ordering or origin")
            minimum, maximum, step = float(controls["focus_min"]), float(controls["focus_max"]), float(controls["focus_step"])
            expected_focus = _round(_clamp(after, minimum, maximum))
            if abs((expected_focus - minimum) / step - round((expected_focus - minimum) / step)) > 1e-5:
                return _failure(f"focus slider {sequence} is off its physical step")
            if not _close(event.get("to"), expected_focus):
                return _failure(f"focus event {sequence} reports false optics")
            focus = expected_focus
            focus_changes += 1
            continue

        if action == "reset":
            if panning or holding:
                return _failure("reset occurred during an active gesture")
            camera = (float(initial["x"]), float(initial["y"]))
            zoom, focus = float(initial["zoom"]), float(initial["focus"])
            visited = [_sector(camera, world)]
            pan_moves = 0
            pan_travel = 0.0
            zoom_changes = 0
            focus_changes = 0
            shutter_attempts = 0
            valid_holds = 0
            reset_count += 1
            if not _camera_claim(event.get("camera_after"), camera, zoom, focus):
                return _failure("reset does not restore the manifest optics")
            continue

        if action == "shutter_start":
            if panning or holding or not _camera_claim(event.get("camera"), camera, zoom, focus):
                return _failure(f"shutter start {sequence} has impossible ordering or stale optics")
            holding = True
            hold_start_time = event_time
            hold_camera, hold_zoom, hold_focus = camera, zoom, focus
            hold_samples = []
            shutter_attempts += 1
            continue

        if action == "shutter_sample":
            if not holding or panning or not _camera_claim(event.get("camera"), camera, zoom, focus):
                return _failure(f"shutter sample {sequence} is not bound to a stable hold")
            if hold_samples and event_time - hold_samples[-1] > float(qualification["maximum_sample_gap_ms"]):
                return _failure(f"shutter sample {sequence} leaves an unverifiable timing gap")
            hold_samples.append(event_time)
            continue

        if action == "shutter_end":
            if not holding or panning or not _camera_claim(event.get("camera"), camera, zoom, focus):
                return _failure(f"shutter end {sequence} is malformed")
            duration = event_time - hold_start_time
            maximum_gap = float(qualification["maximum_sample_gap_ms"])
            gap_ok = bool(hold_samples) and hold_samples[0] - hold_start_time <= maximum_gap and event_time - hold_samples[-1] <= maximum_gap
            stable = camera == hold_camera and _close(zoom, hold_zoom, 1e-9) and _close(focus, hold_focus, 1e-9)
            times = [hold_start_time, *hold_samples, event_time]
            qualified_hold = (
                duration >= float(qualification["minimum_hold_ms"])
                and len(hold_samples) >= int(qualification["minimum_hold_samples"])
                and gap_ok
                and stable
                and all(_qualified(sample_time, camera, zoom, focus, target, contract, viewport, qualification) for sample_time in times)
            )
            if qualified_hold:
                valid_holds += 1
            holding = False
            continue

        if action == "verify":
            if panning or holding:
                return _failure("verification occurred during an active gesture")
            terminal = True
            continue

        return _failure(f"event {sequence} has invalid action {action!r}")

    if not terminal:
        return _failure("transcript has no terminal verification")
    expected_state = {
        "camera": {"x": _round(camera[0]), "y": _round(camera[1]), "zoom": _round(zoom), "focus": _round(focus)},
        "visited_sectors": visited,
        "pan_moves": pan_moves,
        "pan_travel": _round(pan_travel),
        "zoom_changes": zoom_changes,
        "focus_changes": focus_changes,
        "shutter_attempts": shutter_attempts,
        "valid_holds": valid_holds,
        "reset_count": reset_count,
    }
    if payload.get("final_state") != expected_state:
        return _failure("claimed panorama state does not match primitive replay")
    # Search distance is evidence, not a hidden admission fee. A lucky operator
    # who finds the transient specimen early should pass if the independently
    # replayed optics and sustained exposure are genuinely correct.
    passed = valid_holds >= 1
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": f"replayed {pan_moves} pan primitives across {len(visited)} sectors; travel {pan_travel:.1f}; optics {zoom:.2f}/{focus:.0f}; qualified shutter holds {valid_holds}/{shutter_attempts}; resets {reset_count}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "target_id": ground_truth.get("target_id"),
        "event_contract": ground_truth.get("event_contract") or {},
        "solution": ground_truth.get("solution") or {},
        "answers": [],
    }
