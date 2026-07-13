from __future__ import annotations

from typing import Any


MECHANIC_ID = "single_scene_split_boxes"


def _fail(feedback: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "feedback": feedback}


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label} must be an integer")
    return value


def _clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, value))


def _mod(value: int, modulus: int) -> int:
    return ((value % modulus) + modulus) % modulus


def _triangle(value: int, span: int) -> int:
    phase = _mod(value, span * 2)
    return span - abs(phase - span)


def _field(scene: dict[str, Any], x_milli: int, y_milli: int, time_ms: int) -> int:
    seed = int(scene["field_seed"])
    target = scene["target"]
    target_x = _mod((seed % 3000) + (time_ms * int(target["speed_x_milli"]) // 1000), 3000)
    target_y = _triangle(((seed // 17) % 6000) + (time_ms * int(target["speed_y_milli"]) // 1000), 3000)
    base = _mod(x_milli * 17 + y_milli * 29 + (time_ms // 20) * 31 + seed, 4093)
    pulse = max(0, 1100 - (abs(x_milli - target_x) + abs(y_milli - target_y)) // 2)
    return _mod(base + pulse * 3, 8192)


def _world_coordinate(tile: dict[str, Any], rotation: int, local_x: int, local_y: int) -> tuple[int, int]:
    if rotation == 180:
        local_x, local_y = 1000 - local_x, 1000 - local_y
    source = tile["source"]
    return int(source["column"]) * 1000 + local_x, int(source["row"]) * 1000 + local_y


def _continuity(
    scene: dict[str, Any], slots: list[str], tile_by_id: dict[str, dict[str, Any]], rotations: dict[str, int], phases: dict[str, int], scene_tick: int
) -> int:
    phase_ms = int(scene["phase_tick_ms"])
    error = 0
    samples = (220, 500, 780)
    for row in range(3):
        for column in range(2):
            left_id = slots[row * 3 + column]
            right_id = slots[row * 3 + column + 1]
            for local_y in samples:
                left_x, left_y = _world_coordinate(tile_by_id[left_id], rotations[left_id], 1000, local_y)
                right_x, right_y = _world_coordinate(tile_by_id[right_id], rotations[right_id], 0, local_y)
                left_value = _field(scene, left_x, left_y, scene_tick + phases[left_id] * phase_ms)
                right_value = _field(scene, right_x, right_y, scene_tick + phases[right_id] * phase_ms)
                error += abs(left_value - right_value)
    for row in range(2):
        for column in range(3):
            top_id = slots[row * 3 + column]
            bottom_id = slots[(row + 1) * 3 + column]
            for local_x in samples:
                top_x, top_y = _world_coordinate(tile_by_id[top_id], rotations[top_id], local_x, 1000)
                bottom_x, bottom_y = _world_coordinate(tile_by_id[bottom_id], rotations[bottom_id], local_x, 0)
                top_value = _field(scene, top_x, top_y, scene_tick + phases[top_id] * phase_ms)
                bottom_value = _field(scene, bottom_x, bottom_y, scene_tick + phases[bottom_id] * phase_ms)
                error += abs(top_value - bottom_value)
    return error


def _errors(
    scene: dict[str, Any], slots: list[str], tile_by_id: dict[str, dict[str, Any]], rotations: dict[str, int], phases: dict[str, int], scene_tick: int
) -> dict[str, int]:
    spatial = sum(
        int(tile_by_id[tile_id]["source"]["row"]) * 3 + int(tile_by_id[tile_id]["source"]["column"]) != slot
        for slot, tile_id in enumerate(slots)
    )
    rotation = sum(rotations[tile_id] != 0 for tile_id in slots)
    phase = sum(abs(phases[tile_id]) for tile_id in slots)
    return {
        "spatial_error": int(spatial),
        "rotation_error": int(rotation),
        "phase_error": int(phase),
        "continuity_milli": _continuity(scene, slots, tile_by_id, rotations, phases, scene_tick),
    }


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


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]):
    for key in ("scene", "tiles", "phase_range", "requirements"):
        if public_state.get(key) != ground_truth.get(key):
            raise ValueError(f"public {key} differs from hidden contract")
    scene = ground_truth.get("scene")
    tiles = ground_truth.get("tiles")
    phase_range = ground_truth.get("phase_range")
    requirements = ground_truth.get("requirements")
    if not isinstance(scene, dict) or not isinstance(tiles, list) or len(tiles) != 9:
        raise ValueError("scene or tile contract is malformed")
    if not isinstance(phase_range, dict) or not isinstance(requirements, dict):
        raise ValueError("phase or sync contract is malformed")
    ids = [str(tile.get("id") or "") for tile in tiles if isinstance(tile, dict)]
    if len(ids) != 9 or len(set(ids)) != 9 or any(not tile_id for tile_id in ids):
        raise ValueError("tile identities are malformed")
    slots: list[str | None] = [None] * 9
    tile_by_id: dict[str, dict[str, Any]] = {}
    rotations: dict[str, int] = {}
    phases: dict[str, int] = {}
    for tile in tiles:
        tile_id = str(tile["id"])
        slot = _integer(tile.get("initial_slot"), "initial slot")
        source = tile.get("source")
        if not isinstance(source, dict) or not 0 <= slot < 9 or slots[slot] is not None:
            raise ValueError("initial tile placement is malformed")
        source_index = _integer(source.get("row"), "source row") * 3 + _integer(source.get("column"), "source column")
        if not 0 <= source_index < 9:
            raise ValueError("tile source is malformed")
        rotation = _integer(tile.get("initial_rotation"), "initial rotation")
        phase = _integer(tile.get("initial_phase"), "initial phase")
        if rotation not in {0, 180} or not int(phase_range["minimum"]) <= phase <= int(phase_range["maximum"]):
            raise ValueError("initial tile transform is malformed")
        slots[slot] = tile_id
        tile_by_id[tile_id] = tile
        rotations[tile_id] = rotation
        phases[tile_id] = phase
    return scene, [str(tile_id) for tile_id in slots], tile_by_id, rotations, phases, {key: int(value) for key, value in requirements.items()}, int(phase_range["minimum"]), int(phase_range["maximum"])


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    binding_error = _bind(payload, ground_truth, public_state)
    if binding_error:
        return _fail(binding_error)
    try:
        scene, slots, tile_by_id, rotations, phases, requirements, phase_min, phase_max = _contract(ground_truth, public_state)
    except (KeyError, TypeError, ValueError) as exc:
        return _fail(f"invalid shattered-scene contract: {exc}")
    events = payload.get("events")
    if not isinstance(events, list) or not (3 <= len(events) <= 900):
        return _fail("synchronizer transcript is missing or outside limits")

    spatial_touched: set[str] = set()
    rotation_touched: set[str] = set()
    phase_touched: set[str] = set()
    sync_active = False
    sync_complete = False
    sync_start_tick = 0
    sync_samples: list[bool] = []
    last_elapsed = -1
    last_scene_tick = -1
    sync_duration = 0
    for index, event in enumerate(events, start=1):
        if sync_complete:
            return _fail("transcript continues after SYNC release")
        if not isinstance(event, dict) or event.get("sequence") != index:
            return _fail(f"event {index} has an invalid sequence")
        event_type = str(event.get("type") or "")
        if event_type == "swap":
            if sync_active:
                return _fail(f"event {index} moves a tile during SYNC")
            tile_id = str(event.get("tile_id") or "")
            displaced_id = str(event.get("displaced_id") or "")
            try:
                from_slot = _integer(event.get("from_slot"), "swap origin")
                to_slot = _integer(event.get("to_slot"), "swap destination")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if tile_id not in tile_by_id or displaced_id not in tile_by_id or from_slot == to_slot:
                return _fail(f"event {index} has invalid swap identities")
            if not 0 <= from_slot < 9 or not 0 <= to_slot < 9 or slots[from_slot] != tile_id or slots[to_slot] != displaced_id:
                return _fail(f"event {index} swap does not match replay")
            slots[from_slot], slots[to_slot] = slots[to_slot], slots[from_slot]
            spatial_touched.update((tile_id, displaced_id))
        elif event_type == "rotate":
            if sync_active:
                return _fail(f"event {index} rotates a tile during SYNC")
            tile_id = str(event.get("tile_id") or "")
            if tile_id not in tile_by_id:
                return _fail(f"event {index} rotates an unknown tile")
            rotations[tile_id] = 0 if rotations[tile_id] == 180 else 180
            if event.get("rotation_after") != rotations[tile_id]:
                return _fail(f"event {index} rotation state disagrees with replay")
            rotation_touched.add(tile_id)
        elif event_type == "phase":
            if sync_active:
                return _fail(f"event {index} scrubs a tile during SYNC")
            tile_id = str(event.get("tile_id") or "")
            if tile_id not in tile_by_id:
                return _fail(f"event {index} scrubs an unknown tile")
            try:
                delta = _integer(event.get("delta_ticks"), "phase delta")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if delta == 0 or abs(delta) > phase_max - phase_min:
                return _fail(f"event {index} phase delta lies outside limits")
            phases[tile_id] = _clamp(phases[tile_id] + delta, phase_min, phase_max)
            if event.get("phase_after") != phases[tile_id]:
                return _fail(f"event {index} phase state disagrees with replay")
            phase_touched.add(tile_id)
        elif event_type == "sync_start":
            if sync_active:
                return _fail(f"event {index} starts a second SYNC")
            try:
                sync_start_tick = _integer(event.get("scene_tick"), "SYNC start tick")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if sync_start_tick < 0:
                return _fail(f"event {index} has a negative scene tick")
            sync_active = True
            sync_samples = []
            last_elapsed = -1
            last_scene_tick = sync_start_tick - 1
        elif event_type == "sync_sample":
            if not sync_active:
                return _fail(f"event {index} has a stability sample outside SYNC")
            try:
                elapsed = _integer(event.get("elapsed_ms"), "sample elapsed time")
                scene_tick = _integer(event.get("scene_tick"), "sample scene tick")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if elapsed < last_elapsed or scene_tick <= last_scene_tick or abs((scene_tick - sync_start_tick) - elapsed) > 70:
                return _fail(f"event {index} has an inconsistent temporal sample")
            expected = _errors(scene, slots, tile_by_id, rotations, phases, scene_tick)
            for field, value in expected.items():
                if event.get(field) != value:
                    return _fail(f"event {index} {field} disagrees with analytic continuity")
            stable = all(value == 0 for value in expected.values())
            if event.get("stable") is not stable:
                return _fail(f"event {index} misreports scene coherence")
            sync_samples.append(stable)
            last_elapsed, last_scene_tick = elapsed, scene_tick
        elif event_type == "sync_end":
            if not sync_active:
                return _fail(f"event {index} ends SYNC that is not active")
            try:
                sync_duration = _integer(event.get("duration_ms"), "SYNC duration")
                sample_count = _integer(event.get("sample_count"), "SYNC sample count")
            except ValueError as exc:
                return _fail(f"event {index} is malformed: {exc}")
            if sample_count != len(sync_samples) or not 1 <= sync_duration <= 5000:
                return _fail(f"event {index} has an inconsistent SYNC summary")
            sync_active = False
            sync_complete = True
        else:
            return _fail(f"event {index} has unknown type {event_type!r}")

    if sync_active or not sync_complete:
        return _fail("transcript does not end with a released SYNC hold")
    expected_slots = {tile_id: int(tile["source"]["row"]) * 3 + int(tile["source"]["column"]) for tile_id, tile in tile_by_id.items()}
    final_slots = {tile_id: slot for slot, tile_id in enumerate(slots)}
    expected_spatial_touched = {tile_id for tile_id, tile in tile_by_id.items() if int(tile["initial_slot"]) != expected_slots[tile_id]}
    expected_rotation_touched = {tile_id for tile_id, tile in tile_by_id.items() if int(tile["initial_rotation"]) != 0}
    expected_phase_touched = {tile_id for tile_id, tile in tile_by_id.items() if int(tile["initial_phase"]) != 0}
    if payload.get("final_slots") != final_slots or payload.get("final_rotations") != rotations or payload.get("final_phases") != phases:
        return _fail("submitted final mosaic does not match replay")
    final_errors = _errors(scene, slots, tile_by_id, rotations, phases, max(last_scene_tick, 0))
    passed = (
        payload.get("completed") is True
        and final_slots == expected_slots
        and all(value == 0 for value in rotations.values())
        and all(value == 0 for value in phases.values())
        and expected_spatial_touched <= spatial_touched
        and expected_rotation_touched <= rotation_touched
        and expected_phase_touched <= phase_touched
        and len(spatial_touched) >= requirements["minimum_spatial_touches"]
        and len(rotation_touched) >= requirements["minimum_rotation_touches"]
        and len(phase_touched) >= requirements["minimum_phase_touches"]
        and sync_duration >= requirements["hold_ms"] - 40
        and len(sync_samples) >= requirements["minimum_samples"]
        and bool(sync_samples)
        and all(sync_samples)
        and all(value == 0 for value in final_errors.values())
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"shattered-scene replay: spatial touches {len(spatial_touched)}/{len(expected_spatial_touched)}; "
            f"rotation touches {len(rotation_touched)}/{len(expected_rotation_touched)}; "
            f"phase touches {len(phase_touched)}/{len(expected_phase_touched)}; "
            f"stable samples {sum(sync_samples)}/{len(sync_samples)}; hold {sync_duration}ms"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    return {
        "solution_slots": ground_truth.get("solution_slots") or {},
        "solution_rotation": 0,
        "solution_phase": 0,
        "instruction": "Place every shard at its source row/column, clear all 180-degree flips, scrub every phase to master zero, then hold SYNC.",
        "answers": [],
    }
