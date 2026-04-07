#!/usr/bin/env python3
"""
Verifier for consular_visa_section_layout task.

Occupation: Facility Planner
Industry: Government / Diplomatic

Features required: wall creation, door placement, furniture placement, room definition, floor coloring.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Public Waiting & Security -- >=15 chairs, >=1 desk. (Partial 10 pts for >=8 chairs)
  C2 (25 pts): Secure Interview Stations -- Accumulates globally. >=23 chairs (15+8) & >=5 desks (1+4). (Partial 12 pts for >=2 desks + 12 chairs)
  C3 (20 pts): Staff Back-Office -- Global storage >=6, desks >=9 (1+4+4), appliance >=1. (Partial 10 pts if 2/3 conditions met)
  C4 (20 pts): Architectural Partitioning -- >=4 new interior walls, >=3 new doors. (Partial 10 pts for >=2 walls + >=1 door)
  C5 (15 pts): Zoning & Presentation -- >=4 labels/rooms AND >=2 distinct floor colors, file modified.

Wrong-target gate: if total furniture < 20, return score=0 immediately.
"""

import json


def verify_consular_visa_section_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/consular_visa_section_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 20:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 20 items required to qualify for scoring."
            )
        }

    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    storage_count = result.get("storage_count", 0)
    appliance_count = result.get("appliance_count", 0)
    
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    
    zone_identifiers = result.get("zone_identifiers", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Public Waiting & Security ────────────────────────────────
    # Required: >= 15 chairs, >= 1 desk
    if chair_count >= 15 and desk_count >= 1:
        score += 20
        feedback_parts.append(f"PASS C1: Public waiting furnished (≥15 chairs, ≥1 desk) [+20]")
    elif chair_count >= 8:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Public waiting partially furnished ({chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Public waiting needs ≥15 chairs (got {chair_count})")

    # ── C2 (25 pts): Secure Interview Stations ────────────────────────────────
    # Cumulative Required: >= 23 chairs (15 public + 8 booth), >= 5 desks (1 public + 4 booth)
    if chair_count >= 23 and desk_count >= 5:
        score += 25
        feedback_parts.append(f"PASS C2: Interview booths furnished (total ≥23 chairs, ≥5 desks) [+25]")
    elif chair_count >= 12 and desk_count >= 2:
        score += 12
        feedback_parts.append(f"PARTIAL C2: Interview booths partially furnished (total {chair_count} chairs, {desk_count} desks) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: Booths missing furniture (needs cumulative ≥23 chairs, ≥5 desks)")

    # ── C3 (20 pts): Staff Back-Office ────────────────────────────────────────
    # Cumulative Required: >= 9 desks (1+4+4), >= 6 storage, >= 1 appliance
    c3_conditions_met = 0
    if desk_count >= 9:
        c3_conditions_met += 1
    if storage_count >= 6:
        c3_conditions_met += 1
    if appliance_count >= 1:
        c3_conditions_met += 1

    if c3_conditions_met == 3:
        score += 20
        feedback_parts.append(f"PASS C3: Back-office fully furnished (≥9 desks, ≥6 storage, ≥1 appliance) [+20]")
    elif c3_conditions_met >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Back-office partially furnished (met {c3_conditions_met}/3 conditions) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Back-office needs desks, storage, and appliance (met {c3_conditions_met}/3)")

    # ── C4 (20 pts): Architectural Partitioning ───────────────────────────────
    # Required: >= 4 new walls, >= 3 new doors
    if new_walls >= 4 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C4: Partitions created ({new_walls} new walls, {new_doors} doors) [+20]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Partitions incomplete ({new_walls} walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Partitioning needs ≥4 walls and ≥3 doors (got {new_walls} walls, {new_doors} doors)")

    # ── C5 (15 pts): Zoning & Presentation ────────────────────────────────────
    # Required: >= 4 labels/rooms, >= 2 rooms with floor color, file saved
    if zone_identifiers >= 4 and rooms_with_floor_color >= 2 and file_changed:
        score += 15
        feedback_parts.append(f"PASS C5: Zones labeled and colored ({zone_identifiers} labels/rooms, {rooms_with_floor_color} colored) [+15]")
    elif (zone_identifiers >= 2 or rooms_with_floor_color >= 1) and file_changed:
        score += 7
        feedback_parts.append(f"PARTIAL C5: Partial zoning ({zone_identifiers} labels/rooms, {rooms_with_floor_color} colored) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: Zoning needs ≥4 labels/rooms, ≥2 colored floors, and a saved file")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(chairs={chair_count}, desks={desk_count}, storage={storage_count}, appliances={appliance_count}, "
        f"new_walls={new_walls}, new_doors={new_doors})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }