#!/usr/bin/env python3
"""
Verifier for dormitory_floor_conversion task.

Occupation: Director of Residential Life / Facilities Planner
Industry: Higher Education / Student Housing

Features required: wall_creation, door_window_placement, room_definition, furniture_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Sleeping quarters -- >=16 beds + >=8 desks + >=8 chairs + >=4 shelves
  C2 (20 pts): Walls + doors -- >=5 new walls + >=4 new doors
  C3 (15 pts): Room zones -- >=5 named rooms
  C4 (20 pts): Common lounge + kitchen -- >=2 sofas + >=3 tables + >=2 lamps + >=3 appliances
  C5 (20 pts): Bathrooms, Total count, Save -- >=4 toilets, >=4 sinks, >=55 total items, file modified

Wrong-target gate: if total furniture < 10, return score=0.
"""

import json

def verify_dormitory_floor_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/dormitory_floor_conversion_result.json")
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

    bed_count = result.get("bed_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_names = result.get("room_names", [])
    named_rooms_count = len(room_names)
    
    sofa_count = result.get("sofa_count", 0)
    table_count = result.get("table_count", 0)
    lamp_count = result.get("lamp_count", 0)
    appliance_count = result.get("appliance_count", 0)
    
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Sleeping Quarters ────────────────────────────────────────
    if bed_count >= 16 and desk_count >= 8 and chair_count >= 8 and shelf_count >= 4:
        score += 25
        feedback_parts.append(f"PASS C1: sleeping quarters fully equipped ({bed_count} beds, {desk_count} desks, {chair_count} chairs, {shelf_count} shelves) [+25]")
    elif bed_count >= 10 and desk_count >= 4 and chair_count >= 4:
        score += 15
        feedback_parts.append(f"PARTIAL C1: partial sleeping quarters ({bed_count} beds, {desk_count} desks, {chair_count} chairs) [+15]")
    elif bed_count >= 6 and desk_count >= 2:
        score += 8
        feedback_parts.append(f"PARTIAL C1: minimal sleeping quarters ({bed_count} beds, {desk_count} desks) [+8]")
    else:
        feedback_parts.append(f"FAIL C1: insufficient sleeping furniture (need >=16 beds, >=8 desks, >=8 chairs, >=4 shelves)")

    # ── C2 (20 pts): Walls + Doors ────────────────────────────────────────────
    if new_walls >= 5 and new_doors >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: walls and doors ({new_walls} walls, {new_doors} doors) [+20]")
    elif new_walls >= 3 and new_doors >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: some walls and doors ({new_walls} walls, {new_doors} doors) [+10]")
    elif new_walls >= 1 and new_doors >= 1:
        score += 5
        feedback_parts.append(f"PARTIAL C2: minimal walls and doors ({new_walls} walls, {new_doors} doors) [+5]")
    else:
        feedback_parts.append(f"FAIL C2: need >=5 new partition walls and >=4 doors (got {new_walls} walls, {new_doors} doors)")

    # ── C3 (15 pts): Room Zones ───────────────────────────────────────────────
    if named_rooms_count >= 5:
        score += 15
        feedback_parts.append(f"PASS C3: {named_rooms_count} named rooms identified [+15]")
    elif named_rooms_count >= 3:
        score += 8
        feedback_parts.append(f"PARTIAL C3: {named_rooms_count} named rooms identified (need >=5) [+8]")
    elif named_rooms_count >= 1:
        score += 4
        feedback_parts.append(f"PARTIAL C3: {named_rooms_count} named room identified [+4]")
    else:
        feedback_parts.append(f"FAIL C3: no rooms were defined with names")

    # ── C4 (20 pts): Common Lounge + Kitchen ──────────────────────────────────
    # Task asks for >=2 sofas, >=2 tables (lounge) + 1 dining table = >=3 tables total, >=2 lamps, >=3 appliances
    if sofa_count >= 2 and table_count >= 3 and lamp_count >= 2 and appliance_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C4: lounge and kitchen equipped ({sofa_count} sofas, {table_count} tables, {lamp_count} lamps, {appliance_count} appliances) [+20]")
    elif sofa_count >= 1 and table_count >= 1 and appliance_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial lounge/kitchen ({sofa_count} sofas, {table_count} tables, {appliance_count} appliances) [+10]")
    else:
        c4_subreqs = sum([sofa_count >= 1, table_count >= 1, lamp_count >= 1, appliance_count >= 1])
        if c4_subreqs >= 2:
            score += 5
            feedback_parts.append(f"PARTIAL C4: minimal lounge/kitchen items present [+5]")
        else:
            feedback_parts.append(f"FAIL C4: lounge/kitchen missing furniture (need sofas, tables, lamps, appliances)")

    # ── C5 (20 pts): Bathrooms + Total + Save ─────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if toilet_count >= 4:
        c5_score += 5
        c5_parts.append(f"{toilet_count} toilets")
    elif toilet_count >= 2:
        c5_score += 3
        c5_parts.append(f"{toilet_count} toilets (partial)")
        
    if sink_count >= 4:
        c5_score += 5
        c5_parts.append(f"{sink_count} sinks")
    elif sink_count >= 2:
        c5_score += 3
        c5_parts.append(f"{sink_count} sinks (partial)")
        
    if furniture_count >= 55:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total items")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: bathrooms and metadata ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: bathrooms/metadata ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: missing bathroom fixtures, low total count, or file unchanged")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} total "
        f"(beds={bed_count}, desks={desk_count}, chairs={chair_count}, toilets={toilet_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }