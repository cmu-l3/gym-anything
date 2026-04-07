#!/usr/bin/env python3
"""
Verifier for luxury_train_carriage_layout task.

Occupation: Transportation Interior Designer
Industry: Transportation / Rail

Features required: wall creation, door placement, furniture placement, dimension annotation.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Partition walls -- >= 12 new interior walls
  C2 (20 pts): Suite accommodations -- >= 3 beds/sofas AND >= 3 storage items
  C3 (20 pts): En-suite bathrooms -- >= 3 toilets AND >= 3 sinks
  C4 (25 pts): Lounge & doors -- >= 4 lounge chairs/sofas AND >= 1 bar/table AND >= 6 doors
  C5 (15 pts): Dimensioning & File -- >= 2 dimension lines AND file modified

Wrong-target gate: if total furniture (excluding doors) < 12, return score=0.
"""

import json

def verify_luxury_train_carriage_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/luxury_train_carriage_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    real_furniture = result.get("real_furniture_count", 0)
    if real_furniture < 12:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {real_furniture} actual furniture item(s) found. "
                "At least 12 items required to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    bed_count = result.get("bed_count", 0)
    storage_count = result.get("storage_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    lounge_count = result.get("lounge_count", 0)
    bar_count = result.get("bar_count", 0)
    door_window_count = result.get("door_window_count", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Carriage Partitioning ───────────────────────────────────
    if new_walls >= 12:
        score += 20
        feedback_parts.append(f"PASS C1: partitioning ({new_walls} new interior walls) [+20]")
    elif new_walls >= 6:
        score += 10
        feedback_parts.append(f"PARTIAL C1: partial partitioning ({new_walls} interior walls, need >=12) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: insufficient partitioning ({new_walls} interior walls, need >=12)")

    # ── C2 (20 pts): Suite Accommodations ────────────────────────────────────
    if bed_count >= 3 and storage_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C2: suite accommodation ({bed_count} beds/sofas, {storage_count} storage) [+20]")
    elif bed_count >= 2 and storage_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: partial suite accommodation ({bed_count} beds, {storage_count} storage) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=3 beds + >=3 storage items (got {bed_count} beds, {storage_count} storage)")

    # ── C3 (20 pts): En-suite Bathrooms ──────────────────────────────────────
    if toilet_count >= 3 and sink_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: en-suite bathrooms ({toilet_count} toilets, {sink_count} sinks) [+20]")
    elif toilet_count >= 2 and sink_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial bathrooms ({toilet_count} toilets, {sink_count} sinks) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: need >=3 toilets + >=3 sinks (got {toilet_count} toilets, {sink_count} sinks)")

    # ── C4 (25 pts): Lounge & Access Doors ───────────────────────────────────
    if lounge_count >= 4 and bar_count >= 1 and door_window_count >= 6:
        score += 25
        feedback_parts.append(f"PASS C4: lounge & access ({lounge_count} lounge seats, {bar_count} bar/table, {door_window_count} doors) [+25]")
    elif lounge_count >= 2 and door_window_count >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL C4: partial lounge & access ({lounge_count} lounge seats, {door_window_count} doors) [+12]")
    else:
        feedback_parts.append(f"FAIL C4: need >=4 lounge seats + >=1 bar/table + >=6 doors (got {lounge_count} seats, {bar_count} bar/table, {door_window_count} doors)")

    # ── C5 (15 pts): Dimensioning & Save ─────────────────────────────────────
    if new_dimensions >= 2 and file_changed:
        score += 15
        feedback_parts.append(f"PASS C5: clearance dimensioning ({new_dimensions} dimension lines) and file saved [+15]")
    elif new_dimensions >= 1 and file_changed:
        score += 7
        feedback_parts.append(f"PARTIAL C5: minimal dimensioning ({new_dimensions} dimension lines) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: need >=2 dimension lines and file saved (got {new_dimensions} lines, file_changed={file_changed})")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture items: {real_furniture} "
        f"(walls={new_walls}, doors={door_window_count}, beds={bed_count}, "
        f"toilets={toilet_count}, dimensions={new_dimensions})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }