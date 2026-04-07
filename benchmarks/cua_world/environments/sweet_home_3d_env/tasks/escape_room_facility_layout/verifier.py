#!/usr/bin/env python3
"""
Verifier for escape_room_facility_layout task.

Occupation: Escape Room Designer
Industry: Amusement and Recreation

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Layout & Sequencing -- >=5 new partition walls AND >=4 doors placed
  C2 (20 pts): Zoning & Identification -- >=5 text labels placed AND >=3 rooms with floor colors/textures
  C3 (20 pts): Lobby & Control Room -- >=6 seating items AND >=2 desks/tables
  C4 (20 pts): Escape Game Props -- >=8 storage/hiding spot items (boxes, chests, bookcases, cabinets, etc.)
  C5 (20 pts): Ambiance & Completion -- >=4 lamps/lights (5 pts) + >=40 total furniture items (10 pts) + file actively saved/changed (5 pts)

Wrong-target gate: if (furniture_count + new_walls + new_doors) < 15, return score=0.
"""

import json


def verify_escape_room_facility_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/escape_room_facility_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    
    # ── Wrong-target gate ─────────────────────────────────────────────────────
    total_added = furniture_count + new_walls + new_doors
    if total_added < 15:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {total_added} total items added (furniture + walls + doors). "
                "At least 15 additions required to qualify for scoring."
            )
        }

    new_labels = result.get("new_labels", 0)
    new_rooms = result.get("new_rooms", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    
    seating_count = result.get("seating_count", 0)
    desk_count = result.get("desk_count", 0)
    prop_count = result.get("prop_count", 0)
    lamp_count = result.get("lamp_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Layout & Sequencing (walls + doors) ─────────────────────
    walls_ok = new_walls >= 5
    doors_ok = new_doors >= 4
    if walls_ok and doors_ok:
        score += 20
        feedback_parts.append(f"PASS C1: Layout ({new_walls} new walls, {new_doors} doors) [+20]")
    elif walls_ok or doors_ok:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Layout ({new_walls} new walls, {new_doors} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Layout requires >=5 new walls and >=4 doors (got {new_walls} walls, {new_doors} doors)")

    # ── C2 (20 pts): Zoning & Identification ─────────────────────────────────
    labels_or_rooms = max(new_labels, new_rooms)
    labels_ok = labels_or_rooms >= 5
    floors_ok = rooms_with_floor_color >= 3
    if labels_ok and floors_ok:
        score += 20
        feedback_parts.append(f"PASS C2: Zoning ({labels_or_rooms} zones labeled/defined, {rooms_with_floor_color} distinct floors) [+20]")
    elif labels_ok or floors_ok:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Zoning ({labels_or_rooms} zones labeled/defined, {rooms_with_floor_color} distinct floors) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Zoning requires >=5 labels/rooms and >=3 distinct floors")

    # ── C3 (20 pts): Lobby & Control Room (seating + desks) ──────────────────
    seating_ok = seating_count >= 6
    desks_ok = desk_count >= 2
    if seating_ok and desks_ok:
        score += 20
        feedback_parts.append(f"PASS C3: Admin Furnishing ({seating_count} seats, {desk_count} desks) [+20]")
    elif seating_count >= 3 and desk_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Admin Furnishing ({seating_count} seats, {desk_count} desks) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Admin Furnishing requires >=6 seats and >=2 desks")

    # ── C4 (20 pts): Escape Game Props ───────────────────────────────────────
    if prop_count >= 8:
        score += 20
        feedback_parts.append(f"PASS C4: Escape Props ({prop_count} hiding spots/props) [+20]")
    elif prop_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Escape Props ({prop_count} hiding spots/props, need >=8) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Escape Props requires >=8 hiding spots/storage items (got {prop_count})")

    # ── C5 (20 pts): Ambiance & Completion ───────────────────────────────────
    c5_score = 0
    c5_parts = []
    if lamp_count >= 4:
        c5_score += 5
        c5_parts.append(f"{lamp_count} lamps")
    if furniture_count >= 40:
        c5_score += 10
        c5_parts.append(f"{furniture_count} total furniture")
    if file_changed:
        c5_score += 5
        c5_parts.append("file saved")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Completion ({', '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Completion ({', '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Completion requires >=4 lamps, >=40 total items, and saving the file")

    passed = score >= 70
    summary = f"Score: {score}/100 | Items added: {total_added}"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }