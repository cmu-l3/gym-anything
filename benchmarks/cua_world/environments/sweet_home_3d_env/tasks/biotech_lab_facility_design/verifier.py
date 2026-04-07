#!/usr/bin/env python3
"""
Verifier for biotech_lab_facility_design task.

Occupation: Laboratory Manager
Industry: Biotechnology / Research

Features required: furniture_placement, wall_creation, room_definition, dimension_annotation

Scoring (total 100 pts, pass threshold 70):
  C1 (20 pts): Wet Lab Benches -- >=6 tables/desks + >=2 sinks
  C2 (20 pts): Partition Walls & Doors -- >=4 new walls + >=3 doors
  C3 (20 pts): Room Definition & Color -- >=4 named rooms + >=2 with floor color
  C4 (20 pts): Equipment & Write-up -- >=4 shelves + >=2 fridges + >=3 chairs + >=3 computers
  C5 (20 pts): Dimensions & VLM / Save -- >=2 dimension lines + file modified

Wrong-target gate: if total furniture < 15, return score=0 immediately.
"""

import json
import logging

logger = logging.getLogger(__name__)

def verify_biotech_lab_facility_design(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/biotech_lab_facility_design_result.json")
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

    table_count = result.get("table_count", 0)
    sink_count = result.get("sink_count", 0)
    shelf_count = result.get("shelf_count", 0)
    fridge_count = result.get("fridge_count", 0)
    chair_count = result.get("chair_count", 0)
    computer_count = result.get("computer_count", 0)

    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    door_window_count = result.get("door_window_count", 0)
    doors_used = max(new_doors, door_window_count)
    
    new_rooms = result.get("new_rooms", 0)
    room_names = result.get("room_names", [])
    rooms_with_floor_color = result.get("rooms_with_floor_color", 0)
    named_rooms = len(room_names)
    active_rooms = max(new_rooms, named_rooms)

    new_dimensions = result.get("new_dimensions", 0)
    dimension_count = result.get("dimension_count", 0)
    dims_used = max(new_dimensions, dimension_count)

    file_changed = result.get("file_changed", False)

    # ── C1 (20 pts): Wet Lab Benches & Sinks ─────────────────────────────────
    if table_count >= 6 and sink_count >= 2:
        score += 20
        feedback_parts.append(f"PASS C1: Wet lab benches ({table_count} tables, {sink_count} sinks) [+20]")
    elif table_count >= 3 and sink_count >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C1: Partial wet lab ({table_count} tables, {sink_count} sinks) [+10]")
    else:
        feedback_parts.append(f"FAIL C1: Wet lab needs >=6 tables/desks and >=2 sinks (got {table_count}, {sink_count})")

    # ── C2 (20 pts): Partition Walls & Doors ─────────────────────────────────
    if new_walls >= 4 and doors_used >= 3:
        score += 20
        feedback_parts.append(f"PASS C2: Walls & Doors ({new_walls} walls, {doors_used} doors) [+20]")
    elif new_walls >= 2 and doors_used >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Some walls/doors ({new_walls} walls, {doors_used} doors) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Need >=4 walls and >=3 doors (got {new_walls}, {doors_used})")

    # ── C3 (20 pts): Room Definition & Color ─────────────────────────────────
    if active_rooms >= 4 and rooms_with_floor_color >= 2:
        score += 20
        feedback_parts.append(f"PASS C3: Room Definition ({active_rooms} rooms defined, {rooms_with_floor_color} colored) [+20]")
    elif active_rooms >= 2 or rooms_with_floor_color >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial room definition ({active_rooms} rooms, {rooms_with_floor_color} colored) [+10]")
    else:
        feedback_parts.append(f"FAIL C3: Need >=4 rooms defined and >=2 floor colors (got {active_rooms}, {rooms_with_floor_color})")

    # ── C4 (20 pts): Equipment & Write-up ────────────────────────────────────
    if shelf_count >= 4 and fridge_count >= 2 and chair_count >= 3 and computer_count >= 3:
        score += 20
        feedback_parts.append(f"PASS C4: Equipment & Write-up (shelves:{shelf_count}, fridges:{fridge_count}, chairs:{chair_count}, computers:{computer_count}) [+20]")
    elif (shelf_count >= 2 and fridge_count >= 1) or (chair_count >= 2 and computer_count >= 2):
        score += 10
        feedback_parts.append(f"PARTIAL C4: Equipment/Write-up partially furnished (shelves:{shelf_count}, fridges:{fridge_count}, chairs:{chair_count}, computers:{computer_count}) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Missing required storage or write-up furniture.")

    # ── C5 (20 pts): Dimension Lines & Save ──────────────────────────────────
    c5_score = 0
    c5_parts = []
    
    if dims_used >= 2:
        c5_score += 10
        c5_parts.append(f"{dims_used} dimension lines")
    elif dims_used >= 1:
        c5_score += 5
        c5_parts.append(f"{dims_used} dimension line")

    if file_changed:
        c5_score += 10
        c5_parts.append("file saved/changed")

    score += c5_score
    if c5_score == 20:
        feedback_parts.append(f"PASS C5: Documentation & Save ({' and '.join(c5_parts)}) [+20]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: Documentation/Save ({' and '.join(c5_parts)}) [+{c5_score}]")
    else:
        feedback_parts.append("FAIL C5: Need >=2 dimension lines and successful file save.")

    # ── VLM Trajectory Verification Integration (CRITICAL fallback check) ───
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Sample frames from the trajectory and final state
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            prompt = (
                "Did the agent use Sweet Home 3D to layout a laboratory space? "
                "Look for active 3D views, placement of laboratory-style tables, "
                "and interaction with the software. Answer YES or NO."
            )
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and "YES" in vlm_res.get('response', '').upper():
                feedback_parts.append("VLM: Verified trajectory shows Sweet Home 3D activity.")
            else:
                feedback_parts.append("VLM: Trajectory verification inconclusive or negative.")
    except Exception as e:
        logger.warning(f"VLM trajectory verification skipped/failed: {e}")

    # ── Final Verdict ────────────────────────────────────────────────────────
    passed = score >= 70
    
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(tables={table_count}, sinks={sink_count}, shelves={shelf_count}, "
        f"fridges={fridge_count}, chairs={chair_count}, computers={computer_count}, "
        f"walls={new_walls}, doors={doors_used}, dimensions={dims_used})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }