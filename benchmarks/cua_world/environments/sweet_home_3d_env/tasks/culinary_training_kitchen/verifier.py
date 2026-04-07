#!/usr/bin/env python3
"""
Verifier for culinary_training_kitchen task.

Occupation: Culinary School Director / Commercial Kitchen Designer
Industry: Culinary Education / Food Service

Features required: furniture_placement, wall_creation, door_window_placement, room_definition, dimension_annotation

Scoring (total 100 pts, pass threshold 70):
  C1 (15 pts): Partitioning & Egress -- >= 4 new walls + >= 3 doors/windows beyond baseline
  C2 (25 pts): Teaching Kitchen Stations -- >= 9 ovens/cookers + >= 9 prep tables/counters
  C3 (15 pts): Lecture Room Setup -- >= 12 chairs + >= 1 desk/table
  C4 (20 pts): Pantry & Sanitation -- >= 6 shelves/cabinets + >= 3 refrigerators + >= 4 sinks
  C5 (15 pts): Documentation -- >= 4 named rooms/labels + >= 2 dimension lines
  C6 (10 pts): Overall Density & Save -- Total furniture count >= 50 + file updated

Wrong-target gate: if total furniture < 20, return score=0 immediately.
"""

import json


def verify_culinary_training_kitchen(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/culinary_training_kitchen_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 20:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 20 items required to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    oven_count = result.get("oven_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    fridge_count = result.get("fridge_count", 0)
    sink_count = result.get("sink_count", 0)
    dishwasher_count = result.get("dishwasher_count", 0)
    new_dimensions = result.get("new_dimensions", 0)
    zone_identifiers = result.get("zone_identifiers", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (15 pts): Partitioning & Egress ────────────────────────────────────
    if new_walls >= 4 and new_doors >= 3:
        score += 15
        feedback_parts.append(f"PASS C1: Partitioning & Egress ({new_walls} walls, {new_doors} doors) [+15]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C1: Partial Partitioning ({new_walls} walls, {new_doors} doors) [+7]")
    else:
        feedback_parts.append(f"FAIL C1: Requires >= 4 new walls and >= 3 doors/windows (got {new_walls} walls, {new_doors} doors)")

    # ── C2 (25 pts): Teaching Kitchen Stations ────────────────────────────────
    # We require 8 student stations + 1 instructor station = 9 ovens + 9 prep tables
    if oven_count >= 9 and table_count >= 9:
        score += 25
        feedback_parts.append(f"PASS C2: Teaching Kitchen Stations ({oven_count} ovens, {table_count} tables/counters) [+25]")
    elif oven_count >= 5 and table_count >= 5:
        score += 12
        feedback_parts.append(f"PARTIAL C2: Partial Kitchen Stations ({oven_count} ovens, {table_count} tables) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: Teaching Kitchen needs >= 9 ovens and >= 9 tables/counters (got {oven_count}, {table_count})")

    # ── C3 (15 pts): Lecture Room Setup ───────────────────────────────────────
    # Requires 12 chairs and at least 1 extra table/desk for instructor (total tables already counted in C2, but we assume if table_count is high enough it covers both)
    # To be precise, we just require chairs >= 12, as the table constraint is shared.
    if chair_count >= 12 and table_count >= 10: # 9 for kitchen + 1 for lecture
        score += 15
        feedback_parts.append(f"PASS C3: Lecture Room Setup ({chair_count} chairs) [+15]")
    elif chair_count >= 6:
        score += 7
        feedback_parts.append(f"PARTIAL C3: Partial Lecture Room ({chair_count} chairs) [+7]")
    else:
        feedback_parts.append(f"FAIL C3: Lecture Room needs >= 12 chairs (got {chair_count})")

    # ── C4 (20 pts): Pantry & Sanitation ──────────────────────────────────────
    # Needs >= 6 shelves, >= 3 fridges, >= 4 sinks
    c4_targets_met = 0
    c4_components = []
    if shelf_count >= 6:
        c4_targets_met += 1
        c4_components.append(f"{shelf_count} shelves")
    if fridge_count >= 3:
        c4_targets_met += 1
        c4_components.append(f"{fridge_count} fridges")
    if sink_count >= 4:
        c4_targets_met += 1
        c4_components.append(f"{sink_count} sinks")

    if c4_targets_met == 3:
        score += 20
        feedback_parts.append(f"PASS C4: Pantry & Sanitation ({', '.join(c4_components)}) [+20]")
    elif c4_targets_met == 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Pantry & Sanitation missing 1 target ({', '.join(c4_components)}) [+10]")
    elif c4_targets_met == 1:
        score += 5
        feedback_parts.append(f"PARTIAL C4: Pantry & Sanitation missing 2 targets ({', '.join(c4_components)}) [+5]")
    else:
        feedback_parts.append(f"FAIL C4: Pantry & Sanitation needs >= 6 shelves, >= 3 fridges, >= 4 sinks (got {shelf_count}, {fridge_count}, {sink_count})")

    # ── C5 (15 pts): Documentation ────────────────────────────────────────────
    # Needs >= 4 named rooms/labels, >= 2 dimension lines
    if zone_identifiers >= 4 and new_dimensions >= 2:
        score += 15
        feedback_parts.append(f"PASS C5: Documentation ({zone_identifiers} zone identifiers, {new_dimensions} dimension lines) [+15]")
    elif zone_identifiers >= 2 or new_dimensions >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C5: Partial Documentation ({zone_identifiers} zone identifiers, {new_dimensions} dimension lines) [+7]")
    else:
        feedback_parts.append(f"FAIL C5: Documentation needs >= 4 zone identifiers and >= 2 dimension lines (got {zone_identifiers}, {new_dimensions})")

    # ── C6 (10 pts): Overall Density & Save ───────────────────────────────────
    if furniture_count >= 50 and file_changed:
        score += 10
        feedback_parts.append(f"PASS C6: Density & Save (Total furniture: {furniture_count}, file modified) [+10]")
    elif furniture_count >= 30 and file_changed:
        score += 5
        feedback_parts.append(f"PARTIAL C6: Density & Save (Total furniture: {furniture_count}, file modified) [+5]")
    else:
        feedback_parts.append(f"FAIL C6: Density & Save (Total furniture: {furniture_count}, file modified: {file_changed})")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} | Ovens: {oven_count} | Tables: {table_count} | "
        f"Chairs: {chair_count} | Shelves: {shelf_count} | Fridges: {fridge_count} | Sinks: {sink_count}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }