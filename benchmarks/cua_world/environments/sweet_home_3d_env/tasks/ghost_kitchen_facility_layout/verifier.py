#!/usr/bin/env python3
"""
Verifier for ghost_kitchen_facility_layout task.

Occupation: Food Service Consultant
Industry: Commercial Food Service / Hospitality

Features required:
1. Wall creation (>= 3 new wall segments)
2. Room definition (>= 4 named rooms)
3. Floor treatments (>= 3 rooms with distinct floor colors/textures)
4. Furniture placement (Cooking/Cooling, Prep, Sanitation, Storage)
5. Dimension lines (>= 2 for clearance documentation)

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Zoning & Flooring (>=4 named rooms, >=3 rooms with floor color)
  C2 (25 pts): Cooking & Prep (>=6 appliances, >=8 prep tables)
  C3 (20 pts): Sanitation & Storage (>=4 sinks, >=6 storage units)
  C4 (20 pts): Architecture & Safety (>=3 new walls, >=2 dimensions)
  C5 (15 pts): Overall Complexity (Total furniture >= 35, file successfully saved/changed)

Wrong-target gate: Total furniture < 10 or new walls == 0 -> score=0 immediately.
"""

import json


def verify_ghost_kitchen_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/ghost_kitchen_facility_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # Extract parsed properties
    furniture_count = result.get("furniture_count", 0)
    new_walls = result.get("new_walls", 0)
    
    # ── Wrong-target gate ─────────────────────────────────────────────────────
    if furniture_count < 10 or new_walls == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: Layout is too sparse. Found {furniture_count} furniture item(s) "
                f"and {new_walls} new wall segment(s). Minimum 10 items and at least 1 new wall required to qualify."
            )
        }

    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    appliance_count = result.get("appliance_count", 0)
    prep_count = result.get("prep_count", 0)
    sanitation_count = result.get("sanitation_count", 0)
    storage_count = result.get("storage_count", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Zoning & Flooring ────────────────────────────────────────
    named_rooms_count = len(room_names)
    if named_rooms_count >= 4 and rooms_with_floor_color >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: Zoning & Flooring ({named_rooms_count} named rooms, {rooms_with_floor_color} with floor color) [+20]")
    elif named_rooms_count >= 2 and rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Partial Zoning ({named_rooms_count} named rooms, {rooms_with_floor_color} with floor color) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Requires >=4 named rooms and >=3 rooms with floor color (Got {named_rooms_count} named, {rooms_with_floor_color} colored)")

    # ── C2 (25 pts): Cooking & Prep ───────────────────────────────────────────
    if appliance_count >= 6 and prep_count >= 8:
        score += 25
        feedback_parts.append(f"PASS C2: Cooking & Prep Equipment ({appliance_count} appliances, {prep_count} prep tables) [+25]")
    elif appliance_count >= 3 and prep_count >= 4:
        score += 12
        feedback_parts.append(f"PARTIAL C2: Partial Kitchen Equipment ({appliance_count} appliances, {prep_count} prep tables) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: Requires >=6 appliances and >=8 prep tables (Got {appliance_count} appliances, {prep_count} prep tables)")

    # ── C3 (20 pts): Sanitation & Storage ─────────────────────────────────────
    if sanitation_count >= 4 and storage_count >= 6:
        score += 20
        feedback_parts.append(f"PASS C3: Sanitation & Storage ({sanitation_count} sinks, {storage_count} storage racks) [+20]")
    elif sanitation_count >= 2 and storage_count >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial Sanitation/Storage ({sanitation_count} sinks, {storage_count} storage racks) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Requires >=4 sinks and >=6 storage racks (Got {sanitation_count} sinks, {storage_count} racks)")

    # ── C4 (20 pts): Architecture & Safety ────────────────────────────────────
    c4_score = 0
    c4_parts = []
    if new_walls >= 3:
        c4_score += 10
        c4_parts.append(f"{new_walls} new walls")
    elif new_walls >= 1:
        c4_score += 5
        c4_parts.append(f"{new_walls} new wall (partial)")
    
    if new_dimensions >= 2:
        c4_score += 10
        c4_parts.append(f"{new_dimensions} dimension annotations")
    elif new_dimensions == 1:
        c4_score += 5
        c4_parts.append(f"{new_dimensions} dimension annotation (partial)")

    score += c4_score
    if c4_score == 20:
        feedback_parts.append(f"PASS C4: Architecture & Safety ({', '.join(c4_parts)}) [+20]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Architecture & Safety ({', '.join(c4_parts)}) [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: Architecture needs >=3 partition walls, >=2 dimensions (Got {new_walls} walls, {new_dimensions} dimensions)")

    # ── C5 (15 pts): Overall Complexity ───────────────────────────────────────
    c5_score = 0
    c5_parts = []
    if furniture_count >= 35:
        c5_score += 10
        c5_parts.append(f"{furniture_count} total furniture items")
    elif furniture_count >= 20:
        c5_score += 5
        c5_parts.append(f"{furniture_count} furniture items (partial)")
    
    if file_changed:
        c5_score += 5
        c5_parts.append("file saved successfully")
        
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Complexity ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Complexity ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Complexity requires >=35 furniture items and a saved file.")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} | Appliances: {appliance_count} | Sinks: {sanitation_count} | New Walls: {new_walls}"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }