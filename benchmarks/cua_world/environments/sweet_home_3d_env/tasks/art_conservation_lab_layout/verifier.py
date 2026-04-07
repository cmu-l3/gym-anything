#!/usr/bin/env python3
"""
Verifier for art_conservation_lab_layout task.

Occupation: Museum Facility Planner / Art Conservator
Industry: Museums, Historical Sites, and Similar Institutions

Features evaluated:
  - Wall creation (Partitioning zones)
  - Room definition (Naming and Floor Treatments)
  - Furniture placement (Specific equipment to specialized zones)
  - 3D photo rendering (Output artifact)

Scoring (100 points total, Pass threshold 70):
  C1 (20 pts): Room Zones => >=4 new walls (10) AND >=4 new rooms (10)
  C2 (25 pts): Lab Furniture => >=2 sinks (5), >=5 tables/desks (10), >=3 chairs (5), >=4 lamps (5)
  C3 (15 pts): Storage/Isolation => >=5 shelves/cabinets (10) AND >=1 door (5)
  C4 (20 pts): Floor Delineation => >=2 rooms with distinct floorColor or floorTexture
  C5 (20 pts): Render & Save => 3D photo valid/>50KB (10), file modified (5), >=20 total items (5)

Wrong-Target Gate: Total furniture < 12 items -> Score 0 immediately.
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_art_conservation_lab_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/art_conservation_lab_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    # ── Wrong-target gate ─────────────────────────────────────────────────────
    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 12:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 12 items required to qualify for scoring."
            )
        }

    new_walls = result.get("new_walls", 0)
    new_rooms = result.get("new_rooms", 0)
    sink_count = result.get("sink_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    lamp_count = result.get("lamp_count", 0)
    shelf_count = result.get("shelf_count", 0)
    door_count = result.get("door_count", 0)
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    render_valid = result.get("render_valid", False)
    file_changed = result.get("file_changed", False)

    # ── C1: Room Zones (20 points) ────────────────────────────────────────────
    c1_score = 0
    c1_parts = []
    
    if new_walls >= 4:
        c1_score += 10
        c1_parts.append(f"{new_walls} walls")
    elif new_walls >= 2:
        c1_score += 5
        c1_parts.append(f"{new_walls} walls (partial)")
    
    if new_rooms >= 4:
        c1_score += 10
        c1_parts.append(f"{new_rooms} rooms")
    elif new_rooms >= 2:
        c1_score += 5
        c1_parts.append(f"{new_rooms} rooms (partial)")
        
    score += c1_score
    if c1_score == 20:
        feedback_parts.append(f"PASS C1: Room Zones ({', '.join(c1_parts)}) [+20]")
    else:
        feedback_parts.append(f"PARTIAL C1: Room Zones (got {new_walls} new walls, {new_rooms} new rooms) [+{c1_score}]")

    # ── C2: Lab Furniture (25 points) ─────────────────────────────────────────
    c2_score = 0
    c2_parts = []
    
    if sink_count >= 2:
        c2_score += 5
        c2_parts.append(f"{sink_count} sinks")
    if desk_count >= 5:
        c2_score += 10
        c2_parts.append(f"{desk_count} tables/desks")
    elif desk_count >= 2:
        c2_score += 5
        c2_parts.append(f"{desk_count} tables/desks (partial)")
    if chair_count >= 3:
        c2_score += 5
        c2_parts.append(f"{chair_count} chairs")
    if lamp_count >= 4:
        c2_score += 5
        c2_parts.append(f"{lamp_count} lamps")
        
    score += c2_score
    if c2_score == 25:
        feedback_parts.append(f"PASS C2: Lab Furniture ({', '.join(c2_parts)}) [+25]")
    else:
        feedback_parts.append(f"PARTIAL C2: Lab Furniture (sinks={sink_count}, desks={desk_count}, chairs={chair_count}, lamps={lamp_count}) [+{c2_score}]")

    # ── C3: Storage/Isolation (15 points) ─────────────────────────────────────
    c3_score = 0
    if shelf_count >= 5:
        c3_score += 10
    elif shelf_count >= 2:
        c3_score += 5
        
    if door_count >= 1:
        c3_score += 5
        
    score += c3_score
    if c3_score == 15:
        feedback_parts.append(f"PASS C3: Storage/Isolation ({shelf_count} shelves, {door_count} doors) [+15]")
    else:
        feedback_parts.append(f"PARTIAL C3: Storage/Isolation (shelves={shelf_count}, doors={door_count}) [+{c3_score}]")

    # ── C4: Floor Delineation (20 points) ─────────────────────────────────────
    if rooms_with_floor_color >= 2:
        score += 20
        feedback_parts.append(f"PASS C4: Floor Delineation ({rooms_with_floor_color} rooms with color/texture) [+20]")
    elif rooms_with_floor_color == 1:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Floor Delineation (1 room with color/texture) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: No distinct floor colors/textures applied (0 rooms)")

    # ── C5: Render & Save (20 points) ─────────────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if render_valid:
        c5_score += 10
        c5_parts.append("3D render exists (>50KB)")
    if file_changed:
        c5_score += 5
        c5_parts.append("project saved")
    if furniture_count >= 20:
        c5_score += 5
        c5_parts.append(f"total items >= 20 ({furniture_count})")
        
    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Render & Save ({', '.join(c5_parts)}) [+20]")
    else:
        feedback_parts.append(f"PARTIAL C5: Render & Save (render_valid={render_valid}, saved={file_changed}, items={furniture_count}) [+{c5_score}]")

    passed = score >= 70
    summary = f"Score: {score}/100"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }