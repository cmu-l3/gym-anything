#!/usr/bin/env python3
"""
Verifier for floral_shop_design task.

Occupation: Floral Designer
Industry: Retail / Floristry

Features tested: wall_creation, door_window_placement, room_definition, floor_color, furniture_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): >=4 new walls (10 pts) + >=2 new doors/windows (10 pts)
  C2 (20 pts): >=3 named rooms (10 pts) + >=2 rooms with distinct floor treatments (10 pts)
  C3 (20 pts): >=2 sinks (10 pts) + >=3 workbenches/tables (10 pts)
  C4 (20 pts): >=10 plants/flowers (10 pts) + >=5 shelves (10 pts)
  C5 (20 pts): >=3 seating items (5 pts) + >=35 total items (10 pts) + file changed (5 pts)
"""

import json

def verify_floral_shop_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/floral_shop_design_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

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

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    
    sink_count = result.get("sink_count", 0)
    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    seating_count = result.get("seating_count", 0)
    plant_count = result.get("plant_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Walls and Doors ──────────────────────────────────────
    c1_score = 0
    if new_walls >= 4:
        c1_score += 10
    elif new_walls >= 2:
        c1_score += 5
        
    if new_doors >= 2:
        c1_score += 10
    elif new_doors >= 1:
        c1_score += 5
        
    score += c1_score
    feedback_parts.append(f"C1 Walls/Doors: {new_walls} walls, {new_doors} doors [+{c1_score}]")

    # ── C2 (20 pts): Room Zones & Flooring ──────────────────────────────────
    c2_score = 0
    named_rooms_count = len(room_names)
    if named_rooms_count >= 3:
        c2_score += 10
    elif named_rooms_count >= 1:
        c2_score += 5
        
    if rooms_with_floor_color >= 2:
        c2_score += 10
    elif rooms_with_floor_color >= 1:
        c2_score += 5
        
    score += c2_score
    feedback_parts.append(f"C2 Zones: {named_rooms_count} named rooms, {rooms_with_floor_color} floor colored rooms [+{c2_score}]")

    # ── C3 (20 pts): Workspace Fixtures ─────────────────────────────────────
    c3_score = 0
    if sink_count >= 2:
        c3_score += 10
    elif sink_count >= 1:
        c3_score += 5
        
    if desk_count >= 3:
        c3_score += 10
    elif desk_count >= 1:
        c3_score += 5
        
    score += c3_score
    feedback_parts.append(f"C3 Workspace: {sink_count} sinks, {desk_count} desks/tables [+{c3_score}]")

    # ── C4 (20 pts): Retail & Botanicals ────────────────────────────────────
    c4_score = 0
    if plant_count >= 10:
        c4_score += 10
    elif plant_count >= 5:
        c4_score += 5
        
    if shelf_count >= 5:
        c4_score += 10
    elif shelf_count >= 2:
        c4_score += 5
        
    score += c4_score
    feedback_parts.append(f"C4 Retail: {plant_count} plants, {shelf_count} shelves [+{c4_score}]")

    # ── C5 (20 pts): Completion & Constraints ───────────────────────────────
    c5_score = 0
    if seating_count >= 3:
        c5_score += 5
    elif seating_count >= 1:
        c5_score += 2
        
    if furniture_count >= 35:
        c5_score += 10
    elif furniture_count >= 20:
        c5_score += 5
        
    if file_changed:
        c5_score += 5
        
    score += c5_score
    feedback_parts.append(f"C5 Overall: {seating_count} seats, {furniture_count} total items, changed={file_changed} [+{c5_score}]")

    passed = score >= 70
    feedback_parts.insert(0, f"Score: {score}/100")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }