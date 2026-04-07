#!/usr/bin/env python3
"""
Verifier for sitcom_soundstage_design task.

Occupation: Production Designer
Industry: Film & Television Production

Features required: furniture_placement, wall_creation, room_definition, dimension_annotation, floor_color

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Set Walls & Dimensions -- >=4 new walls + >=2 dimension lines
  C2 (20 pts): Studio Zoning -- >=3 rooms defined + >=2 rooms with distinct floor color/texture
  C3 (25 pts): Domestic Set Furnishings -- >=1 sofa, >=1 table, >=2 res chairs, >=2 appliances, >=2 decor
  C4 (20 pts): Production Equipment -- >=4 lamps/spotlights, >=2 desks, >=4 office chairs/stools
  C5 (15 pts): Overall Complexity & Save -- >=35 total items + file changed/saved

Wrong-target gate: if total furniture < 15 or new walls == 0, return score=0.
"""

import json

def verify_sitcom_soundstage_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/sitcom_soundstage_design_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    new_walls = result.get("new_walls", 0)
    
    # ── Wrong-target gate ─────────────────────────────────────────────────────
    if furniture_count < 15 or new_walls == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: found {furniture_count} furniture item(s) and {new_walls} new wall(s). "
                "At least 15 items and 1 new wall are required to qualify for scoring."
            )
        }

    new_dimensions = result.get("new_dimensions", 0)
    room_count = result.get("room_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    
    sofa_count = result.get("sofa_count", 0)
    table_count = result.get("table_count", 0)
    res_chair_count = result.get("res_chair_count", 0)
    appliance_count = result.get("appliance_count", 0)
    decor_count = result.get("decor_count", 0)
    
    lamp_count = result.get("lamp_count", 0)
    desk_count = result.get("desk_count", 0)
    office_chair_count = result.get("office_chair_count", 0)
    
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Set Walls & Dimensions ──────────────────────────────────
    c1_score = 0
    c1_parts = []
    if new_walls >= 4:
        c1_score += 10
        c1_parts.append(f"{new_walls} new walls")
    elif new_walls >= 2:
        c1_score += 5
        c1_parts.append(f"{new_walls} new walls (partial)")
        
    if new_dimensions >= 2:
        c1_score += 10
        c1_parts.append(f"{new_dimensions} dimension lines")
    elif new_dimensions == 1:
        c1_score += 5
        c1_parts.append(f"1 dimension line (partial)")
        
    score += c1_score
    if c1_score == 20:
        feedback_parts.append(f"PASS C1: Set walls & dimensions ({', '.join(c1_parts)}) [+20]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C1: walls & dimensions ({', '.join(c1_parts)}) [+{c1_score}]")

    # ── C2 (20 pts): Studio Zoning ───────────────────────────────────────────
    c2_score = 0
    c2_parts = []
    if room_count >= 3:
        c2_score += 10
        c2_parts.append(f"{room_count} rooms defined")
    elif room_count >= 1:
        c2_score += 5
        c2_parts.append(f"{room_count} room(s) defined")
        
    if rooms_with_floor_color >= 2:
        c2_score += 10
        c2_parts.append(f"{rooms_with_floor_color} rooms with color/texture")
    elif rooms_with_floor_color == 1:
        c2_score += 5
        c2_parts.append(f"1 room with color/texture")
        
    score += c2_score
    if c2_score == 20:
        feedback_parts.append(f"PASS C2: Studio zoning ({', '.join(c2_parts)}) [+20]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C2: Studio zoning ({', '.join(c2_parts)}) [+{c2_score}]")

    # ── C3 (25 pts): Domestic Set Furnishings ────────────────────────────────
    c3_score = 0
    c3_parts = []
    if sofa_count >= 1: c3_score += 5; c3_parts.append("sofa")
    if table_count >= 1: c3_score += 5; c3_parts.append("table")
    if res_chair_count >= 2: c3_score += 5; c3_parts.append(f"{res_chair_count} res chairs")
    if appliance_count >= 2: c3_score += 5; c3_parts.append(f"{appliance_count} appliances")
    if decor_count >= 2: c3_score += 5; c3_parts.append(f"{decor_count} decor items")
    
    score += c3_score
    if c3_score == 25:
        feedback_parts.append(f"PASS C3: Domestic set props ({', '.join(c3_parts)}) [+25]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C3: Domestic set props missing elements [+{c3_score}]")

    # ── C4 (20 pts): Production Equipment ────────────────────────────────────
    c4_score = 0
    c4_parts = []
    if lamp_count >= 4:
        c4_score += 10
        c4_parts.append(f"{lamp_count} lamps")
    elif lamp_count >= 2:
        c4_score += 5
        c4_parts.append(f"{lamp_count} lamps (partial)")
        
    if desk_count >= 2:
        c4_score += 5
        c4_parts.append(f"{desk_count} desks")
    elif desk_count == 1:
        c4_score += 2
        c4_parts.append(f"1 desk (partial)")
        
    if office_chair_count >= 4:
        c4_score += 5
        c4_parts.append(f"{office_chair_count} office chairs/stools")
    elif office_chair_count >= 2:
        c4_score += 2
        c4_parts.append(f"{office_chair_count} office chairs (partial)")
        
    score += c4_score
    if c4_score == 20:
        feedback_parts.append(f"PASS C4: Production equipment ({', '.join(c4_parts)}) [+20]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C4: Production equipment ({', '.join(c4_parts)}) [+{c4_score}]")

    # ── C5 (15 pts): Overall Complexity & Save ───────────────────────────────
    c5_score = 0
    c5_parts = []
    if furniture_count >= 35:
        c5_score += 10
        c5_parts.append(f"total items={furniture_count}")
    elif furniture_count >= 25:
        c5_score += 5
        c5_parts.append(f"total items={furniture_count} (partial)")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file saved successfully")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Complexity & save ({', '.join(c5_parts)}) [+15]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C5: Complexity & save ({', '.join(c5_parts)}) [+{c5_score}]")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Items: {furniture_count} | Walls: {new_walls} | Dims: {new_dimensions} | Rooms: {room_count}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }