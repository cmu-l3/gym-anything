#!/usr/bin/env python3
"""
Verifier for bistro_restaurant_layout task.

Occupation: Restaurant Owner / Hospitality Interior Designer
Industry: Food Service / Hospitality

Scoring (total 100 pts, pass threshold 65):
  C1 (25 pts): Dining seating capacity (>=10 tables, >=40 chairs)
  C2 (15 pts): Room zone definition (>=4 rooms with names or floor colors)
  C3 (20 pts): Kitchen equipment (>=4 appliances, >=3 shelves)
  C4 (15 pts): Bar/lounge + doors (>=2 sofas, >=1 desk, >=2 doors)
  C5 (15 pts): Ambiance + restrooms (>=6 lamps, >=4 plants, >=2 toilets, >=2 sinks)
  C6 (10 pts): 3D rendering >50KB + totals + file save

Wrong-target gate: <10 items total = 0 score.
Diversity gate: <4 distinct categories = -20 penalty.
"""

import json


def verify_bistro_restaurant_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/bistro_restaurant_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    
    # ── Wrong-target gate ─────────────────────────────────────────────────────
    if furniture_count < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 10 items required to qualify for scoring."
            )
        }

    chair_count = result.get("chair_count", 0)
    table_count = result.get("table_count", 0)
    desk_count = result.get("desk_count", 0)
    sofa_count = result.get("sofa_count", 0)
    shelf_count = result.get("shelf_count", 0)
    appliance_count = result.get("appliance_count", 0)
    lamp_count = result.get("lamp_count", 0)
    plant_count = result.get("plant_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    new_rooms = result.get("new_rooms", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    
    distinct_types = result.get("distinct_types", 0)
    photo_found = result.get("photo_found", False)
    photo_size_kb = result.get("photo_size_kb", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Dining seating capacity ──────────────────────────────────
    if table_count >= 10 and chair_count >= 40:
        score += 25
        feedback_parts.append(f"PASS C1: dining capacity ({table_count} tables, {chair_count} chairs) [+25]")
    elif table_count >= 5 and chair_count >= 20:
        score += 12
        feedback_parts.append(f"PARTIAL C1: partial dining ({table_count} tables, {chair_count} chairs) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: dining needs >=10 tables + >=40 chairs (got {table_count}, {chair_count})")

    # ── C2 (15 pts): Room zone definition ─────────────────────────────────────
    # Either named rooms or rooms with floor color applied
    named_or_colored = max(len(room_names), rooms_with_floor_color)
    zones = max(new_rooms, named_or_colored)
    
    if zones >= 4:
        score += 15
        feedback_parts.append(f"PASS C2: room zones ({zones} identified zones/rooms) [+15]")
    elif zones >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C2: room zones ({zones} identified zones/rooms, need 4) [+7]")
    else:
        feedback_parts.append(f"FAIL C2: room zones needs >=4 defined rooms with names or floor colors (got {zones})")

    # ── C3 (20 pts): Kitchen equipment ────────────────────────────────────────
    if appliance_count >= 4 and shelf_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: kitchen ({appliance_count} appliances, {shelf_count} shelves) [+20]")
    elif appliance_count >= 2 and shelf_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial kitchen ({appliance_count} appliances, {shelf_count} shelves) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: kitchen needs >=4 appliances + >=3 shelves (got {appliance_count}, {shelf_count})")

    # ── C4 (15 pts): Bar/lounge + doors ───────────────────────────────────────
    c4_subs = 0
    if sofa_count >= 2: c4_subs += 1
    if desk_count >= 1: c4_subs += 1
    if new_doors >= 2: c4_subs += 1
    
    if c4_subs == 3:
        score += 15
        feedback_parts.append(f"PASS C4: bar/lounge & doors (sofas:{sofa_count}, desks:{desk_count}, doors:{new_doors}) [+15]")
    elif c4_subs == 2:
        score += 8
        feedback_parts.append(f"PARTIAL C4: bar/lounge & doors missing 1 req (sofas:{sofa_count}, desks:{desk_count}, doors:{new_doors}) [+8]")
    else:
        feedback_parts.append(f"FAIL C4: bar/lounge needs >=2 sofas, >=1 desk/counter, >=2 new doors")

    # ── C5 (15 pts): Ambiance + restrooms ─────────────────────────────────────
    if lamp_count >= 6 and plant_count >= 4 and toilet_count >= 2 and sink_count >= 2:
        score += 15
        feedback_parts.append(f"PASS C5: ambiance & restrooms ({lamp_count} lamps, {plant_count} plants, {toilet_count} toilets, {sink_count} sinks) [+15]")
    elif lamp_count >= 3 and plant_count >= 2 and toilet_count >= 1:
        score += 8
        feedback_parts.append(f"PARTIAL C5: partial ambiance/restrooms ({lamp_count} lamps, {plant_count} plants, {toilet_count} toilets) [+8]")
    else:
        feedback_parts.append(f"FAIL C5: ambiance/restrooms needs >=6 lamps, >=4 plants, >=2 toilets, >=2 sinks")

    # ── C6 (10 pts): 3D rendering + totals + save ─────────────────────────────
    c6_score = 0
    c6_parts = []
    
    if photo_found and photo_size_kb >= 50:
        c6_score += 4
        c6_parts.append(f"3D render >50KB ({photo_size_kb}KB)")
    elif photo_found:
        c6_score += 2
        c6_parts.append(f"3D render small ({photo_size_kb}KB)")
        
    if furniture_count >= 55:
        c6_score += 3
        c6_parts.append(f"totals >=55 ({furniture_count})")
        
    if file_changed:
        c6_score += 3
        c6_parts.append("file saved")
        
    score += c6_score
    if c6_score == 10:
        feedback_parts.append(f"PASS C6: render + totals + save ({', '.join(c6_parts)}) [+10]")
    elif c6_score > 0:
        feedback_parts.append(f"PARTIAL C6: render + totals + save ({', '.join(c6_parts)}) [+{c6_score}]")
    else:
        feedback_parts.append("FAIL C6: no valid 3D render, insufficient items, or file not saved")

    # ── Diversity Gate / Penalty ──────────────────────────────────────────────
    if distinct_types < 4:
        score = max(0, score - 20)
        feedback_parts.append(f"PENALTY: Lack of diversity. Only {distinct_types} categories used (need >=4). [-20]")

    passed = score >= 65
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items (types: {distinct_types}) | "
        f"Walls: {new_walls} | Rendered: {photo_found}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }