#!/usr/bin/env python3
"""
Verifier for veterinary_clinic_conversion task.

Occupation: Veterinarian
Industry: Veterinary Services

Features required: wall_creation, door_window_placement, furniture_placement, label_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Partition walls + doors -- >=3 new walls AND >=3 new doors
  C2 (20 pts): Reception/waiting area -- >=1 desk + >=6 chairs + >=1 shelf
  C3 (25 pts): Exam + surgery zones -- >=3 tables + >=4 chairs + >=4 shelves + >=1 lamp
  C4 (15 pts): Zone labels -- >=5 labels placed
  C5 (20 pts): Diversity (>=8 distinct furniture types) + total items (>=35) + file changed

Wrong-target gate: if total furniture < 8, return score=0.
"""

import json

def verify_veterinary_clinic_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/veterinary_clinic_conversion_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 8:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 8 items required to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_labels = result.get("new_labels", 0)
    
    desk_count = result.get("desk_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    lamp_count = result.get("lamp_count", 0)
    appliance_count = result.get("appliance_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    
    distinct_types = result.get("distinct_types", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Partition walls + doors ─────────────────────────
    if new_walls >= 3 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} walls and {new_doors} doors added [+20]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {new_walls} walls and {new_doors} doors added (need >=3 each) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: insufficient partitioning/doors ({new_walls} walls, {new_doors} doors)")

    # ── Criterion 2 (20 pts): Reception/waiting area ──────────────────────────
    if desk_count >= 1 and chair_count >= 6 and shelf_count >= 1:
        score += 20
        feedback_parts.append(f"PASS C2: reception/waiting ({desk_count} desks, {chair_count} chairs, {shelf_count} shelves) [+20]")
    elif desk_count >= 1 and chair_count >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C2: reception/waiting ({desk_count} desks, {chair_count} chairs, {shelf_count} shelves) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: reception area needs >=1 desk, >=6 chairs, >=1 shelf")

    # ── Criterion 3 (25 pts): Exam + surgery zones ────────────────────────────
    if table_count >= 3 and chair_count >= 4 and shelf_count >= 4 and lamp_count >= 1:
        score += 25
        feedback_parts.append(f"PASS C3: clinical zones ({table_count} tables, {chair_count} chairs, {shelf_count} shelves, {lamp_count} lamps) [+25]")
    elif table_count >= 1 and chair_count >= 2 and shelf_count >= 2:
        score += 12
        feedback_parts.append(f"PARTIAL C3: clinical zones ({table_count} tables, {chair_count} chairs, {shelf_count} shelves, {lamp_count} lamps) [+12]")
    else:
        feedback_parts.append(f"FAIL C3: clinical zones need >=3 tables, >=4 chairs, >=4 shelves, >=1 lamp")

    # ── Criterion 4 (15 pts): Zone labels ─────────────────────────────────────
    if new_labels >= 5:
        score += 15
        feedback_parts.append(f"PASS C4: {new_labels} text labels placed [+15]")
    elif new_labels >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C4: {new_labels} text labels placed (need >=5) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: only {new_labels} text labels placed (need >=5)")

    # ── Criterion 5 (20 pts): Diversity, total count, and save ────────────────
    c5_score = 0
    c5_parts = []
    
    if distinct_types >= 8:
        c5_score += 7
        c5_parts.append(f"{distinct_types} distinct item types")
    if furniture_count >= 35:
        c5_score += 7
        c5_parts.append(f"{furniture_count} total items")
    if file_changed:
        c5_score += 6
        c5_parts.append("file modified")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: need >=8 item types, >=35 total items, and modified file")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(desks={desk_count}, tables={table_count}, chairs={chair_count}, "
        f"shelves={shelf_count}, lamps={lamp_count}, appliances={appliance_count}, "
        f"toilets={toilet_count}, sinks={sink_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }