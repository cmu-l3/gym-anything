#!/usr/bin/env python3
"""
Verifier for bicycle_shop_layout_design task.

Occupation: Bicycle Mechanic / Small Business Owner
Industry: Retail / Sporting Goods & Repair

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Partition walls & doors (>=4 new walls, >=3 new doors)
  C2 (25 pts): Retail showroom (>=6 display shelves, >=1 checkout desk, >=1 chair, >=4 bikes or substitute shelves)
  C3 (20 pts): Repair workshop (>=3 workbenches/tables, >=4 tool shelves/cabinets)
               * Note: Aggregated table/desk and shelf counts evaluate C2 + C3 combined perfectly.
  C4 (15 pts): Zoning/Identification (>=4 rooms defined with names OR >=4 text labels placed)
  C5 (20 pts): Breakroom/Restroom (>=1 sofa, >=1 appliance, >=1 toilet, >=1 sink) + Total >= 30 + File modified

Wrong-target gate: if total furniture < 10, return score=0.
"""

import json


def verify_bicycle_shop_layout_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/bicycle_shop_layout_design_result.json")
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

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_rooms = result.get("new_rooms", 0)
    new_labels = result.get("new_labels", 0)
    
    shelf_count = result.get("shelf_count", 0)
    desk_count = result.get("desk_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    bike_count = result.get("bike_count", 0)
    sofa_count = result.get("sofa_count", 0)
    appliance_count = result.get("appliance_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Partition walls & doors ──────────────────────────────────
    if new_walls >= 4 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: structure ({new_walls} walls, {new_doors} doors) [+20]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: partial structure ({new_walls} walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: need >=4 walls and >=3 doors (got {new_walls} walls, {new_doors} doors)")

    # ── C2 (25 pts): Retail Showroom ──────────────────────────────────────────
    # Showroom requirements: >=6 display fixtures (shelves), >=1 desk/counter, >=1 chair, >=4 bikes (or extra shelves)
    # Total desks/tables evaluated across C2 & C3
    showroom_desks_ok = (desk_count + table_count) >= 1
    showroom_chairs_ok = chair_count >= 1
    
    # We allow extra shelves to count as bikes if they couldn't find bikes.
    # Total shelves needed for C2(6) + C3(4) = 10. Any shelves beyond 6 can count as showroom bikes, but we need 10 total for full credit.
    # To keep C2 evaluation clean:
    bikes_or_substitutes = bike_count + max(0, shelf_count - 6)
    
    c2_score = 0
    if shelf_count >= 6:
        c2_score += 10
    elif shelf_count >= 3:
        c2_score += 5
        
    if showroom_desks_ok and showroom_chairs_ok:
        c2_score += 5
        
    if bikes_or_substitutes >= 4:
        c2_score += 10
    elif bikes_or_substitutes >= 2:
        c2_score += 5
        
    score += c2_score
    if c2_score == 25:
        feedback_parts.append(f"PASS C2: showroom equipped ({shelf_count} shelves, {desk_count+table_count} desks/tables, {bike_count} bikes) [+25]")
    elif c2_score > 0:
        feedback_parts.append(f"PARTIAL C2: showroom equipped [+{c2_score}]")
    else:
        feedback_parts.append(f"FAIL C2: showroom needs >=6 shelves, >=1 desk, >=4 bikes")

    # ── C3 (20 pts): Repair Workshop ──────────────────────────────────────────
    # Workshop requirements: >=3 workbenches (tables/desks) + >=4 tool cabinets (shelves)
    # Note: Aggregate desk/table needs = 1 (showroom) + 3 (workshop) = 4
    # Aggregate shelf needs = 6 (showroom) + 4 (workshop) = 10
    c3_score = 0
    if (desk_count + table_count) >= 4:
        c3_score += 10
    elif (desk_count + table_count) >= 2:
        c3_score += 5
        
    if shelf_count >= 10:
        c3_score += 10
    elif shelf_count >= 7:
        c3_score += 5

    score += c3_score
    if c3_score == 20:
        feedback_parts.append(f"PASS C3: workshop equipped (total {desk_count+table_count} desks/tables >= 4, total {shelf_count} shelves >= 10) [+20]")
    elif c3_score > 0:
        feedback_parts.append(f"PARTIAL C3: workshop equipped [+{c3_score}]")
    else:
        feedback_parts.append(f"FAIL C3: workshop needs >=3 workbenches + >=4 tool cabinets (evaluated aggregately)")

    # ── C4 (15 pts): Zoning / Identification ──────────────────────────────────
    if new_rooms >= 4 or new_labels >= 4:
        score += 15
        feedback_parts.append(f"PASS C4: zoning ({new_rooms} rooms defined, {new_labels} labels) [+15]")
    elif new_rooms >= 2 or new_labels >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C4: partial zoning ({new_rooms} rooms, {new_labels} labels) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: zoning needs >=4 named rooms or text labels")

    # ── C5 (20 pts): Breakroom/Restroom + Total + File Modified ───────────────
    c5_score = 0
    c5_parts = []
    
    if sofa_count >= 1 and appliance_count >= 1:
        c5_score += 5
        c5_parts.append("breakroom OK")
        
    if toilet_count >= 1 and sink_count >= 1:
        c5_score += 5
        c5_parts.append("restroom OK")
        
    if furniture_count >= 30:
        c5_score += 5
        c5_parts.append("total >= 30")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: amenities & save ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: amenities & save ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: amenities missing or file not saved")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} total "
        f"(walls={new_walls}, doors={new_doors}, shelves={shelf_count}, desks/tables={desk_count+table_count}, "
        f"bikes={bike_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }