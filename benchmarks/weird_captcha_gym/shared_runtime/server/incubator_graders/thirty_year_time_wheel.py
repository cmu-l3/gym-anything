from __future__ import annotations

import calendar
import math
from typing import Any


MECHANIC_ID = "thirty_year_time_wheel"
COMPONENTS = {"day", "month", "year"}


def _fail(feedback: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "feedback": feedback}


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


def _date(value: Any, minimum: int, maximum: int) -> dict[str, int]:
    if not isinstance(value, dict) or set(value) != {"year", "month", "day"}:
        raise ValueError("date must contain exactly year, month, and day")
    year, month, day = value["year"], value["month"], value["day"]
    if any(isinstance(item, bool) or not isinstance(item, int) for item in (year, month, day)):
        raise ValueError("date fields must be integers")
    if not minimum <= year <= maximum or not 1 <= month <= 12:
        raise ValueError("date lies outside the calendar range")
    if not 1 <= day <= calendar.monthrange(year, month)[1]:
        raise ValueError("day is invalid for its month")
    return {"year": year, "month": month, "day": day}


def _step(date: dict[str, int], component: str, direction: int, minimum: int, maximum: int) -> dict[str, int]:
    year, month, day = date["year"], date["month"], date["day"]
    if component == "day":
        length = calendar.monthrange(year, month)[1]
        return {"year": year, "month": month, "day": ((day - 1 + direction) % length) + 1}
    if component == "month":
        ordinal = max(minimum * 12, min(maximum * 12 + 11, year * 12 + month - 1 + direction))
        next_year, month_index = divmod(ordinal, 12)
        next_month = month_index + 1
        return {
            "year": next_year,
            "month": next_month,
            "day": min(day, calendar.monthrange(next_year, next_month)[1]),
        }
    if component == "year":
        next_year = max(minimum, min(maximum, year + direction))
        return {
            "year": next_year,
            "month": month,
            "day": min(day, calendar.monthrange(next_year, month)[1]),
        }
    raise ValueError("unknown ring component")


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]) -> tuple[dict[str, int], dict[str, int], int, int, float, int]:
    year_range = ground_truth.get("year_range")
    if not isinstance(year_range, dict) or year_range.get("minimum") != 1996 or year_range.get("maximum") != 2025:
        raise ValueError("hidden year range is malformed")
    if public_state.get("year_range") != year_range:
        raise ValueError("public year range differs from hidden contract")
    minimum, maximum = int(year_range["minimum"]), int(year_range["maximum"])
    initial = _date(ground_truth.get("initial_date"), minimum, maximum)
    target = _date(ground_truth.get("target_date"), minimum, maximum)
    if public_state.get("initial_date") != initial or public_state.get("target_date") != target:
        raise ValueError("public dates differ from hidden contract")
    inertia = ground_truth.get("inertia")
    if not isinstance(inertia, dict) or public_state.get("inertia") != inertia:
        raise ValueError("inertia contract mismatch")
    threshold = float(inertia.get("minimum_velocity_rad_s"))
    maximum_detents = int(inertia.get("maximum_detents"))
    if threshold <= 0 or maximum_detents < 2:
        raise ValueError("inertia limits are invalid")
    return initial, target, minimum, maximum, threshold, maximum_detents


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    binding_error = _bind(payload, ground_truth, public_state)
    if binding_error:
        return _fail(binding_error)
    try:
        current, target, minimum, maximum, velocity_threshold, maximum_detents = _contract(ground_truth, public_state)
    except (TypeError, ValueError) as exc:
        return _fail(f"invalid time-wheel contract: {exc}")

    events = payload.get("events")
    if not isinstance(events, list) or not (2 <= len(events) <= 1200):
        return _fail("chronometer transcript is missing or outside limits")

    active_drag: str | None = None
    drag_detents = 0
    last_drag_direction = 0
    released_component: str | None = None
    coast: dict[str, int] | None = None
    coverage: set[str] = set()
    coast_detents = 0
    qualifying_brakes = 0
    locked = False
    for index, event in enumerate(events, start=1):
        if locked:
            return _fail("events continue after LOCK")
        if not isinstance(event, dict) or event.get("sequence") != index:
            return _fail(f"event {index} has an invalid sequence")
        event_type = str(event.get("type") or "")

        if event_type == "drag_start":
            component = str(event.get("component") or "")
            if component not in COMPONENTS or active_drag is not None or coast is not None:
                return _fail(f"event {index} starts an impossible drag")
            active_drag = component
            drag_detents = 0
            last_drag_direction = 0
            released_component = None
        elif event_type == "detent":
            component = str(event.get("component") or "")
            source = str(event.get("source") or "")
            direction = event.get("direction")
            if component not in COMPONENTS or direction not in {-1, 1}:
                return _fail(f"event {index} has an invalid detent")
            if source == "drag":
                if active_drag != component or coast is not None:
                    return _fail(f"event {index} has a drag detent outside its drag")
                drag_detents += 1
                last_drag_direction = direction
                coverage.add(component)
            elif source == "coast":
                if active_drag is not None or coast is None or coast["component"] != component:
                    return _fail(f"event {index} has a coast detent without momentum")
                if direction != coast["direction"] or coast["remaining"] <= 0:
                    return _fail(f"event {index} contradicts the inertia direction")
                coast["remaining"] -= 1
                coast["applied"] += 1
                coast_detents += 1
            else:
                return _fail(f"event {index} has an unknown detent source")
            current = _step(current, component, direction, minimum, maximum)
        elif event_type == "drag_end":
            component = str(event.get("component") or "")
            if active_drag != component or event.get("drag_detents") != drag_detents:
                return _fail(f"event {index} does not close the active drag")
            active_drag = None
            released_component = component if drag_detents > 0 else None
        elif event_type == "inertia_start":
            component = str(event.get("component") or "")
            direction = event.get("direction")
            velocity = event.get("velocity_rad_s")
            budget = event.get("budget")
            if active_drag is not None or coast is not None or released_component != component:
                return _fail(f"event {index} starts inertia without a completed drag")
            if direction not in {-1, 1} or direction != last_drag_direction:
                return _fail(f"event {index} has an invalid inertia direction")
            if isinstance(velocity, bool) or not isinstance(velocity, (int, float)) or not math.isfinite(float(velocity)):
                return _fail(f"event {index} has invalid angular velocity")
            if abs(float(velocity)) < velocity_threshold or (1 if velocity > 0 else -1) != direction:
                return _fail(f"event {index} has insufficient or contradictory angular velocity")
            expected_budget = max(2, min(maximum_detents, int(math.floor(abs(float(velocity)) * 1.3 + 0.5))))
            if budget != expected_budget:
                return _fail(f"event {index} has inconsistent inertia budget")
            coast = {"component": component, "direction": direction, "remaining": budget, "applied": 0}
            released_component = None
        elif event_type == "brake":
            effective = event.get("effective") is True
            if effective:
                if coast is None or event.get("component") != coast["component"]:
                    return _fail(f"event {index} claims an impossible brake")
                if event.get("remaining_before") != coast["remaining"] or coast["remaining"] <= 0:
                    return _fail(f"event {index} has inconsistent brake momentum")
                if coast["applied"] >= 1:
                    qualifying_brakes += 1
                coast = None
            else:
                if coast is not None or event.get("component") is not None or event.get("remaining_before") != 0:
                    return _fail(f"event {index} misreports an idle brake")
            released_component = None
        elif event_type == "inertia_stop":
            if coast is None or coast["remaining"] != 0 or event.get("component") != coast["component"]:
                return _fail(f"event {index} has an impossible friction stop")
            if event.get("reason") != "friction":
                return _fail(f"event {index} has an unknown inertia-stop reason")
            coast = None
            released_component = None
        elif event_type == "lock":
            if active_drag is not None or coast is not None:
                return _fail("LOCK occurred while a ring was still moving")
            locked = True
            released_component = None
        else:
            return _fail(f"event {index} has unknown type {event_type!r}")

        if event.get("date_after") != current:
            return _fail(f"event {index} has a date that disagrees with replay")

    try:
        submitted_final = _date(payload.get("final_date"), minimum, maximum)
    except ValueError as exc:
        return _fail(f"submitted final date is malformed: {exc}")
    if submitted_final != current:
        return _fail("submitted final date does not match replay")
    passed = (
        payload.get("completed") is True
        and locked
        and current == target
        and coverage == COMPONENTS
        and coast_detents >= 1
        and qualifying_brakes >= 1
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"calendar replay {current['year']:04d}-{current['month']:02d}-{current['day']:02d}; "
            f"rings {len(coverage)}/3; coast detents {coast_detents}; effective coast brakes {qualifying_brakes}; "
            f"target {'locked' if current == target else 'not reached'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    return {
        "target_date": ground_truth.get("target_date"),
        "direct_recovery_route": ground_truth.get("direct_recovery_route") or [],
        "instruction": "Demonstrate coast-and-brake once, then use month, year, and day detents to recover the target before LOCK.",
        "answers": [],
    }
