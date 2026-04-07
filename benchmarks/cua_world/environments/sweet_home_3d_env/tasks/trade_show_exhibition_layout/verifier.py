#!/usr/bin/env python3
"""
Verifier for trade_show_exhibition_layout task.

Occupation: Event Planner
Industry: Events / Trade Shows

Features required: furniture_placement, wall_creation, dimension_annotation, label_placement

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Booth partitions -- >=8 new walls (partial >=4 -> 10 pts)
  C2 (25 pts): Vendor furnishings -- >=8 tables, >=16 chairs, >=8 display units (proportional)
  C3 (15 pts): Registration area -- >=2 desks/counters, total chairs >=18
  C4 (20 pts): Code dimensions -- >=2 dimension lines (partial >=1 -> 10 pts)
  C5 (20 pts): Labels & Save -- >=6 labels/rooms + file changed

Wrong-target gate: if total furniture < 10, return score=0.
"""

import json


def verify_trade_show_exhibition_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/trade_show_exhibition_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

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
    table_count = result.get("table_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    display_count = result.get("display_count", 0)
    new_dimensions = result.get("new_dimensions", 0)
    zone_identifiers = result.get("zone_identifiers", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Booth partitions ─────────────────────────────────────────
    if new_walls >= 8:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} new partition walls created for booths [+20]")
    elif new_walls >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {new_walls} new walls (need >=8 for full booth separation) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: need >=8 new walls to partition booths (got {new_walls})")

    # ── C2 (25 pts): Vendor furnishings ───────────────────────────────────────
    c2_score = 0
    c2_parts = []
    
    if table_count >= 8:
        c2_score += 10
        c2_parts.append(f"{table_count} tables")
    elif table_count >= 4:
        c2_score += 5
        c2_parts.append(f"{table_count} tables (partial)")
        
    if chair_count >= 16:
        c2_score += 10
        c2_parts.append(f"{chair_count} chairs")
    elif chair_count >= 8:
        c2_score += 5
        c2_parts.append(f"{chair_count} chairs (partial)")
        
    if display_count >= 8:
        c2_score += 5
        c2_parts.append(f"{display_count} displays")
    elif display_count >= 4:
        c2_score += 2
        c2_parts.append(f"{display_count} displays (partial)")

    score += c2_score
    if c2_score == 25:
        feedback_parts.append(f"PASS C2: vendor furnishings complete ({', '.join(c2_parts)}) [+25]")
    elif c2_score > 0:
        feedback_parts.append(f"PARTIAL C2: vendor furnishings ({', '.join(c2_parts)}) [+{c2_score}]")
    else:
        feedback_parts.append(f"FAIL C2: insufficient tables, chairs, or display units for vendors")

    # ── C3 (15 pts): Registration area ────────────────────────────────────────
    c3_score = 0
    c3_parts = []
    if desk_count >= 2:
        c3_score += 10
        c3_parts.append(f"{desk_count} desks")
    elif desk_count >= 1:
        c3_score += 5
        c3_parts.append(f"{desk_count} desk (partial)")
        
    if chair_count >= 18:
        c3_score += 5
        c3_parts.append(f"total chairs >= 18")
        
    score += c3_score
    if c3_score == 15:
        feedback_parts.append(f"PASS C3: registration area complete ({', '.join(c3_parts)}) [+15]")
    elif c3_score > 0:
        feedback_parts.append(f"PARTIAL C3: registration area ({', '.join(c3_parts)}) [+{c3_score}]")
    else:
        feedback_parts.append("FAIL C3: need >=2 desks/counters and additional seating for registration")

    # ── C4 (20 pts): Code dimensions ──────────────────────────────────────────
    if new_dimensions >= 2:
        score += 20
        feedback_parts.append(f"PASS C4: {new_dimensions} dimension lines placed for fire code clearances [+20]")
    elif new_dimensions >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: {new_dimensions} dimension line placed (need >=2) [+10]")
    else:
        feedback_parts.append("FAIL C4: no dimension lines placed to document aisle widths")

    # ── C5 (20 pts): Labels & Save ────────────────────────────────────────────
    c5_score = 0
    c5_parts = []
    if zone_identifiers >= 6:
        c5_score += 10
        c5_parts.append(f"{zone_identifiers} zone labels/rooms")
    elif zone_identifiers >= 3:
        c5_score += 5
        c5_parts.append(f"{zone_identifiers} zone labels/rooms (partial)")
        
    if file_changed:
        c5_score += 10
        c5_parts.append("file modified and saved")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: labeling and save complete ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: labeling/save status ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: file not changed and insufficient labels")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} total "
        f"(walls={new_walls}, tables={table_count}, desks={desk_count}, "
        f"chairs={chair_count}, displays={display_count}, dims={new_dimensions}, labels={zone_identifiers})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }