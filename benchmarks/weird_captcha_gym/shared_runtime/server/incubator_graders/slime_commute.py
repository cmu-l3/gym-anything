from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "slime_commute"


def _mod(value: float, period: float) -> float:
    return ((value % period) + period) % period


def _distance(first: float, second: float, period: float) -> float:
    raw = abs(first - second)
    return min(raw, period - raw)


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    board = dict(ground_truth.get("board") or {})
    try:
        columns = int(board["columns"])
        max_ticks = int(board["max_ticks"])
        radius = float(board["player_radius"])
        max_deaths = int(board["max_deaths"])
        cooldown_ticks = int(board["hop_cooldown_ticks"])
        start_x, goal_x = float(board["start_x"]), float(board["goal_x"])
        lanes = [dict(lane) for lane in board["lanes"]]
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid crossing contract: {exc}"}
    lane_by_row = {int(lane["row"]): lane for lane in lanes}
    actions = payload.get("actions")
    if not isinstance(actions, list) or len(actions) > 900:
        return {"graded": True, "passed": False, "feedback": "crossing action transcript is invalid"}
    try:
        final_tick = int(payload.get("final_tick"))
    except (TypeError, ValueError):
        return {"graded": True, "passed": False, "feedback": "final world tick is invalid"}
    if not 0 <= final_tick <= max_ticks:
        return {"graded": True, "passed": False, "feedback": "final world tick is outside limits"}
    player = {"x": start_x, "y": 10}
    tick, deaths, cooldown = 0, 0, 0
    reached = False

    def center(lane: dict[str, Any], offset: float, at_tick: int) -> float:
        return _mod(float(offset) + float(lane["phase"]) + at_tick * float(lane["speed"]), columns)

    def support(x: float, row: int, at_tick: int) -> bool:
        lane = lane_by_row.get(row)
        return bool(lane and lane["kind"] == "water" and any(
            _distance(x + 0.5, center(lane, float(offset), at_tick), columns) <= float(lane["length"]) / 2 - radius * 0.25
            for offset in lane["offsets"]
        ))

    def hazard(x: float, row: int, at_tick: int) -> bool:
        lane = lane_by_row.get(row)
        return bool(lane and lane["kind"] != "water" and any(
            _distance(x + 0.5, center(lane, float(offset), at_tick), columns) <= float(lane["length"]) / 2 + radius
            for offset in lane["offsets"]
        ))

    def die() -> None:
        nonlocal deaths, cooldown, player
        deaths += 1
        player = {"x": start_x, "y": 10}
        cooldown = 2

    def check() -> None:
        lane = lane_by_row.get(int(player["y"]))
        if not lane:
            return
        if lane["kind"] == "water":
            if not support(float(player["x"]), int(player["y"]), tick):
                die()
        elif hazard(float(player["x"]), int(player["y"]), tick):
            die()

    def world_step() -> None:
        nonlocal tick, cooldown
        lane = lane_by_row.get(int(player["y"]))
        if lane and lane["kind"] == "water":
            player["x"] += float(lane["speed"])
            if player["x"] + 0.5 < -radius or player["x"] + 0.5 > columns + radius:
                die()
                tick += 1
                return
        tick += 1
        cooldown = max(0, cooldown - 1)
        check()

    key_map = {"w": (0, -1), "arrowup": (0, -1), "s": (0, 1), "arrowdown": (0, 1), "a": (-1, 0), "arrowleft": (-1, 0), "d": (1, 0), "arrowright": (1, 0)}
    for sequence, action in enumerate(actions, start=1):
        if not isinstance(action, dict) or action.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"action {sequence} sequence mismatch"}
        try:
            action_tick = int(action.get("tick"))
        except (TypeError, ValueError):
            return {"graded": True, "passed": False, "feedback": "action tick is invalid"}
        if action_tick < tick or action_tick > final_tick:
            return {"graded": True, "passed": False, "feedback": "action ticks are not monotonic"}
        while tick < action_tick:
            world_step()
            if deaths >= max_deaths:
                break
        key = str(action.get("key") or "").lower()
        if key not in key_map or cooldown > 0 or deaths >= max_deaths or reached:
            return {"graded": True, "passed": False, "feedback": "action could not occur in replayed world state"}
        dx, dy = key_map[key]
        next_x, next_y = player["x"] + dx, player["y"] + dy
        if 0 <= next_x <= columns - 1 and 0 <= next_y <= 10:
            player = {"x": next_x, "y": next_y}
            cooldown = cooldown_ticks
            check()
            reached = player["y"] == 0 and abs(player["x"] - goal_x) < 0.42
    while tick < final_tick and deaths < max_deaths and not reached:
        world_step()
    completed = payload.get("completed") is True
    passed = completed and reached and deaths < max_deaths and tick == final_tick
    return {"graded": True, "passed": passed, "feedback": f"fixed-step replay: tick {tick}; wipeouts {deaths}/{max_deaths}; home={reached}"}
