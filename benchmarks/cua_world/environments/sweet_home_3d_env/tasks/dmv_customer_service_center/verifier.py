#!/usr/bin/env python3
"""
Verifier for dmv_customer_service_center task.

Occupation: Facility Planner
Industry: Government / Civic Architecture

Features required: furniture_placement, wall_creation, room_definition, door_window_placement

Scoring (total 100 pts, pass threshold 70):
  Criterion 1 (25 pts): Waiting Area Seating (≥30 chairs/benches placed). Partial: 15 pts for ≥15.
  Criterion 2 (25 pts): Service Counters (≥8 desks + ≥8 agent chairs).
  Criterion 3 (15 pts): Secure Partition Walls (≥2 new walls built beyond baseline).
  Criterion 4 (15 pts): Administrative Storage (≥4 cabinets/shelves placed).
  Criterion 5 (20 pts): Rooms & Doors (≥3 rooms defined + ≥2 new doors).

Wrong-target gate: if total furniture < 20, return score=0 immediately.
"""

import json


def verify_dmv_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/dmv_customer_service_center_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 20:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 20 items required to qualify for scoring."
            )
        }

    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    shelf_count = result.get("shelf_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    new_rooms = result.get("new_rooms", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    file_changed = result.get("file_changed", False)

    # ── Criterion 1 (25 pts): Waiting Area Seating ────────────────────────────
    # Expecting 30 chairs for the public
    if chair_count >= 30:
        score += 25
        feedback_parts.append(f"PASS C1: {chair_count} seating items found (≥30 required) [+25]")
    elif chair_count >= 15:
        score += 15
        feedback_parts.append(f"PARTIAL C1: {chair_count} seating items found (need 30 for full credit) [+15]")
    else:
        feedback_parts.append(f"FAIL C1: only {chair_count} seating items found (need ≥30 for DMV waiting area)")

    # ── Criterion 2 (25 pts): Service Counters ────────────────────────────────
    # Expecting 8 desks/counters and 8 agent chairs. (Combined with 30 waiting chairs = 38 total chairs needed for BOTH fully satisfied)
    if desk_count >= 8 and chair_count >= 38:
        score += 25
        feedback_parts.append(f"PASS C2: {desk_count} service counters and sufficient agent seating found [+25]")
    elif desk_count >= 4 and chair_count >= 19:
        score += 12
        feedback_parts.append(f"PARTIAL C2: partial service counters ({desk_count} desks and {chair_count} total chairs) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: service counters need ≥8 desks and sufficient total chairs for public + agents")

    # ── Criterion 3 (15 pts): Secure Partition Walls ──────────────────────────
    if new_walls >= 2:
        score += 15
        feedback_parts.append(f"PASS C3: {new_walls} new partition walls created for security [+15]")
    elif new_walls == 1:
        score += 7
        feedback_parts.append(f"PARTIAL C3: {new_walls} new partition wall created (need ≥2) [+7]")
    else:
        feedback_parts.append(f"FAIL C3: no partition walls built to separate secure areas")

    # ── Criterion 4 (15 pts): Administrative Storage ──────────────────────────
    if shelf_count >= 4:
        score += 15
        feedback_parts.append(f"PASS C4: {shelf_count} storage/filing units placed for back office [+15]")
    elif shelf_count >= 2:
        score += 7
        feedback_parts.append(f"PARTIAL C4: {shelf_count} storage units placed (need ≥4) [+7]")
    else:
        feedback_parts.append(f"FAIL C4: back office storage needs ≥4 shelving/filing units (got {shelf_count})")

    # ── Criterion 5 (20 pts): Rooms & Doors ───────────────────────────────────
    # We accept named rooms or colored rooms
    total_defined_rooms = max(new_rooms, len(room_names), rooms_with_floor_color)
    c5_score = 0
    c5_parts = []
    
    if total_defined_rooms >= 3:
        c5_score += 10
        c5_parts.append(f"≥3 rooms defined")
    elif total_defined_rooms >= 1:
        c5_score += 5
        c5_parts.append(f"{total_defined_rooms} room(s) defined")
        
    if new_doors >= 2:
        c5_score += 10
        c5_parts.append(f"≥2 new doors")
    elif new_doors == 1:
        c5_score += 5
        c5_parts.append(f"1 new door")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Rooms & Doors perfectly defined ({' and '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Rooms & Doors ({', '.join(c5_parts) if c5_parts else 'none'}) [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: missing room definitions and doors for the secure partitions")

    if not file_changed:
        feedback_parts.append("WARNING: File appears unmodified from baseline.")

    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(chairs={chair_count}, desks={desk_count}, shelves={shelf_count}, walls={new_walls})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }