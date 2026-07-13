from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "bureaucratic_signature_trap"


def _point(value: Any) -> tuple[float, float]:
    if isinstance(value, dict):
        value = [value.get("x"), value.get("y")]
    if not isinstance(value, list) or len(value) != 2 or not all(isinstance(item, (int, float)) and math.isfinite(item) for item in value):
        raise ValueError("point is malformed")
    return float(value[0]), float(value[1])


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    contract = dict(ground_truth.get("form") or {})
    layers = {str(layer["id"]): dict(layer) for layer in contract.get("layers") or []}
    offsets = {layer_id: _point(layer["initial"]) for layer_id, layer in layers.items()}
    stroke: list[tuple[float, float]] | None = None
    certified = False
    events = payload.get("events")
    if not isinstance(events, list) or not 5 <= len(events) <= 80:
        return {"graded": True, "passed": False, "feedback": "carbon transcript is missing or outside limits"}
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "sheet_drag":
            sheet_id = str(event.get("sheet_id") or "")
            if sheet_id not in layers or certified:
                return {"graded": True, "passed": False, "feedback": "unknown or late sheet drag"}
            try:
                start = _point(event.get("start"))
                samples = [_point(point) for point in event.get("samples") or []]
                end = _point(event.get("end"))
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if math.hypot(start[0] - offsets[sheet_id][0], start[1] - offsets[sheet_id][1]) > 1.5 or not samples or end != samples[-1]:
                return {"graded": True, "passed": False, "feedback": "sheet drag does not continue from visible state"}
            previous = start
            for point in samples:
                if not -170 <= point[0] <= 170 or not -110 <= point[1] <= 110 or math.hypot(point[0] - previous[0], point[1] - previous[1]) > float(contract["max_drag_step"]):
                    return {"graded": True, "passed": False, "feedback": "sheet teleported or left the form rail"}
                previous = point
            offsets[sheet_id] = end
            continue
        if kind == "signature":
            if stroke is not None or certified:
                return {"graded": True, "passed": False, "feedback": "multiple or late signatures are not allowed"}
            tolerance = float(contract["alignment_tolerance"])
            if any(math.hypot(offsets[layer_id][0] - float(layer["target"]["x"]), offsets[layer_id][1] - float(layer["target"]["y"])) > tolerance for layer_id, layer in layers.items()):
                return {"graded": True, "passed": False, "feedback": "signature began while the carbon aperture was closed"}
            try:
                stroke = [_point(point) for point in event.get("points") or []]
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            continue
        if kind == "certify":
            if stroke is None or certified:
                return {"graded": True, "passed": False, "feedback": "form was certified without one physical stroke"}
            certified = True
            continue
        return {"graded": True, "passed": False, "feedback": f"unknown carbon event {kind}"}
    if stroke is None:
        return {"graded": True, "passed": False, "feedback": "counter-signature is missing"}
    requirements = dict(contract["signature"])
    if len(stroke) < int(requirements["min_samples"]):
        return {"graded": True, "passed": False, "feedback": "counter-signature is too sparse"}
    length = 0.0
    for first, second in zip(stroke, stroke[1:]):
        step = math.hypot(second[0] - first[0], second[1] - first[1])
        if step > float(requirements["max_step"]):
            return {"graded": True, "passed": False, "feedback": "counter-signature jumped across the paper"}
        length += step
    aperture = dict(contract["aperture"])
    center = (float(aperture["x"]), float(aperture["y"]))
    radius = float(aperture["radius"])
    if any(math.hypot(point[0] - center[0], point[1] - center[1]) > radius * 0.96 for point in stroke):
        return {"graded": True, "passed": False, "feedback": "counter-signature left the exposed aperture"}
    quadrants = {(point[0] >= center[0], point[1] >= center[1]) for point in stroke}
    closure = math.hypot(stroke[-1][0] - stroke[0][0], stroke[-1][1] - stroke[0][1])
    passed = certified and length >= float(requirements["min_length"]) and closure <= float(requirements["closure"]) and len(quadrants) >= int(requirements["min_quadrants"])
    return {"graded": True, "passed": passed, "feedback": f"carbon layers {len(layers)}/{len(layers)}; stroke {length:.0f}px; quadrants {len(quadrants)}; closure {closure:.1f}px"}
