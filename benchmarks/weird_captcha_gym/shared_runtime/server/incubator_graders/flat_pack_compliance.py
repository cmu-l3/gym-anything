from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "flat_pack_compliance"


def _angle_error(first: float, second: float) -> float:
    return abs((first - second + math.pi) % (2 * math.pi) - math.pi)


def _socket(pose: list[float], local: list[float]) -> tuple[float, float]:
    cosine, sine = math.cos(pose[2]), math.sin(pose[2])
    return pose[0] + local[0] * cosine - local[1] * sine, pose[1] + local[0] * sine + local[1] * cosine


def _joint_valid(joint: dict[str, Any], poses: dict[str, list[float]], targets: dict[str, list[float]]) -> tuple[bool, float]:
    a, b = poses[joint["a"]], poses[joint["b"]]
    first, second = _socket(a, joint["socket_a"]), _socket(b, joint["socket_b"])
    distance = math.hypot(first[0] - second[0], first[1] - second[1])
    angle_ok = _angle_error(a[2], targets[joint["a"]][2]) <= float(joint["max_angle_error"])
    angle_ok = angle_ok and _angle_error(b[2], targets[joint["b"]][2]) <= float(joint["max_angle_error"])
    return distance <= float(joint["max_distance"]) and angle_ok, distance


def _target_valid(poses: dict[str, list[float]], targets: dict[str, list[float]], requirements: dict[str, Any]) -> bool:
    return all(
        math.hypot(poses[part][0] - target[0], poses[part][1] - target[1]) <= float(requirements["pose_tolerance"])
        and _angle_error(poses[part][2], target[2]) <= float(requirements["angle_tolerance"])
        for part, target in targets.items()
    )


def _polygon(vertices: list[list[float]], pose: list[float]) -> list[tuple[float, float]]:
    cosine, sine = math.cos(pose[2]), math.sin(pose[2])
    return [(pose[0] + point[0] * cosine - point[1] * sine, pose[1] + point[0] * sine + point[1] * cosine) for point in vertices]


def _penetration(first: list[tuple[float, float]], second: list[tuple[float, float]]) -> float:
    minimum = math.inf
    for polygon in (first, second):
        for index, point in enumerate(polygon):
            following = polygon[(index + 1) % len(polygon)]
            axis = (-(following[1] - point[1]), following[0] - point[0])
            length = math.hypot(*axis)
            if length <= 1e-9:
                continue
            axis = (axis[0] / length, axis[1] / length)
            first_projection = [item[0] * axis[0] + item[1] * axis[1] for item in first]
            second_projection = [item[0] * axis[0] + item[1] * axis[1] for item in second]
            overlap = min(max(first_projection), max(second_projection)) - max(min(first_projection), min(second_projection))
            if overlap <= 0:
                return 0.0
            minimum = min(minimum, overlap)
    return 0.0 if math.isinf(minimum) else minimum


def _collision_safe(parts: dict[str, dict[str, Any]], poses: dict[str, list[float]], limit: float) -> bool:
    ids = sorted(parts)
    polygons = {part_id: _polygon(parts[part_id]["vertices"], poses[part_id]) for part_id in ids}
    return all(_penetration(polygons[ids[first]], polygons[ids[second]]) <= limit for first in range(len(ids)) for second in range(first + 1, len(ids)))


def _contract_strain(step: dict[str, Any], compliance: dict[str, Any]) -> dict[str, float]:
    base = abs(float(step["force_x"])) * float(compliance["force_x_scale"]) + abs(float(step["force_y"])) * float(compliance["force_y_scale"])
    return {joint_id: math.floor(base * float(factor) * 1000 + 0.5) / 1000 for joint_id, factor in compliance["joint_factors"].items()}


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge or str(payload.get("challenge_id") or "") != challenge or str(public_state.get("challenge_id") or "") != challenge:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return {"graded": True, "passed": False, "feedback": "task identity mismatch"}
    for field in ("task_id", "stage", "parts", "joints", "load_steps", "compliance_model", "requirements"):
        if public_state.get(field) != ground_truth.get(field):
            return {"graded": True, "passed": False, "feedback": f"public/private flat-pack {field} contract skew"}
    try:
        parts = {item["id"]: item for item in ground_truth["parts"]}
        joints = {item["id"]: item for item in ground_truth["joints"]}
        expected_joint_ids = set(ground_truth["expected_joint_ids"])
        targets = {part_id: list(item["target_pose"]) for part_id, item in parts.items()}
        initial = {part_id: list(item["initial_pose"]) for part_id, item in parts.items()}
        load_steps = list(ground_truth["load_steps"])
        requirements = dict(ground_truth["requirements"])
        compliance = dict(ground_truth["compliance_model"])
        if len(parts) < 7 or len(joints) != len(parts) - 1 or expected_joint_ids != set(joints):
            raise ValueError("assembly topology is incomplete")
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid flat-pack contract: {exc}"}
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 1800):
        return {"graded": True, "passed": False, "feedback": "assembly transcript missing or outside limits"}

    poses = {key: list(value) for key, value in initial.items()}
    connected: set[str] = set()
    drag: dict[str, Any] | None = None
    load_active = False
    load_tick = 0
    successful_load = False
    terminal = False
    resets = rejected = contacts = 0
    observed_max_strain = 0.0
    load_previous: dict[str, list[float]] | None = None

    for sequence, event in enumerate(events, start=1):
        if terminal:
            return {"graded": True, "passed": False, "feedback": "interaction continued after terminal load"}
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if kind == "contact":
            pair = event.get("pair")
            if not isinstance(pair, list) or len(pair) != 2 or pair != sorted(pair) or any(item not in parts for item in pair):
                return {"graded": True, "passed": False, "feedback": "invalid symmetric contact trace"}
            contacts += 1
            continue
        if kind == "drag_start":
            part_id, point = str(event.get("part_id") or ""), event.get("point")
            if drag is not None or load_active or part_id not in parts or not isinstance(point, list) or len(point) != 2:
                return {"graded": True, "passed": False, "feedback": "invalid drag start"}
            if math.hypot(float(point[0]) - poses[part_id][0], float(point[1]) - poses[part_id][1]) > 80:
                return {"graded": True, "passed": False, "feedback": "drag did not begin on the rigid body"}
            drag = {"part": part_id, "last": [float(point[0]), float(point[1])], "last_pose": list(poses[part_id]), "samples": 0}
            continue
        if kind == "drag_sample":
            point, sample_pose = event.get("point"), event.get("pose")
            if drag is None or not isinstance(point, list) or len(point) != 2 or not isinstance(sample_pose, list) or len(sample_pose) != 3:
                return {"graded": True, "passed": False, "feedback": "orphan drag sample"}
            candidate = [float(point[0]), float(point[1])]
            if math.hypot(candidate[0] - drag["last"][0], candidate[1] - drag["last"][1]) > 125:
                return {"graded": True, "passed": False, "feedback": "sparse teleport in assembly drag"}
            body_pose = [float(value) for value in sample_pose]
            if math.hypot(body_pose[0] - drag["last_pose"][0], body_pose[1] - drag["last_pose"][1]) > 130 or _angle_error(body_pose[2], drag["last_pose"][2]) > 0.52:
                return {"graded": True, "passed": False, "feedback": "unreplayed rigid-body jump during drag"}
            if math.hypot(body_pose[0] - candidate[0], body_pose[1] - candidate[1]) > 90:
                return {"graded": True, "passed": False, "feedback": "dragged body escaped its pointer spring"}
            drag["last"] = candidate
            drag["last_pose"] = body_pose
            drag["samples"] += 1
            poses[drag["part"]] = body_pose
            continue
        if kind == "drag_end":
            pose = event.get("pose")
            if drag is None or drag["samples"] < 1 or not isinstance(pose, list) or len(pose) != 3 or event.get("part_id") != drag["part"]:
                return {"graded": True, "passed": False, "feedback": "invalid drag release"}
            values = [float(value) for value in pose]
            if not (24 <= values[0] <= 876 and 24 <= values[1] <= 456):
                return {"graded": True, "passed": False, "feedback": "part released outside collision walls"}
            if math.hypot(values[0] - drag["last_pose"][0], values[1] - drag["last_pose"][1]) > 0.1 or _angle_error(values[2], drag["last_pose"][2]) > 0.002:
                return {"graded": True, "passed": False, "feedback": "drag release angle/pose was not explicitly replayed"}
            poses[drag["part"]] = values
            drag = None
            continue
        if kind == "rotate":
            part_id, pose = str(event.get("part_id") or ""), event.get("pose")
            delta = float(event.get("delta") or 0)
            if drag is not None or load_active or part_id not in parts or abs(abs(delta) - math.pi / 2) > 0.001 or not isinstance(pose, list) or len(pose) != 3:
                return {"graded": True, "passed": False, "feedback": "invalid keyed rotation impulse"}
            expected = poses[part_id][2] + delta
            if _angle_error(float(pose[2]), expected) > 0.01:
                return {"graded": True, "passed": False, "feedback": "rotation trace disagrees with rigid-body pose"}
            if math.hypot(float(pose[0]) - poses[part_id][0], float(pose[1]) - poses[part_id][1]) > 0.02:
                return {"graded": True, "passed": False, "feedback": "rotation control teleported the rigid body"}
            poses[part_id] = [float(pose[0]), float(pose[1]), float(pose[2])]
            continue
        if kind == "joint_attempt":
            joint_id, accepted = str(event.get("joint_id") or ""), event.get("accepted") is True
            if load_active:
                return {"graded": True, "passed": False, "feedback": "joint mutated during compliance load"}
            joint = joints.get(joint_id)
            valid, _distance = _joint_valid(joint, poses, targets) if joint else (False, math.inf)
            if accepted != (joint is not None and valid and joint_id not in connected):
                return {"graded": True, "passed": False, "feedback": "joint acceptance disagrees with keyed socket geometry"}
            if accepted:
                connected.add(joint_id)
            else:
                rejected += 1
            continue
        if kind == "load_start":
            accepted = event.get("accepted") is True
            eligible = connected == expected_joint_ids and _target_valid(poses, targets, requirements) and _collision_safe(parts, poses, float(compliance["maximum_contact_penetration"]))
            if load_active or accepted != eligible:
                return {"graded": True, "passed": False, "feedback": "load precondition claim disagrees with assembly replay"}
            if accepted:
                load_active, load_tick, observed_max_strain = True, 0, 0.0
                load_previous = {key: list(value) for key, value in poses.items()}
            continue
        if kind == "load_tick":
            if not load_active or load_tick >= len(load_steps):
                return {"graded": True, "passed": False, "feedback": "load tick outside active deterministic test"}
            load_tick += 1
            expected = load_steps[load_tick - 1]
            if event.get("step") != load_tick or event.get("force_x") != expected["force_x"] or event.get("force_y") != expected["force_y"]:
                return {"graded": True, "passed": False, "feedback": f"load force {load_tick} was tampered"}
            lengths = event.get("constraint_lengths")
            sensor = event.get("contract_strain")
            body_poses = event.get("poses")
            expected_sensor = _contract_strain(expected, compliance)
            if sensor != expected_sensor:
                return {"graded": True, "passed": False, "feedback": "deterministic compliance sensor was fabricated"}
            if not isinstance(lengths, dict) or set(lengths) != expected_joint_ids or not isinstance(body_poses, dict) or set(body_poses) != set(parts):
                return {"graded": True, "passed": False, "feedback": "load pose/contact trace is incomplete"}
            raw_strain = max(float(value) for value in lengths.values())
            if not math.isfinite(raw_strain) or raw_strain > 120:
                return {"graded": True, "passed": False, "feedback": "physical joint separated beyond replayable bounds"}
            observed_max_strain = max(observed_max_strain, max(expected_sensor.values()))
            normalized_poses: dict[str, list[float]] = {}
            for part_id, pose in body_poses.items():
                if not isinstance(pose, list) or len(pose) != 3 or not all(math.isfinite(float(v)) for v in pose):
                    return {"graded": True, "passed": False, "feedback": "invalid rigid-body load pose"}
                normalized_poses[part_id] = [float(value) for value in pose]
                previous = (load_previous or poses)[part_id]
                if math.hypot(normalized_poses[part_id][0] - previous[0], normalized_poses[part_id][1] - previous[1]) > float(compliance["maximum_step_translation"]) or _angle_error(normalized_poses[part_id][2], previous[2]) > float(compliance["maximum_step_rotation"]):
                    return {"graded": True, "passed": False, "feedback": "impossible load-step rigid-body teleport"}
            for joint_id, joint in joints.items():
                first, second = _socket(normalized_poses[joint["a"]], joint["socket_a"]), _socket(normalized_poses[joint["b"]], joint["socket_b"])
                derived_length = math.hypot(first[0] - second[0], first[1] - second[1])
                if abs(float(lengths[joint_id]) - derived_length) > 0.08:
                    return {"graded": True, "passed": False, "feedback": "constraint length disagrees with submitted physical poses"}
            load_previous = normalized_poses
            continue
        if kind == "load_end":
            if not load_active or load_tick != len(load_steps):
                return {"graded": True, "passed": False, "feedback": "compliance test ended before every force step"}
            submitted_strain = float(event.get("max_strain") or 0)
            if abs(submitted_strain - observed_max_strain) > 0.05:
                return {"graded": True, "passed": False, "feedback": "reported strain disagrees with replay"}
            # Survival is derived from exact topology + deterministic load contract, not a client flag.
            successful_load = connected == expected_joint_ids and _target_valid(poses, targets, requirements) and _collision_safe(parts, poses, float(compliance["maximum_contact_penetration"])) and observed_max_strain <= float(requirements["strain_limit"])
            load_active = False
            terminal = successful_load
            continue
        if kind == "reset":
            if load_active or terminal:
                return {"graded": True, "passed": False, "feedback": "assembly reset during or after terminal load"}
            poses = {key: list(value) for key, value in initial.items()}
            connected.clear()
            drag = None
            resets += 1
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    summaries = {
        "completed": successful_load,
        "joint_ids": sorted(connected),
        "load_ticks": load_tick,
        "resets": resets,
        "rejected_attempts": rejected,
        "collision_contacts": contacts,
        "max_strain": round(observed_max_strain, 3),
    }
    for field, value in summaries.items():
        if payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with assembly replay"}
    passed = successful_load and terminal and drag is None and connected == expected_joint_ids
    return {"graded": True, "passed": passed, "score": 100 if passed else 0,
            "feedback": f"flat-pack replay: joints {len(connected)}/{len(joints)}; load {load_tick}/{len(load_steps)}; contacts {contacts}; resets {resets}; max strain {observed_max_strain:.1f}"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"target_poses": {item["id"]: item["target_pose"] for item in ground_truth.get("parts") or []}, "joints": ground_truth.get("joints") or []}
