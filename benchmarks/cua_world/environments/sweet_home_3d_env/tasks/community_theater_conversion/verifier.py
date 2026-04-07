#!/usr/bin/env python3
"""
Verifier for community_theater_conversion task.

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Zoning & Walls (>=4 new walls AND >=4 rooms defined)
  C2 (10 pts): Internal Doors (>=4 doors/windows placed)
  C3 (30 pts): Mass Seating (>=30 chairs/seats placed)
  C4 (20 pts): Supporting Furniture (>=3 desks/tables, >=2 storage, >=2 toilets/sinks)
  C5 (10 pts): 3D Render Artifact (Valid PNG image at /home/ga/Desktop/auditorium_render.png)
  C6 (10 pts): File Saved (File changed from baseline)

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json

def verify_community_theater(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/community_theater_conversion_result.json")
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
                "At least 15 items must be added to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    room_count = result.get("room_count", 0)
    door_window_count = result.get("door_window_count", 0)
    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    storage_count = result.get("storage_count", 0)
    plumbing_count = result.get("plumbing_count", 0)
    render_exists = result.get("render_exists", False)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Zoning & Walls ───────────────────────────────────────────
    if new_walls >= 4 and room_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C1: Zoning established ({new_walls} new walls, {room_count} rooms) [+20]")
    elif new_walls >= 4 or room_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Incomplete zoning ({new_walls} walls, {room_count} rooms, both need to be >=4) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Zoning needs >=4 new walls and >=4 rooms (got {new_walls} walls, {room_count} rooms)")

    # ── C2 (10 pts): Internal Doors ───────────────────────────────────────────
    if door_window_count >= 4:
        score += 10
        feedback_parts.append(f"PASS C2: Doors placed ({door_window_count} doors/windows) [+10]")
    elif door_window_count >= 2:
        score += 5
        feedback_parts.append(f"PARTIAL C2: Insufficient doors ({door_window_count} placed, need >=4) [+5]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=4 doors/windows for traffic flow (got {door_window_count})")

    # ── C3 (30 pts): Mass Seating ─────────────────────────────────────────────
    if chair_count >= 30:
        score += 30
        feedback_parts.append(f"PASS C3: Mass seating ({chair_count} chairs/seats placed) [+30]")
    elif chair_count >= 20:
        score += 20
        feedback_parts.append(f"PARTIAL C3: Partial mass seating ({chair_count} chairs/seats) [+20]")
    elif chair_count >= 10:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Minimal mass seating ({chair_count} chairs/seats) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Auditorium needs >=30 chairs/seats (got {chair_count})")

    # ── C4 (20 pts): Supporting Furniture ─────────────────────────────────────
    c4_score = 0
    c4_parts = []
    if desk_count >= 3:
        c4_score += 8
        c4_parts.append(f"{desk_count} desks/tables")
    if storage_count >= 2:
        c4_score += 6
        c4_parts.append(f"{storage_count} storage/shelves")
    if plumbing_count >= 2:
        c4_score += 6
        c4_parts.append(f"{plumbing_count} plumbing fixtures")

    score += c4_score
    if c4_score == 20:
        feedback_parts.append(f"PASS C4: Supporting furniture ({', '.join(c4_parts)}) [+20]")
    elif c4_score > 0:
        feedback_parts.append(f"PARTIAL C4: Partial supporting furniture ({', '.join(c4_parts)}) [+{c4_score}]")
    else:
        feedback_parts.append("FAIL C4: Missing supporting furniture (needs desks, storage, toilets)")

    # ── C5 (10 pts): 3D Render Artifact ───────────────────────────────────────
    if render_exists:
        score += 10
        feedback_parts.append("PASS C5: 3D Render image found on Desktop [+10]")
    else:
        feedback_parts.append("FAIL C5: 3D Render image not found at expected path")

    # ── C6 (10 pts): File Saved ───────────────────────────────────────────────
    if file_changed:
        score += 10
        feedback_parts.append("PASS C6: File was successfully modified and saved [+10]")
    else:
        feedback_parts.append("FAIL C6: File appears unchanged from starter template")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(chairs={chair_count}, desks={desk_count}, storage={storage_count}, plumbing={plumbing_count})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }