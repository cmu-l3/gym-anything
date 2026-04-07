#!/usr/bin/env python3
"""
Verifier for courtroom_layout_design task.

Occupation: Court Administrator
Industry: Government / Judicial

Features required: wall creation, door placement, furniture placement, labels.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Judge's bench -- >=1 desk, >=1 chair, >=2 shelves/cabinets
  C2 (25 pts): Seating (jury + gallery) -- >=22 chairs
  C3 (20 pts): Counsel/Witness/Clerk -- >=3 desks/tables, >=7 chairs
               (Note: Verified cumulatively: desks >= 4, chairs >= 30)
  C4 (20 pts): Walls & Doors -- >=3 new walls, >=3 doors placed
  C5 (15 pts): Labels >= 4, Total Items >= 35, File changed from baseline

Wrong-target gate: total_furniture < 10 -> score=0 immediately.
"""

import json


def verify_courtroom_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/courtroom_layout_design_result.json")
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
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_labels = result.get("new_labels", 0)
    file_changed = result.get("file_changed", False)

    # We evaluate cumulative counts to handle overlapping requirements gracefully.
    # Total required chairs = 1 (judge) + 22 (jury/gallery) + 7 (counsel/witness/clerk) = 30
    # Total required desks = 1 (judge) + 3 (counsel/witness/clerk) = 4

    # ── C1 (20 pts): Judge's Bench Area ───────────────────────────────────────
    if desk_count >= 1 and chair_count >= 1 and shelf_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C1: Judge's area requirements met (desk, chair, >=2 shelves) [+20]")
    elif desk_count >= 1 and chair_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Judge's area missing shelves (got {desk_count} desk, {chair_count} chair, {shelf_count} shelves) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Judge's area needs >=1 desk, >=1 chair, >=2 shelves")

    # ── C2 (25 pts): Jury + Gallery Seating ───────────────────────────────────
    if chair_count >= 22:
        score += 25
        feedback_parts.append(f"PASS C2: Seating requirements met ({chair_count} total chairs >= 22 base requirement) [+25]")
    elif chair_count >= 16:
        score += 15
        feedback_parts.append(f"PARTIAL C2: Insufficient seating ({chair_count} chairs, need >=22) [+15]")
    elif chair_count >= 10:
        score += 8
        feedback_parts.append(f"PARTIAL C2: Poor seating capacity ({chair_count} chairs, need >=22) [+8]")
    else:
        feedback_parts.append(f"FAIL C2: Severely insufficient seating ({chair_count} chairs)")

    # ── C3 (20 pts): Counsel/Witness/Clerk ────────────────────────────────────
    # They require >=3 desks/tables and >=7 chairs, bringing overall totals to >=4 desks, >=30 chairs
    if desk_count >= 4 and chair_count >= 30:
        score += 20
        feedback_parts.append(f"PASS C3: Additional zones fully furnished (>=4 desks, >=30 chairs overall) [+20]")
    elif desk_count >= 3 and chair_count >= 25:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Additional zones partially furnished ({desk_count} desks, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Counsel/Witness/Clerk zones lack adequate furniture (need >=4 desks, >=30 chairs overall)")

    # ── C4 (20 pts): Walls and Doors ──────────────────────────────────────────
    if new_walls >= 3 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C4: Proper zone separation ({new_walls} new walls, {new_doors} doors) [+20]")
    elif new_walls >= 2 and new_doors >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Incomplete separation ({new_walls} walls, {new_doors} doors) [+10]")
    elif new_walls >= 1 or new_doors >= 1:
        score += 5
        feedback_parts.append(f"PARTIAL C4: Minimal separation ({new_walls} walls, {new_doors} doors) [+5]")
    else:
        feedback_parts.append(f"FAIL C4: Missing partition walls or doors (need >=3 each)")

    # ── C5 (15 pts): Labels, Total count, and File check ──────────────────────
    c5_score = 0
    c5_parts = []
    
    if new_labels >= 4:
        c5_score += 5
        c5_parts.append(f"{new_labels} labels")
    if furniture_count >= 35:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total items")
    if file_changed:
        c5_score += 5
        c5_parts.append("file saved")

    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: Met all metadata requirements ({', '.join(c5_parts)}) [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Met some metadata requirements ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Missing labels, insufficient total items, or file unsaved")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Items: {furniture_count} "
        f"(Chairs: {chair_count}, Desks/Tables: {desk_count}, Shelves: {shelf_count}, "
        f"Walls: {new_walls}, Doors: {new_doors}, Labels: {new_labels})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }