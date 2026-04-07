#!/usr/bin/env python3
"""
Verifier for heritage_hotel_lobby_design task.

Occupation: Commercial Interior Designer
Industry: Hospitality / Commercial Real Estate

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Utility Walls & Doors -- >=3 new walls + >=2 new doors (10 pts if >=3 walls OR >=2 doors)
  C2 (20 pts): Room Zones & Flooring -- >=4 named rooms + >=2 rooms_with_floor_color (10 pts if >=2 rooms + >=1 color)
  C3 (20 pts): Lounge & Reception -- >=1 desk/counter, >=3 sofas/armchairs, >=2 tables, >=2 decor (Partial: 10 pts for >= 5 items combined)
  C4 (15 pts): Breakfast Dining Area -- >=12 chairs, >=2 buffet surfaces, >=6 tables total (Partial: 7 pts for >=6 chairs + >=4 tables)
  C5 (25 pts): Restrooms & Rendering -- >=2 toilets (5), >=2 sinks (5), lobby_render.png exists (10), file modified (5)

Wrong-target gate: if total furniture < 15, return score=0.
"""

import json

def verify_heritage_hotel_lobby_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/heritage_hotel_lobby_design_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

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

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    
    desk_count = result.get("desk_count", 0)
    sofa_count = result.get("sofa_count", 0)
    table_count = result.get("table_count", 0)
    decor_count = result.get("decor_count", 0)
    chair_count = result.get("chair_count", 0)
    buffet_count = result.get("buffet_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    
    photo_found = result.get("photo_found", False)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Utility Walls & Doors
    if new_walls >= 3 and new_doors >= 2:
        score += 20
        feedback_parts.append(f"PASS C1: Utility rooms enclosed ({new_walls} walls, {new_doors} doors) [+20]")
    elif new_walls >= 3 or new_doors >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Partial utility enclosure ({new_walls} walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Need >=3 new walls and >=2 doors for utility rooms (got {new_walls} walls, {new_doors} doors)")

    # ── C2 (20 pts): Room Zones & Flooring
    named_count = len(room_names)
    if named_count >= 4 and rooms_with_floor_color >= 2:
        score += 20
        feedback_parts.append(f"PASS C2: Zones defined ({named_count} named rooms, {rooms_with_floor_color} with floor color) [+20]")
    elif named_count >= 2 and rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Partial zones ({named_count} named rooms, {rooms_with_floor_color} with floor color) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=4 named rooms and >=2 with floor color (got {named_count} rooms, {rooms_with_floor_color} colored)")

    # ── C3 (20 pts): Lounge & Reception
    c3_items = desk_count + sofa_count + table_count + decor_count
    c3_passed = desk_count >= 1 and sofa_count >= 3 and table_count >= 2 and decor_count >= 2
    if c3_passed:
        score += 20
        feedback_parts.append(f"PASS C3: Lounge & Reception ({desk_count} desks, {sofa_count} sofas, {table_count} tables, {decor_count} decor) [+20]")
    elif c3_items >= 5:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial lounge ({c3_items} total lounge items) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Lounge & Reception needs desk, >=3 sofas, >=2 tables, >=2 decor (got {c3_items} total)")

    # ── C4 (15 pts): Breakfast Dining Area
    c4_passed = chair_count >= 12 and buffet_count >= 2 and table_count >= 6
    if c4_passed:
        score += 15
        feedback_parts.append(f"PASS C4: Breakfast Area ({chair_count} chairs, {table_count} tables, {buffet_count} buffets) [+15]")
    elif chair_count >= 6 and table_count >= 4:
        score += 7
        feedback_parts.append(f"PARTIAL C4: Partial Breakfast Area ({chair_count} chairs, {table_count} tables, {buffet_count} buffets) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: Breakfast Area needs >=12 chairs, >=2 buffets, >=6 tables overall (got {chair_count} chairs, {table_count} tables, {buffet_count} buffets)")

    # ── C5 (25 pts): Restrooms & Rendering
    c5_score = 0
    c5_parts = []
    if toilet_count >= 2:
        c5_score += 5
        c5_parts.append(f"{toilet_count} toilets")
    if sink_count >= 2:
        c5_score += 5
        c5_parts.append(f"{sink_count} sinks")
    if photo_found:
        c5_score += 10
        c5_parts.append("3D photo generated")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
    
    score += c5_score
    if c5_score == 25:
        feedback_parts.append(f"PASS C5: Restrooms & Rendering ({', '.join(c5_parts)}) [+25]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Missing restrooms, rendering, and file save")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }