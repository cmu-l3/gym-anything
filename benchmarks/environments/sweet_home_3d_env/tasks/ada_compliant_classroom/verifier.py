#!/usr/bin/env python3
"""
Verifier for ada_compliant_classroom task.

Occupation: Architect
Industry: Educational Architecture

This task exercises 4 Sweet Home 3D features:
  - Furniture placement (chairs, desks, shelves, restroom fixtures)
  - Wall creation (partition walls for classroom zones)
  - Door/window placement (wheelchair-accessible doorways)
  - Dimension annotation (clearance documentation for ADA review)

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Student seating -- >=24 chairs + >=12 desks
  C2 (20 pts): Walls + doors -- >=2 new walls + >=2 doors/windows
  C3 (20 pts): Resource zone -- >=4 shelves + >=1 instructor desk
  C4 (15 pts): Dimension annotations -- >=2 new dimension lines
  C5 (20 pts): Restrooms (>=2 toilets, >=2 sinks) + total>=50 + file changed

Wrong-target gate: furniture_count < 10 -> score=0.
"""

import json


def verify_ada_compliant_classroom(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/ada_compliant_classroom_result.json")
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

    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    toilet_count = result.get("toilet_count", 0)
    sink_count = result.get("sink_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Student seating ─────────────────────────────────────────
    if chair_count >= 24 and desk_count >= 12:
        score += 25
        feedback_parts.append(
            f"PASS C1: student seating ({chair_count} chairs, {desk_count} desks) [+25]"
        )
    elif chair_count >= 16 and desk_count >= 8:
        score += 15
        feedback_parts.append(
            f"PARTIAL C1: partial seating ({chair_count} chairs, {desk_count} desks) [+15]"
        )
    elif chair_count >= 8 and desk_count >= 4:
        score += 8
        feedback_parts.append(
            f"PARTIAL C1: minimal seating ({chair_count} chairs, {desk_count} desks) [+8]"
        )
    else:
        feedback_parts.append(
            f"FAIL C1: student seating needs >=24 chairs + >=12 desks "
            f"(got {chair_count}, {desk_count})"
        )

    # ── C2 (20 pts): Walls + doors ───────────────────────────────────────────
    if new_walls >= 2 and new_doors >= 2:
        score += 20
        feedback_parts.append(
            f"PASS C2: walls + doors ({new_walls} new walls, {new_doors} new doors/windows) [+20]"
        )
    elif new_walls >= 1 and new_doors >= 1:
        score += 10
        feedback_parts.append(
            f"PARTIAL C2: some walls/doors ({new_walls} walls, {new_doors} doors) [+10]"
        )
    elif new_walls >= 1 or new_doors >= 1:
        score += 5
        feedback_parts.append(
            f"PARTIAL C2: minimal ({new_walls} walls, {new_doors} doors) [+5]"
        )
    else:
        feedback_parts.append(
            f"FAIL C2: need >=2 new walls + >=2 doors/windows "
            f"(got {new_walls} walls, {new_doors} doors)"
        )

    # ── C3 (20 pts): Resource zone + instructor desk ─────────────────────────
    if shelf_count >= 4 and desk_count >= 1:
        score += 20
        feedback_parts.append(
            f"PASS C3: resource zone ({shelf_count} shelves, {desk_count} desks incl. instructor) [+20]"
        )
    elif shelf_count >= 2:
        score += 10
        feedback_parts.append(
            f"PARTIAL C3: partial resource zone ({shelf_count} shelves) [+10]"
        )
    else:
        feedback_parts.append(
            f"FAIL C3: resource zone needs >=4 shelves + >=1 instructor desk "
            f"(got {shelf_count} shelves, {desk_count} desks)"
        )

    # ── C4 (15 pts): Dimension annotations ───────────────────────────────────
    if new_dimensions >= 2:
        score += 15
        feedback_parts.append(
            f"PASS C4: dimension annotations ({new_dimensions} new dimension lines) [+15]"
        )
    elif new_dimensions >= 1:
        score += 7
        feedback_parts.append(
            f"PARTIAL C4: partial annotations ({new_dimensions} dimension line) [+7]"
        )
    else:
        feedback_parts.append(
            f"FAIL C4: need >=2 new dimension lines for ADA clearance review "
            f"(got {new_dimensions})"
        )

    # ── C5 (20 pts): Restrooms + total count + file changed ──────────────────
    c5_score = 0
    c5_parts = []
    if toilet_count >= 2:
        c5_score += 5
        c5_parts.append(f"{toilet_count} toilets")
    if sink_count >= 2:
        c5_score += 5
        c5_parts.append(f"{sink_count} sinks")
    if furniture_count >= 50:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total items")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(
            f"FAIL C5: need >=2 toilets, >=2 sinks, >=50 items, file changed"
        )

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(chairs={chair_count}, desks={desk_count}, shelves={shelf_count}, "
        f"toilets={toilet_count}, sinks={sink_count}) | "
        f"Walls={new_walls}, Doors={new_doors}, Dimensions={new_dimensions}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
