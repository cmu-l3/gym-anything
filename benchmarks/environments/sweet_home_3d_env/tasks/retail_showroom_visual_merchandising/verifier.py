#!/usr/bin/env python3
"""
Verifier for retail_showroom_visual_merchandising task.

Occupation: Merchandise Displayer / Visual Merchandiser
Industry: Retail / Fashion

Features required: furniture_placement, room_definition, floor_color, 3d_photo_rendering

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Display fixtures -- >=12 shelves+tables combined
  C2 (20 pts): Room zones with floor color -- >=3 rooms_with_floor_color (partial >=1 -> 10)
  C3 (15 pts): VIP + checkout -- >=3 sofas + >=2 desks + >=2 chairs (partial scoring)
  C4 (25 pts): Ambient decor -- >=8 lamps + >=5 plants (partial >=4+2 -> 12)
  C5 (15 pts): 3D photo exists (5) + >=45 total (5) + file changed (5)

Wrong-target gate: if total furniture < 8, return score=0 immediately.
"""

import json


def verify_retail_showroom_visual_merchandising(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/retail_showroom_visual_merchandising_result.json")
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

    shelf_count = result.get("shelf_count", 0)
    sofa_count = result.get("sofa_count", 0)
    table_count = result.get("table_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    lamp_count = result.get("lamp_count", 0)
    plant_count = result.get("plant_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    photo_found = result.get("photo_found", False)
    file_changed = result.get("file_changed", False)

    # Display fixtures = shelves + tables used as displays
    display_count = shelf_count + table_count

    # ── Criterion 1 (25 pts): Merchandise display floor ───────────────────────
    if display_count >= 12:
        score += 25
        feedback_parts.append(f"PASS C1: display floor ({display_count} fixtures: {shelf_count} shelves + {table_count} tables) [+25]")
    elif display_count >= 6:
        score += 12
        feedback_parts.append(f"PARTIAL C1: partial display ({display_count} fixtures) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: display floor needs >=12 fixtures (got {display_count})")

    # ── Criterion 2 (20 pts): Room zones with floor color ─────────────────────
    if rooms_with_floor_color >= 3:
        score += 20
        feedback_parts.append(f"PASS C2: merchandising zones ({rooms_with_floor_color} rooms with floor color/texture) [+20]")
    elif rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: partial zones ({rooms_with_floor_color} rooms with floor color, need >=3) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=3 rooms with floor color/texture set (got {rooms_with_floor_color})")

    # ── Criterion 3 (15 pts): VIP lounge + checkout counter ───────────────────
    c3_score = 0
    c3_parts = []
    if sofa_count >= 3:
        c3_score += 5
        c3_parts.append(f"{sofa_count} sofas")
    elif sofa_count >= 1:
        c3_score += 2
        c3_parts.append(f"{sofa_count} sofa(s) (partial)")
    if desk_count >= 2:
        c3_score += 5
        c3_parts.append(f"{desk_count} desks/counters")
    elif desk_count >= 1:
        c3_score += 2
        c3_parts.append(f"{desk_count} desk (partial)")
    if chair_count >= 2:
        c3_score += 5
        c3_parts.append(f"{chair_count} chairs")
    elif chair_count >= 1:
        c3_score += 2
        c3_parts.append(f"{chair_count} chair (partial)")
    score += c3_score
    if c3_score == 15:
        feedback_parts.append(f"PASS C3: VIP + checkout ({', '.join(c3_parts)}) [+15]")
    elif c3_score > 0:
        feedback_parts.append(f"PARTIAL C3: partial VIP/checkout ({', '.join(c3_parts)}) [+{c3_score}]")
    else:
        feedback_parts.append(f"FAIL C3: VIP + checkout needs >=3 sofas + >=2 desks + >=2 chairs (got {sofa_count}, {desk_count}, {chair_count})")

    # ── Criterion 4 (25 pts): Ambient lighting and decor ──────────────────────
    if lamp_count >= 8 and plant_count >= 5:
        score += 25
        feedback_parts.append(f"PASS C4: ambient decor ({lamp_count} lamps, {plant_count} plants) [+25]")
    elif lamp_count >= 4 and plant_count >= 2:
        score += 12
        feedback_parts.append(f"PARTIAL C4: partial decor ({lamp_count} lamps, {plant_count} plants) [+12]")
    else:
        feedback_parts.append(f"FAIL C4: ambient decor needs >=8 lamps + >=5 plants (got {lamp_count}, {plant_count})")

    # ── Criterion 5 (15 pts): 3D photo + total count + file changed ──────────
    c5_score = 0
    c5_parts = []
    if photo_found:
        c5_score += 5
        c5_parts.append("3D photo rendered")
    if furniture_count >= 45:
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
        feedback_parts.append(f"FAIL C5: need 3D photo, >=45 items, file changed")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(shelves={shelf_count}, sofas={sofa_count}, tables={table_count}, "
        f"desks={desk_count}, chairs={chair_count}, lamps={lamp_count}, plants={plant_count}) | "
        f"Rooms w/ floor color: {rooms_with_floor_color} | 3D photo: {photo_found}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
