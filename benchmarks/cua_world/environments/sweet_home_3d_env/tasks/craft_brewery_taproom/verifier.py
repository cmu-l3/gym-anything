#!/usr/bin/env python3
"""
Verifier for craft_brewery_taproom task.

Occupation: Hospitality Design Consultant
Industry: Food & Beverage / Architecture

Features required: wall_creation, room_definition, floor_color, door_window_placement, furniture_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Bar zone -- >=3 tables/counters + >=8 chairs/stools
  C2 (20 pts): Communal seating -- >=7 tables + >=24 chairs across the plan (includes C1)
  C3 (20 pts): Walls + doors/windows -- >=3 new walls + >=3 doors/windows
  C4 (20 pts): Lounge + merchandise + decor -- >=3 sofas + >=5 shelves + >=6 lamps + >=4 plants
  C5 (20 pts): Room zones + floor color + total + save -- >=4 rooms + >=3 rooms w/ floor color + >=50 total items + file changed

Wrong-target gate: if total furniture < 10, return score=0 immediately.
"""

import json


def verify_craft_brewery_taproom(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/craft_brewery_taproom_result.json")
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

    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    sofa_count = result.get("sofa_count", 0)
    shelf_count = result.get("shelf_count", 0)
    lamp_count = result.get("lamp_count", 0)
    plant_count = result.get("plant_count", 0)
    room_count = result.get("room_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Bar zone ─────────────────────────────────────────
    if table_count >= 3 and chair_count >= 8:
        score += 20
        feedback_parts.append(f"PASS C1: Bar zone ({table_count} tables/counters, {chair_count} chairs/stools) [+20]")
    elif table_count >= 2 and chair_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Partial bar zone ({table_count} tables, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Bar zone needs >=3 tables/counters and >=8 chairs/stools")

    # ── Criterion 2 (20 pts): Communal seating (Total plan counts) ─────────────
    # Includes C1 requirement (3 tables + 4 tables = 7, 8 chairs + 16 chairs = 24)
    if table_count >= 7 and chair_count >= 24:
        score += 20
        feedback_parts.append(f"PASS C2: Communal seating ({table_count} total tables, {chair_count} total chairs) [+20]")
    elif table_count >= 5 and chair_count >= 16:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Partial communal seating ({table_count} total tables, {chair_count} total chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Communal seating needs >=7 total tables and >=24 total chairs across plan")

    # ── Criterion 3 (20 pts): Walls + doors/windows ────────────────────────────
    if new_walls >= 3 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: Space division ({new_walls} new walls, {new_doors} new doors/windows) [+20]")
    elif new_walls >= 1 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial space division ({new_walls} new walls, {new_doors} new doors/windows) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Need >=3 new partition walls and >=3 doors/windows")

    # ── Criterion 4 (20 pts): Lounge + merchandise + decor ─────────────────────
    c4_score = 0
    c4_parts = []
    if sofa_count >= 3:
        c4_score += 5
        c4_parts.append("sofas ok")
    if shelf_count >= 5:
        c4_score += 5
        c4_parts.append("shelves ok")
    if lamp_count >= 6:
        c4_score += 5
        c4_parts.append("lamps ok")
    if plant_count >= 4:
        c4_score += 5
        c4_parts.append("plants ok")
    score += c4_score
    
    if c4_score == 20:
        feedback_parts.append(f"PASS C4: Lounge/merch/decor complete ({sofa_count} sofas, {shelf_count} shelves, {lamp_count} lamps, {plant_count} plants) [+20]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Lounge/merch/decor partial ({', '.join(c4_parts)}) [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: Missing lounge/merch/decor items")

    # ── Criterion 5 (20 pts): Rooms + floor color + total + save ───────────────
    c5_score = 0
    c5_parts = []
    if room_count >= 4:
        c5_score += 5
        c5_parts.append("rooms defined")
    if rooms_with_floor_color >= 3:
        c5_score += 5
        c5_parts.append("floor colors applied")
    if furniture_count >= 50:
        c5_score += 5
        c5_parts.append(f"total items ({furniture_count}) ok")
    if file_changed:
        c5_score += 5
        c5_parts.append("file saved")
    score += c5_score

    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Rooms and formatting complete [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Rooms/formatting partial ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Missing room definitions, floor colors, or save")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Total Items: {furniture_count} "
        f"(tables={table_count}, chairs={chair_count}, sofas={sofa_count}, "
        f"shelves={shelf_count}, lamps={lamp_count}, rooms={room_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }