from __future__ import annotations

from copy import deepcopy
from typing import Any


MECHANIC_ID = "exit_vim_terminal_escape"


def _layer_name(state: dict[str, Any]) -> str:
    index = int(state["layer_index"])
    if index < 0:
        return "editor"
    layers = state["layer_order"]
    if index >= len(layers):
        return "complete"
    return str(layers[index])


def _mode_name(state: dict[str, Any]) -> str:
    return str(state["mode"]) if int(state["layer_index"]) < 0 else _layer_name(state)


def _clamp_cursor(state: dict[str, Any]) -> None:
    row = max(0, min(int(state["row"]), len(state["buffer"]) - 1))
    state["row"] = row
    state["col"] = max(0, min(int(state["col"]), len(state["buffer"][row])))


def _push_undo(state: dict[str, Any]) -> None:
    state["undo"].append({"buffer": list(state["buffer"]), "row": state["row"], "col": state["col"]})
    state["undo"] = state["undo"][-30:]


def _advance_layer(state: dict[str, Any]) -> None:
    current = _layer_name(state)
    if current in {"editor", "complete"}:
        return
    state["exit_log"].append(current)
    state["layer_index"] += 1
    state["ssh_input"] = ""


def _apply_editor_key(state: dict[str, Any], key: str, ctrl: bool, alt: bool, meta: bool) -> None:
    mode = state["mode"]
    if mode == "insert":
        if key == "Escape":
            state["mode"] = "normal"
            state["pending"] = ""
        elif key == "Backspace":
            if state["col"] > 0:
                _push_undo(state)
                row = state["row"]
                col = state["col"]
                line = state["buffer"][row]
                state["buffer"][row] = line[: col - 1] + line[col:]
                state["col"] -= 1
        elif key == "Delete":
            row = state["row"]
            col = state["col"]
            line = state["buffer"][row]
            if col < len(line):
                _push_undo(state)
                state["buffer"][row] = line[:col] + line[col + 1 :]
        elif len(key) == 1 and not ctrl and not alt and not meta:
            _push_undo(state)
            row = state["row"]
            col = state["col"]
            line = state["buffer"][row]
            state["buffer"][row] = line[:col] + key + line[col:]
            state["col"] += 1
            state["inserted_chars"] += 1
        _clamp_cursor(state)
        return

    if mode == "command":
        if key == "Escape":
            state["mode"] = "normal"
            state["command"] = ""
        elif key == "Backspace":
            state["command"] = state["command"][:-1]
        elif key == "Enter":
            command = state["command"]
            state["command_history"].append(command)
            state["command"] = ""
            state["mode"] = "normal"
            if command == "wq" and state["buffer"] == state["target_buffer"]:
                state["saved"] = True
                state["layer_index"] = 0
            else:
                state["command_errors"] += 1
        elif len(key) == 1 and not ctrl and not alt and not meta:
            state["command"] += key
        return

    if key == "Escape":
        state["pending"] = ""
        return
    if ctrl or alt or meta:
        state["pending"] = ""
        return
    if key == ":":
        state["mode"] = "command"
        state["command"] = ""
        state["pending"] = ""
        return
    if key == "g":
        if state["pending"] == "g":
            state["row"] = 0
            state["col"] = 0
            state["pending"] = ""
        else:
            state["pending"] = "g"
        return
    if key == "c":
        if state["pending"] == "c":
            _push_undo(state)
            state["buffer"][state["row"]] = ""
            state["col"] = 0
            state["mode"] = "insert"
            state["pending"] = ""
            state["clear_count"] += 1
        else:
            state["pending"] = "c"
        return
    state["pending"] = ""
    if key in {"j", "ArrowDown"}:
        state["row"] += 1
    elif key in {"k", "ArrowUp"}:
        state["row"] -= 1
    elif key in {"h", "ArrowLeft"}:
        state["col"] -= 1
    elif key in {"l", "ArrowRight"}:
        state["col"] += 1
    elif key in {"0", "Home"}:
        state["col"] = 0
    elif key in {"$", "End"}:
        state["col"] = len(state["buffer"][state["row"]])
    elif key == "i":
        state["mode"] = "insert"
    elif key == "a":
        state["col"] = min(len(state["buffer"][state["row"]]), state["col"] + 1)
        state["mode"] = "insert"
    elif key == "x":
        row = state["row"]
        col = state["col"]
        line = state["buffer"][row]
        if col < len(line):
            _push_undo(state)
            state["buffer"][row] = line[:col] + line[col + 1 :]
    elif key == "u" and state["undo"]:
        snapshot = state["undo"].pop()
        state["buffer"] = list(snapshot["buffer"])
        state["row"] = snapshot["row"]
        state["col"] = snapshot["col"]
    _clamp_cursor(state)


def _apply_event(state: dict[str, Any], event: dict[str, Any]) -> None:
    key = str(event.get("key") or "")
    ctrl = event.get("ctrl") is True
    alt = event.get("alt") is True
    meta = event.get("meta") is True
    current = _layer_name(state)
    if current == "editor":
        _apply_editor_key(state, key, ctrl, alt, meta)
    elif current == "pager":
        if key.lower() == "q" and not ctrl and not alt and not meta:
            _advance_layer(state)
    elif current == "job":
        if key.lower() == "c" and ctrl and not alt and not meta:
            _advance_layer(state)
    elif current == "ssh":
        if key == "Backspace":
            state["ssh_input"] = state["ssh_input"][:-1]
        elif key == "Enter":
            if state["ssh_input"].strip() == "exit":
                _advance_layer(state)
            else:
                state["command_errors"] += 1
                state["ssh_input"] = ""
        elif len(key) == 1 and not ctrl and not alt and not meta:
            state["ssh_input"] += key


def _initial_state(ground_truth: dict[str, Any]) -> dict[str, Any]:
    initial = ground_truth.get("initial_buffer")
    target = ground_truth.get("target_buffer")
    layers = ground_truth.get("layer_order")
    if not isinstance(initial, list) or not isinstance(target, list) or not isinstance(layers, list):
        raise ValueError("terminal contract is malformed")
    if len(initial) != len(target) or len(initial) < 2:
        raise ValueError("terminal buffer shape is invalid")
    if not all(isinstance(item, str) for item in [*initial, *target, *layers]):
        raise ValueError("terminal contract contains non-text values")
    return {
        "buffer": list(initial),
        "target_buffer": list(target),
        "layer_order": list(layers),
        "layer_index": -1,
        "mode": "normal",
        "row": 0,
        "col": 0,
        "pending": "",
        "command": "",
        "undo": [],
        "saved": False,
        "exit_log": [],
        "ssh_input": "",
        "clear_count": 0,
        "inserted_chars": 0,
        "command_errors": 0,
        "command_history": [],
    }


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
        state = _initial_state(ground_truth)
    except ValueError as exc:
        return {"graded": True, "passed": False, "feedback": str(exc)}

    events = payload.get("events")
    if not isinstance(events, list) or len(events) > 1200:
        return {"graded": True, "passed": False, "feedback": "keystroke transcript is missing or too long"}
    allowed_fields = {"sequence", "key", "ctrl", "shift", "alt", "meta", "layer_before", "mode_before", "layer_after", "mode_after"}
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"key event {sequence} has invalid sequence"}
        if set(event) != allowed_fields:
            return {"graded": True, "passed": False, "feedback": f"key event {sequence} has an invalid schema"}
        key = event.get("key")
        if not isinstance(key, str) or not key or len(key) > 24:
            return {"graded": True, "passed": False, "feedback": f"key event {sequence} has invalid key data"}
        if any(not isinstance(event.get(flag), bool) for flag in ("ctrl", "shift", "alt", "meta")):
            return {"graded": True, "passed": False, "feedback": f"key event {sequence} has invalid modifiers"}
        before_layer = _layer_name(state)
        before_mode = _mode_name(state)
        if event.get("layer_before") != before_layer or event.get("mode_before") != before_mode:
            return {"graded": True, "passed": False, "feedback": f"key event {sequence} disagrees before replay"}
        _apply_event(state, event)
        if event.get("layer_after") != _layer_name(state) or event.get("mode_after") != _mode_name(state):
            return {"graded": True, "passed": False, "feedback": f"key event {sequence} disagrees after replay"}

    final_state = {
        "buffer": list(state["buffer"]),
        "saved": state["saved"],
        "layer_index": state["layer_index"],
        "exit_log": list(state["exit_log"]),
        "mode": _mode_name(state),
    }
    submitted_final = payload.get("final_state")
    if submitted_final != final_state:
        return {"graded": True, "passed": False, "feedback": "claimed terminal state does not match key replay"}
    layers = state["layer_order"]
    passed = (
        state["saved"] is True
        and state["buffer"] == state["target_buffer"]
        and state["layer_index"] == len(layers)
        and state["exit_log"] == layers
        and state["clear_count"] >= len(state["target_buffer"])
        and state["inserted_chars"] >= sum(len(line) for line in state["target_buffer"])
        and "wq" in state["command_history"]
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"fields rewritten {state['clear_count']}/{len(state['target_buffer'])}; "
            f"buffer {'saved' if state['saved'] else 'unsaved'}; "
            f"layers escaped {len(state['exit_log'])}/{len(layers)}; key events {len(events)}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "target_buffer": deepcopy(ground_truth.get("target_buffer") or []),
        "layer_order": list(ground_truth.get("layer_order") or []),
        "instructions": ["gg", "cc", "type each target line", "Escape", ":wq", "escape each visible outer layer"],
        "answers": [],
    }
