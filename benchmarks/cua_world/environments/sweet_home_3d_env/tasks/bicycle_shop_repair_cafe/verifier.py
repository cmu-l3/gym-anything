#!/usr/bin/env python3
"""
Verifier for bicycle_shop_repair_cafe task.

Validates the layout of a hybrid bicycle shop, mechanical repair bay, and cafe.
Checks for required walls, doors, rooms, dimensions, and categorical furnishings.
"""

import json

def verify_bicycle_shop_repair_cafe(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/bicycle_shop_repair_cafe_result.json")
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
    doors = max(new_doors, result.get("door_window_count", 0))
    room_count = result.get("room_count", 0)
    named_rooms_count = len(result.get("room_names", []))
    dimension_count = result.get("dimension_count", 0)

    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    chair_count = result.get("chair_count", 0)
    appliance_count = result.get("appliance_count", 0)
    sink_count = result.get("sink_count", 0)
    toilet_count = result.get("toilet_count", 0)
    
    is_target_filename = result.get("is_target_filename", False)

    # C1: Spatial Division (Walls & Doors) - 20 pts
    if new_walls >= 3 and doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: Spatial division ({new_walls} new walls, {doors} doors) [+20]")
    elif new_walls >= 2 or doors >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Spatial division ({new_walls} new walls, {doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Need >=3 new walls and >=3 doors (got {new_walls} walls, {doors} doors)")

    # C2: Room Definitions - 15 pts
    if named_rooms_count >= 4:
        score += 15
        feedback_parts.append(f"PASS C2: Room definitions ({named_rooms_count} named rooms) [+15]")
    elif named_rooms_count >= 2 or room_count >= 4:
        score += 7
        feedback_parts.append(f"PARTIAL C2: Room definitions ({room_count} rooms, {named_rooms_count} named) [+7]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=4 named rooms (got {room_count} rooms, {named_rooms_count} named)")

    # C3: Workshop & Office Furnishings - 25 pts
    # Requirement: >=2 desks/benches + >=3 shelves + >=1 sink
    c3_reqs_met = sum([desk_count >= 2, shelf_count >= 3, sink_count >= 1])
    
    if c3_reqs_met == 3:
        score += 25
        feedback_parts.append("PASS C3: Workshop furnishings met [+25]")
    elif c3_reqs_met >= 2:
        score += 12
        feedback_parts.append(f"PARTIAL C3: Workshop furnishings partially met ({c3_reqs_met}/3) [+12]")
    else:
        feedback_parts.append(f"FAIL C3: Workshop furnishings not met (got {desk_count} benches, {shelf_count} shelves, {sink_count} sinks)")

    # C4: Cafe & Retail Furnishings - 25 pts
    # Requirement: >=3 desks/counters (total) + >=7 shelves (total) + >=4 chairs + >=1 appliance
    c4_reqs_met = sum([desk_count >= 3, shelf_count >= 7, chair_count >= 4, appliance_count >= 1])
    
    if c4_reqs_met == 4:
        score += 25
        feedback_parts.append("PASS C4: Cafe/Retail furnishings met [+25]")
    elif c4_reqs_met >= 2:
        score += 12
        feedback_parts.append(f"PARTIAL C4: Cafe/Retail furnishings partially met ({c4_reqs_met}/4) [+12]")
    else:
        feedback_parts.append(f"FAIL C4: Cafe/Retail furnishings not met (got {desk_count} desks, {shelf_count} shelves, {chair_count} chairs, {appliance_count} appliances)")

    # C5: Dimensions, Restroom & Save - 15 pts
    c5_score = 0
    if dimension_count >= 2: c5_score += 5
    if toilet_count >= 1: c5_score += 5
    if is_target_filename: c5_score += 5
    
    score += c5_score
    if c5_score == 15:
        feedback_parts.append("PASS C5: Dimensions, restroom, and filename conditions met [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Secondary conditions partially met [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Dimensions, restroom, and correct filename not met")

    passed = score >= 70
    feedback = f"Score: {score}/100 | " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }