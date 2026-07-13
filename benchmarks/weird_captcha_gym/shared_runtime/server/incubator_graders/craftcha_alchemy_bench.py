from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "craftcha_alchemy_bench"
PROCESS_STATIONS = ("grind", "heat", "infuse", "press")
ALL_STATIONS = (*PROCESS_STATIONS, "assemble")


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def _point(value: Any, width: float, height: float) -> tuple[float, float] | None:
    if not isinstance(value, dict):
        return None
    x, y = _number(value.get("x")), _number(value.get("y"))
    if x is None or y is None or x < 0 or y < 0 or x > width or y > height:
        return None
    return x, y


def _rect(value: Any) -> tuple[float, float, float, float] | None:
    if not isinstance(value, dict):
        return None
    values = tuple(_number(value.get(key)) for key in ("x1", "y1", "x2", "y2"))
    if any(item is None for item in values):
        return None
    x1, y1, x2, y2 = values
    return (x1, y1, x2, y2) if x1 < x2 and y1 < y2 else None


def _inside(point: tuple[float, float], rect: tuple[float, float, float, float], margin: float = 0.0) -> bool:
    x, y = point
    x1, y1, x2, y2 = rect
    return x1 - margin <= x <= x2 + margin and y1 - margin <= y <= y2 + margin


def _distance(left: tuple[float, float], right: tuple[float, float]) -> float:
    return math.hypot(left[0] - right[0], left[1] - right[1])


def _time(value: Any) -> float | None:
    result = _number(value)
    return result if result is not None and 0 <= result <= 3_600_000 else None


def _snapshot(
    inventory: list[str | None],
    stations: dict[str, str | None],
    assembly: list[str],
    delivery: str | None,
    *,
    recipe_sealed: bool,
    memory_charge: int,
    replay_count: int,
    reset_count: int,
    transform_count: int,
    discard_count: int,
    drag_count: int,
    submitted: bool,
) -> dict[str, Any]:
    return {
        "inventory": list(inventory),
        "stations": {station: stations[station] for station in ALL_STATIONS},
        "assembly": list(assembly),
        "delivery": delivery,
        "recipe_sealed": recipe_sealed,
        "memory_charge": memory_charge,
        "replay_count": replay_count,
        "reset_count": reset_count,
        "transform_count": transform_count,
        "discard_count": discard_count,
        "drag_count": drag_count,
        "submitted": submitted,
    }


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("mechanic mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return _failure("stale challenge")
    if str(public_state.get("challenge_id") or "") != challenge_id or str(public_state.get("mechanic_id") or "") != MECHANIC_ID:
        return _failure("public alchemy state does not match the hidden challenge")
    compared_fields = (
        "geometry", "recipe", "recipe_hash", "recipe_window_ms", "replay_window_ms",
        "memory_charge_initial", "memory_replay_cost", "replay_limit", "inventory_capacity",
        "initial_inventory", "active_station_ids", "station_serials",
    )
    if any(public_state.get(field) != ground_truth.get(field) for field in compared_fields):
        return _failure("public bench manifest disagrees with hidden state")

    recipe = ground_truth.get("recipe")
    geometry = ground_truth.get("geometry")
    if not isinstance(recipe, dict) or not isinstance(geometry, dict):
        return _failure("hidden recipe or bench geometry is missing")
    width, height = _number(geometry.get("width")), _number(geometry.get("height"))
    if width is None or height is None or width < 500 or height < 400:
        return _failure("hidden bench dimensions are invalid")
    raw_slot_rects = geometry.get("inventory_slots")
    raw_station_rects = geometry.get("stations")
    raw_cycle_rects = geometry.get("cycle_buttons")
    if not isinstance(raw_slot_rects, list) or len(raw_slot_rects) != 4 or not isinstance(raw_station_rects, dict) or not isinstance(raw_cycle_rects, dict):
        return _failure("hidden interaction geometry is incomplete")
    slot_rects = [_rect(value) for value in raw_slot_rects]
    station_rects = {station: _rect(raw_station_rects.get(station)) for station in ALL_STATIONS}
    cycle_rects = {station: _rect(raw_cycle_rects.get(station)) for station in ALL_STATIONS}
    delivery_rect = _rect(geometry.get("delivery"))
    replay_rect = _rect(geometry.get("replay_button"))
    reset_rect = _rect(geometry.get("reset_button"))
    verify_rect = _rect(geometry.get("verify_button"))
    if any(rect is None for rect in slot_rects) or any(rect is None for rect in station_rects.values()) or any(rect is None for rect in cycle_rects.values()) or None in (delivery_rect, replay_rect, reset_rect, verify_rect):
        return _failure("hidden interaction rectangles are malformed")

    branches = recipe.get("branches")
    if not isinstance(branches, list) or len(branches) != 3:
        return _failure("hidden recipe does not contain three material lineages")
    transition_by_input: dict[str, tuple[str, str]] = {}
    terminal_states: list[str] = []
    raw_states: list[str] = []
    for branch in branches:
        if not isinstance(branch, dict):
            return _failure("hidden material lineage is malformed")
        raw_state = str(branch.get("raw_state_id") or "")
        terminal = str(branch.get("terminal_state_id") or "")
        steps = branch.get("steps")
        if not raw_state or not terminal or not isinstance(steps, list) or not steps:
            return _failure("hidden material lineage is incomplete")
        raw_states.append(raw_state)
        terminal_states.append(terminal)
        expected_input = raw_state
        for step in steps:
            if not isinstance(step, dict):
                return _failure("hidden transformation step is malformed")
            input_state = str(step.get("input_state_id") or "")
            output_state = str(step.get("output_state_id") or "")
            station = str(step.get("station_id") or "")
            if input_state != expected_input or not output_state or station not in PROCESS_STATIONS or input_state in transition_by_input:
                return _failure("hidden transformation chain is inconsistent")
            transition_by_input[input_state] = (station, output_state)
            expected_input = output_state
        if expected_input != terminal:
            return _failure("hidden lineage terminal does not match its chain")
    if len(set(raw_states)) != 3 or len(set(terminal_states)) != 3:
        return _failure("hidden material lineages are not distinct")
    device_state = str(recipe.get("device_state_id") or "")
    step_count = recipe.get("step_count")
    if not device_state or not isinstance(step_count, int) or not 6 <= step_count <= 9 or step_count != len(transition_by_input) + 1:
        return _failure("hidden final assembly is inconsistent")

    initial_inventory = ground_truth.get("initial_inventory")
    if not isinstance(initial_inventory, list) or len(initial_inventory) != 4 or initial_inventory != [*raw_states, None]:
        return _failure("hidden inventory initialization is malformed")
    memory_initial = int(ground_truth.get("memory_charge_initial") or 0)
    replay_cost = int(ground_truth.get("memory_replay_cost") or 0)
    replay_limit = int(ground_truth.get("replay_limit") or 0)
    initial_window = int(ground_truth.get("recipe_window_ms") or 0)
    replay_window = int(ground_truth.get("replay_window_ms") or 0)
    recipe_hash = str(ground_truth.get("recipe_hash") or "")
    if memory_initial < replay_cost > 0 or replay_limit != 1 or initial_window < 1000 or replay_window < 800 or not recipe_hash:
        return _failure("hidden recipe shutter settings are malformed")

    inventory: list[str | None] = list(initial_inventory)
    stations: dict[str, str | None] = {station: None for station in ALL_STATIONS}
    assembly: list[str] = []
    delivery: str | None = None
    recipe_sealed = False
    initial_sealed = False
    replay_pending = False
    replay_started_at = -1.0
    memory_charge = memory_initial
    replay_count = 0
    reset_count = 0
    transform_count = 0
    discard_count = 0
    drag_count = 0
    waste_serial = 0
    submitted = False
    previous_time = -1.0

    events = payload.get("events")
    if not isinstance(events, list) or not events or len(events) > 320:
        return _failure("alchemy interaction transcript is missing or too long")
    for index, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("seq") != index:
            return _failure(f"alchemy event {index} has invalid sequence")
        event_time = _time(event.get("t_ms"))
        if event_time is None or event_time < previous_time:
            return _failure(f"alchemy event {index} has invalid timing")
        previous_time = event_time
        if submitted:
            return _failure("alchemy transcript continues after certification")
        kind = str(event.get("kind") or "")

        if kind == "recipe_seal":
            reason = str(event.get("reason") or "")
            if event.get("recipe_hash") != recipe_hash:
                return _failure(f"recipe shutter {index} has the wrong recipe signature")
            if reason == "initial":
                if initial_sealed or replay_pending or event_time < initial_window - 220:
                    return _failure("initial recipe shutter timing is impossible")
                initial_sealed = True
            elif reason == "replay":
                if not initial_sealed or not replay_pending or event_time - replay_started_at < replay_window - 220:
                    return _failure("replayed recipe shutter timing is impossible")
                replay_pending = False
            else:
                return _failure(f"recipe shutter {index} has an invalid reason")
            recipe_sealed = True
            continue

        if kind == "replay":
            point = _point(event.get("point"), width, height)
            accepted = (
                point is not None and _inside(point, replay_rect) and initial_sealed and recipe_sealed
                and replay_count < replay_limit and memory_charge >= replay_cost
            )
            if event.get("accepted") is not accepted:
                return _failure(f"recipe replay {index} reports a false acceptance")
            if not accepted:
                return _failure("an unavailable recipe replay was recorded")
            replay_count += 1
            memory_charge -= replay_cost
            recipe_sealed = False
            replay_pending = True
            replay_started_at = event_time
            if event.get("memory_after") != memory_charge:
                return _failure("recipe replay reports a false memory charge")
            continue

        if kind == "reset":
            point = _point(event.get("point"), width, height)
            if point is None or not _inside(point, reset_rect) or not initial_sealed or not recipe_sealed:
                return _failure(f"bench reset {index} is not a physical reset press")
            inventory = list(initial_inventory)
            stations = {station: None for station in ALL_STATIONS}
            assembly = []
            delivery = None
            transform_count = 0
            discard_count = 0
            drag_count = 0
            waste_serial = 0
            reset_count += 1
            if event.get("inventory_after") != inventory or event.get("reset_count") != reset_count:
                return _failure("bench reset does not restore the original material rack")
            continue

        if not initial_sealed or not recipe_sealed or replay_pending:
            return _failure(f"alchemy action {index} occurred while the recipe shutter was open")

        if kind == "drag":
            start = _point(event.get("start"), width, height)
            end = _point(event.get("end"), width, height)
            raw_samples = event.get("samples")
            duration = _number(event.get("duration_ms"))
            if start is None or end is None or not isinstance(raw_samples, list) or not 4 <= len(raw_samples) <= 48 or duration is None or not 35 <= duration <= 8_000:
                return _failure(f"drag {index} lacks a physical pointer trajectory")
            samples = [_point(sample, width, height) for sample in raw_samples]
            if any(sample is None for sample in samples):
                return _failure(f"drag {index} leaves the physical bench")
            if _distance(samples[0], start) > 14 or _distance(samples[-1], end) > 14:
                return _failure(f"drag {index} trajectory is detached from its endpoints")
            direct_distance = _distance(start, end)
            path_distance = sum(_distance(left, right) for left, right in zip(samples, samples[1:]))
            if direct_distance < 70 or path_distance < direct_distance * 0.96:
                return _failure(f"drag {index} is not a sustained physical transfer")
            source_matches = [slot for slot, rect in enumerate(slot_rects) if _inside(start, rect)]
            if len(source_matches) != 1:
                return _failure(f"drag {index} does not begin in one inventory slot")
            source_slot = source_matches[0]
            state_id = inventory[source_slot]
            if state_id is None:
                return _failure(f"drag {index} begins in an empty inventory slot")
            station_matches = [station for station, rect in station_rects.items() if _inside(end, rect)]
            to_delivery = _inside(end, delivery_rect)
            if len(station_matches) + int(to_delivery) != 1:
                return _failure(f"drag {index} does not end at exactly one machine or delivery bay")
            if to_delivery:
                if delivery is not None:
                    return _failure("delivery bay received more than one item")
                destination = "delivery"
                inventory[source_slot] = None
                delivery = state_id
            else:
                destination = station_matches[0]
                if destination == "assemble":
                    if len(assembly) >= 3:
                        return _failure("assembler intake exceeds its three physical sockets")
                    inventory[source_slot] = None
                    assembly.append(state_id)
                else:
                    if stations[destination] is not None:
                        return _failure(f"drag {index} overloads the {destination} machine")
                    inventory[source_slot] = None
                    stations[destination] = state_id
            drag_count += 1
            if event.get("source_slot") != source_slot or event.get("destination") != destination or event.get("state_id") != state_id:
                return _failure(f"drag {index} labels disagree with coordinate replay")
            continue

        if kind == "cycle":
            point = _point(event.get("point"), width, height)
            duration = _number(event.get("duration_ms"))
            if point is None or duration is None or not 280 <= duration <= 1_600 or event.get("cycle_pulses") != [1, 2, 3, 4]:
                return _failure(f"machine cycle {index} lacks its physical four-phase cycle")
            matches = [station for station, rect in cycle_rects.items() if _inside(point, rect)]
            if len(matches) != 1:
                return _failure(f"machine cycle {index} is not bound to one crank")
            station = matches[0]
            input_states: list[str]
            if station == "assemble":
                if not assembly:
                    return _failure("assembler cycled with no staged material")
                input_states = list(assembly)
                exact_assembly = len(input_states) == 3 and sorted(input_states) == sorted(terminal_states)
                if exact_assembly:
                    output_state = device_state
                else:
                    waste_serial += 1
                    output_state = f"{challenge_id}:waste:assemble:{waste_serial}"
                    discard_count += 1
                assembly = []
            else:
                loaded = stations[station]
                if loaded is None:
                    return _failure(f"{station} cycled without a loaded item")
                input_states = [loaded]
                transition = transition_by_input.get(loaded)
                if transition is not None and transition[0] == station:
                    output_state = transition[1]
                else:
                    waste_serial += 1
                    output_state = f"{challenge_id}:waste:{station}:{waste_serial}"
                    discard_count += 1
                stations[station] = None
            try:
                output_slot = inventory.index(None)
            except ValueError:
                return _failure(f"machine cycle {index} has no free output inventory slot")
            inventory[output_slot] = output_state
            transform_count += 1
            if (
                event.get("station_id") != station
                or event.get("input_state_ids") != input_states
                or event.get("output_state_id") != output_state
                or event.get("output_slot") != output_slot
            ):
                return _failure(f"machine cycle {index} reports a false transformation lineage")
            continue

        if kind == "submit":
            point = _point(event.get("point"), width, height)
            if point is None or not _inside(point, verify_rect):
                return _failure("certification was not pressed at the physical delivery console")
            certified = delivery == device_state
            if event.get("certified") is not certified:
                return _failure("certification reports a false delivered device")
            submitted = True
            continue

        return _failure(f"alchemy event {index} has invalid action {kind!r}")

    final_state = _snapshot(
        inventory,
        stations,
        assembly,
        delivery,
        recipe_sealed=recipe_sealed,
        memory_charge=memory_charge,
        replay_count=replay_count,
        reset_count=reset_count,
        transform_count=transform_count,
        discard_count=discard_count,
        drag_count=drag_count,
        submitted=submitted,
    )
    if payload.get("final_state") != final_state:
        return _failure("claimed final alchemy state does not match transcript replay")
    expected_drag_count = len(transition_by_input) + 3 + 1
    passed = (
        submitted
        and delivery == device_state
        and recipe_sealed
        and transform_count == step_count
        and discard_count == 0
        and drag_count == expected_drag_count
        and inventory == [None, None, None, None]
        and all(value is None for value in stations.values())
        and not assembly
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"replayed {transform_count}/{step_count} transforms; {drag_count}/{expected_drag_count} drags; "
            f"discarded {discard_count}; recipe replays {replay_count}; resets {reset_count}; "
            f"device delivered {delivery == device_state}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "recipe": ground_truth.get("recipe") or {},
        "solution_steps": ground_truth.get("solution_steps") or [],
        "geometry": ground_truth.get("geometry") or {},
        "answers": [],
    }
