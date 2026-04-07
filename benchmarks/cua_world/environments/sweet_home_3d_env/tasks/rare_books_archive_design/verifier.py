#!/usr/bin/env python3
"""
Verifier for rare_books_archive_design task.

Occupation: Facility Planner
Industry: Academic/Archive Facilities

Features required: wall_creation, door_window_placement, room_definition (w/ floor colors), 
furniture_placement, dimension_annotation.

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): High-Density Storage -> >=12 storage items (partial >=8 -> 15)
  C2 (20 pts): Researcher & Lab Surfaces -> >=7 desks/tables + >=10 chairs (partial >=4+5 -> 10)
  C3 (20 pts): Zoning & Access Control -> >=4 new walls + >=3 new doors (partial >=2+1 -> 10)
  C4 (15 pts): Room Definition & Flooring -> >=4 rooms defined, >=2 with floor color (partial >=2 rooms -> 7)
  C5 (10 pts): Dimension Annotations -> >=2 dimension lines
  C6 (10 pts): Total Integrity & Save -> >= 45 total items + file changed

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json

def verify_rare_books_archive_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/rare_books_archive_design_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 15:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 15 items required to qualify for scoring."
            )
        }

    storage_count = result.get("storage_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    sink_count = result.get("sink_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_count = result.get("room_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): High-Density Storage ─────────────────────────────────────
    if storage_count >= 12:
        score += 25
        feedback_parts.append(f"PASS C1: High-Density Storage ({storage_count} items) [+25]")
    elif storage_count >= 8:
        score += 15
        feedback_parts.append(f"PARTIAL C1: High-Density Storage ({storage_count} items, need >=12) [+15]")
    else:
        feedback_parts.append(f"FAIL C1: High-Density Storage needs >=12 items (got {storage_count})")

    # ── C2 (20 pts): Researcher & Lab Surfaces ────────────────────────────────
    # Also ensuring sink count doesn't directly fail but adds context if present
    if desk_count >= 7 and chair_count >= 10:
        score += 20
        feedback_parts.append(f"PASS C2: Surfaces & Seating ({desk_count} desks, {chair_count} chairs, {sink_count} sinks) [+20]")
    elif desk_count >= 4 and chair_count >= 5:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Surfaces & Seating ({desk_count} desks, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Needs >=7 desks/tables + >=10 chairs (got {desk_count}, {chair_count})")

    # ── C3 (20 pts): Zoning & Access Control ──────────────────────────────────
    if new_walls >= 4 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: Zoning & Access Control ({new_walls} new walls, {new_doors} doors) [+20]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Zoning & Access Control ({new_walls} new walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Needs >=4 new walls + >=3 new doors (got {new_walls}, {new_doors})")

    # ── C4 (15 pts): Room Definition & Flooring ───────────────────────────────
    if room_count >= 4 and rooms_with_floor_color >= 2:
        score += 15
        feedback_parts.append(f"PASS C4: Room Definition & Flooring ({room_count} rooms defined, {rooms_with_floor_color} colored) [+15]")
    elif room_count >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C4: Room Definition ({room_count} rooms defined, {rooms_with_floor_color} colored) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: Needs >=4 rooms defined + >=2 colored (got {room_count}, {rooms_with_floor_color})")

    # ── C5 (10 pts): Dimension Annotations ────────────────────────────────────
    if new_dimensions >= 2:
        score += 10
        feedback_parts.append(f"PASS C5: Dimension Annotations ({new_dimensions} lines) [+10]")
    else:
        feedback_parts.append(f"FAIL C5: Needs >=2 dimension lines (got {new_dimensions})")

    # ── C6 (10 pts): Total Integrity & Save ───────────────────────────────────
    if furniture_count >= 45 and file_changed:
        score += 10
        feedback_parts.append(f"PASS C6: Total Integrity & Save ({furniture_count} total items, file modified) [+10]")
    elif file_changed:
        score += 5
        feedback_parts.append(f"PARTIAL C6: File saved, but only {furniture_count} items (need >=45) [+5]")
    else:
        feedback_parts.append(f"FAIL C6: Needs >=45 total items and file save (got {furniture_count}, changed={file_changed})")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(storage={storage_count}, desks={desk_count}, chairs={chair_count}, walls={new_walls}, doors={new_doors})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }