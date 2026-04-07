#!/usr/bin/env python3
"""
Verifier for ski_resort_day_lodge task.

Occupation: Resort Operations Manager
Industry: Hospitality / Tourism

Features required: furniture_placement, wall_creation, room_definition, label_placement, floor_texture

Scoring (total 100 pts, pass threshold 70):
  C1: Rental & Locker Zone (25 pts) -- >= 6 storage units + >= 2 benches/stools.
  C2: Warming Lounge (25 pts) -- >= 1 fireplace/stove + >= 4 lounge seats + >= 1 room with floorColor/floorTexture.
  C3: Cafeteria Zone (20 pts) -- >= 3 tables + >= 10 chairs + >= 2 appliances.
  C4: Walls & Wayfinding (15 pts) -- >= 3 new walls + >= 4 labels.
  C5: Overall Complexity (15 pts) -- File modified + >= 40 total furniture items.

Wrong-target gate: if total furniture < 10, return score=0.
"""

import json


def verify_ski_resort_day_lodge(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/ski_resort_day_lodge_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    file_changed = result.get("file_changed", False)
    
    if furniture_count < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 10 items required to qualify for scoring."
            )
        }
    if not file_changed:
        return {
            "passed": False,
            "score": 0,
            "feedback": "File was not modified. Ensure you save your work with Ctrl+S."
        }

    # Extract metrics
    storage_count = result.get("storage_count", 0)
    bench_count = result.get("bench_count", 0)
    fire_count = result.get("fire_count", 0)
    lounge_count = result.get("lounge_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    appliance_count = result.get("appliance_count", 0)
    new_walls = result.get("new_walls", 0)
    new_labels = result.get("new_labels", 0)

    # ── C1 (25 pts): Rental & Locker Zone ────────────────────────────────────
    if storage_count >= 6 and bench_count >= 2:
        score += 25
        feedback_parts.append(f"PASS C1: Rental/Locker zone furnished ({storage_count} storage units, {bench_count} benches) [+25]")
    elif storage_count >= 3 and bench_count >= 1:
        score += 12
        feedback_parts.append(f"PARTIAL C1: Rental/Locker zone partially furnished ({storage_count} storage, {bench_count} benches) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: Rental/Locker needs >= 6 storage units and >= 2 benches (got {storage_count}, {bench_count})")

    # ── C2 (25 pts): Warming Lounge ──────────────────────────────────────────
    c2_score = 0
    if fire_count >= 1:
        c2_score += 10
    if lounge_count >= 4:
        c2_score += 10
    elif lounge_count >= 2:
        c2_score += 5
    if rooms_with_floor_color >= 1:
        c2_score += 5

    score += c2_score
    if c2_score == 25:
        feedback_parts.append(f"PASS C2: Warming Lounge complete (fireplace, {lounge_count} lounge seats, room defined with floor texture) [+25]")
    elif c2_score > 0:
        feedback_parts.append(f"PARTIAL C2: Warming Lounge incomplete (fire={fire_count}, lounge_seats={lounge_count}, colored_rooms={rooms_with_floor_color}) [+{c2_score}]")
    else:
        feedback_parts.append(f"FAIL C2: Warming Lounge needs fireplace, lounge seats, and a defined room with floor texture.")

    # ── C3 (20 pts): Cafeteria Zone ──────────────────────────────────────────
    if table_count >= 3 and chair_count >= 10 and appliance_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C3: Cafeteria complete ({table_count} tables, {chair_count} chairs, {appliance_count} appliances) [+20]")
    elif table_count >= 1 and chair_count >= 4 and appliance_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Cafeteria partially furnished ({table_count} tables, {chair_count} chairs, {appliance_count} appliances) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Cafeteria needs >= 3 tables, >= 10 chairs, >= 2 appliances.")

    # ── C4 (15 pts): Walls & Wayfinding ──────────────────────────────────────
    c4_score = 0
    if new_walls >= 3:
        c4_score += 7
    elif new_walls >= 1:
        c4_score += 3
        
    if new_labels >= 4:
        c4_score += 8
    elif new_labels >= 2:
        c4_score += 4

    score += c4_score
    if c4_score == 15:
        feedback_parts.append(f"PASS C4: Architecture & Wayfinding ({new_walls} new walls, {new_labels} text labels) [+15]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Architecture & Wayfinding ({new_walls}/3 walls, {new_labels}/4 labels) [+{c4_score}]")
    else:
        feedback_parts.append(f"FAIL C4: Need at least 3 partition walls and 4 wayfinding labels.")

    # ── C5 (15 pts): Overall Complexity ──────────────────────────────────────
    if furniture_count >= 40:
        score += 15
        feedback_parts.append(f"PASS C5: Scale met ({furniture_count} total items) [+15]")
    elif furniture_count >= 25:
        score += 7
        feedback_parts.append(f"PARTIAL C5: Scale partially met ({furniture_count}/40 items) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: Total furniture count low ({furniture_count}/40).")

    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items."
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }