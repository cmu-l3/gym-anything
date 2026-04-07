#!/usr/bin/env python3
"""
Verifier for jazz_club_venue_design task.

Occupation: Entertainment Entrepreneur / Hospitality Design
Industry: Arts, Entertainment, and Recreation

Features required: wall_creation, room_definition, furniture_placement, 3d_photo_rendering

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Stage & Green Room -> >=1 piano, >=1 sofa
  C2 (25 pts): Audience Seating -> >= 15 tables, >= 30 chairs
  C3 (20 pts): Bar & Restrooms -> >=3 desks/counters, >=2 toilets, >=2 sinks
  C4 (20 pts): Architecture -> >= 3 new walls, >= 4 defined rooms
  C5 (15 pts): 3D Render & Save -> valid image rendered and project saved

Wrong-target gate: if total furniture < 15, score = 0.
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_jazz_club_venue_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/jazz_club_venue_design_result.json")
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

    piano_count = result.get('piano_count', 0)
    sofa_count = result.get('sofa_count', 0)
    chair_count = result.get('chair_count', 0)
    table_count = result.get('table_count', 0)
    desk_count = result.get('desk_count', 0)
    toilet_count = result.get('toilet_count', 0)
    sink_count = result.get('sink_count', 0)

    # ── C1 (20 pts): Stage & Green Room ───────────────────────────────────────
    if piano_count >= 1 and sofa_count >= 1:
        score += 20
        feedback_parts.append(f"PASS C1: Stage & Green Room ({piano_count} piano, {sofa_count} sofa) [+20]")
    elif piano_count >= 1 or sofa_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Missing piano or sofa ({piano_count} piano, {sofa_count} sofa) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: No piano or sofa found")

    # ── C2 (25 pts): Audience Seating ─────────────────────────────────────────
    if table_count >= 15 and chair_count >= 30:
        score += 25
        feedback_parts.append(f"PASS C2: Audience seating ({table_count} tables, {chair_count} chairs/stools) [+25]")
    elif table_count >= 8 and chair_count >= 15:
        score += 12
        feedback_parts.append(f"PARTIAL C2: Partial audience seating ({table_count} tables, {chair_count} chairs) [+12]")
    else:
        feedback_parts.append(f"FAIL C2: Insufficient audience seating (got {table_count} tables, {chair_count} chairs)")

    # ── C3 (20 pts): Bar & Restrooms ──────────────────────────────────────────
    # Note: Bar stools pool into chair_count. Audience (30) + Bar (6) + Stage (2) = 38
    if desk_count >= 3 and toilet_count >= 2 and sink_count >= 2:
        if chair_count >= 38:
            score += 20
            feedback_parts.append(f"PASS C3: Bar & Restrooms + ample total seating ({desk_count} counters, {toilet_count} toilets, {sink_count} sinks) [+20]")
        else:
            score += 15
            feedback_parts.append(f"PARTIAL C3: Bar & Restrooms met, but overall seating capacity slightly low ({chair_count} total chairs) [+15]")
    elif desk_count >= 1 and (toilet_count >= 1 or sink_count >= 1):
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial Bar/Restrooms ({desk_count} counters, {toilet_count} toilets, {sink_count} sinks) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Missing Bar or Restroom requirements")

    # ── C4 (20 pts): Architecture (Zones & Partitioning) ──────────────────────
    new_walls = result.get('new_walls', 0)
    new_rooms = result.get('new_rooms', 0)
    room_names = result.get('room_names', [])
    rooms_colored = result.get('rooms_with_floor_color', 0)
    
    rooms_identified = max(new_rooms, len(set(room_names)), rooms_colored)
    
    if new_walls >= 3 and rooms_identified >= 4:
        score += 20
        feedback_parts.append(f"PASS C4: Architecture ({new_walls} new walls, {rooms_identified} defined zones) [+20]")
    elif new_walls >= 1 and rooms_identified >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Architecture ({new_walls} walls, {rooms_identified} zones) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Architecture needs >= 3 walls and >= 4 defined rooms/zones")

    # ── C5 (15 pts): 3D Render & Save ─────────────────────────────────────────
    photo_found = result.get('photo_found', False)
    photo_size = result.get('photo_size', 0)
    file_changed = result.get('file_changed', False)

    c5_score = 0
    c5_msgs = []
    
    if photo_found and photo_size > 10000:
        c5_score += 10
        c5_msgs.append("valid 3D photo rendered")
    elif photo_found:
        c5_score += 5
        c5_msgs.append("3D photo exists (but small size)")
        
    if file_changed:
        c5_score += 5
        c5_msgs.append("project saved")

    score += c5_score
    if c5_score > 0:
        feedback_parts.append(f"PASS/PARTIAL C5: {', '.join(c5_msgs)} [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: 3D photo not found and project not saved")

    # ── Final Verdict ─────────────────────────────────────────────────────────
    # We include optional VLM trajectory check if available via the framework, 
    # but the rigorous programmatic score remains deterministic for the pass/fail boundary.
    passed = score >= 70
    
    summary = f"Score: {score}/100 | Furniture: {furniture_count} items."
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }