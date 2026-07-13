from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "recursive_dollhouse_smuggling"


def _inverse(view: dict[str, Any], screen: list[float]) -> list[float]:
    matrix, origin = view["matrix"], view["origin"]
    a, b, c, d = float(matrix[0][0]), float(matrix[0][1]), float(matrix[1][0]), float(matrix[1][1])
    determinant = a * d - b * c
    u, v = float(screen[0]) - float(origin[0]), float(screen[1]) - float(origin[1])
    return [(d * u - b * v) / determinant, (-c * u + a * v) / determinant]


def _inside(point: list[float], center: list[float], size: list[float], margin: float = 0) -> bool:
    return abs(point[0] - center[0]) <= size[0] / 2 - margin and abs(point[1] - center[1]) <= size[1] / 2 - margin


def _contained(inner_center: list[float], inner_size: list[float], outer_center: list[float], outer_size: list[float]) -> bool:
    return abs(inner_center[0] - outer_center[0]) + inner_size[0] / 2 <= outer_size[0] / 2 + 1e-6 and abs(inner_center[1] - outer_center[1]) + inner_size[1] / 2 <= outer_size[1] / 2 + 1e-6


def _overlap(first_center: list[float], first_size: list[float], second_center: list[float], second_size: list[float]) -> bool:
    return abs(first_center[0] - second_center[0]) < (first_size[0] + second_size[0]) / 2 - 1e-6 and abs(first_center[1] - second_center[1]) < (first_size[1] + second_size[1]) / 2 - 1e-6


def _blocker(entity: str, start: list[float], end: list[float], parcel_scale: int, gate_center: list[float], contract: dict[str, Any]) -> str | None:
    parcel, gate, room = contract["parcel"], contract["gate"], contract["room"]
    size = gate["size"] if entity == "gate" else parcel["sizes"][parcel_scale]
    distance = math.hypot(end[0] - start[0], end[1] - start[1])
    steps = max(1, math.ceil(distance / float(contract["requirements"]["collision_substep"])))
    for index in range(1, steps + 1):
        amount = index / steps
        center = [start[0] + (end[0] - start[0]) * amount, start[1] + (end[1] - start[1]) * amount]
        if center[0] - size[0] / 2 < 0 or center[0] + size[0] / 2 > room["width"] or center[1] - size[1] / 2 < 0 or center[1] + size[1] / 2 > room["depth"]:
            return "room-boundary"
        for wall in contract["walls"]:
            if _overlap(center, size, wall["center"], wall["size"]):
                return str(wall["id"])
        if entity == "parcel" and _overlap(center, size, gate_center, gate["size"]):
            return "gate"
        if entity == "gate" and _overlap(center, size, contract["_parcel_center"], parcel["sizes"][parcel_scale]):
            return "parcel"
    return None


def _bound(public: dict[str, Any], truth: dict[str, Any]) -> str | None:
    for field in ("task_id", "room", "views", "walls", "gate", "parking", "portals", "parcel", "bay", "requirements"):
        if public.get(field) != truth.get(field):
            return field
    return None


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge, task_id = str(ground_truth.get("challenge_id") or ""), str(ground_truth.get("task_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge or str(payload.get("challenge_id") or "") != challenge or str(public_state.get("challenge_id") or "") != challenge:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return {"graded": True, "passed": False, "feedback": "task identity mismatch"}
    skew = _bound(public_state, ground_truth)
    if skew:
        return {"graded": True, "passed": False, "feedback": f"public/private dollhouse {skew} contract skew"}
    try:
        views = {item["id"]: item for item in ground_truth["views"]}
        portals = {item["id"]: item for item in ground_truth["portals"]}
        parcel = ground_truth["parcel"]
        initial_parcel = list(parcel["initial_center"])
        initial_gate = list(ground_truth["gate"]["center"])
        requirements = ground_truth["requirements"]
        if set(views) != {"mini", "human", "giant"} or len(portals) != 2:
            raise ValueError("three views and two nested frames required")
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid dollhouse contract: {exc}"}
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 1800):
        return {"graded": True, "passed": False, "feedback": "cross-scale transcript missing or outside limits"}
    parcel_center, gate_center, scale = list(initial_parcel), list(initial_gate), int(parcel["initial_scale"])
    drag: dict[str, Any] | None = None
    transitions: list[str] = []
    views_used: set[str] = set()
    collisions = resets = 0
    gate_parked = delivered = terminal = False

    for sequence, event in enumerate(events, 1):
        if terminal:
            return {"graded": True, "passed": False, "feedback": "interaction continued after nested delivery"}
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "drag_start":
            entity, view_id, screen, claimed = str(event.get("entity") or ""), str(event.get("view_id") or ""), event.get("screen"), event.get("canonical")
            if drag is not None or view_id not in views or entity not in {"parcel", "gate"} or not isinstance(screen, list) or not isinstance(claimed, list):
                return {"graded": True, "passed": False, "feedback": "invalid cross-scale drag start"}
            mapped = _inverse(views[view_id], screen)
            if math.hypot(mapped[0] - float(claimed[0]), mapped[1] - float(claimed[1])) > float(requirements["inverse_tolerance"]):
                return {"graded": True, "passed": False, "feedback": "screen/canonical inverse transform mismatch"}
            center, size = (gate_center, ground_truth["gate"]["size"]) if entity == "gate" else (parcel_center, parcel["sizes"][scale])
            if entity == "gate" and view_id != ground_truth["gate"]["movable_in_view"]:
                return {"graded": True, "passed": False, "feedback": "gate manipulated through the wrong room scale"}
            if entity == "parcel" and int(views[view_id]["index"]) != scale:
                return {"graded": True, "passed": False, "feedback": "parcel manipulated through the wrong room scale"}
            if not _inside(mapped, center, size):
                return {"graded": True, "passed": False, "feedback": "drag ray missed canonical footprint"}
            drag = {"entity": entity, "view": view_id, "offset": [mapped[0] - center[0], mapped[1] - center[1]], "last_screen": [float(screen[0]), float(screen[1])]}
            views_used.add(view_id)
            continue
        if kind == "drag_sample":
            if drag is None:
                return {"graded": True, "passed": False, "feedback": "orphan cross-scale drag sample"}
            screen, claimed, center_claim = event.get("screen"), event.get("canonical"), event.get("center")
            if event.get("entity") != drag["entity"] or event.get("view_id") != drag["view"] or not all(isinstance(item, list) and len(item) == 2 for item in (screen, claimed, center_claim)):
                return {"graded": True, "passed": False, "feedback": "malformed cross-scale drag sample"}
            if math.hypot(float(screen[0]) - drag["last_screen"][0], float(screen[1]) - drag["last_screen"][1]) > float(requirements["max_screen_step"]):
                return {"graded": True, "passed": False, "feedback": "sparse cross-view pointer teleport"}
            mapped = _inverse(views[drag["view"]], screen)
            expected_center = [mapped[0] - drag["offset"][0], mapped[1] - drag["offset"][1]]
            if math.hypot(mapped[0] - float(claimed[0]), mapped[1] - float(claimed[1])) > float(requirements["inverse_tolerance"]) or math.hypot(expected_center[0] - float(center_claim[0]), expected_center[1] - float(center_claim[1])) > float(requirements["inverse_tolerance"]):
                return {"graded": True, "passed": False, "feedback": "cross-view canonical pose lie"}
            current = gate_center if drag["entity"] == "gate" else parcel_center
            replay_contract = {**ground_truth, "_parcel_center": parcel_center}
            blocker = _blocker(drag["entity"], current, expected_center, scale, gate_center, replay_contract)
            accepted = blocker is None
            if (event.get("accepted") is True) != accepted or (None if accepted else str(event.get("blocker") or "")) != blocker:
                return {"graded": True, "passed": False, "feedback": "visible collision/containment disagrees with canonical replay"}
            if accepted:
                if drag["entity"] == "gate": gate_center = expected_center
                else: parcel_center = expected_center
            else:
                collisions += 1
            drag["last_screen"] = [float(screen[0]), float(screen[1])]
            continue
        if kind == "drag_end":
            center_claim = event.get("center")
            current = gate_center if drag and drag["entity"] == "gate" else parcel_center
            if drag is None or event.get("entity") != drag["entity"] or not isinstance(center_claim, list) or math.hypot(float(center_claim[0]) - current[0], float(center_claim[1]) - current[1]) > 0.12:
                return {"graded": True, "passed": False, "feedback": "drag release disagrees with canonical body"}
            drag = None
            continue
        if kind == "gate_parked":
            if drag is not None or gate_parked or not _contained(gate_center, ground_truth["gate"]["size"], ground_truth["parking"]["center"], ground_truth["parking"]["size"]):
                return {"graded": True, "passed": False, "feedback": "gate parking claim lacks full containment"}
            gate_parked = True
            continue
        if kind == "portal_transition":
            portal_id = str(event.get("portal_id") or ""); portal = portals.get(portal_id)
            if drag is not None or not portal or event.get("from_scale") != scale or event.get("to_scale") != scale + 1 or int(portal["from_scale"]) != scale or not _contained(parcel_center, parcel["sizes"][scale], portal["center"], portal["size"]):
                return {"graded": True, "passed": False, "feedback": "portal teleport or wrong-scale transfer"}
            if scale == 0 and not gate_parked:
                return {"graded": True, "passed": False, "feedback": "miniature route was not physically opened at giant scale"}
            transitions.append(portal_id); scale += 1
            continue
        if kind == "delivery":
            if drag is not None or delivered or scale != int(ground_truth["bay"]["scale"]) or not _contained(parcel_center, parcel["sizes"][scale], ground_truth["bay"]["center"], ground_truth["bay"]["size"]):
                return {"graded": True, "passed": False, "feedback": "final bay fit or parcel scale is invalid"}
            delivered = terminal = True
            continue
        if kind == "reset":
            if drag is not None or terminal:
                return {"graded": True, "passed": False, "feedback": "reset during active drag or after delivery"}
            parcel_center, gate_center, scale = list(initial_parcel), list(initial_gate), int(parcel["initial_scale"])
            transitions.clear(); views_used.clear(); gate_parked = delivered = False; resets += 1
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    summary = {"delivered": delivered, "parcel_scale": scale, "portal_ids": transitions, "gate_parked": gate_parked,
               "collisions": collisions, "resets": resets, "views_used": sorted(views_used),
               "parcel_center": [round(value, 3) for value in parcel_center], "gate_center": [round(value, 3) for value in gate_center]}
    for field, value in summary.items():
        if field in {"parcel_center", "gate_center"}:
            submitted = payload.get(field)
            if not isinstance(submitted, list) or len(submitted) != 2 or math.hypot(float(submitted[0]) - value[0], float(submitted[1]) - value[1]) > 0.01:
                return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with nested-room replay"}
        elif payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with nested-room replay"}
    passed = delivered and transitions == ["frame-mini-human", "frame-human-giant"] and gate_parked and views_used == set(requirements["required_views"])
    return {"graded": True, "passed": passed, "score": 100 if passed else 0,
            "feedback": f"dollhouse replay: portals {len(transitions)}/2; views {len(views_used)}/3; gate {'parked' if gate_parked else 'blocking'}; collisions {collisions}; resets {resets}"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"solver_waypoints": ground_truth.get("solver_waypoints") or {}, "views": ground_truth.get("views") or []}
