#!/usr/bin/env python3
"""
Verifier for police_precinct_conversion task.

Occupation: Municipal Architect
Industry: Government / Law Enforcement Infrastructure

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Workspaces (Bullpen & Reception) -- >= 6 desks/tables + >= 8 chairs
  C2 (20 pts): Holding Cells -- >= 2 beds/cots + >= 2 toilets
  C3 (20 pts): Structural Mods -- >= 4 new walls + >= 3 new doors
  C4 (15 pts): Zoning & Annotations -- >= 4 new room definitions or text labels
  C5 (25 pts): Render photo exists (10) + Total items >= 35 (10) + File changed (5)

Wrong-target gate: if total furniture count < 10, return score=0 immediately.
"""

import json


def verify_police_precinct_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/police_precinct_conversion_result.json")
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
                "At least 10 items required to qualify for scoring. Ensure the file was saved."
            )
        }

    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    bed_count = result.get("bed_count", 0)
    toilet_count = result.get("toilet_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    zone_ids = result.get("zone_identifiers", 0)
    photo_found = result.get("photo_found", False)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (20 pts): Workspaces (Bullpen + Reception + Interrogation) ─
    if desk_count >= 6 and chair_count >= 8:
        score += 20
        feedback_parts.append(f"PASS C1: Workspaces ({desk_count} desks, {chair_count} chairs) [+20]")
    elif desk_count >= 3 and chair_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Partial Workspaces ({desk_count} desks, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Workspaces need >=6 desks & >=8 chairs (got {desk_count}, {chair_count})")

    # ── Criterion 2 (20 pts): Holding Cells ────────────────────────────────────
    if bed_count >= 2 and toilet_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C2: Holding Cells ({bed_count} beds/cots, {toilet_count} toilets) [+20]")
    elif bed_count >= 1 and toilet_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Partial Holding Cells ({bed_count} beds, {toilet_count} toilets) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Holding Cells need >=2 beds & >=2 toilets (got {bed_count}, {toilet_count})")

    # ── Criterion 3 (20 pts): Structural Mods (Walls + Doors) ──────────────────
    if new_walls >= 4 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: Structural Mods ({new_walls} new walls, {new_doors} new doors) [+20]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial Structural Mods ({new_walls} new walls, {new_doors} new doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Structural Mods need >=4 new walls & >=3 new doors (got {new_walls}, {new_doors})")

    # ── Criterion 4 (15 pts): Zoning & Annotations ─────────────────────────────
    if zone_ids >= 4:
        score += 15
        feedback_parts.append(f"PASS C4: Zoning ({zone_ids} named rooms or labels) [+15]")
    elif zone_ids >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C4: Partial Zoning ({zone_ids} identifiers) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: Zoning needs >=4 named rooms or labels (got {zone_ids})")

    # ── Criterion 5 (25 pts): Render, Scope & Save ─────────────────────────────
    c5_score = 0
    c5_parts = []
    if photo_found:
        c5_score += 10
        c5_parts.append("3D photo generated")
    if furniture_count >= 35:
        c5_score += 10
        c5_parts.append(f"Total furniture >= 35 ({furniture_count})")
    if file_changed:
        c5_score += 5
        c5_parts.append("File modified & saved")

    score += c5_score
    if c5_score == 25:
        feedback_parts.append(f"PASS C5: Render, Scope & Save ({', '.join(c5_parts)}) [+25]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Render, Scope & Save ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Missing 3D photo, scope < 35, or file unchanged")

    # ── Final Verdict ──────────────────────────────────────────────────────────
    passed = score >= 70
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items | Walls added: {new_walls} | Render: {'Yes' if photo_found else 'No'}"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }