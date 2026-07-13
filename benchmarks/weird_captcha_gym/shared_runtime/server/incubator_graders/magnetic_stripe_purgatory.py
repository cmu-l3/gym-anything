from __future__ import annotations

import copy
import math
from typing import Any


MECHANIC_ID = "magnetic_stripe_purgatory"


def _fail(feedback: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": feedback}


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    return value


def _point(value: Any, width: int, height: int, label: str) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{label} point is malformed")
    x = _integer(value[0], f"{label} x")
    y = _integer(value[1], f"{label} y")
    if not 0 <= x <= width or not 0 <= y <= height:
        raise ValueError(f"{label} point leaves the calibration desk")
    return x, y


def _inside(point: tuple[int, int], rect: dict[str, Any]) -> bool:
    x, y = point
    return int(rect["x"]) <= x <= int(rect["x"]) + int(rect["width"]) and int(rect["y"]) <= y <= int(rect["y"]) + int(rect["height"])


def _public_card(card: dict[str, Any]) -> dict[str, Any]:
    return {key: copy.deepcopy(card[key]) for key in ("id", "label", "account", "holder", "badge", "initial_rect")}


def _public_reader(reader: dict[str, Any]) -> dict[str, Any]:
    return {
        key: copy.deepcopy(reader[key])
        for key in ("id", "label", "serial", "badge", "rect", "slot", "track", "interference_zones", "profile_token")
    }


def _bind(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> str | None:
    for label, value in (("payload", payload), ("ground-truth", ground_truth), ("public-state", public_state)):
        if str(value.get("mechanic_id") or "") != MECHANIC_ID:
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


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    for key in ("palette", "stage", "requirements"):
        if public_state.get(key) != ground_truth.get(key):
            raise ValueError(f"public {key} differs from hidden contract")
    cards = ground_truth.get("cards")
    readers = ground_truth.get("readers")
    if not isinstance(cards, list) or len(cards) != 3 or not isinstance(readers, list) or len(readers) != 3:
        raise ValueError("exactly three cards and readers are required")
    if public_state.get("cards") != [_public_card(card) for card in cards]:
        raise ValueError("public card rack differs from hidden contract")
    if public_state.get("readers") != [_public_reader(reader) for reader in readers]:
        raise ValueError("public reader geometry differs from hidden contract")
    card_ids = [str(card.get("id") or "") for card in cards if isinstance(card, dict)]
    reader_ids = [str(reader.get("id") or "") for reader in readers if isinstance(reader, dict)]
    if len(set(card_ids)) != 3 or len(set(reader_ids)) != 3 or any(not item for item in card_ids + reader_ids):
        raise ValueError("card or reader identities are malformed")
    reader_by_id = {str(reader["id"]): reader for reader in readers}
    card_by_id = {str(card["id"]): card for card in cards}
    assignments = {str(card["assigned_reader"]) for card in cards}
    if assignments != set(reader_ids):
        raise ValueError("card-reader assignment is not one-to-one")
    for card in cards:
        reader = reader_by_id[str(card["assigned_reader"])]
        if card.get("badge") != reader.get("badge"):
            raise ValueError("visible badge does not match hidden assignment")
    windows = []
    for reader in readers:
        calibration = reader.get("calibration")
        if not isinstance(calibration, dict):
            raise ValueError("reader calibration is missing")
        minimum = _integer(calibration.get("minimum_ms"), "minimum swipe time")
        maximum = _integer(calibration.get("maximum_ms"), "maximum swipe time")
        solver = _integer(calibration.get("solver_ms"), "solver swipe time")
        if not 400 <= minimum < solver < maximum <= 1500:
            raise ValueError("reader timing window is not humane")
        windows.append((minimum, maximum))
    if len(set(windows)) != 3:
        raise ValueError("reader timing windows are not distinct")
    stage = ground_truth.get("stage")
    if not isinstance(stage, dict):
        raise ValueError("stage is malformed")
    width = _integer(stage.get("width"), "stage width")
    height = _integer(stage.get("height"), "stage height")
    requirements = ground_truth.get("requirements")
    if not isinstance(requirements, dict):
        raise ValueError("requirements are malformed")
    return {
        "cards": copy.deepcopy(cards),
        "readers": copy.deepcopy(readers),
        "card_by_id": card_by_id,
        "reader_by_id": reader_by_id,
        "width": width,
        "height": height,
        "requirements": {key: int(value) for key, value in requirements.items()},
    }


def _reader_at_slot(point: tuple[int, int], readers: list[dict[str, Any]]) -> str | None:
    for reader in readers:
        if _inside(point, reader["slot"]):
            return str(reader["id"])
    return None


def _zone_hit(point: tuple[int, int], zones: list[dict[str, Any]]) -> bool:
    return any(_inside(point, zone) for zone in zones)


def _evaluate_swipe(reader: dict[str, Any], points: list[tuple[int, int]], duration_ms: int) -> dict[str, Any]:
    track = reader["track"]
    calibration = reader["calibration"]
    direction = str(track["direction"])
    x_start, x_end = int(track["x_start"]), int(track["x_end"])
    expected_start = x_start if direction == "ltr" else x_end
    expected_end = x_end if direction == "ltr" else x_start
    span = abs(x_end - x_start)
    center_y = int(track["y"])
    start_error = abs(points[0][0] - expected_start)
    end_error = abs(points[-1][0] - expected_end)
    directional_progress = (points[-1][0] - points[0][0]) * (1 if direction == "ltr" else -1)
    coverage_milli = max(0, min(1000, round(directional_progress / span * 1000)))
    maximum_deviation = max(abs(point[1] - center_y) for point in points)
    maximum_gap = 0.0
    backtrack = 0
    for first, second in zip(points, points[1:]):
        maximum_gap = max(maximum_gap, math.hypot(second[0] - first[0], second[1] - first[1]))
        signed = (second[0] - first[0]) * (1 if direction == "ltr" else -1)
        if signed < 0:
            backtrack += -signed
    zone_hits = sum(_zone_hit(point, reader["interference_zones"]) for point in points)
    geometry_bad = (
        len(points) - 1 < int(calibration["minimum_samples"])
        or start_error > span * (1 - int(calibration["minimum_coverage_milli"]) / 1000)
        or end_error > span * (1 - int(calibration["minimum_coverage_milli"]) / 1000)
        or coverage_milli < int(calibration["minimum_coverage_milli"])
        or maximum_deviation > int(calibration["straightness_px"])
        or backtrack > int(calibration["maximum_backtrack_px"])
        or maximum_gap > int(calibration["maximum_sample_gap_px"])
        or zone_hits > 0
    )
    if geometry_bad:
        feedback = "BAD READ"
    elif duration_ms < int(calibration["minimum_ms"]):
        feedback = "TOO FAST"
    elif duration_ms > int(calibration["maximum_ms"]):
        feedback = "TOO SLOW"
    else:
        feedback = "ACCEPTED"
    return {
        "feedback": feedback,
        "coverage_milli": coverage_milli,
        "maximum_deviation": maximum_deviation,
        "maximum_gap_milli": round(maximum_gap * 1000),
        "backtrack_px": backtrack,
        "zone_hits": zone_hits,
        "sample_count": len(points) - 1,
        "duration_ms": duration_ms,
    }


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    binding_error = _bind(payload, ground_truth, public_state)
    if binding_error:
        return _fail(binding_error)
    try:
        contract = _contract(ground_truth, public_state)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid calibration contract: {exc}")
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 1500):
        return _fail("calibration transcript is missing or outside limits")

    cards = contract["cards"]
    readers = contract["readers"]
    card_by_id = contract["card_by_id"]
    reader_by_id = contract["reader_by_id"]
    requirements = contract["requirements"]
    card_locations: dict[str, str | None] = {str(card["id"]): None for card in cards}
    reader_cards: dict[str, str | None] = {str(reader["id"]): None for reader in readers}
    reader_locked: dict[str, bool] = {str(reader["id"]): False for reader in readers}
    reader_attempts: dict[str, int] = {str(reader["id"]): 0 for reader in readers}
    reader_feedback: dict[str, str] = {str(reader["id"]): "INSERT CARD" for reader in readers}
    insert_drag: dict[str, Any] | None = None
    swipe: dict[str, Any] | None = None
    invalid_insertions = 0
    swipe_attempts = 0
    reset_count = 0
    audit_count = 0
    audit_complete = False

    def reset_desk() -> None:
        nonlocal card_locations, reader_cards, reader_locked, reader_attempts, reader_feedback
        nonlocal insert_drag, swipe, invalid_insertions, swipe_attempts, audit_count, audit_complete
        card_locations = {str(card["id"]): None for card in cards}
        reader_cards = {str(reader["id"]): None for reader in readers}
        reader_locked = {str(reader["id"]): False for reader in readers}
        reader_attempts = {str(reader["id"]): 0 for reader in readers}
        reader_feedback = {str(reader["id"]): "INSERT CARD" for reader in readers}
        insert_drag = None
        swipe = None
        invalid_insertions = 0
        swipe_attempts = 0
        audit_count = 0
        audit_complete = False

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return _fail(f"event {sequence} has an invalid sequence")
        kind = str(event.get("kind") or "")
        if audit_complete:
            return _fail("transcript continues after a complete audit")
        if kind == "reset":
            if insert_drag is not None or swipe is not None:
                return _fail(f"event {sequence} resets during an active pointer hold")
            reset_desk()
            reset_count += 1
            continue
        if kind == "insert_down":
            card_id = str(event.get("card_id") or "")
            if insert_drag is not None or swipe is not None or card_id not in card_by_id or card_locations[card_id] is not None:
                return _fail(f"event {sequence} begins an invalid card insertion")
            try:
                point = _point(event.get("point"), contract["width"], contract["height"], "insertion start")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            if event.get("elapsed_ms") != 0 or not _inside(point, card_by_id[card_id]["initial_rect"]):
                return _fail(f"event {sequence} did not pick up the claimed rack card")
            insert_drag = {"card_id": card_id, "last_elapsed": 0, "moves": 0, "points": [point]}
            continue
        if kind == "insert_move":
            if insert_drag is None or str(event.get("card_id") or "") != insert_drag["card_id"]:
                return _fail(f"event {sequence} insertion move has no matching card hold")
            try:
                point = _point(event.get("point"), contract["width"], contract["height"], "insertion move")
                elapsed = _integer(event.get("elapsed_ms"), "insertion elapsed")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            if elapsed < insert_drag["last_elapsed"]:
                return _fail(f"event {sequence} insertion time reversed")
            insert_drag["last_elapsed"] = elapsed
            insert_drag["moves"] += 1
            insert_drag["points"].append(point)
            continue
        if kind == "insert_up":
            if insert_drag is None or str(event.get("card_id") or "") != insert_drag["card_id"]:
                return _fail(f"event {sequence} insertion release has no matching card hold")
            try:
                point = _point(event.get("point"), contract["width"], contract["height"], "insertion release")
                duration = _integer(event.get("duration_ms"), "insertion duration")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            if duration < insert_drag["last_elapsed"] or duration > 10_000:
                return _fail(f"event {sequence} insertion duration is inconsistent")
            detected_reader = _reader_at_slot(point, readers)
            claimed_reader = event.get("reader_id")
            if claimed_reader != detected_reader:
                return _fail(f"event {sequence} claimed insertion slot disagrees with geometry")
            card_id = insert_drag["card_id"]
            valid = (
                detected_reader is not None
                and str(card_by_id[card_id]["assigned_reader"]) == detected_reader
                and reader_cards[detected_reader] is None
                and insert_drag["moves"] >= requirements["minimum_insert_moves"]
                and duration >= requirements["minimum_insert_ms"]
            )
            if valid:
                card_locations[card_id] = detected_reader
                reader_cards[detected_reader] = card_id
                reader_feedback[detected_reader] = "READY TO SWIPE"
            else:
                invalid_insertions += 1
                if detected_reader is not None:
                    reader_feedback[detected_reader] = "WRONG CARD"
            insert_drag = None
            continue
        if kind == "swipe_down":
            reader_id = str(event.get("reader_id") or "")
            card_id = str(event.get("card_id") or "")
            if swipe is not None or insert_drag is not None or reader_id not in reader_by_id:
                return _fail(f"event {sequence} begins an invalid stripe swipe")
            if reader_cards[reader_id] != card_id or reader_locked[reader_id]:
                return _fail(f"event {sequence} swipes a card that is not inserted and unlocked")
            try:
                point = _point(event.get("point"), contract["width"], contract["height"], "swipe start")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            track = reader_by_id[reader_id]["track"]
            expected_x = int(track["x_start"]) if track["direction"] == "ltr" else int(track["x_end"])
            if event.get("elapsed_ms") != 0 or abs(point[0] - expected_x) > 24 or abs(point[1] - int(track["y"])) > int(track["lane_half_height"]):
                return _fail(f"event {sequence} swipe did not begin on the illuminated pickup end")
            swipe = {"reader_id": reader_id, "card_id": card_id, "last_elapsed": 0, "points": [point]}
            continue
        if kind == "swipe_move":
            if swipe is None or str(event.get("reader_id") or "") != swipe["reader_id"] or str(event.get("card_id") or "") != swipe["card_id"]:
                return _fail(f"event {sequence} swipe sample has no matching hold")
            try:
                point = _point(event.get("point"), contract["width"], contract["height"], "swipe sample")
                elapsed = _integer(event.get("elapsed_ms"), "swipe elapsed")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            if elapsed < swipe["last_elapsed"] or elapsed > 10_000:
                return _fail(f"event {sequence} swipe sample time is inconsistent")
            swipe["last_elapsed"] = elapsed
            swipe["points"].append(point)
            continue
        if kind == "swipe_up":
            if swipe is None or str(event.get("reader_id") or "") != swipe["reader_id"] or str(event.get("card_id") or "") != swipe["card_id"]:
                return _fail(f"event {sequence} swipe release has no matching hold")
            try:
                point = _point(event.get("point"), contract["width"], contract["height"], "swipe release")
                duration = _integer(event.get("duration_ms"), "swipe duration")
            except ValueError as exc:
                return _fail(f"event {sequence}: {exc}")
            if duration < swipe["last_elapsed"] or duration > 10_000:
                return _fail(f"event {sequence} swipe duration is inconsistent")
            if point != swipe["points"][-1]:
                swipe["points"].append(point)
            reader_id = swipe["reader_id"]
            result = _evaluate_swipe(reader_by_id[reader_id], swipe["points"], duration)
            reader_attempts[reader_id] += 1
            swipe_attempts += 1
            reader_feedback[reader_id] = result["feedback"]
            if result["feedback"] == "ACCEPTED":
                reader_locked[reader_id] = True
            swipe = None
            continue
        if kind == "audit":
            if insert_drag is not None or swipe is not None:
                return _fail(f"event {sequence} audits during an active pointer hold")
            audit_count += 1
            audit_complete = all(reader_locked.values())
            continue
        return _fail(f"event {sequence} has unknown kind {kind!r}")

    expected_reader_states = {
        reader_id: {"card_id": reader_cards[reader_id], "locked": reader_locked[reader_id], "attempts": reader_attempts[reader_id]}
        for reader_id in reader_by_id
    }
    expected_payload = {
        "card_locations": card_locations,
        "reader_states": expected_reader_states,
        "locked_count": sum(reader_locked.values()),
        "invalid_insertions": invalid_insertions,
        "swipe_attempts": swipe_attempts,
        "reset_count": reset_count,
        "audit_count": audit_count,
    }
    for field, expected in expected_payload.items():
        if payload.get(field) != expected:
            return _fail(f"submitted {field} does not match calibration replay")
    passed = (
        payload.get("completed") is True
        and audit_complete
        and audit_count >= 1
        and insert_drag is None
        and swipe is None
        and all(reader_locked.values())
        and all(card_locations[card_id] == str(card_by_id[card_id]["assigned_reader"]) for card_id in card_by_id)
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"calibration replay: inserted {sum(value is not None for value in card_locations.values())}/3; "
            f"locked {sum(reader_locked.values())}/3; swipe attempts {swipe_attempts}; invalid insertions {invalid_insertions}; "
            f"reset count {reset_count}; audit={'complete' if audit_complete else 'incomplete'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "assignments": {card["id"]: card["assigned_reader"] for card in ground_truth.get("cards") or []},
        "readers": {
            reader["id"]: {
                "direction": reader["track"]["direction"],
                "minimum_ms": reader["calibration"]["minimum_ms"],
                "maximum_ms": reader["calibration"]["maximum_ms"],
                "solver_ms": reader["calibration"]["solver_ms"],
                "straightness_px": reader["calibration"]["straightness_px"],
            }
            for reader in ground_truth.get("readers") or []
        },
        "instruction": "Match badge to badge, insert each card, then swipe monotonically from the illuminated arrow end through the track centre using the reader solver duration.",
        "answers": [],
    }
