#!/usr/bin/env python3
"""
Verifier for antique_auction_house_layout task.

Occupation: Operations Director
Industry: Fine Arts and Antiques / Retail

Features required: wall_creation, door_placement, room_definition, furniture_placement

Scoring (total 100 pts, pass threshold 70):
  C1: Auction Floor Seating (25 pts): >= 20 chairs + >= 1 podium/desk/table.
  C2: Walls & Doors (20 pts): >= 4 new walls + >= 3 new doors.
  C3: Display & Storage (20 pts): >= 8 shelving/cabinet/display units.
  C4: Room Definitions (15 pts): >= 4 named rooms.
  C5: Admin & Complexity (20 pts): >= 24 total chairs (20+4), >= 3 total desks (1+2), >= 5 decor items, file changed.

Wrong-target gate: if total furniture < 15, return score=0.
"""

import json


def verify_antique_auction_house_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/antique_auction_house_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 15:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 15 items required to qualify for scoring."
            )
        }

    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    display_count = result.get("display_count", 0)
    decor_count = result.get("decor_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    room_names = result.get("room_names", [])
    named_room_count = len(room_names)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Auction Floor Seating ────────────────────────────────────
    if chair_count >= 20 and desk_count >= 1:
        score += 25
        feedback_parts.append(f"PASS C1: auction floor seating ({chair_count} chairs, {desk_count} desks/podiums) [+25]")
    elif chair_count >= 10:
        score += 15
        feedback_parts.append(f"PARTIAL C1: partial seating ({chair_count} chairs, need >=20) [+15]")
    else:
        feedback_parts.append(f"FAIL C1: auction seating needs >=20 chairs + >=1 podium/desk (got {chair_count} chairs)")

    # ── C2 (20 pts): Walls & Doors ────────────────────────────────────────────
    if new_walls >= 4 and new_doors >= 3:
        score += 20
        feedback_parts.append(f"PASS C2: secure zones constructed ({new_walls} walls, {new_doors} doors) [+20]")
    elif new_walls >= 2 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: partial walls/doors ({new_walls} walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: secure zones need >=4 walls and >=3 doors (got {new_walls} walls, {new_doors} doors)")

    # ── C3 (20 pts): Display & Storage ────────────────────────────────────────
    if display_count >= 8:
        score += 20
        feedback_parts.append(f"PASS C3: gallery/vault storage ({display_count} display/storage units) [+20]")
    elif display_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C3: partial storage ({display_count} display units, need >=8) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: gallery/vault needs >=8 display/storage units (got {display_count})")

    # ── C4 (15 pts): Room Definitions ─────────────────────────────────────────
    if named_room_count >= 4:
        score += 15
        feedback_parts.append(f"PASS C4: functional zones defined ({named_room_count} named rooms) [+15]")
    elif named_room_count >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C4: partial zones defined ({named_room_count} named rooms, need >=4) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: layout needs >=4 named room boundaries (got {named_room_count})")

    # ── C5 (20 pts): Admin, Decor & Complexity ────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if desk_count >= 3:
        c5_score += 5
        c5_parts.append(f"desks/counters: {desk_count}")
    
    if chair_count >= 24:
        c5_score += 5
        c5_parts.append(f"total chairs: {chair_count}")
        
    if decor_count >= 5:
        c5_score += 5
        c5_parts.append(f"ambient decor: {decor_count}")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file saved")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: admin & complexity ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: admin & complexity ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: admin & decor needs >=3 total desks, >=24 total chairs, >=5 decor, and file saved")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(chairs={chair_count}, desks={desk_count}, displays={display_count}, decor={decor_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }