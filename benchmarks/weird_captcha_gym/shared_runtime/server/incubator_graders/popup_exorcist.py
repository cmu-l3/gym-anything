from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "popup_exorcist"


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id or str(public_state.get("challenge_id") or "") != challenge_id:
        return {"graded": True, "passed": False, "feedback": "stale challenge"}
    events = payload.get("events")
    if not isinstance(events, list) or not 5 <= len(events) <= 180:
        return {"graded": True, "passed": False, "feedback": "containment transcript is missing or outside limits"}
    originals = set(str(item) for item in ground_truth.get("popup_ids") or [])
    parasite = str(ground_truth.get("parasite_id") or "")
    echoes = set(str(item) for item in ground_truth.get("echo_ids") or [])
    popup_by_id = {str(item.get("id")): dict(item) for item in public_state.get("popups") or []}
    live, infected = set(originals), set()
    provoked = False
    spawn_pending = False
    contained = ""
    last_drag: dict[str, list[list[int]]] = {}
    purged = False
    for sequence, event in enumerate(events, start=1):
        if not isinstance(event, dict) or event.get("sequence") != sequence:
            return {"graded": True, "passed": False, "feedback": f"event {sequence} sequence mismatch"}
        kind, window_id = str(event.get("kind") or ""), str(event.get("window_id") or "")
        if spawn_pending and kind != "spawn":
            return {"graded": True, "passed": False, "feedback": "parasite echoes were not recorded immediately"}
        if kind == "focus":
            if window_id not in live:
                return {"graded": True, "passed": False, "feedback": "focused window was not live"}
            continue
        if kind == "close":
            if window_id not in live:
                return {"graded": True, "passed": False, "feedback": "closed window was not live"}
            if window_id == parasite and not provoked:
                provoked = True
                infected.add(parasite)
                spawn_pending = True
            elif window_id not in infected:
                live.remove(window_id)
            continue
        if kind == "spawn":
            listed = set(str(item) for item in event.get("echo_ids") or [])
            if not spawn_pending or str(event.get("parent_id") or "") != parasite or listed != echoes:
                return {"graded": True, "passed": False, "feedback": "parasite echo set was forged"}
            live.update(echoes)
            infected.update(echoes)
            spawn_pending = False
            continue
        if kind == "drag":
            if window_id not in live:
                return {"graded": True, "passed": False, "feedback": "dragged window was not live"}
            samples = event.get("samples")
            if not isinstance(samples, list) or not samples or len(samples) > 80:
                return {"graded": True, "passed": False, "feedback": "window drag samples are missing"}
            clean = []
            for point in samples:
                if not isinstance(point, list) or len(point) != 2 or not all(isinstance(value, int) for value in point):
                    return {"graded": True, "passed": False, "feedback": "window drag sample is malformed"}
                if clean and math.hypot(point[0] - clean[-1][0], point[1] - clean[-1][1]) > 120:
                    return {"graded": True, "passed": False, "feedback": "window teleported during containment"}
                clean.append(point)
            last_drag[window_id] = clean
            continue
        if kind == "contain":
            if not provoked or window_id not in infected or window_id not in live or window_id not in last_drag:
                return {"graded": True, "passed": False, "feedback": "containment occurred before an infected window was physically discovered"}
            source = popup_by_id.get(parasite, {}) if window_id in echoes else popup_by_id.get(window_id, {})
            end = last_drag[window_id][-1]
            cx, cy = end[0] + float(source.get("w") or 0) / 2, end[1] + float(source.get("h") or 0) / 2
            well = ground_truth.get("containment") or {}
            if not (float(well.get("x")) <= cx <= float(well.get("x")) + float(well.get("w")) and float(well.get("y")) <= cy <= float(well.get("y")) + float(well.get("h"))):
                return {"graded": True, "passed": False, "feedback": "infected window did not enter the visible containment well"}
            contained = window_id
            continue
        if kind == "purge":
            if purged or not contained or str(event.get("contained_id") or "") != contained:
                return {"graded": True, "passed": False, "feedback": "purge was not triggered by the contained parasite"}
            remaining = set(str(item) for item in event.get("remaining_before") or [])
            if remaining != live:
                return {"graded": True, "passed": False, "feedback": "purge inventory did not match the live desktop"}
            live.clear()
            purged = True
            continue
        return {"graded": True, "passed": False, "feedback": f"unknown containment event {kind}"}
    passed = provoked and not spawn_pending and bool(contained) and purged and not live
    return {"graded": True, "passed": passed, "feedback": f"parasite provoked={provoked}; infected contained={bool(contained)}; live windows={len(live)}"}
