#!/usr/bin/env python3
"""
Verifier for emergency_shelter_layout task.

Occupation: Urban/Regional Planner
Industry: Emergency Management / Government

Features required: furniture_placement, wall_creation, door_window_placement, label_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Sleeping dormitory -- >=30 beds/cots
                  partial: >=20 -> 15 pts, >=10 -> 8 pts
  C2 (20 pts): Partition walls + doors -- >=3 new walls + >=2 doors
                  partial: >=1 wall + >=1 door -> 10 pts
  C3 (20 pts): Dining/distribution hall -- >=6 tables + >=30 chairs
                  partial: >=3 tables + >=15 chairs -> 10 pts
  C4 (15 pts): Zone labels -- >=3 labels or named rooms (zone_identifiers)
                  partial: >=1 -> 7 pts
  C5 (20 pts): Admin + sanitation + storage:
                  >=4 desks (5 pts), >=3 toilets+sinks (5 pts),
                  >=6 shelves (5 pts), file changed (5 pts)

Wrong-target gate: if total furniture < 10, return score=0 immediately.
"""

import json


def verify_emergency_shelter_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/emergency_shelter_layout_result.json")
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

    bed_count = result.get("bed_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    shelf_count = result.get("shelf_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    zone_identifiers = result.get("zone_identifiers", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Sleeping dormitory ───────────────────────────────────────
    if bed_count >= 30:
        score += 25
        feedback_parts.append(f"PASS C1: dormitory ({bed_count} beds/cots) [+25]")
    elif bed_count >= 20:
        score += 15
        feedback_parts.append(f"PARTIAL C1: partial dormitory ({bed_count} beds, need 30) [+15]")
    elif bed_count >= 10:
        score += 8
        feedback_parts.append(f"PARTIAL C1: minimal dormitory ({bed_count} beds, need 30) [+8]")
    else:
        feedback_parts.append(f"FAIL C1: dormitory needs >=30 beds (got {bed_count})")

    # ── C2 (20 pts): Partition walls + doors ──────────────────────────────────
    if new_walls >= 3 and new_doors >= 2:
        score += 20
        feedback_parts.append(f"PASS C2: partitions ({new_walls} new walls, {new_doors} doors) [+20]")
    elif new_walls >= 1 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: some partitions ({new_walls} walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=3 new walls + >=2 doors (got {new_walls} walls, {new_doors} doors)")

    # ── C3 (20 pts): Dining/distribution hall ─────────────────────────────────
    if table_count >= 6 and chair_count >= 30:
        score += 20
        feedback_parts.append(f"PASS C3: dining hall ({table_count} tables, {chair_count} chairs) [+20]")
    elif table_count >= 3 and chair_count >= 15:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial dining ({table_count} tables, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: dining hall needs >=6 tables + >=30 chairs (got {table_count}, {chair_count})")

    # ── C4 (15 pts): Zone labels ──────────────────────────────────────────────
    if zone_identifiers >= 3:
        score += 15
        feedback_parts.append(f"PASS C4: zone labels ({zone_identifiers} zone identifiers) [+15]")
    elif zone_identifiers >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C4: some zone labels ({zone_identifiers} identifiers, need >=3) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: no zone labels or named rooms placed (need >=3)")

    # ── C5 (20 pts): Admin + sanitation + storage + file changed ──────────────
    c5_score = 0
    c5_parts = []
    if desk_count >= 4:
        c5_score += 5
        c5_parts.append(f"{desk_count} desks")
    elif desk_count >= 2:
        c5_score += 2
        c5_parts.append(f"{desk_count} desks (partial)")
    if toilet_count >= 3 and sink_count >= 3:
        c5_score += 5
        c5_parts.append(f"{toilet_count} toilets + {sink_count} sinks")
    elif toilet_count >= 1 and sink_count >= 1:
        c5_score += 2
        c5_parts.append(f"{toilet_count} toilets + {sink_count} sinks (partial)")
    if shelf_count >= 6:
        c5_score += 5
        c5_parts.append(f"{shelf_count} storage units")
    elif shelf_count >= 3:
        c5_score += 2
        c5_parts.append(f"{shelf_count} storage units (partial)")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: need >=4 desks, >=3 toilets+sinks, >=6 shelves, file changed")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(beds={bed_count}, tables={table_count}, chairs={chair_count}, "
        f"desks={desk_count}, toilets={toilet_count}, sinks={sink_count}, shelves={shelf_count}) | "
        f"Walls: {new_walls} new | Doors: {new_doors} new | Zone IDs: {zone_identifiers}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
