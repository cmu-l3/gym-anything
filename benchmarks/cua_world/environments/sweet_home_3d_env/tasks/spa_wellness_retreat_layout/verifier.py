#!/usr/bin/env python3
"""
Verifier for spa_wellness_retreat_layout task.

Occupation: Spa Director
Industry: Hospitality / Wellness

Features required: wall_creation, door_window_placement, room_definition, floor_color, furniture_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Architecture (Walls & Doors) -- >= 4 new walls + >= 5 new doors
  C2 (20 pts): Zoning & Flooring -- >= 5 named rooms + >= 3 rooms with custom floor color/texture
  C3 (20 pts): Treatment Rooms -- >= 3 beds + >= 3 cabinets/shelves + >= 3 chairs/stools
  C4 (20 pts): Locker & Wet Rooms -- >= 4 wardrobes + >= 2 showers + >= 2 toilets/sinks
  C5 (20 pts): Reception & Lounge -- >= 1 desk/table + >= 3 sofas/armchairs + >= 2 plants

Wrong-target gate: if total furniture < 15 or file not changed, return score=0 immediately.
"""

import json


def verify_spa_wellness_retreat_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/spa_wellness_retreat_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    file_changed = result.get("file_changed", False)
    
    if not file_changed:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Wrong-target gate: The file was not modified from the starter template."
        }
        
    if furniture_count < 15:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 15 items are required to qualify for a complete spa layout."
            )
        }

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    
    bed_count = result.get("bed_count", 0)
    cabinet_shelf_count = result.get("cabinet_shelf_count", 0)
    chair_count = result.get("chair_count", 0)
    
    wardrobe_count = result.get("wardrobe_count", 0)
    shower_count = result.get("shower_count", 0)
    toilet_sink_count = result.get("toilet_sink_count", 0)
    
    desk_table_count = result.get("desk_table_count", 0)
    sofa_count = result.get("sofa_count", 0)
    plant_count = result.get("plant_count", 0)

    # ── C1 (20 pts): Architecture (Walls & Doors) ─────────────────────────────
    c1_score = 0
    c1_parts = []
    if new_walls >= 4:
        c1_score += 10
        c1_parts.append(f"{new_walls} partition walls")
    elif new_walls >= 2:
        c1_score += 5
        c1_parts.append(f"{new_walls} partition walls (partial)")
    else:
        c1_parts.append(f"Insufficient walls ({new_walls})")
        
    if new_doors >= 5:
        c1_score += 10
        c1_parts.append(f"{new_doors} doors")
    elif new_doors >= 2:
        c1_score += 5
        c1_parts.append(f"{new_doors} doors (partial)")
    else:
        c1_parts.append(f"Insufficient doors ({new_doors})")
        
    score += c1_score
    if c1_score == 20:
        feedback_parts.append(f"PASS C1: Architecture ({', '.join(c1_parts)}) [+20]")
    elif c1_score > 0:
        feedback_parts.append(f"PARTIAL C1: Architecture ({', '.join(c1_parts)}) [+{c1_score}]")
    else:
        feedback_parts.append("FAIL C1: Architecture needs >=4 new walls and >=5 doors")

    # ── C2 (20 pts): Zoning & Flooring ────────────────────────────────────────
    c2_score = 0
    c2_parts = []
    num_named_rooms = len(room_names)
    
    if num_named_rooms >= 5:
        c2_score += 10
        c2_parts.append(f"{num_named_rooms} named rooms")
    elif num_named_rooms >= 2:
        c2_score += 5
        c2_parts.append(f"{num_named_rooms} named rooms (partial)")
        
    if rooms_with_floor_color >= 3:
        c2_score += 10
        c2_parts.append(f"{rooms_with_floor_color} rooms with custom floor")
    elif rooms_with_floor_color >= 1:
        c2_score += 5
        c2_parts.append(f"{rooms_with_floor_color} room(s) with custom floor (partial)")
        
    score += c2_score
    if c2_score == 20:
        feedback_parts.append(f"PASS C2: Zoning & Flooring ({', '.join(c2_parts)}) [+20]")
    elif c2_score > 0:
        feedback_parts.append(f"PARTIAL C2: Zoning & Flooring ({', '.join(c2_parts)}) [+{c2_score}]")
    else:
        feedback_parts.append("FAIL C2: Zoning & Flooring needs >=5 named rooms and >=3 floor colors")

    # ── C3 (20 pts): Treatment Rooms ──────────────────────────────────────────
    if bed_count >= 3 and cabinet_shelf_count >= 3 and chair_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: Treatment Rooms ({bed_count} beds, {cabinet_shelf_count} cabinets/shelves, {chair_count} chairs) [+20]")
    elif bed_count >= 2 and (cabinet_shelf_count >= 1 or chair_count >= 1):
        score += 10
        feedback_parts.append(f"PARTIAL C3: Treatment Rooms ({bed_count} beds, {cabinet_shelf_count} cabinets, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Treatment Rooms require >=3 beds, >=3 cabinets, >=3 chairs")

    # ── C4 (20 pts): Locker & Wet Rooms ───────────────────────────────────────
    if wardrobe_count >= 4 and shower_count >= 2 and toilet_sink_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C4: Locker & Wet Rooms ({wardrobe_count} wardrobes, {shower_count} showers, {toilet_sink_count} toilets/sinks) [+20]")
    elif wardrobe_count >= 2 and (shower_count >= 1 or toilet_sink_count >= 1):
        score += 10
        feedback_parts.append(f"PARTIAL C4: Locker & Wet Rooms ({wardrobe_count} wardrobes, {shower_count} showers, {toilet_sink_count} toilets/sinks) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Locker & Wet Rooms require >=4 wardrobes, >=2 showers, >=2 toilets/sinks")

    # ── C5 (20 pts): Reception & Lounge ───────────────────────────────────────
    if desk_table_count >= 1 and sofa_count >= 3 and plant_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C5: Reception & Lounge ({desk_table_count} desks, {sofa_count} lounge seats, {plant_count} plants) [+20]")
    elif desk_table_count >= 1 and sofa_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C5: Reception & Lounge ({desk_table_count} desks, {sofa_count} lounge seats, {plant_count} plants) [+10]")
    else:
        feedback_parts.append(f"FAIL C5: Reception & Lounge require >=1 desk, >=3 lounge seats, >=2 plants")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = f"Total Score: {score}/100. Total Furniture Placed: {furniture_count}."
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }