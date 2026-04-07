#!/usr/bin/env python3
"""
Verifier for data_center_server_room task.

Occupation: IT Facilities Manager
Industry: Information Technology / Data Centers

Features required: wall creation, door placement, furniture placement, label placement.

Scoring (total 100 pts, pass threshold 60):
  C1 (25 pts): Server racks -- >=14 shelves/cabinets total
  C2 (20 pts): Partition walls + doors -- >=3 new walls (10) + >=3 new doors (10)
  C3 (20 pts): NOC workstations -- >=5 desks + >=5 chairs + >=3 lamps
  C4 (15 pts): Zone labels -- >=5 new labels placed
  C5 (20 pts): Staging/electrical + totals + save -- >=2 tables (5), >=17 total shelves (5), >=40 total items (5), file changed (5)

Wrong-target gate: if total furniture < 10, return score=0 immediately.
"""

import json


def verify_data_center_server_room(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/data_center_server_room_result.json")
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

    shelf_count = result.get("shelf_count", 0)
    desk_count = result.get("desk_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    lamp_count = result.get("lamp_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_labels = result.get("new_labels", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Server Racks ─────────────────────────────────────────────
    if shelf_count >= 14:
        score += 25
        feedback_parts.append(f"PASS C1: server racks ({shelf_count} shelves/cabinets found) [+25]")
    elif shelf_count >= 8:
        score += 12
        feedback_parts.append(f"PARTIAL C1: partial server racks ({shelf_count} shelves/cabinets found, need >=14) [+12]")
    elif shelf_count >= 4:
        score += 6
        feedback_parts.append(f"PARTIAL C1: minimal server racks ({shelf_count} shelves/cabinets found, need >=14) [+6]")
    else:
        feedback_parts.append(f"FAIL C1: need >=14 server racks (got {shelf_count})")

    # ── C2 (20 pts): Partition walls + doors ──────────────────────────────────
    c2_score = 0
    c2_parts = []
    if new_walls >= 3:
        c2_score += 10
        c2_parts.append(f"{new_walls} walls")
    elif new_walls >= 1:
        c2_score += 5
        c2_parts.append(f"{new_walls} walls (partial)")
    else:
        c2_parts.append("no new walls")

    if new_doors >= 3:
        c2_score += 10
        c2_parts.append(f"{new_doors} doors")
    elif new_doors >= 1:
        c2_score += 5
        c2_parts.append(f"{new_doors} doors (partial)")
    else:
        c2_parts.append("no new doors")

    score += c2_score
    if c2_score == 20:
        feedback_parts.append(f"PASS C2: zone partitioning ({', '.join(c2_parts)}) [+20]")
    elif c2_score > 0:
        feedback_parts.append(f"PARTIAL C2: zone partitioning ({', '.join(c2_parts)}) [+{c2_score}]")
    else:
        feedback_parts.append(f"FAIL C2: need >=3 new walls + >=3 new doors (got {new_walls} walls, {new_doors} doors)")

    # ── C3 (20 pts): NOC Workstations ─────────────────────────────────────────
    c3_score = 0
    if desk_count >= 5 and chair_count >= 5 and lamp_count >= 3:
        c3_score += 20
        feedback_parts.append(f"PASS C3: NOC workstations ({desk_count} desks, {chair_count} chairs, {lamp_count} lamps) [+20]")
    elif desk_count >= 3 and chair_count >= 3:
        c3_score += 10
        feedback_parts.append(f"PARTIAL C3: partial NOC ({desk_count} desks, {chair_count} chairs, {lamp_count} lamps) [+10]")
    elif desk_count >= 1 and chair_count >= 1:
        c3_score += 5
        feedback_parts.append(f"PARTIAL C3: minimal NOC ({desk_count} desks, {chair_count} chairs) [+5]")
    else:
        feedback_parts.append(f"FAIL C3: NOC needs >=5 desks + >=5 chairs + >=3 lamps")
    score += c3_score

    # ── C4 (15 pts): Zone Labels ──────────────────────────────────────────────
    if new_labels >= 5:
        score += 15
        feedback_parts.append(f"PASS C4: zone labeling ({new_labels} text labels added) [+15]")
    elif new_labels >= 3:
        score += 8
        feedback_parts.append(f"PARTIAL C4: partial labeling ({new_labels} labels, need >=5) [+8]")
    elif new_labels >= 1:
        score += 4
        feedback_parts.append(f"PARTIAL C4: minimal labeling ({new_labels} labels, need >=5) [+4]")
    else:
        feedback_parts.append(f"FAIL C4: need >=5 text labels for zones (got {new_labels})")

    # ── C5 (20 pts): Staging/Electrical + Totals + Save ───────────────────────
    c5_score = 0
    c5_parts = []
    
    if table_count >= 2:
        c5_score += 5
        c5_parts.append(f"{table_count} tables")
    
    if shelf_count >= 17:
        c5_score += 5
        c5_parts.append(f"{shelf_count} total shelves")
        
    if furniture_count >= 40:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total items")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file saved")

    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: staging & completion ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: staging & completion ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: missing staging tables, total capacity, or file not saved")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 60

    summary = (
        f"Score: {score}/100 | Items: {furniture_count} total "
        f"(shelves={shelf_count}, desks={desk_count}, tables={table_count}, chairs={chair_count}, lamps={lamp_count}) | "
        f"Walls: +{new_walls} | Doors: +{new_doors} | Labels: +{new_labels}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }