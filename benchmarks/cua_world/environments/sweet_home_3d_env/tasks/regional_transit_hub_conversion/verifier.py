#!/usr/bin/env python3
"""
Verifier for regional_transit_hub_conversion task.

Occupation: Transportation Planner
Industry: Public Transit / Urban Planning

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): High-Density Seating >= 16 chairs/benches (Partial 12 for >=8)
  C2 (20 pts): Walls & Doors >= 3 new walls AND >= 4 doors (Partial 10 if >= 1 wall AND >= 1 door)
  C3 (20 pts): Ticketing & Cafe >= 2 desks, >= 3 tables, >= 1 appliance (Partial 10 if >= 2 conditions met)
  C4 (20 pts): Zoning & Floors >= 4 named rooms AND >= 2 rooms with custom floor color (Partial 10 if only one condition met)
  C5 (15 pts): Restrooms & Save >= 3 toilets, >= 2 sinks, file saved (Partial 7 if file saved but missing fixtures)

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json

def verify_regional_transit_hub(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/regional_transit_hub_conversion_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
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

    chair_count = result.get("chair_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    desk_count = result.get("desk_count", 0)
    table_count = result.get("table_count", 0)
    appliance_count = result.get("appliance_count", 0)
    named_rooms = result.get("named_rooms", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): High-Density Seating ─────────────────────────────────────
    if chair_count >= 16:
        score += 25
        feedback_parts.append(f"PASS C1: high-density seating ({chair_count} chairs/benches) [+25]")
    elif chair_count >= 8:
        score += 12
        feedback_parts.append(f"PARTIAL C1: partial seating ({chair_count} chairs/benches) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: need >=16 chairs/benches (got {chair_count})")

    # ── C2 (20 pts): Walls & Doors ────────────────────────────────────────────
    if new_walls >= 3 and new_doors >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: walls & doors ({new_walls} new walls, {new_doors} new doors) [+20]")
    elif new_walls >= 1 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: some walls/doors ({new_walls} walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=3 new walls AND >=4 new doors (got {new_walls} walls, {new_doors} doors)")

    # ── C3 (20 pts): Ticketing & Cafe ─────────────────────────────────────────
    c3_conditions_met = 0
    if desk_count >= 2: c3_conditions_met += 1
    if table_count >= 3: c3_conditions_met += 1
    if appliance_count >= 1: c3_conditions_met += 1

    if c3_conditions_met == 3:
        score += 20
        feedback_parts.append(f"PASS C3: ticketing & cafe ({desk_count} desks, {table_count} tables, {appliance_count} appliances) [+20]")
    elif c3_conditions_met >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial ticketing/cafe ({desk_count} desks, {table_count} tables, {appliance_count} appliances) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: need >=2 desks, >=3 tables, >=1 appliance (got {desk_count}, {table_count}, {appliance_count})")

    # ── C4 (20 pts): Zoning & Floors ──────────────────────────────────────────
    c4_cond1 = named_rooms >= 4
    c4_cond2 = rooms_with_floor_color >= 2

    if c4_cond1 and c4_cond2:
        score += 20
        feedback_parts.append(f"PASS C4: zoning & floors ({named_rooms} named rooms, {rooms_with_floor_color} rooms with custom floor) [+20]")
    elif c4_cond1 or c4_cond2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial zoning ({named_rooms} named rooms, {rooms_with_floor_color} colored floors) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: need >=4 named rooms AND >=2 colored floors (got {named_rooms}, {rooms_with_floor_color})")

    # ── C5 (15 pts): Restrooms & Save ─────────────────────────────────────────
    if toilet_count >= 3 and sink_count >= 2 and file_changed:
        score += 15
        feedback_parts.append(f"PASS C5: restrooms & save ({toilet_count} toilets, {sink_count} sinks, file changed) [+15]")
    elif file_changed:
        score += 7
        feedback_parts.append(f"PARTIAL C5: file changed but missing fixtures ({toilet_count} toilets, {sink_count} sinks) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: file not changed or missing fixtures ({toilet_count} toilets, {sink_count} sinks)")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }