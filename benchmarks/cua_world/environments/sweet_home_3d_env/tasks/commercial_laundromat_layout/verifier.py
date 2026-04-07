#!/usr/bin/env python3
"""
Verifier for commercial_laundromat_layout task.

Occupation: Commercial Interior Designer
Industry: Commercial Facilities Planning

Features required: furniture placement, wall creation, room definition, dimension annotation

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Utility Room Structure -- >= 2 new walls + >= 1 door
  C2 (15 pts): Room Definitions -- >= 4 named rooms
  C3 (25 pts): Commercial Laundry Equip -- >= 20 appliances
  C4 (20 pts): Folding & Lounge -- >= 4 tables + >= 8 seats
  C5 (15 pts): Clearance Dimensions -- >= 2 dimension lines
  C6 ( 5 pts): File Saved -- file modification timestamp and hash changed

Wrong-target gate: furniture_count < 15 -> score=0.
"""

import json

def verify_commercial_laundromat_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/commercial_laundromat_layout_result.json")
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

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    door_window_count = result.get("door_window_count", 0)
    
    # We'll use either new doors or total doors (since baseline was stripped)
    doors = max(new_doors, door_window_count)

    room_count = result.get("room_count", 0)
    room_names = result.get("room_names", [])
    named_rooms_count = len([n for n in room_names if n.strip()])

    appliance_count = result.get("appliance_count", 0)
    table_count = result.get("table_count", 0)
    seat_count = result.get("seat_count", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Utility Room Structure ──────────────────────────────────
    c1_score = 0
    c1_parts = []
    if new_walls >= 2:
        c1_score += 10
        c1_parts.append(f"{new_walls} partition walls")
    elif new_walls >= 1:
        c1_score += 5
        c1_parts.append(f"{new_walls} partition wall (partial)")

    if doors >= 1:
        c1_score += 10
        c1_parts.append(f"{doors} door(s)")
        
    score += c1_score
    if c1_score == 20:
        feedback_parts.append(f"PASS C1: Utility structure ({' and '.join(c1_parts)}) [+20]")
    elif c1_score > 0:
        feedback_parts.append(f"PARTIAL C1: Utility structure ({', '.join(c1_parts)} | needs >=2 walls and >=1 door) [+{c1_score}]")
    else:
        feedback_parts.append("FAIL C1: Utility room needs >=2 walls and >=1 door")

    # ── C2 (15 pts): Room Definitions ────────────────────────────────────────
    # Accept either pure room object count or specifically named rooms
    zones = max(room_count, named_rooms_count)
    if zones >= 4:
        score += 15
        feedback_parts.append(f"PASS C2: Zone definitions ({zones} rooms/zones defined) [+15]")
    elif zones >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C2: Partial zones ({zones} rooms, need >=4) [+7]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=4 rooms defined (got {zones})")

    # ── C3 (25 pts): Commercial Laundry Equip ────────────────────────────────
    if appliance_count >= 20:
        score += 25
        feedback_parts.append(f"PASS C3: Equipment banks ({appliance_count} appliances) [+25]")
    elif appliance_count >= 10:
        score += 12
        feedback_parts.append(f"PARTIAL C3: Partial equipment ({appliance_count} appliances, need >=20) [+12]")
    else:
        feedback_parts.append(f"FAIL C3: Need >=20 laundry appliances (got {appliance_count})")

    # ── C4 (20 pts): Folding & Lounge ────────────────────────────────────────
    c4_score = 0
    c4_parts = []
    if table_count >= 4:
        c4_score += 10
        c4_parts.append(f"{table_count} tables")
    elif table_count >= 2:
        c4_score += 5
        c4_parts.append(f"{table_count} tables (partial)")
        
    if seat_count >= 8:
        c4_score += 10
        c4_parts.append(f"{seat_count} seats")
    elif seat_count >= 4:
        c4_score += 5
        c4_parts.append(f"{seat_count} seats (partial)")

    score += c4_score
    if c4_score == 20:
        feedback_parts.append(f"PASS C4: Lounge & Folding ({' and '.join(c4_parts)}) [+20]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Lounge & Folding ({', '.join(c4_parts)} | needs >=4 tables and >=8 seats) [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: Need >=4 tables and >=8 seats for lounge area")

    # ── C5 (15 pts): Clearance Dimensions ────────────────────────────────────
    if new_dimensions >= 2:
        score += 15
        feedback_parts.append(f"PASS C5: Clearance dimensions ({new_dimensions} dimension lines) [+15]")
    elif new_dimensions >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C5: Clearance dimensions ({new_dimensions} line, need >=2) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: Need >=2 dimension lines for aisle clearance")

    # ── C6 (5 pts): File Saved ───────────────────────────────────────────────
    if file_changed:
        score += 5
        feedback_parts.append("PASS C6: File was modified and saved [+5]")
    else:
        feedback_parts.append("FAIL C6: File appears unchanged. Save changes with Ctrl+S.")

    # ── Final verdict ────────────────────────────────────────────────────────
    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items (Appls={appliance_count}, Tables={table_count}, Seats={seat_count})"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }