#!/usr/bin/env python3
"""
Verifier for dental_office_conversion task.

Occupation: Dental Practice Consultant
Industry: Healthcare / Dental Practice

Features required: furniture_placement, wall_creation, door_window_placement, label_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Operatory equipment -- >=3 lamps + >=3 shelves/cabinets + >=3 chairs
  C2 (20 pts): Walls + doors -- >=4 new walls + >=4 new doors
  C3 (20 pts): Reception/waiting -- >=1 desk + >=9 total chairs + >=2 tables
  C4 (15 pts): Zone labels -- >=5 new labels/rooms
  C5 (20 pts): Support areas -- >=6 shelves + >=2 toilets + >=2 sinks + >=1 appliance + file changed

Wrong-target gate: if total furniture < 10, return score=0 immediately.
"""

import json


def verify_dental_office_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/dental_office_conversion_result.json")
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
    new_labels = result.get("new_labels", 0) + result.get("new_rooms", 0)
    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    lamp_count = result.get("lamp_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    table_count = result.get("table_count", 0)
    appliance_count = result.get("appliance_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Operatory equipment ──────────────────────────────────────
    c1_score = 0
    c1_parts = []
    if lamp_count >= 3:
        c1_score += 9
        c1_parts.append(f"{lamp_count} lamps")
    else:
        c1_parts.append(f"{lamp_count}/3 lamps")

    if shelf_count >= 3:
        c1_score += 8
        c1_parts.append(f"{shelf_count} shelves")
    else:
        c1_parts.append(f"{shelf_count}/3 shelves")

    if chair_count >= 3:
        c1_score += 8
        c1_parts.append(f"{chair_count} chairs")
    else:
        c1_parts.append(f"{chair_count}/3 chairs")

    if c1_score == 25:
        feedback_parts.append(f"PASS C1: Operatory equipment ({', '.join(c1_parts)}) [+25]")
    elif c1_score > 0:
        feedback_parts.append(f"PARTIAL C1: Operatory equipment ({', '.join(c1_parts)}) [+{c1_score}]")
    else:
        feedback_parts.append("FAIL C1: Operatory equipment missing")
    score += c1_score

    # ── C2 (20 pts): Walls + doors ───────────────────────────────────────────
    c2_score = 0
    if new_walls >= 4 and new_doors >= 4:
        c2_score = 20
        feedback_parts.append(f"PASS C2: Partition walls and doors ({new_walls} walls, {new_doors} doors) [+20]")
    elif new_walls >= 2 and new_doors >= 2:
        c2_score = 10
        feedback_parts.append(f"PARTIAL C2: Walls and doors ({new_walls} walls, {new_doors} doors) [+10]")
    elif new_walls >= 1 or new_doors >= 1:
        c2_score = 5
        feedback_parts.append(f"PARTIAL C2: Walls or doors ({new_walls} walls, {new_doors} doors) [+5]")
    else:
        feedback_parts.append("FAIL C2: Partition walls and doors missing")
    score += c2_score

    # ── C3 (20 pts): Reception/waiting ───────────────────────────────────────
    c3_score = 0
    c3_parts = []
    if desk_count >= 1:
        c3_score += 5
        c3_parts.append(f"{desk_count} desks")
    else:
        c3_parts.append(f"{desk_count}/1 desks")

    if chair_count >= 9:
        c3_score += 10
        c3_parts.append(f"{chair_count} total chairs")
    elif chair_count >= 6:
        c3_score += 5
        c3_parts.append(f"{chair_count}/9 total chairs")
    else:
        c3_parts.append(f"{chair_count}/9 total chairs")

    if table_count >= 2:
        c3_score += 5
        c3_parts.append(f"{table_count} tables")
    else:
        c3_parts.append(f"{table_count}/2 tables")

    if c3_score == 20:
        feedback_parts.append(f"PASS C3: Reception/waiting ({', '.join(c3_parts)}) [+20]")
    elif c3_score > 0:
        feedback_parts.append(f"PARTIAL C3: Reception/waiting ({', '.join(c3_parts)}) [+{c3_score}]")
    else:
        feedback_parts.append("FAIL C3: Reception/waiting missing")
    score += c3_score

    # ── C4 (15 pts): Zone labels ─────────────────────────────────────────────
    if new_labels >= 5:
        score += 15
        feedback_parts.append(f"PASS C4: Zone labels ({new_labels} labels/rooms) [+15]")
    elif new_labels >= 3:
        score += 8
        feedback_parts.append(f"PARTIAL C4: Zone labels ({new_labels}/5 labels/rooms) [+8]")
    elif new_labels >= 1:
        score += 4
        feedback_parts.append(f"PARTIAL C4: Zone labels ({new_labels}/5 labels/rooms) [+4]")
    else:
        feedback_parts.append("FAIL C4: Zone labels missing")

    # ── C5 (20 pts): Support areas + total + file changed ────────────────────
    c5_score = 0
    c5_parts = []

    if shelf_count >= 6:
        c5_score += 4
        c5_parts.append("sterilization shelves")
    if toilet_count >= 2 and sink_count >= 2:
        c5_score += 4
        c5_parts.append("restrooms")
    if appliance_count >= 1:
        c5_score += 4
        c5_parts.append("break room appliance")
    if furniture_count >= 40:
        c5_score += 4
        c5_parts.append("items>=40")
    if file_changed:
        c5_score += 4
        c5_parts.append("file saved")

    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Support areas ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Support areas ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Support areas missing")
    score += c5_score

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items " \
              f"(chairs={chair_count}, desks={desk_count}, shelves={shelf_count}, " \
              f"lamps={lamp_count}, toilets={toilet_count}, sinks={sink_count}, " \
              f"tables={table_count}, appliances={appliance_count})"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }