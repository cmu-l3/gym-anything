#!/usr/bin/env python3
"""
Verifier for public_aquarium_visitor_center task.

Occupation: Museum / Exhibit Designer
Industry: Museums, Zoos, and Aquariums

Features required: furniture_placement, wall_creation, room_definition, label_placement, polyline_drawing

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Zones & Rooms -- >=5 named rooms defined
  C2 (20 pts): Exhibit & Retail Furnishing -- >=10 shelving/display units
  C3 (20 pts): Education & Lobby Furnishing -- >=12 chairs AND >=4 desks/tables
  C4 (20 pts): Visitor Flow Path -- >=1 polyline with >=4 points
  C5 (20 pts): Architecture & Annotation -- >=4 new walls AND >=3 text labels

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json

def verify_public_aquarium_visitor_center(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/public_aquarium_visitor_center_result.json")
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

    # ── Criterion 1 (20 pts): Zones & Rooms ────────────────────────────────────
    room_names = result.get("room_names", [])
    if len(room_names) >= 5:
        score += 20
        feedback_parts.append(f"PASS C1: {len(room_names)} named rooms defined [+20]")
    elif len(room_names) >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C1: {len(room_names)} named rooms (need >=5) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: need >=5 named rooms (got {len(room_names)})")

    # ── Criterion 2 (20 pts): Exhibit & Retail Furnishing ──────────────────────
    shelf_count = result.get("shelf_count", 0)
    if shelf_count >= 10:
        score += 20
        feedback_parts.append(f"PASS C2: {shelf_count} display/shelving units [+20]")
    elif shelf_count >= 5:
        score += 10
        feedback_parts.append(f"PARTIAL C2: {shelf_count} display/shelving units (need >=10) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: need >=10 display/shelving units (got {shelf_count})")

    # ── Criterion 3 (20 pts): Education & Lobby Furnishing ─────────────────────
    chair_count = result.get("chair_count", 0)
    desk_count = result.get("desk_count", 0)
    if chair_count >= 12 and desk_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C3: {chair_count} chairs, {desk_count} desks/tables [+20]")
    elif chair_count >= 12 or desk_count >= 4:
        score += 10
        feedback_parts.append(f"PARTIAL C3: {chair_count} chairs, {desk_count} desks/tables (need 12 and 4) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: need >=12 chairs and >=4 desks/tables (got {chair_count}, {desk_count})")

    # ── Criterion 4 (20 pts): Visitor Flow Path ────────────────────────────────
    polylines = result.get("polylines", [])
    max_points = max(polylines) if polylines else 0
    if max_points >= 4:
        score += 20
        feedback_parts.append(f"PASS C4: polyline with {max_points} points found [+20]")
    elif len(polylines) > 0:
        score += 10
        feedback_parts.append(f"PARTIAL C4: polyline found but only {max_points} points (need >=4) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: no polyline flow path found")

    # ── Criterion 5 (20 pts): Architecture & Annotation ────────────────────────
    new_walls = result.get("new_walls", 0)
    label_texts = result.get("label_texts", [])
    label_count = len(label_texts)
    
    if new_walls >= 4 and label_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C5: {new_walls} new walls, {label_count} labels [+20]")
    elif new_walls >= 4 or label_count >= 3:
        score += 10
        feedback_parts.append(f"PARTIAL C5: {new_walls} new walls, {label_count} labels [+10]")
    else:
        feedback_parts.append(f"FAIL C5: need >=4 new walls and >=3 labels (got {new_walls}, {label_count})")

    passed = score >= 70
    feedback_parts.insert(0, f"Score: {score}/100")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }