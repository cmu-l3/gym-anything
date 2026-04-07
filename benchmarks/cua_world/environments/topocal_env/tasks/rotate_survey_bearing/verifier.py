#!/usr/bin/env python3
"""
Verifier for rotate_survey_bearing task.

VERIFICATION STRATEGY:
1. File check: Result CSV and TopoCal (.top) files must exist and be modified after task start.
2. Mathematical check: 
   - Point 1 (Pivot) must remain exactly at (5000, 5000, 1850).
   - Z coordinates must be preserved across all points.
   - X, Y coordinates must reflect exactly a 45-degree CCW rotation around Point 1.
3. Anti-gaming check: VLM verifies trajectory frames to ensure the agent actively used the TopoCal UI to rotate (did not just write a python script).
"""

import os
import json
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rotate_survey_bearing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    metadata = task_info.get('metadata', {})
    
    # Expected metrics
    original_points = {pt['id']: pt for pt in metadata.get('original_points', [])}
    pivot = metadata.get('pivot_point', {"id": 1, "x": 5000.0, "y": 5000.0, "z": 1850.0})
    angle_deg = metadata.get('rotation_angle_deg', 45.0)
    angle_rad = math.radians(angle_deg)
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)

    # 1. Fetch JSON state
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("C:\\temp\\task_result.json", result_json_path)
        with open(result_json_path, 'r', encoding='utf-8') as f:
            result_state = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    # 2. Score file outputs (20 points)
    csv_exists = result_state.get('csv_exists', False)
    csv_fresh = result_state.get('csv_created_during_task', False)
    top_exists = result_state.get('top_exists', False)
    
    if csv_exists and csv_fresh:
        score += 10
        feedback_parts.append("Exported CSV found and newly created.")
    else:
        feedback_parts.append("Exported CSV missing or stale.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    if top_exists:
        score += 10
        feedback_parts.append("TopoCal project file saved.")

    # 3. Read and Parse the CSV File
    csv_temp_path = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\rotated_points.csv", csv_temp_path)
        with open(csv_temp_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve CSV: {e}"}
    finally:
        if os.path.exists(csv_temp_path):
            os.unlink(csv_temp_path)

    # Parse points (handles standard TopoCal CSV formats: comma, semi-colon, or space)
    agent_points = {}
    for line in lines:
        line = line.strip()
        if not line: continue
        parts = line.replace(';', ',').replace('\t', ',').split(',')
        if len(parts) >= 4:
            try:
                pt_id = int(float(parts[0].strip()))
                x = float(parts[1].strip())
                y = float(parts[2].strip())
                z = float(parts[3].strip())
                agent_points[pt_id] = {"x": x, "y": y, "z": z}
            except ValueError:
                continue

    if len(agent_points) < len(original_points):
        feedback_parts.append(f"Missing points in CSV. Found {len(agent_points)}, expected {len(original_points)}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Mathematical Verification
    pivot_preserved = False
    elevations_preserved = True
    rotations_correct = True
    
    # Check Pivot
    pt1 = agent_points.get(pivot['id'])
    if pt1 and abs(pt1['x'] - pivot['x']) <= 0.01 and abs(pt1['y'] - pivot['y']) <= 0.01:
        score += 20
        pivot_preserved = True
        feedback_parts.append("Pivot point (Point 1) perfectly preserved.")
    else:
        feedback_parts.append(f"Pivot point drifted or missing! Found {pt1}")
        
    # Check all points geometry
    tested_points = 0
    failed_elevations = 0
    failed_rotations = 0

    for pt_id, orig_pt in original_points.items():
        if pt_id not in agent_points: continue
        tested_points += 1
        agt_pt = agent_points[pt_id]

        # Check Z
        if abs(agt_pt['z'] - orig_pt['z']) > 0.01:
            failed_elevations += 1
            
        # Check X, Y rotation
        if pt_id != pivot['id']:
            dx = orig_pt['x'] - pivot['x']
            dy = orig_pt['y'] - pivot['y']
            
            exp_x = pivot['x'] + (dx * cos_a) - (dy * sin_a)
            exp_y = pivot['y'] + (dx * sin_a) + (dy * cos_a)
            
            # Allow 0.05m tolerance for floating point / gradian rounding artifacts
            if abs(agt_pt['x'] - exp_x) > 0.05 or abs(agt_pt['y'] - exp_y) > 0.05:
                failed_rotations += 1
                logger.warning(f"Rotation mismatch Pt{pt_id}: Expected({exp_x:.3f}, {exp_y:.3f}), Got({agt_pt['x']:.3f}, {agt_pt['y']:.3f})")

    if failed_elevations == 0 and tested_points > 0:
        score += 20
        feedback_parts.append("Elevations (Z) fully preserved.")
    else:
        elevations_preserved = False
        feedback_parts.append(f"Elevations corrupted in {failed_elevations} points.")

    if failed_rotations == 0 and pivot_preserved:
        score += 20
        feedback_parts.append("45-degree CCW geometry rotation correct.")
    else:
        rotations_correct = False
        feedback_parts.append(f"Rotation incorrect in {failed_rotations} points.")

    # 5. Anti-gaming / VLM Trajectory Verification (20 points)
    # Proves the agent actually used the TopoCal UI rather than executing a Python math script
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "You are verifying a CAD trajectory. Look at these frames. "
            "Did the user actively use the TopoCal software to perform a rotation? "
            "Look for the TopoCal interface, specifically the Spanish menus for transforming points "
            "('Puntos', 'Transformar', 'Girar') and any dialogs for rotation or point selection. "
            "Reply with a JSON: {\"used_topocal_ui\": true/false, \"reasoning\": \"...\"}"
        )
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("used_topocal_ui", False):
                score += 20
                feedback_parts.append("VLM verified UI usage.")
            else:
                feedback_parts.append("VLM did not detect TopoCal rotation UI usage (possible script cheating).")
        else:
            feedback_parts.append("VLM verification skipped/failed.")

    # Final Evaluation
    key_criteria_met = (csv_fresh and pivot_preserved and rotations_correct and elevations_preserved)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }