#!/usr/bin/env python3
"""
Verifier for apartment_renovation_presentation task.

Occupation: Interior Designer / Renovation Consultant
Industry: Architecture & Interior Design

Features required: room_definition, floor_texture, wall_texture,
    door_window_placement, furniture_placement, furniture_elevation,
    dimension_annotation, 3d_photo_rendering

Scoring (total 100 pts, pass threshold 65):
  C1 (20 pts): Room naming + floor textures -- 5 named rooms + >=5 floor textures
  C2 (20 pts): Wall finishes -- >=8 wall segments with left/right side texture or color
  C3 (15 pts): Doors -- >=5 door/window items placed
  C4 (25 pts): Furniture diversity + elevation -- >=30 items from >=5 categories + >=3 elevated
  C5 (20 pts): 3D render + dimensions + file saved

Wrong-target gate: if total furniture < 10, return score=0 immediately.

NOTE: Actual verification is primarily done via external VLM evaluators.
      This programmatic verifier provides a best-effort score from parsed XML data.
"""

import json


def verify_apartment_renovation_presentation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/apartment_renovation_presentation_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 10 items required to qualify for scoring."
            )
        }

    # Extract fields
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    walls_with_texture = result.get("walls_with_texture", 0)
    door_window_count = result.get("door_window_count", 0)
    categories_with_items = result.get("categories_with_items", 0)
    elevated_items = result.get("elevated_items", 0)
    new_dimensions = result.get("new_dimensions", 0)
    photo_found = result.get("photo_found", False)
    photo_size = result.get("photo_size", 0)
    file_changed = result.get("file_changed", False)

    named_rooms = len(room_names)

    # ── C1 (20 pts): Room naming + floor textures ────────────────────────────
    c1_rooms = min(named_rooms, 5)
    c1_floors = min(rooms_with_floor_color, 5)

    if c1_rooms >= 5 and c1_floors >= 5:
        score += 20
        feedback_parts.append(f"PASS C1: {named_rooms} named rooms, {rooms_with_floor_color} with floor finish [+20]")
    elif c1_rooms >= 3 and c1_floors >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL C1: {named_rooms} named rooms, {rooms_with_floor_color} floor finishes [+12]")
    elif c1_rooms >= 2 or c1_floors >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C1: {named_rooms} named rooms, {rooms_with_floor_color} floor finishes [+7]")
    else:
        feedback_parts.append(f"FAIL C1: need 5 named rooms + 5 floor textures (got {named_rooms}, {rooms_with_floor_color})")

    # ── C2 (20 pts): Wall finishes ───────────────────────────────────────────
    if walls_with_texture >= 8:
        score += 20
        feedback_parts.append(f"PASS C2: {walls_with_texture} walls with finish [+20]")
    elif walls_with_texture >= 5:
        score += 12
        feedback_parts.append(f"PARTIAL C2: {walls_with_texture} walls with finish (need >=8) [+12]")
    elif walls_with_texture >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C2: {walls_with_texture} walls with finish (need >=8) [+7]")
    else:
        feedback_parts.append(f"FAIL C2: need >=8 walls with texture/color (got {walls_with_texture})")

    # ── C3 (15 pts): Doors ───────────────────────────────────────────────────
    if door_window_count >= 5:
        score += 15
        feedback_parts.append(f"PASS C3: {door_window_count} doors/windows placed [+15]")
    elif door_window_count >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C3: {door_window_count} doors/windows (need >=5) [+10]")
    elif door_window_count >= 1:
        score += 5
        feedback_parts.append(f"PARTIAL C3: {door_window_count} door(s) placed (need >=5) [+5]")
    else:
        feedback_parts.append(f"FAIL C3: no doors placed (need >=5)")

    # ── C4 (25 pts): Furniture diversity + elevation ─────────────────────────
    c4_score = 0
    c4_parts = []

    # Furniture volume (15 pts)
    if furniture_count >= 30 and categories_with_items >= 5:
        c4_score += 15
        c4_parts.append(f"{furniture_count} items across {categories_with_items} categories")
    elif furniture_count >= 20 and categories_with_items >= 3:
        c4_score += 10
        c4_parts.append(f"{furniture_count} items, {categories_with_items} categories (partial)")
    elif furniture_count >= 15:
        c4_score += 5
        c4_parts.append(f"{furniture_count} items (partial)")

    # Elevated items (10 pts)
    if elevated_items >= 3:
        c4_score += 10
        c4_parts.append(f"{elevated_items} wall-mounted items")
    elif elevated_items >= 1:
        c4_score += 5
        c4_parts.append(f"{elevated_items} elevated item(s) (partial)")

    score += c4_score
    if c4_score == 25:
        feedback_parts.append(f"PASS C4: {', '.join(c4_parts)} [+25]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: {', '.join(c4_parts)} [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: need >=30 items from >=5 categories + >=3 elevated")

    # ── C5 (20 pts): 3D render + dimensions + file saved ────────────────────
    c5_score = 0
    c5_parts = []

    # 3D photo rendering (8 pts)
    if photo_found and photo_size > 10000:
        c5_score += 8
        c5_parts.append("3D photo rendered")
    elif photo_found:
        c5_score += 4
        c5_parts.append("photo file found (small)")

    # Dimension lines (7 pts)
    if new_dimensions >= 4:
        c5_score += 7
        c5_parts.append(f"{new_dimensions} dimension lines")
    elif new_dimensions >= 2:
        c5_score += 4
        c5_parts.append(f"{new_dimensions} dimension lines (partial)")

    # File saved (5 pts)
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")

    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: need 3D render, >=4 dimension lines, file saved")

    # ── Final verdict ────────────────────────────────────────────────────────
    passed = score >= 65
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items | "
        f"Rooms: {named_rooms} named, {rooms_with_floor_color} w/floor | "
        f"Walls w/finish: {walls_with_texture} | Doors: {door_window_count} | "
        f"Elevated: {elevated_items} | Dims: {new_dimensions} | "
        f"Photo: {photo_found} | File changed: {file_changed}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
