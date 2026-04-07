#!/usr/bin/env python3
"""
Verifier for independent_bookstore_cafe_layout task.

Occupation: Spatial Designer
Industry: Retail / Hospitality

Features required: wall_creation, furniture_placement, label_placement, dimension_annotation

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Retail Shelving & Checkout -- >=10 shelves AND >=1 desk/counter (Partial: 15 pts for >=6 shelves)
  C2 (25 pts): Cafe Seating & Equipment -- >=3 tables AND >=6 chairs AND >=1 appliance (Partial: 15 pts for tables + chairs only)
  C3 (20 pts): Spatial Zoning -- >=2 new walls AND >=3 text labels (Partial: 10 pts for walls OR labels)
  C4 (15 pts): Accessibility Dimensions -- >=2 dimension lines (Partial: 7 pts for 1 dimension line)
  C5 (15 pts): Overall Completion -- File changed (5 pts) + Total items >=30 (10 pts)

Wrong-target gate: if total furniture < 10, return score=0 immediately.
"""

import json

def verify_independent_bookstore_cafe_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/independent_bookstore_cafe_layout_result.json")
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

    shelf_count = result.get("shelf_count", 0)
    desk_count = result.get("desk_count", 0)
    table_count = result.get("table_count", 0)
    chair_count = result.get("chair_count", 0)
    appliance_count = result.get("appliance_count", 0)
    new_walls = result.get("new_walls", 0)
    new_labels = result.get("new_labels", 0)
    new_dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (25 pts): Retail Shelving & Checkout ──────────────────────
    if shelf_count >= 10 and desk_count >= 1:
        score += 25
        feedback_parts.append(f"PASS C1: Retail Zone ({shelf_count} shelves, {desk_count} checkout desk/counter) [+25]")
    elif shelf_count >= 6:
        score += 15
        feedback_parts.append(f"PARTIAL C1: Retail Zone ({shelf_count} shelves, {desk_count} checkout desk/counter) [+15]")
    else:
        feedback_parts.append(f"FAIL C1: Retail Zone needs >=10 shelves and >=1 checkout desk (got {shelf_count} shelves, {desk_count} desk)")

    # ── Criterion 2 (25 pts): Cafe Seating & Equipment ────────────────────────
    if table_count >= 3 and chair_count >= 6 and appliance_count >= 1:
        score += 25
        feedback_parts.append(f"PASS C2: Cafe Zone ({table_count} tables, {chair_count} chairs, {appliance_count} appliances) [+25]")
    elif table_count >= 3 and chair_count >= 6:
        score += 15
        feedback_parts.append(f"PARTIAL C2: Cafe seating but missing appliances ({table_count} tables, {chair_count} chairs, 0 appliances) [+15]")
    else:
        feedback_parts.append(f"FAIL C2: Cafe Zone needs >=3 tables, >=6 chairs, >=1 appliance (got {table_count}t, {chair_count}c, {appliance_count}a)")

    # ── Criterion 3 (20 pts): Spatial Zoning (Walls & Labels) ─────────────────
    if new_walls >= 2 and new_labels >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: Spatial Zoning ({new_walls} partition walls, {new_labels} text labels) [+20]")
    elif new_walls >= 2 or new_labels >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Spatial Zoning ({new_walls} partition walls, {new_labels} text labels) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Spatial Zoning needs >=2 new walls and >=3 text labels (got {new_walls} walls, {new_labels} labels)")

    # ── Criterion 4 (15 pts): Accessibility Dimensions ────────────────────────
    if new_dimensions >= 2:
        score += 15
        feedback_parts.append(f"PASS C4: ADA dimensions ({new_dimensions} dimension lines) [+15]")
    elif new_dimensions >= 1:
        score += 7
        feedback_parts.append(f"PARTIAL C4: ADA dimensions ({new_dimensions} dimension line) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: ADA dimensions needs >=2 dimension lines drawn (got {new_dimensions})")

    # ── Criterion 5 (15 pts): Overall Completion ──────────────────────────────
    c5_score = 0
    c5_parts = []
    if file_changed:
        c5_score += 5
        c5_parts.append("file changed")
    if furniture_count >= 30:
        c5_score += 10
        c5_parts.append(f"total items: {furniture_count} (>=30)")
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Completion ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Completion ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Completion needs saved file and >=30 total items")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} total "
        f"(shelves={shelf_count}, tables={table_count}, chairs={chair_count}, desks={desk_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }