#!/usr/bin/env python3
"""
Verifier for boutique_hair_salon_conversion task.

Occupation: Cosmetologist / Salon Owner
Industry: Personal Care Services / Commercial Design

Features required: furniture_placement, wall_creation, floor_color, label_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Styling stations -- >=6 chairs + >=6 desks/tables
  C2 (20 pts): Walls + floor zones -- >=2 new walls + >=3 rooms with floor color/texture
  C3 (20 pts): Reception + retail -- >=1 desk + >=3 waiting seats + >=4 shelves
  C4 (20 pts): Labels + ambient decor -- >=4 new labels + >=4 lamps + >=3 plants
  C5 (15 pts): Washing + break + save -- >=2 sinks (5) + >=1 appliance (5) + file changed (5)

Wrong-target gate: if total furniture < 8, return score=0 immediately.
"""

import json

def verify_boutique_hair_salon_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/boutique_hair_salon_conversion_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 8:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 8 items required to qualify for scoring."
            )
        }

    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    sofa_count = result.get("sofa_count", 0)
    sink_count = result.get("sink_count", 0)
    appliance_count = result.get("appliance_count", 0)
    lamp_count = result.get("lamp_count", 0)
    plant_count = result.get("plant_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_labels = result.get("new_labels", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (25 pts): Styling stations ────────────────────────────────
    if chair_count >= 6 and desk_count >= 6:
        score += 25
        feedback_parts.append(f"PASS C1: styling stations ({chair_count} chairs, {desk_count} desks/tables) [+25]")
    elif chair_count >= 3 and desk_count >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL C1: partial styling stations ({chair_count} chairs, {desk_count} desks/tables) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: styling stations need >=6 chairs + >=6 desks/tables (got {chair_count}, {desk_count})")

    # ── Criterion 2 (20 pts): Walls + Floor zones ─────────────────────────────
    if new_walls >= 2 and rooms_with_floor_color >= 3:
        score += 20
        feedback_parts.append(f"PASS C2: zoning ({new_walls} new walls, {rooms_with_floor_color} colored floors) [+20]")
    elif new_walls >= 1 or rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: partial zoning ({new_walls} new walls, {rooms_with_floor_color} colored floors) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: zoning needs >=2 new walls and >=3 colored floors (got {new_walls}, {rooms_with_floor_color})")

    # ── Criterion 3 (20 pts): Reception & Retail ──────────────────────────────
    # Assume 6 chairs and 6 desks are consumed by styling stations.
    remaining_desks = max(0, desk_count - 6)
    waiting_seats = max(0, chair_count - 6) + sofa_count

    if remaining_desks >= 1 and waiting_seats >= 3 and shelf_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C3: reception/retail ({remaining_desks} extra desk, {waiting_seats} waiting seats, {shelf_count} shelves) [+20]")
    elif remaining_desks >= 1 and waiting_seats >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial reception/retail ({remaining_desks} extra desk, {waiting_seats} waiting seats, {shelf_count} shelves) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: reception/retail needs extra desk, >=3 waiting seats, >=4 shelves (got {remaining_desks} desk, {waiting_seats} seats, {shelf_count} shelves)")

    # ── Criterion 4 (20 pts): Labels + Ambient decor ──────────────────────────
    if new_labels >= 4 and lamp_count >= 4 and plant_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C4: labels & decor ({new_labels} labels, {lamp_count} lamps, {plant_count} plants) [+20]")
    elif new_labels >= 2 and lamp_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial labels & decor ({new_labels} labels, {lamp_count} lamps, {plant_count} plants) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: labels & decor needs >=4 labels, >=4 lamps, >=3 plants (got {new_labels}, {lamp_count}, {plant_count})")

    # ── Criterion 5 (15 pts): Washing, Break room, Save ───────────────────────
    c5_score = 0
    c5_parts = []
    
    if sink_count >= 2:
        c5_score += 5
        c5_parts.append(f"{sink_count} sinks")
    
    if appliance_count >= 1:
        c5_score += 5
        c5_parts.append(f"{appliance_count} appliances")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: wash & break ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: wash & break ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: wash & break needs >=2 sinks, >=1 appliance, and saved file")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture count: {furniture_count}"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }