#!/usr/bin/env python3
"""
Verifier for indoor_vertical_farm_layout task.

Occupation: Agricultural Engineer
Industry: AgTech / Controlled Environment Agriculture

Features required: wall_creation, room_definition, door_window_placement, floor_color, furniture_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): High-Density Grow Racks -- >=15 shelving/storage units (partial >=8 -> 15)
  C2 (20 pts): Biosecurity & Partitions -- >=3 new walls AND >=3 doors (partial 10 for walls OR doors)
  C3 (20 pts): Support Zone Equipment -- >=3 tables/workbenches AND >=2 utility fixtures (partial 10)
  C4 (20 pts): Room Definition & Floors -- >=4 rooms defined AND >=2 rooms with floor color (partial 10)
  C5 (15 pts): Scale & Save -- >=35 total furniture items AND file changed

Wrong-target gate: if total furniture < 10 or new_walls == 0, return score=0 immediately.
"""

import json


def verify_indoor_vertical_farm_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/indoor_vertical_farm_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    new_walls = result.get("new_walls", 0)
    
    if furniture_count < 10 or new_walls == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: {furniture_count} furniture item(s) and {new_walls} new walls found. "
                "At least 10 furniture items and 1 new wall required to qualify for scoring."
            )
        }

    rack_count = result.get("rack_count", 0)
    locker_count = result.get("locker_count", 0)
    table_count = result.get("table_count", 0)
    utility_count = result.get("utility_count", 0)
    door_window_count = result.get("door_window_count", 0)
    new_doors = result.get("new_doors", 0)
    new_rooms = result.get("new_rooms", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    doors_to_count = max(door_window_count, new_doors)
    rooms_to_count = max(new_rooms, len(room_names))

    # ── Criterion 1 (25 pts): High-Density Grow Racks ─────────────────────────
    if rack_count >= 15:
        score += 25
        feedback_parts.append(f"PASS C1: High-density grow area ({rack_count} racks/shelves) [+25]")
    elif rack_count >= 8:
        score += 15
        feedback_parts.append(f"PARTIAL C1: Partial grow area ({rack_count} racks/shelves) [+15]")
    else:
        feedback_parts.append(f"FAIL C1: Need >=15 racks/shelves for grow area (got {rack_count})")

    # ── Criterion 2 (20 pts): Biosecurity & Partitions ────────────────────────
    walls_ok = new_walls >= 3
    doors_ok = doors_to_count >= 3
    
    if walls_ok and doors_ok:
        score += 20
        feedback_parts.append(f"PASS C2: Biosecurity partitions ({new_walls} new walls, {doors_to_count} doors) [+20]")
    elif walls_ok or doors_ok:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Partial partitions ({new_walls} new walls, {doors_to_count} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=3 new walls and >=3 doors (got {new_walls} walls, {doors_to_count} doors)")

    # ── Criterion 3 (20 pts): Support Zone Equipment ──────────────────────────
    tables_ok = table_count >= 3
    utility_ok = utility_count >= 2
    
    if tables_ok and utility_ok:
        score += 20
        feedback_parts.append(f"PASS C3: Support zones ({table_count} tables, {utility_count} utility fixtures) [+20]")
    elif tables_ok or utility_ok:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial support zones ({table_count} tables, {utility_count} utility fixtures) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Need >=3 tables and >=2 utility fixtures (got {table_count} tables, {utility_count} fixtures)")

    # ── Criterion 4 (20 pts): Room Definition & Floors ────────────────────────
    rooms_ok = rooms_to_count >= 4
    floors_ok = rooms_with_floor_color >= 2
    
    if rooms_ok and floors_ok:
        score += 20
        feedback_parts.append(f"PASS C4: Zone communication ({rooms_to_count} defined rooms, {rooms_with_floor_color} colored floors) [+20]")
    elif rooms_ok or floors_ok:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Partial zone communication ({rooms_to_count} defined rooms, {rooms_with_floor_color} colored floors) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Need >=4 rooms and >=2 colored floors (got {rooms_to_count} rooms, {rooms_with_floor_color} colored floors)")

    # ── Criterion 5 (15 pts): Scale & Save ────────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if furniture_count >= 35:
        c5_score += 10
        c5_parts.append(f"{furniture_count} total items")
    elif furniture_count >= 20:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total items (partial)")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file changed")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Scale & Save ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Need >=35 items and saved file")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(racks={rack_count}, lockers={locker_count}, tables={table_count}, utility={utility_count}) "
        f"| Walls: {new_walls} | Rooms: {rooms_to_count}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }