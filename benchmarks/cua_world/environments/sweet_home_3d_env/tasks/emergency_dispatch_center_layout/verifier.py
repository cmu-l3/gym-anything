#!/usr/bin/env python3
"""
Verifier for emergency_dispatch_center_layout task.

Occupation: Facility Planner
Industry: Public Safety / Emergency Services

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Zoning & Walls -- >= 3 new interior walls AND >= 3 rooms defined with text labels.
  C2 (20 pts): Dispatch Consoles -- >= 8 desks/tables AND >= 8 chairs.
  C3 (15 pts): IT Infrastructure -- >= 1 room with floorColor/Texture AND >= 4 shelves/cabinets.
  C4 (15 pts): 24/7 Support Areas -- >= 2 beds/sofas AND >= 2 kitchen appliances.
  C5 (30 pts): Access & Integrity -- >= 4 doors (10), total furniture >= 30 (10), file modified (10).

Wrong-target gate:
  If total furniture added < 15 or new_walls == 0, return score=0.
"""

import json

def verify_emergency_dispatch_center_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/emergency_dispatch_center_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # Extract metrics
    furniture_count = result.get("furniture_count", 0)
    new_walls = result.get("new_walls", 0)
    new_rooms = result.get("new_rooms", 0)
    new_labels = result.get("new_labels", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    bed_count = result.get("bed_count", 0)
    appliance_count = result.get("appliance_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    door_window_count = result.get("door_window_count", 0)
    file_changed = result.get("file_changed", False)

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    if furniture_count < 15 or new_walls == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: Found {furniture_count} furniture item(s) and {new_walls} new walls. "
                "You must build partition walls and add at least 15 furniture items to qualify for scoring."
            )
        }

    # ── C1 (20 pts): Zoning & Walls ───────────────────────────────────────────
    # Requires >= 3 new walls AND >= 3 rooms or labels
    zone_identifiers = new_rooms + new_labels
    if new_walls >= 3 and zone_identifiers >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} new walls and {zone_identifiers} zone identifiers found [+20]")
    elif new_walls >= 1 and zone_identifiers >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {new_walls} walls, {zone_identifiers} zone identifiers (need >=3 of each) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Need >=3 new walls and >=3 rooms/labels for zoning (got {new_walls} walls, {zone_identifiers} identifiers)")

    # ── C2 (20 pts): Dispatch Consoles ────────────────────────────────────────
    if desk_count >= 8 and chair_count >= 8:
        score += 20
        feedback_parts.append(f"PASS C2: Dispatch consoles ({desk_count} desks, {chair_count} chairs) [+20]")
    elif desk_count >= 4 and chair_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Partial dispatch consoles ({desk_count} desks, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=8 desks and >=8 chairs for dispatch floor (got {desk_count}, {chair_count})")

    # ── C3 (15 pts): IT Infrastructure ────────────────────────────────────────
    c3_score = 0
    c3_parts = []
    if rooms_with_floor_color >= 1:
        c3_score += 7
        c3_parts.append("anti-static flooring found")
    if shelf_count >= 4:
        c3_score += 8
        c3_parts.append(f"{shelf_count} telecom/server racks")
    elif shelf_count >= 2:
        c3_score += 4
        c3_parts.append(f"{shelf_count} racks (partial)")
        
    score += c3_score
    if c3_score == 15:
        feedback_parts.append(f"PASS C3: IT Infrastructure ({', '.join(c3_parts)}) [+15]")
    elif c3_score > 0:
        feedback_parts.append(f"PARTIAL C3: IT Infrastructure ({', '.join(c3_parts)}) [+{c3_score}]")
    else:
        feedback_parts.append(f"FAIL C3: Need floor color for server room and >=4 shelves/racks")

    # ── C4 (15 pts): 24/7 Support Areas ───────────────────────────────────────
    c4_score = 0
    c4_parts = []
    if bed_count >= 2:
        c4_score += 7
        c4_parts.append(f"{bed_count} beds/sofas")
    elif bed_count >= 1:
        c4_score += 3
        c4_parts.append(f"{bed_count} bed (partial)")
        
    if appliance_count >= 2:
        c4_score += 8
        c4_parts.append(f"{appliance_count} appliances")
    elif appliance_count >= 1:
        c4_score += 4
        c4_parts.append(f"{appliance_count} appliance (partial)")
        
    score += c4_score
    if c4_score == 15:
        feedback_parts.append(f"PASS C4: Break area ({', '.join(c4_parts)}) [+15]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Break area ({', '.join(c4_parts)}) [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: Break area needs >=2 beds/sofas and >=2 appliances")

    # ── C5 (30 pts): Access & File Integrity ──────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if door_window_count >= 4:
        c5_score += 10
        c5_parts.append(f"{door_window_count} doors")
    elif door_window_count > 0:
        c5_score += 5
        c5_parts.append(f"{door_window_count} door(s) (partial)")
        
    if furniture_count >= 30:
        c5_score += 10
        c5_parts.append(f"{furniture_count} total furniture")
    elif furniture_count >= 20:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total furniture (partial)")
        
    if file_changed:
        c5_score += 10
        c5_parts.append("file correctly saved")
        
    score += c5_score
    if c5_score == 30:
        feedback_parts.append(f"PASS C5: Access/Integrity ({', '.join(c5_parts)}) [+30]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Access/Integrity ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Access/Integrity criteria missed")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(desks={desk_count}, chairs={chair_count}, shelves={shelf_count}, beds/sofas={bed_count}, "
        f"appliances={appliance_count}, doors={door_window_count}, new walls={new_walls})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }