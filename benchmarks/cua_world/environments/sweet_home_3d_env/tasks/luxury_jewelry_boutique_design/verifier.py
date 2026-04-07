#!/usr/bin/env python3
"""
Verifier for luxury_jewelry_boutique_design task.

Occupation: Physical Security Consultant / Retail Architect
Industry: Retail / High-Value Goods

Features required: wall_creation, door_window_placement, room_definition, furniture_placement, dimension_annotation

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Walls & Doors -- >= 4 new walls (10 pts) + >= 5 doors (10 pts)
  C2 (15 pts): Room Definitions -- >= 4 named rooms (partial 7 pts for >= 2)
  C3 (20 pts): Displays & Vault Storage -- >= 12 storage/display items total (showroom + vault)
  C4 (20 pts): VIP, Security, Break -- >= 2 desks/surfaces + >= 6 seating + >= 1 appliance + >= 1 tech item
  C5 (15 pts): Dimensions Annotations -- >= 2 dimension lines placed
  C6 (10 pts): Minimum total furniture > 40 + file modified timestamp updated

Wrong-target gate: if total furniture < 15 or new_walls == 0, return score=0.
"""

import json

def verify_luxury_jewelry_boutique_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/luxury_jewelry_boutique_design_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    new_walls = result.get("new_walls", 0)
    
    if furniture_count < 15 or new_walls == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: found {furniture_count} furniture items and {new_walls} new walls. "
                "You must place >=15 furniture items and create >=1 new partition wall to qualify for scoring."
            )
        }

    door_count = result.get("door_window_count", 0)
    room_names = result.get("room_names", [])
    named_rooms_count = len(room_names)
    dimension_count = result.get("dimension_count", 0)
    file_changed = result.get("file_changed", False)
    
    storage_count = result.get("storage_count", 0)
    seating_count = result.get("seating_count", 0)
    surface_count = result.get("surface_count", 0)
    appliance_count = result.get("appliance_count", 0)
    tech_count = result.get("tech_count", 0)

    # ── C1 (20 pts): Walls & Doors ───────────────────────────────────────────
    c1_score = 0
    c1_fb = []
    
    if new_walls >= 4:
        c1_score += 10
        c1_fb.append(f"{new_walls} new walls (>=4 required)")
    else:
        c1_score += 5
        c1_fb.append(f"{new_walls} new walls (partial)")
        
    if door_count >= 5:
        c1_score += 10
        c1_fb.append(f"{door_count} doors (>=5 required)")
    elif door_count >= 2:
        c1_score += 5
        c1_fb.append(f"{door_count} doors (partial)")
    else:
        c1_fb.append(f"only {door_count} doors")
        
    score += c1_score
    feedback_parts.append(f"[{'PASS' if c1_score==20 else 'PARTIAL'} C1] Walls/Doors: {', '.join(c1_fb)} (+{c1_score})")

    # ── C2 (15 pts): Room Definitions ────────────────────────────────────────
    if named_rooms_count >= 4:
        score += 15
        feedback_parts.append(f"[PASS C2] Rooms: {named_rooms_count} named rooms identified (+15)")
    elif named_rooms_count >= 2:
        score += 7
        feedback_parts.append(f"[PARTIAL C2] Rooms: {named_rooms_count} named rooms (>=4 required) (+7)")
    else:
        feedback_parts.append(f"[FAIL C2] Rooms: only {named_rooms_count} named rooms found")

    # ── C3 (20 pts): Displays & Vault Storage ────────────────────────────────
    if storage_count >= 12:
        score += 20
        feedback_parts.append(f"[PASS C3] Storage/Displays: {storage_count} items placed (+20)")
    elif storage_count >= 6:
        score += 10
        feedback_parts.append(f"[PARTIAL C3] Storage/Displays: {storage_count} items placed (>=12 required) (+10)")
    else:
        feedback_parts.append(f"[FAIL C3] Storage/Displays: insufficient storage items ({storage_count})")

    # ── C4 (20 pts): VIP, Security, Break ────────────────────────────────────
    c4_score = 0
    c4_fb = []
    
    if surface_count >= 2:
        c4_score += 5; c4_fb.append(f"{surface_count} desks")
    if seating_count >= 6:
        c4_score += 5; c4_fb.append(f"{seating_count} seats")
    if appliance_count >= 1:
        c4_score += 5; c4_fb.append(f"{appliance_count} appliance")
    if tech_count >= 1:
        c4_score += 5; c4_fb.append(f"{tech_count} tech items")
        
    score += c4_score
    if c4_score == 20:
        feedback_parts.append(f"[PASS C4] VIP/Security/Break: {', '.join(c4_fb)} (+20)")
    elif c4_score > 0:
        feedback_parts.append(f"[PARTIAL C4] VIP/Security/Break: completed criteria -> {', '.join(c4_fb)} (+{c4_score})")
    else:
        feedback_parts.append(f"[FAIL C4] VIP/Security/Break: missing desks, seats, appliances, and tech items")

    # ── C5 (15 pts): Dimensions Annotations ──────────────────────────────────
    if dimension_count >= 2:
        score += 15
        feedback_parts.append(f"[PASS C5] Dimensions: {dimension_count} dimension lines placed (+15)")
    elif dimension_count == 1:
        score += 7
        feedback_parts.append(f"[PARTIAL C5] Dimensions: 1 dimension line placed (>=2 required) (+7)")
    else:
        feedback_parts.append(f"[FAIL C5] Dimensions: no dimension annotations found")

    # ── C6 (10 pts): Minimum Total & File Changed ────────────────────────────
    if furniture_count > 40 and file_changed:
        score += 10
        feedback_parts.append(f"[PASS C6] Minimums: >40 total furniture ({furniture_count}) and file successfully saved (+10)")
    elif furniture_count >= 15 and file_changed:
        score += 5
        feedback_parts.append(f"[PARTIAL C6] Minimums: file saved with {furniture_count} total furniture (need >40 for full points) (+5)")
    else:
        feedback_parts.append(f"[FAIL C6] Minimums: file not saved properly or extremely low furniture count")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items | New Walls: {new_walls}"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }