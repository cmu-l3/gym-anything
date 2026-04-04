#!/usr/bin/env python3
"""
Verifier for solar_facility_site_plan task.

Occupation: Solar Energy Systems Engineer
Industry: Renewable Energy / Solar Power

Features required: furniture placement, wall creation, room/label identification

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Partition walls -- >=3 new walls added beyond baseline
  C2 (25 pts): Control room furniture -- >=4 desks + >=2 shelves + >=10 chairs
  C3 (20 pts): Zone identification -- >=3 rooms defined or labels placed
  C4 (20 pts): Storage + break room -- >=3 shelves, >=1 appliance, >=6 chairs
  C5 (15 pts): Restrooms + total >=30 + file changed

Wrong-target gate: if total furniture < 8, return score=0.
"""

import json


def verify_solar_facility_site_plan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/solar_facility_site_plan_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

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

    # ── C1 (20 pts): Partition walls ──────────────────────────────────────────
    new_walls = result.get("new_walls", 0)
    if new_walls >= 3:
        score += 20
        feedback_parts.append(f"PASS C1: {new_walls} new partition walls created [+20]")
    elif new_walls >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {new_walls} new wall(s) (need >=3 for zone separation) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: no new partition walls created (need >=3 for zone separation)")

    # ── C2 (25 pts): Control room + training furniture ────────────────────────
    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    chair_count = result.get("chair_count", 0)
    if desk_count >= 4 and shelf_count >= 2 and chair_count >= 10:
        score += 25
        feedback_parts.append(f"PASS C2: control/training ({desk_count} desks, {shelf_count} shelves, {chair_count} chairs) [+25]")
    elif desk_count >= 2 and chair_count >= 5:
        score += 12
        feedback_parts.append(f"PARTIAL C2: partial furnishing ({desk_count} desks, {shelf_count} shelves, {chair_count} chairs) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: insufficient furnishing ({desk_count} desks, {shelf_count} shelves, {chair_count} chairs)")

    # ── C3 (20 pts): Zone identification (rooms defined or labels placed) ─────
    zone_ids = result.get("zone_identifiers", 0)
    if zone_ids >= 3:
        score += 20
        feedback_parts.append(f"PASS C3: {zone_ids} zone identifiers (rooms/labels) [+20]")
    elif zone_ids >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: {zone_ids} zone identifier(s) (need >=3) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: no rooms defined or labels placed for zone identification")

    # ── C4 (20 pts): Storage + break room ─────────────────────────────────────
    appliance_count = result.get("appliance_count", 0)
    if shelf_count >= 3 and appliance_count >= 1 and chair_count >= 6:
        score += 20
        feedback_parts.append(f"PASS C4: storage+break ({shelf_count} shelves, {appliance_count} appliances, {chair_count} chairs) [+20]")
    elif shelf_count >= 2 or appliance_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: partial ({shelf_count} shelves, {appliance_count} appliances) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: storage+break room needs shelves, appliances, chairs")

    # ── C5 (15 pts): Restrooms + total count + file changed ──────────────────
    toilet_count = result.get("toilet_count", 0)
    file_changed = result.get("file_changed", False)
    c5_score = 0
    c5_parts = []
    if toilet_count >= 2:
        c5_score += 5
        c5_parts.append(f"{toilet_count} restroom fixtures")
    if furniture_count >= 30:
        c5_score += 5
        c5_parts.append(f"{furniture_count} total furniture")
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
    score += c5_score
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: need >=2 toilets, >=30 furniture, file changed")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} | "
        f"New walls: {new_walls} | Zone IDs: {zone_ids} | "
        f"Desks: {desk_count} | Shelves: {shelf_count} | Chairs: {chair_count}"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
