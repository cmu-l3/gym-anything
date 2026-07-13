from __future__ import annotations

from typing import Any


MECHANIC_ID = "minecraft_block_grid"
GRID = 5
CANVAS_WIDTH = 900
TILE_W = 78
TILE_H = 38
CUBE_H = 38


def _rotate(x: int, y: int, orientation: int) -> tuple[int, int]:
    orientation %= 4
    if orientation == 0:
        return x, y
    if orientation == 1:
        return GRID - 1 - y, x
    if orientation == 2:
        return GRID - 1 - x, GRID - 1 - y
    return y, GRID - 1 - x


def _inverse(rx: int, ry: int, orientation: int) -> tuple[int, int]:
    orientation %= 4
    if orientation == 0:
        return rx, ry
    if orientation == 1:
        return ry, GRID - 1 - rx
    if orientation == 2:
        return GRID - 1 - rx, GRID - 1 - ry
    return GRID - 1 - ry, rx


def _neighbor(x: int, y: int, orientation: int, axis: str) -> tuple[int, int]:
    rx, ry = _rotate(x, y, orientation)
    if axis == "x":
        rx += 1
    else:
        ry += 1
    return _inverse(rx, ry, orientation)


def _project(x: int, y: int, z: int, orientation: int) -> tuple[float, float]:
    rx, ry = _rotate(x, y, orientation)
    return CANVAS_WIDTH / 2 + (rx - ry) * TILE_W / 2, 55 + (rx + ry) * TILE_H / 2 + (2 - z) * CUBE_H


def _faces(voxels: dict[str, dict[str, Any]], orientation: int) -> list[dict[str, Any]]:
    occupied = {(int(v["x"]), int(v["y"]), int(v["z"])) for v in voxels.values()}
    ordered = sorted(voxels.values(), key=lambda voxel: (
        sum(_rotate(int(voxel["x"]), int(voxel["y"]), orientation)),
        int(voxel["z"]),
        _rotate(int(voxel["x"]), int(voxel["y"]), orientation)[0],
    ))
    result: list[dict[str, Any]] = []
    for voxel in ordered:
        x, y, z = int(voxel["x"]), int(voxel["y"]), int(voxel["z"])
        sx, sy = _project(x, y, z, orientation)
        nx, ny = _neighbor(x, y, orientation, "x"), _neighbor(x, y, orientation, "y")
        if (nx[0], nx[1], z) not in occupied:
            result.append({"voxel_id": voxel["id"], "face": "right", "points": [(sx, sy), (sx + TILE_W / 2, sy + TILE_H / 2), (sx + TILE_W / 2, sy + TILE_H / 2 + CUBE_H), (sx, sy + CUBE_H)]})
        if (ny[0], ny[1], z) not in occupied:
            result.append({"voxel_id": voxel["id"], "face": "left", "points": [(sx, sy), (sx - TILE_W / 2, sy + TILE_H / 2), (sx - TILE_W / 2, sy + TILE_H / 2 + CUBE_H), (sx, sy + CUBE_H)]})
        if (x, y, z + 1) not in occupied:
            result.append({"voxel_id": voxel["id"], "face": "top", "points": [(sx, sy), (sx + TILE_W / 2, sy + TILE_H / 2), (sx, sy + TILE_H), (sx - TILE_W / 2, sy + TILE_H / 2)]})
    return result


def _inside(x: float, y: float, points: list[tuple[float, float]]) -> bool:
    inside = False
    previous = len(points) - 1
    for index, (xi, yi) in enumerate(points):
        xj, yj = points[previous]
        if ((yi > y) != (yj > y)) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi:
            inside = not inside
        previous = index
    return inside


def _raycast(voxels: dict[str, dict[str, Any]], orientation: int, x: float, y: float) -> dict[str, Any] | None:
    for face in reversed(_faces(voxels, orientation)):
        if _inside(x, y, face["points"]):
            return {"voxel_id": str(face["voxel_id"]), "face": str(face["face"])}
    return None


def _state_snapshot(orientation: int, durability: int, inventory: list[str], collapsed: bool, voxels: dict[str, dict[str, Any]]) -> dict[str, Any]:
    return {
        "orientation": orientation,
        "durability": durability,
        "inventory": sorted(inventory),
        "collapsed": collapsed,
        "remaining_voxel_ids": sorted(voxels),
    }


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "public-state challenge mismatch"}
    initial = ground_truth.get("voxels")
    if not isinstance(initial, list):
        return {"graded": True, "passed": False, "feedback": "private voxel pile is missing"}
    voxels = {str(voxel.get("id") or ""): dict(voxel) for voxel in initial if isinstance(voxel, dict)}
    if not voxels or "" in voxels:
        return {"graded": True, "passed": False, "feedback": "private voxel pile is malformed"}
    orientation = int(ground_truth.get("starting_orientation") or 0)
    durability = int(ground_truth.get("starting_durability") or 0)
    inventory: list[str] = []
    collapsed = False
    rotations = 0
    visited = {orientation}
    resets = 0
    events = payload.get("events")
    if not isinstance(events, list) or len(events) > 240:
        return {"graded": True, "passed": False, "feedback": "mine transcript is missing or too long"}
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"mine event {sequence} has invalid sequence"}
        action = str(event.get("action") or "")
        if action == "rotate":
            delta = event.get("delta")
            if delta not in {-1, 1} or event.get("orientation_before") != orientation:
                return {"graded": True, "passed": False, "feedback": f"rotation {sequence} is malformed"}
            orientation = (orientation + int(delta)) % 4
            if event.get("orientation_after") != orientation:
                return {"graded": True, "passed": False, "feedback": f"rotation {sequence} disagrees with replay"}
            rotations += 1
            visited.add(orientation)
        elif action == "reset":
            orientation = int(ground_truth.get("starting_orientation") or 0)
            durability = int(ground_truth.get("starting_durability") or 0)
            inventory = []
            collapsed = False
            voxels = {str(voxel["id"]): dict(voxel) for voxel in initial}
            rotations = 0
            visited = {orientation}
            resets += 1
        elif action == "mine":
            try:
                click_x, click_y = float(event["x"]), float(event["y"])
            except (KeyError, TypeError, ValueError):
                return {"graded": True, "passed": False, "feedback": f"mine event {sequence} has invalid coordinates"}
            if event.get("orientation") != orientation:
                return {"graded": True, "passed": False, "feedback": f"mine event {sequence} has stale camera state"}
            hit = _raycast(voxels, orientation, click_x, click_y)
            expected_id = hit["voxel_id"] if hit else None
            expected_face = hit["face"] if hit else None
            if event.get("voxel_id") != expected_id or event.get("face") != expected_face:
                return {"graded": True, "passed": False, "feedback": f"mine event {sequence} violates click-ray occlusion"}
            outcome = "miss"
            if hit and durability <= 0:
                outcome = "tool_broken"
            elif hit:
                voxel = voxels[expected_id]
                material = str(voxel.get("material") or "")
                durability -= 1
                if material == "diamond":
                    inventory.append(expected_id)
                    del voxels[expected_id]
                    outcome = "diamond_extracted"
                elif material == "stone":
                    del voxels[expected_id]
                    outcome = "stone_removed"
                elif material == "lava":
                    outcome = "lava_strike"
                elif material == "support":
                    collapsed = True
                    outcome = "support_collapse"
                else:
                    return {"graded": True, "passed": False, "feedback": f"mine event {sequence} hit unknown material"}
            if event.get("outcome") != outcome or event.get("durability_after") != durability or sorted(event.get("inventory_after") or []) != sorted(inventory):
                return {"graded": True, "passed": False, "feedback": f"mine event {sequence} disagrees with material replay"}
        else:
            return {"graded": True, "passed": False, "feedback": f"mine event {sequence} has invalid action"}
    final_state = _state_snapshot(orientation, durability, inventory, collapsed, voxels)
    if payload.get("final_state") != final_state:
        return {"graded": True, "passed": False, "feedback": "claimed mine state does not match transcript replay"}
    diamond_ids = sorted(str(item) for item in ground_truth.get("diamond_ids") or [])
    passed = (
        sorted(inventory) == diamond_ids
        and all(diamond_id not in voxels for diamond_id in diamond_ids)
        and not collapsed
        and durability >= 0
        and rotations >= 2
        and len(visited) >= 3
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": f"diamonds {len(inventory)}/{len(diamond_ids)}; durability {durability}; rotations {rotations}; viewpoints {len(visited)}; resets {resets}; support {'failed' if collapsed else 'stable'}",
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"solution_steps": ground_truth.get("solution_steps") or [], "edge_case_hit": ground_truth.get("edge_case_hit"), "diamond_ids": ground_truth.get("diamond_ids") or [], "answers": []}
