from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "relation_prompt_grounding"


def _point(value: Any, width: int, height: int) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2 or any(isinstance(item, bool) for item in value):
        raise ValueError("table point is malformed")
    x, y = int(value[0]), int(value[1])
    if not (0 <= x <= width and 0 <= y <= height):
        raise ValueError("table point leaves assembly stage")
    return x, y


def _inside(point: tuple[int, int], rect: dict[str, Any]) -> bool:
    x, y = point
    return (
        int(rect["x"]) <= x <= int(rect["x"]) + int(rect["width"])
        and int(rect["y"]) <= y <= int(rect["y"]) + int(rect["height"])
    )


def _carousel_point(item: dict[str, Any], tick: int, carousel: dict[str, Any]) -> tuple[int, int]:
    phase = int(item["carousel_phase"])
    ticks = int(carousel["ticks"])
    angle = 2 * math.pi * ((phase + tick) % ticks) / ticks
    center_x, center_y = [int(value) for value in carousel["center"]]
    return (
        round(center_x + int(carousel["radius_x"]) * math.cos(angle)),
        round(center_y + int(carousel["radius_y"]) * math.sin(angle)),
    )


def _snapshot(states: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {"id": object_id, "x": state["x"], "y": state["y"], "depth": state["depth"], "placed": state["placed"]}
        for object_id, state in sorted(states.items())
    ]


def _browser_round(value: float) -> int:
    """Match JavaScript Math.round, including its negative-half behavior."""
    return math.floor(value + 0.5)


def _relations(
    states: dict[str, dict[str, Any]],
    objects: dict[str, dict[str, Any]],
    constraints: list[dict[str, Any]],
    rules: dict[str, Any],
) -> list[bool]:
    results: list[bool] = []
    for constraint in constraints:
        first = states[str(constraint["a"])]
        second = states[str(constraint["b"])]
        first_object = objects[str(constraint["a"])]
        second_object = objects[str(constraint["b"])]
        kind = str(constraint["type"])
        if kind == "left_of":
            ok = first["x"] + int(rules["horizontal_gap"]) <= second["x"]
        elif kind == "right_of":
            ok = first["x"] >= second["x"] + int(rules["horizontal_gap"])
        elif kind == "inside":
            allowance = int(second_object["radius"]) - int(first_object["radius"]) - int(rules["inside_inset"])
            ok = allowance >= 0 and abs(first["x"] - second["x"]) <= allowance and abs(first["y"] - second["y"]) <= allowance
        elif kind == "in_front_of":
            ok = first["depth"] >= second["depth"] + int(rules["depth_gap"])
        elif kind == "behind":
            ok = first["depth"] + int(rules["depth_gap"]) <= second["depth"]
        else:
            distance = math.hypot(first["x"] - second["x"], first["y"] - second["y"])
            contact_distance = int(first_object["radius"]) + int(second_object["radius"])
            if kind == "touching":
                ok = abs(distance - contact_distance) <= int(rules["touch_tolerance"])
            elif kind == "not_touching":
                ok = distance >= contact_distance + int(rules["not_touch_gap"])
            else:
                ok = False
        results.append(ok)
    return results


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "ground-truth mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "public-state challenge mismatch"}
    try:
        stage = ground_truth.get("stage") or {}
        width, height = int(stage["width"]), int(stage["height"])
        carousel = dict(ground_truth.get("carousel") or {})
        worktable = dict(ground_truth.get("worktable_rect") or {})
        objects = {str(item["id"]): dict(item) for item in ground_truth.get("objects") or []}
        if len(objects) != 5:
            raise ValueError("five assembly objects are required")
        constraints = [dict(item) for item in ground_truth.get("constraints") or []]
        if len(constraints) != 3:
            raise ValueError("three relations are required")
        settle_vectors = {str(key): dict(value) for key, value in (ground_truth.get("settle_vectors") or {}).items()}
        settle_ticks = int(ground_truth.get("settle_ticks"))
        rules = dict(ground_truth.get("rules") or {})
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid relation contract: {exc}"}

    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 700):
        return {"graded": True, "passed": False, "feedback": "manipulation transcript is missing or outside limits"}
    states = {
        object_id: {"x": None, "y": None, "depth": int(item["initial_depth"]), "placed": False}
        for object_id, item in objects.items()
    }
    drag: dict[str, Any] | None = None
    depth_drag: dict[str, Any] | None = None
    settle: dict[str, Any] | None = None
    settled = False
    drag_count = 0
    drag_samples = 0
    total_drag_distance = 0.0
    depth_samples = 0
    depth_distance = 0
    settle_samples = 0
    reset_count = 0

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "reset":
            states = {
                object_id: {"x": None, "y": None, "depth": int(item["initial_depth"]), "placed": False}
                for object_id, item in objects.items()
            }
            drag = depth_drag = settle = None
            settled = False
            drag_count = drag_samples = depth_samples = depth_distance = settle_samples = 0
            total_drag_distance = 0.0
            reset_count += 1
            continue
        if settled and kind not in {"settle_complete"}:
            return {"graded": True, "passed": False, "feedback": "object manipulation continued after inspection settled"}

        if kind == "drag_start":
            if drag is not None or depth_drag is not None or settle is not None:
                return {"graded": True, "passed": False, "feedback": "overlapping manipulation gestures"}
            object_id = str(event.get("object_id") or "")
            if object_id not in objects:
                return {"graded": True, "passed": False, "feedback": "unknown assembly object"}
            try:
                point = _point(event.get("point"), width, height)
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            state = states[object_id]
            source = str(event.get("source") or "")
            if not state["placed"]:
                tick = int(event.get("carousel_tick"))
                expected = _carousel_point(objects[object_id], tick, carousel)
                if source != "carousel" or math.hypot(point[0] - expected[0], point[1] - expected[1]) > int(objects[object_id]["radius"]) + 10:
                    return {"graded": True, "passed": False, "feedback": "drag did not begin on the moving carousel object"}
            elif source != "table" or math.hypot(point[0] - state["x"], point[1] - state["y"]) > int(objects[object_id]["radius"]) + 12:
                return {"graded": True, "passed": False, "feedback": "table drag missed the current object geometry"}
            drag = {"object_id": object_id, "start": point, "moves": 0}
            continue
        if kind == "drag_move":
            if drag is None or event.get("object_id") != drag["object_id"]:
                return {"graded": True, "passed": False, "feedback": "drag move has no matching object"}
            try:
                _point(event.get("point"), width, height)
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            drag["moves"] += 1
            drag_samples += 1
            continue
        if kind == "drag_cancel":
            if drag is None or event.get("object_id") != drag["object_id"]:
                return {"graded": True, "passed": False, "feedback": "drag cancellation has no matching object"}
            drag = None
            continue
        if kind == "drag_end":
            if drag is None or event.get("object_id") != drag["object_id"]:
                return {"graded": True, "passed": False, "feedback": "drag end has no matching object"}
            try:
                point = _point(event.get("point"), width, height)
            except ValueError as exc:
                return {"graded": True, "passed": False, "feedback": str(exc)}
            if drag["moves"] < 2 or not _inside(point, worktable):
                return {"graded": True, "passed": False, "feedback": "object was not physically carried onto the worktable"}
            states[drag["object_id"]].update({"x": point[0], "y": point[1], "placed": True})
            total_drag_distance += math.hypot(point[0] - drag["start"][0], point[1] - drag["start"][1])
            drag_count += 1
            drag = None
            continue
        if kind == "depth_start":
            object_id = str(event.get("object_id") or "")
            if drag is not None or depth_drag is not None or settle is not None or object_id not in states or not states[object_id]["placed"]:
                return {"graded": True, "passed": False, "feedback": "depth rail started without a placed selection"}
            if event.get("value") != states[object_id]["depth"]:
                return {"graded": True, "passed": False, "feedback": "depth rail start value mismatch"}
            depth_drag = {"object_id": object_id, "start": states[object_id]["depth"], "moves": 0}
            continue
        if kind == "depth_move":
            if depth_drag is None or event.get("object_id") != depth_drag["object_id"]:
                return {"graded": True, "passed": False, "feedback": "depth motion has no selected object"}
            value = int(event.get("value"))
            if not 0 <= value <= 100:
                return {"graded": True, "passed": False, "feedback": "depth value outside rail"}
            states[depth_drag["object_id"]]["depth"] = value
            depth_drag["moves"] += 1
            depth_samples += 1
            continue
        if kind == "depth_end":
            if depth_drag is None or event.get("object_id") != depth_drag["object_id"] or event.get("value") != states[depth_drag["object_id"]]["depth"]:
                return {"graded": True, "passed": False, "feedback": "depth rail end mismatch"}
            if depth_drag["moves"] < 2:
                return {"graded": True, "passed": False, "feedback": "depth adjustment was not a physical drag"}
            depth_distance += abs(states[depth_drag["object_id"]]["depth"] - depth_drag["start"])
            depth_drag = None
            continue
        if kind == "settle_start":
            if drag is not None or depth_drag is not None or settle is not None or not all(state["placed"] for state in states.values()):
                return {"graded": True, "passed": False, "feedback": "settle began before all objects were placed"}
            settle = {"next_tick": 1, "elapsed": 0}
            continue
        if kind == "settle_tick":
            if settle is None or event.get("tick") != settle["next_tick"]:
                return {"graded": True, "passed": False, "feedback": "settle tick is out of order"}
            tick = settle["next_tick"]
            for object_id, state in states.items():
                vector = settle_vectors[object_id]
                factor = settle_ticks - tick + 1
                state["x"] += _browser_round(int(vector["dx"]) * factor / settle_ticks)
                state["y"] += _browser_round(int(vector["dy"]) * factor / settle_ticks)
            if event.get("snapshot") != _snapshot(states):
                return {"graded": True, "passed": False, "feedback": f"settle tick {tick} geometry was tampered"}
            elapsed = int(event.get("elapsed_ms"))
            if elapsed < tick * 70 or elapsed < settle["elapsed"]:
                return {"graded": True, "passed": False, "feedback": "settle inspection was not observed for long enough"}
            settle["elapsed"] = elapsed
            settle["next_tick"] += 1
            settle_samples += 1
            continue
        if kind == "settle_complete":
            if settle is None or settle["next_tick"] != settle_ticks + 1:
                return {"graded": True, "passed": False, "feedback": "settle completed before all force ticks"}
            settle = None
            settled = True
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    final_snapshot = _snapshot(states)
    if payload.get("final_states") != final_snapshot:
        return {"graded": True, "passed": False, "feedback": "submitted assembly state does not match replay"}
    expected = {
        "drag_count": drag_count,
        "drag_samples": drag_samples,
        "depth_samples": depth_samples,
        "depth_distance": depth_distance,
        "settle_samples": settle_samples,
        "reset_count": reset_count,
    }
    for field, value in expected.items():
        if payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} does not match replay"}
    relation_results = _relations(states, objects, constraints, rules) if all(state["placed"] for state in states.values()) else [False] * len(constraints)
    passed = (
        settled
        and drag is None
        and depth_drag is None
        and all(state["placed"] for state in states.values())
        and all(relation_results)
        and drag_count >= 5
        and drag_samples >= 15
        and total_drag_distance >= 900
        and depth_samples >= 4
        and depth_distance >= 45
        and settle_samples == settle_ticks
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"relation replay: constraints {sum(relation_results)}/{len(relation_results)}; placed {sum(state['placed'] for state in states.values())}/5; "
            f"drags {drag_count}; depth travel {depth_distance}; settle ticks {settle_samples}/{settle_ticks}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "constraints": ground_truth.get("constraints"),
        "solution_positions": ground_truth.get("solution_positions"),
        "settle_vectors": ground_truth.get("settle_vectors"),
    }
