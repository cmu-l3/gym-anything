#!/usr/bin/env python3
"""
Verifier for open_plan_office_renovation task.

Occupation: Interior Designer
Industry: Commercial Interior Design

Features required: furniture_placement, room_definition, door_window_placement, floor_color

Scoring (total 100 pts, pass threshold 70):
  Criterion 1 (20 pts): Room zones -- >=3 new rooms defined with names or floor colors
  Criterion 2 (25 pts): Office furniture -- >=8 desks + >=8 chairs
  Criterion 3 (20 pts): Doors + reception decor -- >=2 doors/windows placed + >=3 decor items
  Criterion 4 (20 pts): Lounge/kitchenette -- >=1 sofa + >=1 table + >=2 appliances
  Criterion 5 (15 pts): Total >=35, distinct types >=10, file changed

Wrong-target gate: if total furniture < 8, return score=0 immediately.
"""

import json


def verify_open_plan_office_renovation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/open_plan_office_renovation_result.json")
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

    new_rooms = result.get("new_rooms", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    sofa_count = result.get("sofa_count", 0)
    table_count = result.get("table_count", 0)
    bookcase_count = result.get("bookcase_count", 0)
    appliance_count = result.get("appliance_count", 0)
    decor_count = result.get("decor_count", 0)
    door_window_count = result.get("door_window_count", 0)
    new_doors = result.get("new_doors", 0)
    distinct_types = result.get("distinct_types", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Room zones ────────────────────────────────────
    # Requires >=3 new room definitions with names or floor colors applied
    named_or_colored = max(len(room_names), rooms_with_floor_color)
    c1_rooms = max(new_rooms, named_or_colored)
    if c1_rooms >= 3 and rooms_with_floor_color >= 2:
        score += 20
        feedback_parts.append(
            f"PASS C1: room zones ({c1_rooms} rooms, {len(room_names)} named, "
            f"{rooms_with_floor_color} with floor color) [+20]"
        )
    elif c1_rooms >= 2 or rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(
            f"PARTIAL C1: some zones ({c1_rooms} rooms, {len(room_names)} named, "
            f"{rooms_with_floor_color} with floor color) [+10]"
        )
    else:
        feedback_parts.append(
            f"FAIL C1: need >=3 room zones with names/floor colors "
            f"(got {c1_rooms} rooms, {rooms_with_floor_color} colored)"
        )

    # ── Criterion 2 (25 pts): Office furniture ──────────────────────────────
    if desk_count >= 8 and chair_count >= 8:
        score += 25
        feedback_parts.append(
            f"PASS C2: office furniture ({desk_count} desks, {chair_count} chairs) [+25]"
        )
    elif desk_count >= 4 and chair_count >= 4:
        score += 12
        feedback_parts.append(
            f"PARTIAL C2: partial office ({desk_count} desks, {chair_count} chairs) [+12]"
        )
    else:
        feedback_parts.append(
            f"FAIL C2: office needs >=8 desks + >=8 chairs "
            f"(got {desk_count}, {chair_count})"
        )

    # ── Criterion 3 (20 pts): Doors + reception decor ───────────────────────
    doors_ok = new_doors >= 2 or door_window_count >= 2
    decor_ok = decor_count >= 3
    if doors_ok and decor_ok:
        score += 20
        feedback_parts.append(
            f"PASS C3: doors/decor ({door_window_count} doors/windows total, "
            f"{new_doors} new, {decor_count} decor) [+20]"
        )
    elif doors_ok or decor_ok:
        score += 10
        feedback_parts.append(
            f"PARTIAL C3: {'doors OK' if doors_ok else 'decor OK'} but "
            f"{'need >=3 decor' if not decor_ok else 'need >=2 doors/windows'} "
            f"(doors={door_window_count}, decor={decor_count}) [+10]"
        )
    else:
        feedback_parts.append(
            f"FAIL C3: need >=2 doors/windows + >=3 decor "
            f"(got {door_window_count} doors, {decor_count} decor)"
        )

    # ── Criterion 4 (20 pts): Lounge/kitchenette ───────────────────────────
    if sofa_count >= 1 and table_count >= 1 and appliance_count >= 2:
        score += 20
        feedback_parts.append(
            f"PASS C4: lounge ({sofa_count} sofas, {table_count} tables, "
            f"{appliance_count} appliances) [+20]"
        )
    elif sofa_count >= 1 or (table_count >= 1 and appliance_count >= 1):
        score += 10
        feedback_parts.append(
            f"PARTIAL C4: partial lounge ({sofa_count} sofas, {table_count} tables, "
            f"{appliance_count} appliances) [+10]"
        )
    else:
        feedback_parts.append(
            f"FAIL C4: lounge needs >=1 sofa + >=1 table + >=2 appliances "
            f"(got {sofa_count}, {table_count}, {appliance_count})"
        )

    # ── Criterion 5 (15 pts): Diversity + total count + file changed ───────
    c5_score = 0
    c5_parts = []
    if distinct_types >= 10:
        c5_score += 5
        c5_parts.append(f"{distinct_types} distinct types")
    if furniture_count >= 35:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total items")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(
            f"FAIL C5: need >=10 types, >=35 items, file changed "
            f"(got {distinct_types} types, {furniture_count} items, changed={file_changed})"
        )

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(desks={desk_count}, chairs={chair_count}, sofas={sofa_count}, "
        f"tables={table_count}, bookcases={bookcase_count}, appliances={appliance_count}, "
        f"decor={decor_count}) | Rooms: {result.get('room_count', 0)} "
        f"(new={new_rooms}, colored={rooms_with_floor_color}) | "
        f"Doors/Windows: {door_window_count} (new={new_doors})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
