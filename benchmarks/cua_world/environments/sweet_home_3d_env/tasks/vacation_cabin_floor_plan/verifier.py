#!/usr/bin/env python3
"""
Verifier for vacation_cabin_floor_plan task.

Task: Design a complete 1-bedroom vacation cabin from scratch.
Features: wall drawing, room definition, door/window placement, furniture placement, dimension annotation.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Exterior walls (>=4 walls)
  C2 (20 pts): Interior walls + rooms (>=7 total walls + >=4 named rooms)
  C3 (20 pts): Doors & Windows (>=7 door/window items)
  C4 (25 pts): Furniture (1 bed, 1 sofa, 1 table, 4 chairs, 2 appliances, 1 toilet, 1 sink)
  C5 (15 pts): Dimensions >=3, total items >=25, file saved

Wrong-target gate: furniture < 6 -> score=0
"""

import json

def verify_vacation_cabin_floor_plan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/vacation_cabin_floor_plan_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    file_found = result.get("file_found", False)
    if not file_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to find the saved .sh3d file. Ensure you saved it to ~/Documents/SweetHome3D/vacation_cabin.sh3d"
        }

    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 6:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 6 items required to qualify for scoring."
            )
        }

    wall_count = result.get("wall_count", 0)
    named_rooms = len(result.get("room_names", []))
    door_window_count = result.get("door_window_count", 0)
    dimension_count = result.get("dimension_count", 0)

    bed_count = result.get("bed_count", 0)
    sofa_count = result.get("sofa_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    appliance_count = result.get("appliance_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)

    # C1: Exterior walls (>= 4 total walls)
    if wall_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C1: {wall_count} walls drawn (>=4 for perimeter) [+20]")
    elif wall_count >= 2:
        score += 8
        feedback_parts.append(f"PARTIAL C1: {wall_count} walls drawn (need >=4) [+8]")
    else:
        feedback_parts.append(f"FAIL C1: only {wall_count} walls drawn")

    # C2: Interior walls + named rooms (>=7 total walls, >=4 named rooms)
    if wall_count >= 7 and named_rooms >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: interior walls & rooms (walls={wall_count}, named_rooms={named_rooms}) [+20]")
    elif wall_count >= 5 and named_rooms >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: partial walls/rooms (walls={wall_count}, named_rooms={named_rooms}) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=7 walls and >=4 named rooms (got walls={wall_count}, named={named_rooms})")

    # C3: Doors & Windows (>=7 total)
    if door_window_count >= 7:
        score += 20
        feedback_parts.append(f"PASS C3: doors & windows (count={door_window_count}) [+20]")
    elif door_window_count >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial doors/windows (count={door_window_count}, need 7) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: need >=7 doors/windows (got {door_window_count})")

    # C4: Furniture (1 bed, 1 sofa, 1 table, 4 chairs, 2 appliances, 1 toilet, 1 sink)
    c4_reqs_met = 0
    if bed_count >= 1: c4_reqs_met += 1
    if sofa_count >= 1: c4_reqs_met += 1
    if table_count >= 1: c4_reqs_met += 1
    if chair_count >= 4: c4_reqs_met += 1
    if appliance_count >= 2: c4_reqs_met += 1
    if toilet_count >= 1: c4_reqs_met += 1
    if sink_count >= 1: c4_reqs_met += 1

    if c4_reqs_met >= 7:
        score += 25
        feedback_parts.append("PASS C4: all required furniture types placed [+25]")
    elif c4_reqs_met >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL C4: {c4_reqs_met}/7 required furniture types placed [+12]")
    else:
        feedback_parts.append(f"FAIL C4: only {c4_reqs_met}/7 required furniture types placed")

    # C5: Dimensions + total + save
    c5_score = 0
    c5_parts = []
    if dimension_count >= 3:
        c5_score += 5
        c5_parts.append(">=3 dimensions")
    if furniture_count >= 25:
        c5_score += 5
        c5_parts.append(">=25 total items")
    if file_found:
        c5_score += 5
        c5_parts.append("file saved")

    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: missing dimensions, item count, or file not saved")

    passed = score >= 70
    summary = f"Score: {score}/100 | Walls: {wall_count} | Rooms: {named_rooms} | Furniture: {furniture_count} | Dimensions: {dimension_count}"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }