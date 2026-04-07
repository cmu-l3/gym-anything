#!/usr/bin/env python3
"""
Verifier for civic_polling_station_layout task.

Occupation: Election Administrator
Industry: Government / Civic Services

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Room Zones & Colors -- >=4 rooms defined, >=2 with floor color
  C2 (20 pts): Privacy Walls -- >=6 new partition walls
  C3/C4 (35 pts): Desks & Chairs -- >=12 desks/tables, >=12 chairs
  C5 (15 pts): Wayfinding & Dimensions -- >=4 labels, >=1 dimension line
  C6 (10 pts): File modified + sufficient total items

Wrong-target gate: if total furniture < 10, return score=0 immediately.
"""

import json

def verify_civic_polling_station_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/civic_polling_station_layout_result.json")
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

    new_rooms = result.get("new_rooms", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    new_walls = result.get("new_walls", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    new_labels = result.get("new_labels", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── C1: Room Zones & Colors (20 pts) ──────────────────────────────────────
    c1_score = 0
    if new_rooms >= 4:
        c1_score += 10
    elif new_rooms >= 2:
        c1_score += 5
        
    if rooms_with_floor_color >= 2:
        c1_score += 10
    elif rooms_with_floor_color >= 1:
        c1_score += 5
        
    score += c1_score
    feedback_parts.append(f"C1 (Rooms/Colors): {new_rooms} rooms, {rooms_with_floor_color} colored [+{c1_score}/20]")

    # ── C2: Privacy Walls (20 pts) ────────────────────────────────────────────
    if new_walls >= 6:
        score += 20
        feedback_parts.append(f"C2 (Walls): {new_walls} new walls (privacy dividers) [+{20}/20]")
    elif new_walls >= 3:
        score += 10
        feedback_parts.append(f"C2 (Walls): {new_walls} new walls [+{10}/20]")
    else:
        feedback_parts.append(f"C2 (Walls): {new_walls} new walls (need 6) [+0/20]")

    # ── C3/C4: Furniture configuration (35 pts) ───────────────────────────────
    # Requires >=12 desks/tables/cabinets and >=12 chairs/benches combined
    c34_score = 0
    if desk_count >= 12:
        c34_score += 20
    elif desk_count >= 6:
        c34_score += 10
        
    if chair_count >= 12:
        c34_score += 15
    elif chair_count >= 6:
        c34_score += 7
        
    score += c34_score
    feedback_parts.append(f"C3/C4 (Furniture): {desk_count} desks/tables, {chair_count} chairs [+{c34_score}/35]")

    # ── C5: Wayfinding & Dimensions (15 pts) ──────────────────────────────────
    c5_score = 0
    if new_labels >= 4:
        c5_score += 10
    elif new_labels >= 2:
        c5_score += 5
        
    if new_dimensions >= 1:
        c5_score += 5
        
    score += c5_score
    feedback_parts.append(f"C5 (Labels/Dims): {new_labels} labels, {new_dimensions} dimensions [+{c5_score}/15]")

    # ── C6: Save & Baseline Delta (10 pts) ────────────────────────────────────
    if file_changed and furniture_count >= 24:
        score += 10
        feedback_parts.append(f"C6 (File): Modified and populated with items [+{10}/10]")
    elif file_changed:
        score += 5
        feedback_parts.append(f"C6 (File): Modified from baseline [+{5}/10]")
    else:
        feedback_parts.append(f"C6 (File): Not modified [+0/10]")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }