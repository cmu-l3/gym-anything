from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "jigsaw_slider_alignment"


def _fail(feedback: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "feedback": feedback}


def _js_round(value: float) -> int:
    return math.floor(value + 0.5)


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    return value


def _clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, value))


def _project_offset(depth_milli: int, parallax_milli: int) -> int:
    return _js_round((depth_milli - 500) * parallax_milli / 1000)


def _layer(scene: dict[str, Any], layer_id: str) -> dict[str, Any]:
    for item in scene.get("layers") or []:
        if isinstance(item, dict) and item.get("id") == layer_id:
            return item
    raise ValueError("gap layer is missing")


def _geometry(
    scene: dict[str, Any], rail_milli: int, depth_milli: int, target_depth_milli: int
) -> tuple[int, int]:
    gap = scene["gap"]
    piece = scene["piece"]
    gap_layer = _layer(scene, str(gap["layer_id"]))
    gap_x = int(gap["base_x_milli"]) + _project_offset(depth_milli, int(gap_layer["parallax_milli"]))
    piece_x = rail_milli + _project_offset(depth_milli, int(piece["parallax_milli"]))
    return abs(piece_x - gap_x), abs(depth_milli - target_depth_milli)


def _bind(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> str | None:
    for label, source in (("payload", payload), ("ground-truth", ground_truth), ("public-state", public_state)):
        if str(source.get("mechanic_id") or "") != MECHANIC_ID:
            return f"{label} mechanic mismatch"
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return "stale challenge"
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return "public-state challenge mismatch"
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return "payload task mismatch"
    if str(public_state.get("task_id") or "") != task_id:
        return "public-state task mismatch"
    return None


def _scaled_size(base_milli: int, depth_milli: int, scale_base_milli: int, scale_span_milli: int) -> int:
    scale = scale_base_milli + _js_round(scale_span_milli * depth_milli / 1000)
    return _js_round(base_milli * scale / 1000)


def _contract(
    ground_truth: dict[str, Any], public_state: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, int], dict[str, int], int, int]:
    scene = ground_truth.get("scene")
    if not isinstance(scene, dict) or public_state.get("scene") != scene:
        raise ValueError("public scene differs from hidden scene contract")
    tolerances = ground_truth.get("tolerances")
    inertia = ground_truth.get("inertia")
    if not isinstance(tolerances, dict) or public_state.get("tolerances") != tolerances:
        raise ValueError("tolerance contract mismatch")
    if not isinstance(inertia, dict) or public_state.get("inertia") != inertia:
        raise ValueError("inertia contract mismatch")
    target_rail = _integer(ground_truth.get("target_rail_milli"), "target rail")
    target_depth = _integer(ground_truth.get("target_depth_milli"), "target depth")
    rail = scene.get("rail")
    depth = scene.get("depth")
    piece = scene.get("piece")
    gap = scene.get("gap")
    if not all(isinstance(item, dict) for item in (rail, depth, piece, gap)):
        raise ValueError("scene controls are malformed")
    gap_layer = _layer(scene, str(gap.get("layer_id") or ""))
    expected_target = int(gap["base_x_milli"]) + _project_offset(target_depth, int(gap_layer["parallax_milli"]))
    expected_target -= _project_offset(target_depth, int(piece["parallax_milli"]))
    if target_rail != expected_target:
        raise ValueError("hidden target rail disagrees with analytic projection")
    expected_y = int(piece["base_y_milli"]) + _js_round(target_depth * int(piece["vertical_span_milli"]) / 1000)
    expected_width = _scaled_size(
        int(piece["base_width_milli"]), target_depth, int(piece["scale_base_milli"]), int(piece["scale_span_milli"])
    )
    expected_height = _scaled_size(
        int(piece["base_height_milli"]), target_depth, int(piece["scale_base_milli"]), int(piece["scale_span_milli"])
    )
    if (gap.get("y_milli"), gap.get("width_milli"), gap.get("height_milli")) != (
        expected_y,
        expected_width,
        expected_height,
    ):
        raise ValueError("gap projection disagrees with target depth")
    return scene, {key: int(value) for key, value in tolerances.items()}, {key: int(value) for key, value in inertia.items()}, target_rail, target_depth


def _event_state(event: dict[str, Any], rail_milli: int, depth_milli: int, index: int) -> str | None:
    if event.get("rail_milli") != rail_milli:
        return f"event {index} rail does not match replay"
    if event.get("depth_milli") != depth_milli:
        return f"event {index} depth does not match replay"
    return None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    binding_error = _bind(payload, ground_truth, public_state)
    if binding_error:
        return _fail(binding_error)
    try:
        scene, tolerances, inertia_contract, target_rail, target_depth = _contract(ground_truth, public_state)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid alignment contract: {exc}")

    events = payload.get("events")
    if not isinstance(events, list) or not (3 <= len(events) <= 800):
        return _fail("alignment transcript is missing or outside limits")
    rail_contract = scene["rail"]
    depth_contract = scene["depth"]
    rail_min, rail_max = int(rail_contract["minimum_milli"]), int(rail_contract["maximum_milli"])
    depth_min, depth_max = int(depth_contract["minimum_milli"]), int(depth_contract["maximum_milli"])
    rail_milli = int(rail_contract["initial_milli"])
    depth_milli = int(depth_contract["initial_milli"])
    mode = "idle"
    last_rail_delta = 0
    last_rail_dt = 1
    inertia_state: dict[str, Any] | None = None
    rail_travel = 0
    depth_travel = 0
    rail_sample_count = 0
    depth_sample_count = 0
    inertia_samples = 0
    scan_samples: list[tuple[int, int]] = []
    scan_duration = 0
    scan_complete = False

    for index, event in enumerate(events, start=1):
        if scan_complete:
            return _fail("transcript continues after optical lock release")
        if not isinstance(event, dict) or event.get("sequence") != index:
            return _fail(f"event {index} has an invalid sequence")
        event_type = str(event.get("type") or "")

        if event_type == "rail_start":
            if mode != "idle":
                return _fail(f"event {index} starts a rail drag while {mode}")
            mode = "rail"
            last_rail_delta, last_rail_dt = 0, 1
        elif event_type == "rail_sample":
            if mode != "rail":
                return _fail(f"event {index} has a rail sample outside a drag")
            try:
                delta = _integer(event.get("delta_milli"), "rail delta")
                dt_ms = _integer(event.get("dt_ms"), "rail sample time")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if not 1 <= dt_ms <= 250 or abs(delta) > 700000:
                return _fail(f"event {index} rail sample lies outside limits")
            expected = _clamp(rail_milli + delta, rail_min, rail_max)
            if expected - rail_milli != delta:
                return _fail(f"event {index} rail delta crosses a hard stop")
            rail_milli = expected
            rail_travel += abs(delta)
            rail_sample_count += 1
            last_rail_delta, last_rail_dt = delta, dt_ms
        elif event_type == "rail_end":
            if mode != "rail":
                return _fail(f"event {index} ends a rail drag that is not active")
            velocity_cap = inertia_contract["velocity_cap_milli_s"]
            expected_velocity = _clamp(_js_round(last_rail_delta * 1000 / last_rail_dt), -velocity_cap, velocity_cap)
            if event.get("velocity_milli_s") != expected_velocity:
                return _fail(f"event {index} release velocity disagrees with pointer samples")
            if abs(expected_velocity) >= inertia_contract["velocity_threshold_milli_s"]:
                mode = "inertia"
                inertia_state = {"velocity": expected_velocity, "must_end": False, "reason": None}
            else:
                mode = "idle"
        elif event_type == "inertia_sample":
            if mode != "inertia" or inertia_state is None or inertia_state["must_end"]:
                return _fail(f"event {index} has an impossible inertia sample")
            velocity = int(inertia_state["velocity"])
            expected_raw = _js_round(velocity * inertia_contract["tick_ms"] / 1000)
            next_rail = _clamp(rail_milli + expected_raw, rail_min, rail_max)
            expected_delta = next_rail - rail_milli
            expected_velocity_after = _js_round(velocity * inertia_contract["friction_milli"] / 1000)
            reason = None
            if expected_delta == 0:
                expected_velocity_after = 0
                reason = "boundary"
            elif abs(expected_velocity_after) < inertia_contract["stop_velocity_milli_s"]:
                reason = "friction"
            if event.get("delta_milli") != expected_delta or event.get("velocity_after_milli_s") != expected_velocity_after:
                return _fail(f"event {index} inertia does not match the friction replay")
            rail_milli = next_rail
            inertia_samples += 1
            inertia_state = {
                "velocity": expected_velocity_after,
                "must_end": reason is not None,
                "reason": reason,
            }
        elif event_type == "inertia_end":
            if mode != "inertia" or inertia_state is None or not inertia_state["must_end"]:
                return _fail(f"event {index} stops inertia before friction or a hard stop")
            if event.get("reason") != inertia_state["reason"]:
                return _fail(f"event {index} reports the wrong inertia-stop reason")
            mode = "idle"
            inertia_state = None
        elif event_type == "depth_start":
            if mode != "idle":
                return _fail(f"event {index} starts a depth drag while {mode}")
            mode = "depth"
        elif event_type == "depth_sample":
            if mode != "depth":
                return _fail(f"event {index} has a depth sample outside a drag")
            try:
                delta = _integer(event.get("delta_milli"), "depth delta")
                dt_ms = _integer(event.get("dt_ms"), "depth sample time")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if not 1 <= dt_ms <= 250 or abs(delta) > 1000:
                return _fail(f"event {index} depth sample lies outside limits")
            expected = _clamp(depth_milli + delta, depth_min, depth_max)
            if expected - depth_milli != delta:
                return _fail(f"event {index} depth delta crosses a hard stop")
            depth_milli = expected
            depth_travel += abs(delta)
            depth_sample_count += 1
        elif event_type == "depth_end":
            if mode != "depth":
                return _fail(f"event {index} ends a depth drag that is not active")
            mode = "idle"
        elif event_type == "scan_start":
            if mode != "idle":
                return _fail(f"event {index} starts optical lock while {mode}")
            mode = "scan"
            scan_samples = []
        elif event_type == "scan_sample":
            if mode != "scan":
                return _fail(f"event {index} has an optical sample outside a hold")
            x_error, depth_error = _geometry(scene, rail_milli, depth_milli, target_depth)
            if event.get("x_error_milli") != x_error or event.get("depth_error_milli") != depth_error:
                return _fail(f"event {index} optical error disagrees with analytic geometry")
            expected_stable = x_error <= tolerances["x_milli"] and depth_error <= tolerances["depth_milli"]
            if event.get("stable") is not expected_stable:
                return _fail(f"event {index} misreports optical stability")
            scan_samples.append((x_error, depth_error))
        elif event_type == "scan_end":
            if mode != "scan":
                return _fail(f"event {index} ends an optical hold that is not active")
            try:
                scan_duration = _integer(event.get("duration_ms"), "scan duration")
                sample_count = _integer(event.get("sample_count"), "scan sample count")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if sample_count != len(scan_samples) or not 1 <= scan_duration <= 5000:
                return _fail(f"event {index} optical hold summary is inconsistent")
            mode = "idle"
            scan_complete = True
        else:
            return _fail(f"event {index} has unknown type {event_type!r}")

        state_error = _event_state(event, rail_milli, depth_milli, index)
        if state_error:
            return _fail(state_error)

    if mode != "idle" or not scan_complete:
        return _fail("transcript does not end with a released optical lock")
    if payload.get("final_rail_milli") != rail_milli or payload.get("final_depth_milli") != depth_milli:
        return _fail("submitted final controls do not match replay")
    final_x_error, final_depth_error = _geometry(scene, rail_milli, depth_milli, target_depth)
    stable_samples = bool(scan_samples) and all(
        x_error <= tolerances["x_milli"] and depth_error <= tolerances["depth_milli"]
        for x_error, depth_error in scan_samples
    )
    passed = (
        payload.get("completed") is True
        and rail_sample_count > 0
        and depth_sample_count > 0
        and rail_travel >= tolerances["minimum_rail_travel_milli"]
        and depth_travel >= tolerances["minimum_depth_travel_milli"]
        and inertia_samples >= tolerances["minimum_inertia_samples"]
        and scan_duration >= tolerances["hold_ms"] - 40
        and len(scan_samples) >= tolerances["minimum_scan_samples"]
        and stable_samples
        and final_x_error <= tolerances["x_milli"]
        and final_depth_error <= tolerances["depth_milli"]
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"projection replay: rail travel {rail_travel / 1000:.1f}px; depth travel {depth_travel}; "
            f"inertia samples {inertia_samples}; stable scan samples "
            f"{sum(1 for x, d in scan_samples if x <= tolerances['x_milli'] and d <= tolerances['depth_milli'])}/{len(scan_samples)}; "
            f"hold {scan_duration}ms"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    return {
        "target_rail_milli": ground_truth.get("target_rail_milli"),
        "target_depth_milli": ground_truth.get("target_depth_milli"),
        "instruction": "Calibrate depth, settle the inertial rail at the target projection, then hold optical lock for at least 700 ms.",
        "answers": [],
    }
