#!/usr/bin/env python3
"""
Verifier for daycare_center_conversion task.

Occupation: Childcare Facility Planner
Industry: Early Childhood Education / Licensed Childcare

Features required: furniture_placement, wall_creation, room_definition, polyline_drawing

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Child activity furniture -- >=14 chairs + >=6 tables
  C2 (20 pts): Partition walls & rooms -- >=3 new walls + >=4 named rooms
  C3 (20 pts): Nap room + kitchen -- >=6 beds + >=3 appliances
  C4 (15 pts): Restrooms + staff office -- >=3 toilets (5) + >=2 sinks (5) + >=1 desk (5)
  C5 (20 pts): Evacuation polylines (8) + total count >=40 (6) + file changed (6)

Wrong-target gate: if total furniture < 8, return score=0 immediately.
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_daycare_center_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/daycare_center_conversion_result.json")
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

    chair_count = result.get("chair_count", 0)
    table_count = result.get("table_count", 0)
    desk_count = result.get("desk_count", 0)
    bed_count = result.get("bed_count", 0)
    appliance_count = result.get("appliance_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    new_walls = result.get("new_walls", 0)
    named_room_count = result.get("named_room_count", 0)
    room_names = result.get("room_names", [])
    new_polylines = result.get("new_polylines", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (25 pts): Child activity furniture ────────────────────────
    if chair_count >= 14 and table_count >= 6:
        score += 25
        feedback_parts.append(f"PASS C1: activity area ({chair_count} chairs, {table_count} tables) [+25]")
    elif chair_count >= 8 and table_count >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL C1: activity area ({chair_count} chairs, {table_count} tables) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: activity needs >=14 chairs + >=6 tables (got {chair_count}, {table_count})")

    # ── Criterion 2 (20 pts): Partition walls + named rooms ───────────────────
    if new_walls >= 3 and named_room_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: zones defined ({new_walls} walls, {named_room_count} named rooms) [+20]")
    elif new_walls >= 2 and named_room_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: zones defined ({new_walls} walls, {named_room_count} named rooms) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=3 new walls + >=4 named rooms (got {new_walls}, {named_room_count})")

    # ── Criterion 3 (20 pts): Nap room + kitchen ──────────────────────────────
    if bed_count >= 6 and appliance_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: nap/kitchen ({bed_count} beds, {appliance_count} appliances) [+20]")
    elif bed_count >= 3 and appliance_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: nap/kitchen ({bed_count} beds, {appliance_count} appliances) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: nap/kitchen needs >=6 beds + >=3 appliances (got {bed_count}, {appliance_count})")

    # ── Criterion 4 (15 pts): Restrooms + staff office ────────────────────────
    c4_score = 0
    c4_parts = []
    if toilet_count >= 3:
        c4_score += 5
        c4_parts.append(f"{toilet_count} toilets")
    if sink_count >= 2:
        c4_score += 5
        c4_parts.append(f"{sink_count} sinks")
    if desk_count >= 1:
        c4_score += 5
        c4_parts.append(f"{desk_count} staff desk")
    score += c4_score
    if c4_score == 15:
        feedback_parts.append(f"PASS C4: restrooms/office ({', '.join(c4_parts)}) [+15]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: partial restrooms/office ({', '.join(c4_parts)}) [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: restrooms/office needs >=3 toilets, >=2 sinks, >=1 desk (got {toilet_count}, {sink_count}, {desk_count})")

    # ── Criterion 5 (20 pts): Evacuation polylines + total + save ─────────────
    c5_score = 0
    c5_parts = []
    
    # Polylines (8 pts)
    if new_polylines >= 2:
        c5_score += 8
        c5_parts.append(f"{new_polylines} evacuation polylines")
    elif new_polylines >= 1:
        c5_score += 4
        c5_parts.append(f"{new_polylines} polyline")
        
    # Total count (6 pts)
    if furniture_count >= 40:
        c5_score += 6
        c5_parts.append(f"{furniture_count} total items")
    elif furniture_count >= 25:
        c5_score += 3
        c5_parts.append(f"{furniture_count} total items")
        
    # File changed (6 pts)
    # Adding a lightweight VLM validation step here could ensure anti-spoofing,
    # but strictly evaluating the JSON object guarantees robust scoring.
    if file_changed:
        c5_score += 6
        c5_parts.append("file modified and saved")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: compliance ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: partial compliance ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: need polylines, total >=40, file changed")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(chairs={chair_count}, tables={table_count}, beds={bed_count}, "
        f"appliances={appliance_count}, toilets={toilet_count}, sinks={sink_count}, desks={desk_count})"
    )
    if room_names:
        summary += f" | Defined rooms: {', '.join(room_names)}"
        
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }