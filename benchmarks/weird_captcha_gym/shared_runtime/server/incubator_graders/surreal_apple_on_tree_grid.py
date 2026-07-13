from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "surreal_apple_on_tree_grid"


def _fail(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label} is not finite")
    return float(value)


def _point(value: Any, width: int, height: int, label: str) -> tuple[float, float]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{label} is malformed")
    x, y = _number(value[0], f"{label} x"), _number(value[1], f"{label} y")
    if not 0 <= x <= width or not 0 <= y <= height:
        raise ValueError(f"{label} leaves the orchard")
    return x, y


def _project(point: list[float], angle_deg: float) -> tuple[float, float]:
    angle = math.radians(angle_deg)
    x, y, z = (float(item) for item in point)
    return 430 + x * math.cos(angle) + z * math.sin(angle), 246 + y + 0.10 * z * math.cos(angle) - 0.05 * x * math.sin(angle)


def _inside(point: tuple[float, float], rect: dict[str, Any]) -> bool:
    return (
        float(rect["x"]) <= point[0] <= float(rect["x"]) + float(rect["width"])
        and float(rect["y"]) <= point[1] <= float(rect["y"]) + float(rect["height"])
    )


def _sector(angle: float) -> int:
    if angle < -36: return 0
    if angle < -12: return 1
    if angle < 12: return 2
    if angle < 36: return 3
    return 4


def _explored(samples: int, angles: list[float], sectors: set[int], requirements: dict[str, Any]) -> bool:
    return (
        samples >= int(requirements["minimum_orbit_samples"])
        and max(angles) - min(angles) >= float(requirements["minimum_orbit_span_deg"])
        and sum(abs(b - a) for a, b in zip(angles, angles[1:])) >= float(requirements["minimum_orbit_travel_deg"])
        and len(sectors) >= int(requirements["minimum_view_sectors"])
    )


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge = str(ground_truth.get("challenge_id") or "")
    task_id = str(ground_truth.get("task_id") or "")
    if any(str(item.get("mechanic_id") or "") != MECHANIC_ID for item in (payload, ground_truth, public_state)):
        return _fail("mechanic mismatch")
    if not challenge or str(payload.get("challenge_id") or "") != challenge or str(public_state.get("challenge_id") or "") != challenge:
        return _fail("stale orchard challenge")
    if not task_id or str(payload.get("task_id") or "") != task_id or str(public_state.get("task_id") or "") != task_id:
        return _fail("task identity mismatch")
    try:
        stage = dict(ground_truth["stage"])
        width, height = int(stage["width"]), int(stage["height"])
        limit = float(ground_truth["view_limit_deg"])
        basket = dict(ground_truth["basket"])
        requirements = dict(ground_truth["requirements"])
        apples = [dict(item) for item in ground_truth["apples"]]
        apple_by_id = {str(item["id"]): item for item in apples}
        attached = {str(item) for item in ground_truth["attached_ids"]}
        if len(apples) != 5 or len(apple_by_id) != 5 or len(attached) != 3 or not attached <= set(apple_by_id):
            raise ValueError("fruit contract is incomplete")
        for key in ("stage", "basket", "requirements", "apples", "branches"):
            if public_state.get(key) != ground_truth.get(key):
                raise ValueError(f"public {key} differs from replay contract")
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid parallax contract: {exc}")

    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 1600):
        return _fail("orchard transcript is missing or outside limits")
    angle = float(public_state.get("initial_angle_deg") or 0)
    angles = [angle]
    sectors = {_sector(angle)}
    orbit_samples = 0
    orbit: dict[str, Any] | None = None
    pluck: dict[str, Any] | None = None
    plucked: set[str] = set()
    invalid_plucks = reset_count = seal_count = 0
    strike_active = False

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} has invalid sequence")
        kind = str(event.get("kind") or "")
        try:
            if kind == "orbit_start":
                if orbit is not None or pluck is not None:
                    return _fail(f"event {sequence} overlaps a pointer hold")
                point = _point(event.get("point"), width, height, "orbit start")
                before = _number(event.get("angle_before"), "orbit angle")
                if abs(before - angle) > 0.02:
                    return _fail(f"event {sequence} starts from a stale view")
                orbit = {"start": point, "angle": angle, "last": point}
            elif kind == "orbit_move":
                if orbit is None or pluck is not None:
                    return _fail(f"event {sequence} moves no active orbit")
                point = _point(event.get("point"), width, height, "orbit move")
                if math.hypot(point[0] - orbit["last"][0], point[1] - orbit["last"][1]) > 180:
                    return _fail(f"event {sequence} teleports the orchard")
                expected = max(-limit, min(limit, orbit["angle"] + (point[0] - orbit["start"][0]) * 0.24))
                after = _number(event.get("angle_after"), "orbit result")
                if abs(after - expected) > 0.03:
                    return _fail(f"event {sequence} reports false parallax")
                angle = after
                orbit["last"] = point
                orbit_samples += 1
                angles.append(angle)
                sectors.add(_sector(angle))
            elif kind == "orbit_end":
                if orbit is None:
                    return _fail(f"event {sequence} ends no active orbit")
                _point(event.get("point"), width, height, "orbit end")
                if abs(_number(event.get("angle"), "final orbit angle") - angle) > 0.03:
                    return _fail(f"event {sequence} ends at a false view")
                orbit = None
            elif kind == "pluck_start":
                if orbit is not None or pluck is not None or strike_active or not _explored(orbit_samples, angles, sectors, requirements):
                    return _fail(f"event {sequence} plucks before a valid depth inspection")
                apple_id = str(event.get("apple_id") or "")
                if apple_id not in apple_by_id or apple_id in plucked:
                    return _fail(f"event {sequence} selects unavailable fruit")
                point = _point(event.get("point"), width, height, "pluck start")
                reported_angle = _number(event.get("angle"), "pluck view")
                center = _project(apple_by_id[apple_id]["position"], angle)
                if abs(reported_angle - angle) > 0.03 or math.hypot(point[0] - center[0], point[1] - center[1]) > float(apple_by_id[apple_id]["radius"]) + 9:
                    return _fail(f"event {sequence} misses the visible apple")
                pluck = {"apple_id": apple_id, "moves": 0, "last_elapsed": 0}
            elif kind == "pluck_move":
                if pluck is None or str(event.get("apple_id") or "") != pluck["apple_id"]:
                    return _fail(f"event {sequence} moves no matching fruit")
                _point(event.get("point"), width, height, "pluck move")
                elapsed = int(_number(event.get("elapsed_ms"), "pluck elapsed"))
                if elapsed < pluck["last_elapsed"] or elapsed > 10_000:
                    return _fail(f"event {sequence} reverses pluck time")
                pluck["last_elapsed"] = elapsed
                pluck["moves"] += 1
            elif kind == "pluck_end":
                if pluck is None or str(event.get("apple_id") or "") != pluck["apple_id"]:
                    return _fail(f"event {sequence} releases no matching fruit")
                point = _point(event.get("point"), width, height, "pluck end")
                duration = int(_number(event.get("duration_ms"), "pluck duration"))
                in_basket = _inside(point, basket)
                accepted = (
                    in_basket
                    and pluck["apple_id"] in attached
                    and pluck["moves"] >= int(requirements["minimum_pluck_moves"])
                    and duration >= int(requirements["minimum_pluck_ms"])
                )
                if bool(event.get("accepted")) != accepted or bool(event.get("in_basket")) != in_basket:
                    return _fail(f"event {sequence} lies about the physical harvest")
                if accepted:
                    plucked.add(pluck["apple_id"])
                elif in_basket:
                    invalid_plucks += 1
                    strike_active = True
                pluck = None
            elif kind == "reset":
                if orbit is not None or pluck is not None:
                    return _fail(f"event {sequence} resets during a pointer hold")
                plucked.clear()
                strike_active = False
                reset_count += 1
            elif kind == "seal":
                if orbit is not None or pluck is not None:
                    return _fail(f"event {sequence} seals during a pointer hold")
                seal_count += 1
            else:
                return _fail(f"event {sequence} has unknown kind {kind!r}")
        except (TypeError, ValueError) as exc:
            return _fail(f"event {sequence}: {exc}")

    travel = round(sum(abs(b - a) for a, b in zip(angles, angles[1:])), 2)
    span = round(max(angles) - min(angles), 2)
    expected = {
        "final_angle_deg": round(angle, 2),
        "orbit_samples": orbit_samples,
        "orbit_span_deg": span,
        "orbit_travel_deg": travel,
        "view_sector_count": len(sectors),
        "plucked_ids": sorted(plucked),
        "invalid_plucks": invalid_plucks,
        "reset_count": reset_count,
        "seal_count": seal_count,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            return _fail(f"submitted {key} does not match orchard replay")
    passed = (
        payload.get("completed") is True
        and orbit is None
        and pluck is None
        and not strike_active
        and plucked == attached
        and seal_count >= 1
        and _explored(orbit_samples, angles, sectors, requirements)
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": f"parallax replay: span {span}°; travel {travel}°; sectors {len(sectors)}/5; harvest {len(plucked)}/{len(attached)}; bad plucks {invalid_plucks}; resets {reset_count}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"attached_ids": ground_truth.get("attached_ids") or [], "answers": []}
