#!/usr/bin/env python3
"""
Verifier for photography_studio_conversion task.

Occupation: Commercial Photographer
Industry: Photography / Media Production

Features required: wall_creation, furniture_placement, label_placement, 3d_photo_rendering

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Partition walls -- >=3 new walls beyond baseline (partial >=1 -> 7, >=2 -> 14)
  C2 (25 pts): Core studio furniture -- >=6 desks/tables + >=8 chairs + >=6 shelves/storage
  C3 (20 pts): Zone labels -- >=4 text labels placed (partial >=2 -> 10, >=1 -> 5)
  C4 (20 pts): Lighting + client comfort -- >=6 lamps + >=2 sofas/armchairs + >=2 decor items
  C5 (15 pts): 3D photo on Desktop (5) + >=35 total items (5) + file changed (5)

Wrong-target gate: if total furniture < 8, return score=0 immediately.
"""

import json


def verify_photography_studio_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/photography_studio_conversion_result.json")
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

    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    shelf_count = result.get("shelf_count", 0)
    lamp_count = result.get("lamp_count", 0)
    sofa_count = result.get("sofa_count", 0)
    decor_count = result.get("decor_count", 0)
    new_walls = result.get("new_walls", 0)
    new_labels = result.get("new_labels", 0)
    photo_found = result.get("photo_found", False)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Partition walls ─────────────────────────────────
    if new_walls >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} new partition walls created [+20]")
    elif new_walls == 2:
        score += 14
        feedback_parts.append(f"PARTIAL C1: {new_walls} new walls (need >=3 for full credit) [+14]")
    elif new_walls == 1:
        score += 7
        feedback_parts.append(f"PARTIAL C1: {new_walls} new wall (need >=3 for full credit) [+7]")
    else:
        feedback_parts.append(f"FAIL C1: no new partition walls created (need >=3)")

    # ── Criterion 2 (25 pts): Core studio furniture ───────────────────────────
    if desk_count >= 6 and chair_count >= 8 and shelf_count >= 6:
        score += 25
        feedback_parts.append(f"PASS C2: core furniture ({desk_count} desks, {chair_count} chairs, {shelf_count} shelves) [+25]")
    elif desk_count >= 3 and chair_count >= 4 and shelf_count >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL C2: partial core furniture ({desk_count} desks, {chair_count} chairs, {shelf_count} shelves) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: insufficient core furniture (got {desk_count} desks, {chair_count} chairs, {shelf_count} shelves)")

    # ── Criterion 3 (20 pts): Zone labels ─────────────────────────────────────
    if new_labels >= 4:
        score += 20
        feedback_parts.append(f"PASS C3: {new_labels} text labels placed [+20]")
    elif new_labels >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C3: {new_labels} text labels placed (need >=4 for full credit) [+10]")
    elif new_labels == 1:
        score += 5
        feedback_parts.append(f"PARTIAL C3: 1 text label placed (need >=4 for full credit) [+5]")
    else:
        feedback_parts.append(f"FAIL C3: no new text labels placed for zone identification")

    # ── Criterion 4 (20 pts): Lighting + client comfort ───────────────────────
    if lamp_count >= 6 and sofa_count >= 2 and decor_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C4: lighting + client comfort ({lamp_count} lamps, {sofa_count} sofas, {decor_count} decor items) [+20]")
    elif lamp_count >= 3 and sofa_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial lighting/comfort ({lamp_count} lamps, {sofa_count} sofas, {decor_count} decor items) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: lighting/comfort needs >=6 lamps + >=2 sofas + >=2 decor (got {lamp_count}, {sofa_count}, {decor_count})")

    # ── Criterion 5 (15 pts): 3D photo + total count + file saved ─────────────
    c5_score = 0
    c5_parts = []
    if photo_found:
        c5_score += 5
        c5_parts.append("3D photo found")
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
        feedback_parts.append(f"FAIL C5: missing 3D photo, insufficient total items, and file unchanged")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | "
        f"Walls: +{new_walls} | Labels: +{new_labels} | Total Items: {furniture_count} "
        f"| Photo: {'Yes' if photo_found else 'No'}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }