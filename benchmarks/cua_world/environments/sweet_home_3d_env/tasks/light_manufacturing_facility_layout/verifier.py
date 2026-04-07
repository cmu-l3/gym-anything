#!/usr/bin/env python3
"""
Verifier for light_manufacturing_facility_layout task.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Partition Walls & Doors (>= 4 new walls AND >= 3 new doors)
  C2 (15 pts): Room Definitions (>= 4 rooms defined with names)
  C3 (25 pts): Assembly & Storage Gear (>= 6 tables/benches + >= 6 chairs/stools + >= 8 shelves/racks)
  C4 (20 pts): Office & Breakroom (incremental >= 9 tables total, >= 12 chairs total, >= 2 computers + >= 2 appliances + >= 1 sink)
  C5 (20 pts): Labels & File Integrity (>= 3 text labels placed + file saved with >= 40 total items)

Wrong-target gate: if total furniture count < 15 or new_walls == 0, return score=0.
"""

import json

def verify_light_manufacturing_facility_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/light_manufacturing_facility_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    if not result.get("file_found", False):
        return {"passed": False, "score": 0, "feedback": "No modified .sh3d file found."}

    furniture_count = result.get("furniture_count", 0)
    new_walls = result.get("new_walls", 0)

    # Anti-gaming gate: ensure agent actually added infrastructure
    if furniture_count < 15 or new_walls == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: found {furniture_count} furniture item(s) and {new_walls} new walls. "
                "Task requires significant furniture placement (>=15) and wall creation to qualify for points."
            )
        }

    # Extract metrics
    new_doors = result.get("new_doors", 0)
    room_count = result.get("room_count", 0)
    room_names = result.get("room_names", [])
    
    work_surface_count = result.get("work_surface_count", 0)
    seating_count = result.get("seating_count", 0)
    storage_count = result.get("storage_count", 0)
    appliance_count = result.get("appliance_count", 0)
    sink_count = result.get("sink_count", 0)
    computer_count = result.get("computer_count", 0)
    label_count = result.get("label_count", 0)
    file_changed = result.get("file_changed", False)

    named_rooms = len(room_names)

    # ── C1 (20 pts): Partition Walls & Doors ──────────────────────────────────
    if new_walls >= 4 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} walls, {new_doors} doors [+20]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {new_walls} walls, {new_doors} doors [+10]")
    else:
        feedback_parts.append(f"FAIL C1: need >=4 new walls, >=3 doors (got {new_walls}, {new_doors})")

    # ── C2 (15 pts): Room Definitions ─────────────────────────────────────────
    if room_count >= 4 and named_rooms >= 4:
        score += 15
        feedback_parts.append(f"PASS C2: {room_count} rooms defined, {named_rooms} named [+15]")
    elif room_count >= 2 and named_rooms >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C2: {room_count} rooms, {named_rooms} named [+7]")
    else:
        feedback_parts.append(f"FAIL C2: need >=4 named rooms (got {room_count} rooms, {named_rooms} named)")

    # ── C3 (25 pts): Assembly & Storage Gear ──────────────────────────────────
    c3_score = 0
    if work_surface_count >= 6: c3_score += 8
    elif work_surface_count >= 3: c3_score += 4
    
    if seating_count >= 6: c3_score += 8
    elif seating_count >= 3: c3_score += 4
    
    if storage_count >= 8: c3_score += 9
    elif storage_count >= 4: c3_score += 4
    
    score += c3_score
    if c3_score == 25:
        feedback_parts.append(f"PASS C3: Assembly & Storage gear adequate [+25]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C3: Assembly & Storage gear partial [+{c3_score}]")

    # ── C4 (20 pts): Office & Breakroom ───────────────────────────────────────
    c4_score = 0
    if work_surface_count >= 9: c4_score += 4  # Covers 6 assembly + 3 office
    if seating_count >= 12: c4_score += 4      # Covers 6 assembly + 3 office + 3 breakroom
    if computer_count >= 2: c4_score += 4
    if appliance_count >= 2: c4_score += 4
    if sink_count >= 1: c4_score += 4
    
    score += c4_score
    if c4_score == 20:
        feedback_parts.append(f"PASS C4: Office & Breakroom equipped [+20]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C4: Office & Breakroom partial [+{c4_score}]")

    # ── C5 (20 pts): Labels & File Integrity ──────────────────────────────────
    c5_score = 0
    if label_count >= 3: c5_score += 10
    elif label_count >= 1: c5_score += 5
    
    if file_changed and furniture_count >= 40: c5_score += 10
    elif file_changed and furniture_count >= 25: c5_score += 5
    
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Labels & total density met [+20]")
    else:
        feedback_parts.append(f"PARTIAL/FAIL C5: Labels/density partial [+{c5_score}]")

    passed = score >= 70
    feedback_parts.insert(0, f"Score: {score}/100")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }