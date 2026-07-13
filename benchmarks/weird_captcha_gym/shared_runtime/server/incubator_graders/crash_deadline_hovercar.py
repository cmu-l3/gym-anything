from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "crash_deadline_hovercar"


def _road(progress: float, physics: dict[str, Any]) -> float:
    return 240 + float(physics["road_amplitude"]) * math.sin(progress / float(physics["road_period"]) + float(physics["road_phase"]))


def _target_point(target: dict[str, Any], tick: int) -> tuple[float, float]:
    phase = float(target["phase"])
    return (float(target["base_x"]) + float(target["orbit_x"]) * math.sin(tick * 0.17 + phase),
            float(target["base_y"]) + float(target["orbit_y"]) * math.cos(tick * 0.13 + phase * 0.7))


def _fresh(physics: dict[str, Any]) -> dict[str, Any]:
    return {"tick": 0, "progress": 0.0, "lateral": _road(0, physics), "lateral_velocity": 0.0,
            "speed": float(physics["start_speed"]), "keys": set(), "crashed": False, "finished": False}


def _step(run: dict[str, Any], physics: dict[str, Any], obstacles: list[dict[str, Any]]) -> tuple[dict[str, float], str | None]:
    up, down = "up" in run["keys"], "down" in run["keys"]
    steer = (1 if "right" in run["keys"] else 0) - (1 if "left" in run["keys"] else 0)
    run["speed"] = max(float(physics["min_speed"]), min(float(physics["max_speed"]), run["speed"] + (float(physics["acceleration"]) if up else 0) - (float(physics["brake"]) if down else 0) - float(physics["drag"])))
    run["lateral_velocity"] = (run["lateral_velocity"] + steer * float(physics["steer_gain"])) * float(physics["lateral_damping"])
    run["lateral"] += run["lateral_velocity"]
    run["progress"] += run["speed"] / 10
    run["tick"] += 1
    road_center = _road(run["progress"], physics)
    reason = None
    if abs(run["lateral"] - road_center) > float(physics["road_half_width"]) - float(physics["car_half_height"]):
        reason = "road_departure"
    for obstacle in obstacles:
        obstacle_y = _road(float(obstacle["world_x"]), physics) + float(obstacle["lane_offset"])
        hit_x = abs(run["progress"] - float(obstacle["world_x"])) <= float(obstacle["width"]) / 2 + float(physics["car_half_width"])
        hit_y = abs(run["lateral"] - obstacle_y) <= float(obstacle["height"]) / 2 + float(physics["car_half_height"])
        if hit_x and hit_y:
            reason = f"collision:{obstacle['id']}"
            break
    if run["tick"] > int(physics["deadline_tick"]):
        reason = "deadline"
    return {"tick": run["tick"], "progress": run["progress"], "lateral": run["lateral"],
            "lateral_velocity": run["lateral_velocity"], "speed": run["speed"], "road_center": road_center}, reason


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge or str(payload.get("challenge_id") or "") != challenge or str(public_state.get("challenge_id") or "") != challenge:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return {"graded": True, "passed": False, "feedback": "task identity mismatch"}
    for field in ("task_id", "stage", "physics", "targets", "obstacles", "requirements"):
        if public_state.get(field) != ground_truth.get(field):
            return {"graded": True, "passed": False, "feedback": f"public/private hovercar {field} contract skew"}
    try:
        physics = dict(ground_truth["physics"])
        targets = {item["id"]: item for item in ground_truth["targets"]}
        obstacles = list(ground_truth["obstacles"])
        requirements = dict(ground_truth["requirements"])
        if len(targets) < 5 or int(requirements.get("check_count", 0)) != len(targets):
            raise ValueError("expanded inspection manifest required")
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid hovercar contract: {exc}"}
    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 3000):
        return {"graded": True, "passed": False, "feedback": "flight transcript missing or outside limits"}

    run = _fresh(physics)
    pointer: list[float] | None = None
    dwell = {target_id: 0 for target_id in targets}
    checks: set[str] = set()
    emitted_checks: set[str] = set()
    pending_crash: str | None = None
    finished = False
    crashes = retries = pointer_samples = 0
    terminal = False

    for sequence, event in enumerate(events, start=1):
        if terminal:
            return {"graded": True, "passed": False, "feedback": "interaction continued after terminal finish"}
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if pending_crash and kind != "crash":
            return {"graded": True, "passed": False, "feedback": "client omitted independently detected crash"}
        if kind == "key_transition":
            key, down = str(event.get("key") or ""), event.get("down") is True
            if run["crashed"] or run["finished"] or key not in {"up", "down", "left", "right"} or event.get("tick") != run["tick"]:
                return {"graded": True, "passed": False, "feedback": "invalid or post-crash key transition"}
            if down:
                run["keys"].add(key)
            else:
                run["keys"].discard(key)
            continue
        if kind == "pointer_move":
            point = event.get("point")
            if run["crashed"] or run["finished"] or event.get("tick") != run["tick"] or not isinstance(point, list) or len(point) != 2:
                return {"graded": True, "passed": False, "feedback": "invalid pointer sample"}
            candidate = [float(point[0]), float(point[1])]
            if not (0 <= candidate[0] <= 980 and 0 <= candidate[1] <= 480):
                return {"graded": True, "passed": False, "feedback": "pointer outside flight console"}
            # Pointer event density varies substantially between a local browser,
            # VNC, and computer-use clients.  Correctness comes from sustained
            # per-tick containment while the simulated craft keeps moving, not
            # from an arbitrary distance between two sampled pointer events.
            pointer = candidate
            pointer_samples += 1
            continue
        if kind == "physics_tick":
            if run["crashed"] or run["finished"]:
                return {"graded": True, "passed": False, "feedback": "physics tick after stopped vehicle"}
            previous_progress = run["progress"]
            expected, reason = _step(run, physics, obstacles)
            if event.get("tick") != run["tick"]:
                return {"graded": True, "passed": False, "feedback": "fixed-step time reversal or omission"}
            reported = event.get("state")
            if not isinstance(reported, dict):
                return {"graded": True, "passed": False, "feedback": "vehicle state trace missing"}
            for field in ("progress", "lateral", "lateral_velocity", "speed", "road_center"):
                if abs(float(reported.get(field, math.inf)) - expected[field]) > 0.025:
                    return {"graded": True, "passed": False, "feedback": f"vehicle {field} disagrees with fixed-step replay"}
            for target_id, target in targets.items():
                if target_id in checks:
                    continue
                inside_window = int(target["window_start"]) <= run["tick"] <= int(target["window_end"])
                point = _target_point(target, run["tick"])
                inside = pointer is not None and math.hypot(pointer[0] - point[0], pointer[1] - point[1]) <= float(target["radius"])
                motion = run["progress"] - previous_progress
                if inside_window and inside and run["speed"] >= float(physics["min_speed"]) and motion >= float(requirements["minimum_motion_during_dwell"]):
                    dwell[target_id] += 1
                    if dwell[target_id] >= int(target["required_ticks"]):
                        checks.add(target_id)
                else:
                    dwell[target_id] = 0
            if reason:
                pending_crash = reason
                run["crashed"] = True
            elif run["progress"] >= float(physics["finish_progress"]):
                if checks == set(targets):
                    run["finished"] = True
                else:
                    pending_crash = "inspection_incomplete"
                    run["crashed"] = True
            continue
        if kind == "check_complete":
            target_id = str(event.get("target_id") or "")
            if target_id not in checks or target_id in emitted_checks or event.get("tick") != run["tick"]:
                return {"graded": True, "passed": False, "feedback": "fabricated hover dwell total"}
            emitted_checks.add(target_id)
            continue
        if kind == "crash":
            if not pending_crash or event.get("reason") != pending_crash or event.get("tick") != run["tick"]:
                return {"graded": True, "passed": False, "feedback": "client crash flag disagrees with symmetric collision replay"}
            pending_crash = None
            crashes += 1
            continue
        if kind == "retry":
            if not run["crashed"] or pending_crash or event.get("from_tick") != run["tick"]:
                return {"graded": True, "passed": False, "feedback": "invalid humane retry"}
            run = _fresh(physics)
            pointer = None
            dwell = {target_id: 0 for target_id in targets}
            checks.clear()
            emitted_checks.clear()
            retries += 1
            continue
        if kind == "finish":
            if not run["finished"] or set(event.get("checks") or []) != set(targets) or checks != set(targets) or emitted_checks != set(targets) or event.get("tick") != run["tick"]:
                return {"graded": True, "passed": False, "feedback": "finish lacks all independently replayed divided-attention checks"}
            finished = terminal = True
            continue
        return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}

    summary = {"completed_checks": sorted(checks), "crashes": crashes, "retries": retries,
               "pointer_samples": pointer_samples, "final_tick": run["tick"], "final_progress": round(run["progress"], 3), "finished": finished}
    for field, value in summary.items():
        if payload.get(field) != value:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} disagrees with divided-attention replay"}
    passed = finished and terminal and checks == set(targets) and not pending_crash
    return {"graded": True, "passed": passed, "score": 100 if passed else 0,
            "feedback": f"hovercar replay: checks {len(checks)}/{len(targets)}; tick {run['tick']}/{physics['deadline_tick']}; crashes {crashes}; pointer samples {pointer_samples}"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"targets": ground_truth.get("targets") or [], "physics": ground_truth.get("physics") or {}}
