from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "fake_desktop_automation_inversion"


def _point(value: Any, width: int, height: int) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError("pointer coordinate is malformed")
    if isinstance(value[0], bool) or isinstance(value[1], bool):
        raise ValueError("boolean pointer coordinate is invalid")
    x, y = int(value[0]), int(value[1])
    if not (0 <= x <= width and 0 <= y <= height):
        raise ValueError("pointer coordinate leaves desktop")
    return x, y


def _mapped(point: tuple[int, int], mapping: str, width: int, height: int) -> tuple[int, int]:
    x, y = point
    if mapping == "mirror_x":
        return width - x, y
    if mapping == "mirror_y":
        return x, height - y
    if mapping == "rotate_180":
        return width - x, height - y
    if mapping != "normal":
        raise ValueError("unknown pointer mapping")
    return x, y


def _inside(point: tuple[int, int], rect: tuple[int, int, int, int]) -> bool:
    x, y = point
    left, top, width, height = rect
    return left <= x <= left + width and top <= y <= top + height


def _initial_windows(ground_truth: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = ground_truth.get("initial_windows")
    if not isinstance(raw, list) or len(raw) != 4:
        raise ValueError("desktop must define four windows")
    windows: dict[str, dict[str, Any]] = {}
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError("window is malformed")
        window_id = str(item.get("id") or "")
        if not window_id or window_id in windows:
            raise ValueError("window identity is invalid")
        windows[window_id] = {
            "id": window_id,
            "title": str(item.get("title") or ""),
            "x": int(item.get("x")),
            "y": int(item.get("y")),
            "width": int(item.get("width")),
            "height": int(item.get("height")),
            "z": int(item.get("z")),
            "closed": bool(item.get("closed")),
            "closable": bool(item.get("closable")),
        }
    return windows


def _top_window(windows: dict[str, dict[str, Any]], point: tuple[int, int]) -> dict[str, Any] | None:
    candidates = [
        window for window in windows.values()
        if not window["closed"] and _inside(point, (window["x"], window["y"], window["width"], window["height"]))
    ]
    return max(candidates, key=lambda item: item["z"], default=None)


def _file_rect(window: dict[str, Any], slot: int, geometry: dict[str, Any]) -> tuple[int, int, int, int]:
    origin_x, origin_y = [int(value) for value in geometry["file_origin"]]
    file_width, file_height = [int(value) for value in geometry["file_size"]]
    gap = int(geometry["file_gap"])
    return window["x"] + origin_x + slot * (file_width + gap), window["y"] + origin_y, file_width, file_height


def _relative_rect(window: dict[str, Any], values: Any) -> tuple[int, int, int, int]:
    if not isinstance(values, list) or len(values) != 4:
        raise ValueError("relative rectangle is malformed")
    x, y, width, height = [int(value) for value in values]
    return window["x"] + x, window["y"] + y, width, height


def _down_hit(
    windows: dict[str, dict[str, Any]],
    files: list[dict[str, Any]],
    point: tuple[int, int],
    geometry: dict[str, Any],
) -> tuple[str, dict[str, Any] | None]:
    window = _top_window(windows, point)
    if window is None:
        return "desktop", None
    title_height = int(geometry["title_height"])
    close_width = int(geometry["close_width"])
    close_rect = (window["x"] + window["width"] - close_width, window["y"], close_width, title_height)
    if window["closable"] and _inside(point, close_rect):
        return f"close:{window['id']}", window
    if window["id"] == "vault":
        for file_item in files:
            if _inside(point, _file_rect(window, int(file_item["slot"]), geometry)):
                return f"file:{file_item['id']}", window
    if window["id"] == "verifier" and _inside(point, _relative_rect(window, geometry["arm_control"])):
        return "arm", window
    if point[1] <= window["y"] + title_height:
        return f"title:{window['id']}", window
    return f"window:{window['id']}", window


def _window_snapshot(windows: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "id": window["id"],
            "x": window["x"],
            "y": window["y"],
            "z": window["z"],
            "closed": window["closed"],
        }
        for window in sorted(windows.values(), key=lambda item: item["id"])
    ]


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
        desktop = ground_truth.get("desktop") or {}
        width, height = int(desktop["width"]), int(desktop["height"])
        mappings = [str(item) for item in ground_truth.get("mapping_sequence") or []]
        if len(mappings) != 2 or len(set(mappings)) != 2:
            raise ValueError("mapping sequence is invalid")
        geometry = ground_truth.get("geometry") or {}
        initial = _initial_windows(ground_truth)
        files = [dict(item) for item in ground_truth.get("files") or []]
        if len(files) != 3:
            raise ValueError("key vault is malformed")
    except (KeyError, TypeError, ValueError) as exc:
        return {"graded": True, "passed": False, "feedback": f"invalid desktop contract: {exc}"}

    events = payload.get("events")
    if not isinstance(events, list) or not (1 <= len(events) <= 700):
        return {"graded": True, "passed": False, "feedback": "pointer transcript is missing or outside limits"}

    windows = {key: dict(value) for key, value in initial.items()}
    z_counter = max(window["z"] for window in windows.values())
    boundary = 0
    boundary_pending = False
    active: dict[str, Any] | None = None
    loaded_file: str | None = None
    armed = False
    move_count = 0
    close_count = 0
    z_order_changes = 0
    file_drag_moves = 0
    resets = 0
    phases_seen: set[int] = set()

    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind = str(event.get("kind") or "")
        if boundary_pending and kind != "boundary":
            return {"graded": True, "passed": False, "feedback": "missing visible workflow-boundary remap"}

        if kind == "reset":
            windows = {key: dict(value) for key, value in initial.items()}
            z_counter = max(window["z"] for window in windows.values())
            boundary = 0
            boundary_pending = False
            active = None
            loaded_file = None
            armed = False
            move_count = close_count = z_order_changes = file_drag_moves = 0
            phases_seen.clear()
            resets += 1
            continue

        if kind == "boundary":
            expected = {
                "from": 0,
                "to": 1,
                "reason": "keyfile_loaded",
                "mapping": mappings[1],
            }
            if not boundary_pending or any(event.get(field) != value for field, value in expected.items()):
                return {"graded": True, "passed": False, "feedback": "workflow-boundary event is inconsistent"}
            boundary = 1
            boundary_pending = False
            continue

        if kind not in {"pointer_down", "pointer_move", "pointer_up"}:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} has unknown kind"}
        try:
            physical = _point(event.get("physical"), width, height)
            remote = _point(event.get("remote"), width, height)
            expected_remote = _mapped(physical, mappings[boundary], width, height)
        except (TypeError, ValueError) as exc:
            return {"graded": True, "passed": False, "feedback": f"event {sequence}: {exc}"}
        if remote != expected_remote:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} remote cursor does not match physical mapping"}
        if event.get("boundary") != boundary or str(event.get("mapping") or "") != mappings[boundary]:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} mapping phase mismatch"}

        if kind == "pointer_down":
            phases_seen.add(boundary)
            hit, window = _down_hit(windows, files, remote, geometry)
            if event.get("hit") != hit:
                return {"graded": True, "passed": False, "feedback": f"event {sequence} claimed the wrong remote target"}
            if hit.startswith("close:") and window is not None:
                window["closed"] = True
                close_count += 1
                active = None
                continue
            if window is not None:
                current_top = max((item["z"] for item in windows.values() if not item["closed"]), default=window["z"])
                if window["z"] != current_top:
                    z_order_changes += 1
                z_counter += 1
                window["z"] = z_counter
            if hit.startswith("title:") and window is not None:
                active = {
                    "type": "window",
                    "id": window["id"],
                    "offset": [remote[0] - window["x"], remote[1] - window["y"]],
                    "start": [window["x"], window["y"]],
                }
            elif hit.startswith("file:"):
                active = {"type": "file", "id": hit.split(":", 1)[1], "moves": 0}
            elif hit == "arm":
                if boundary == 1 and loaded_file == str(ground_truth.get("target_file_id") or ""):
                    armed = True
                active = None
            else:
                active = None
            continue

        if kind == "pointer_move":
            if active and active["type"] == "window":
                window = windows[active["id"]]
                next_x = max(0, min(width - window["width"], remote[0] - active["offset"][0]))
                next_y = max(0, min(height - window["height"], remote[1] - active["offset"][1]))
                window["x"], window["y"] = next_x, next_y
            elif active and active["type"] == "file":
                active["moves"] += 1
                file_drag_moves += 1
            continue

        if active and active["type"] == "window":
            window = windows[active["id"]]
            distance = math.hypot(window["x"] - active["start"][0], window["y"] - active["start"][1])
            if distance >= int(ground_truth.get("minimum_window_move") or 44):
                move_count += 1
        elif active and active["type"] == "file":
            verifier = windows.get("verifier")
            if verifier and not verifier["closed"] and _inside(remote, _relative_rect(verifier, geometry["drop_zone"])):
                loaded_file = str(active["id"])
                if loaded_file == str(ground_truth.get("target_file_id") or ""):
                    boundary_pending = True
        active = None

    if boundary_pending:
        return {"graded": True, "passed": False, "feedback": "keyfile loaded without completing the visible remap"}
    expected_snapshot = _window_snapshot(windows)
    if payload.get("window_state") != expected_snapshot:
        return {"graded": True, "passed": False, "feedback": "submitted window state does not match pointer replay"}
    expected_scalars = {
        "boundary_index": boundary,
        "active_mapping": mappings[boundary],
        "loaded_file_id": loaded_file,
        "armed": armed,
        "move_count": move_count,
        "closed_count": close_count,
        "z_order_changes": z_order_changes,
        "file_drag_moves": file_drag_moves,
        "reset_count": resets,
    }
    for field, expected in expected_scalars.items():
        if payload.get(field) != expected:
            return {"graded": True, "passed": False, "feedback": f"submitted {field} does not match replay"}

    target_file_id = str(ground_truth.get("target_file_id") or "")
    blocker_id = str(ground_truth.get("required_blocker_id") or "")
    blocker_closed = bool(windows.get(blocker_id, {}).get("closed"))
    passed = (
        loaded_file == target_file_id
        and armed
        and boundary == 1
        and blocker_closed
        and move_count >= 1
        and z_order_changes >= 1
        and file_drag_moves >= 3
        and phases_seen == {0, 1}
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"desktop replay: keyfile={'loaded' if loaded_file == target_file_id else 'missing'}; "
            f"mapped phases {len(phases_seen)}/2; windows moved {move_count}; closed {close_count}; "
            f"z-order changes {z_order_changes}; manual arm={'on' if armed else 'off'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "target_filename": ground_truth.get("target_filename"),
        "target_file_id": ground_truth.get("target_file_id"),
        "mapping_sequence": ground_truth.get("mapping_sequence"),
        "required_blocker_id": ground_truth.get("required_blocker_id"),
    }
