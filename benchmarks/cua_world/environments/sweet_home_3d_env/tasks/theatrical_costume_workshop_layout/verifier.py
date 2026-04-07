#!/usr/bin/env python3
"""
Verifier for theatrical_costume_workshop_layout task.

Occupation: Head of Wardrobe / Costume Designer
Industry: Theater / Performing Arts

Features required: furniture_placement, wall_creation, room_definition, dimension_annotation

Scoring (total 100 pts, pass threshold 70):
  C1 (15 pts): Partition walls -- >=4 new walls created
  C2 (20 pts): Room definition -- >=4 thematic rooms defined ('cutting', 'sewing', 'fitting', 'storage')
  C3 (25 pts): Workstations -- >=8 tables/desks AND >=8 chairs/stools
  C4 (25 pts): Storage & fitting -- >=8 storage units AND >=1 mirror AND >=2 armchairs/sofas
  C5 (15 pts): Dimension annotations -- >=2 dimension lines added

Wrong-target gate: if total furniture < 12 or file unaltered, return score=0.
"""

import json

def verify_theatrical_costume_workshop_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/theatrical_costume_workshop_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    file_changed = result.get("file_changed", False)

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    if furniture_count < 12 or not file_changed:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found, and file_changed={file_changed}. "
                "At least 12 items required and file must be modified/saved to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    room_names = result.get("room_names", [])
    table_desk_count = result.get("table_desk_count", 0)
    chair_count = result.get("chair_count", 0)
    storage_count = result.get("storage_count", 0)
    mirror_count = result.get("mirror_count", 0)
    sofa_count = result.get("sofa_count", 0)
    new_dimensions = result.get("new_dimensions", 0)

    # ── C1 (15 pts): Partition walls ──────────────────────────────────────────
    if new_walls >= 4:
        score += 15
        feedback_parts.append(f"PASS C1: {new_walls} new partition walls created [+15]")
    elif new_walls >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C1: {new_walls} new partition walls (need >=4) [+7]")
    else:
        feedback_parts.append(f"FAIL C1: only {new_walls} new walls created (need >=4)")

    # ── C2 (20 pts): Room definition ──────────────────────────────────────────
    found_zones = set()
    for name in room_names:
        for keyword in ["cutting", "sewing", "fitting", "storage", "wardrobe"]:
            if keyword in name.lower():
                found_zones.add(keyword if keyword != "wardrobe" else "storage")
    
    zone_count = len(found_zones)
    if zone_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: {zone_count} thematic rooms defined ({', '.join(found_zones)}) [+20]")
    elif zone_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: {zone_count} thematic rooms defined (need 4) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: only {zone_count} thematic rooms defined (need 4)")

    # ── C3 (25 pts): Workstations ─────────────────────────────────────────────
    if table_desk_count >= 8 and chair_count >= 8:
        score += 25
        feedback_parts.append(f"PASS C3: workstations ({table_desk_count} tables/desks, {chair_count} chairs) [+25]")
    elif table_desk_count >= 4 and chair_count >= 4:
        score += 12
        feedback_parts.append(f"PARTIAL C3: partial workstations ({table_desk_count} tables, {chair_count} chairs) [+12]")
    else:
        feedback_parts.append(f"FAIL C3: insufficient workstations ({table_desk_count} tables, {chair_count} chairs)")

    # ── C4 (25 pts): Storage & Fitting ────────────────────────────────────────
    storage_ok = storage_count >= 8
    fitting_ok = mirror_count >= 1 and sofa_count >= 2

    if storage_ok and fitting_ok:
        score += 25
        feedback_parts.append(f"PASS C4: storage & fitting ({storage_count} storage, {mirror_count} mirror, {sofa_count} armchairs/sofas) [+25]")
    elif storage_ok or fitting_ok:
        score += 12
        ok_str = "storage" if storage_ok else "fitting"
        feedback_parts.append(f"PARTIAL C4: {ok_str} met, but not both ({storage_count} storage, {mirror_count} mirror, {sofa_count} armchairs/sofas) [+12]")
    else:
        feedback_parts.append(f"FAIL C4: storage & fitting missing or insufficient")

    # ── C5 (15 pts): Dimension Annotations ────────────────────────────────────
    if new_dimensions >= 2:
        score += 15
        feedback_parts.append(f"PASS C5: {new_dimensions} dimension lines added [+15]")
    elif new_dimensions >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C5: {new_dimensions} dimension line added (need >=2) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: no dimension lines added")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }