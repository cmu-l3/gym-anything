#!/usr/bin/env python3
import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_georeference_survey_alignment(traj, env_info, task_info):
    """
    Verifies that the agent correctly translated and rotated the 60 points
    based on the control baseline.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Retrieve the task result JSON
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # Validate output exists and timestamp logic (Anti-gaming)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output georeferenced_points.csv not found. Task not completed."}
    
    if not result.get('file_created_during_task', False):
        feedback.append("Warning: File timestamp indicates it might not have been modified during this task session.")

    # 2. Retrieve the exported coordinates CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("C:\\temp\\georeferenced_points.csv", temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy or read CSV from environment: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Parse the CSV file
    parsed_points = {}
    for line in lines:
        parts = [p.strip() for p in line.split(',')]
        if len(parts) >= 4:
            try:
                pid = int(parts[0])
                x = float(parts[1])
                y = float(parts[2])
                z = float(parts[3])
                parsed_points[pid] = (x, y, z)
            except ValueError:
                continue

    if len(parsed_points) == 0:
        return {"passed": False, "score": 0, "feedback": "Could not parse any points from CSV. Check format."}

    # CRITERION 1: Point count (10 pts)
    if len(parsed_points) >= 60:
        score += 10
        feedback.append("All 60 points exported successfully (10/10)")
    else:
        feedback.append(f"Found {len(parsed_points)} points. Expected 60.")

    # CRITERION 2: Base Translation (Point 1 matches target) (20 pts)
    pt1 = parsed_points.get(1)
    if pt1:
        dx = abs(pt1[0] - 481020.500)
        dy = abs(pt1[1] - 4398100.250)
        if dx <= 0.05 and dy <= 0.05:
            score += 20
            feedback.append("Point 1 matched target base translation (20/20)")
        else:
            feedback.append(f"Point 1 deviation: dE={dx:.3f}, dN={dy:.3f}")
    else:
        feedback.append("Point 1 missing from export.")

    # CRITERION 3: Base Rotation (Point 2 matches target) (20 pts)
    pt2 = parsed_points.get(2)
    if pt2:
        dx = abs(pt2[0] - 481150.850)
        dy = abs(pt2[1] - 4398175.400)
        if dx <= 0.05 and dy <= 0.05:
            score += 20
            feedback.append("Point 2 matched target base rotation (20/20)")
        else:
            feedback.append(f"Point 2 deviation: dE={dx:.3f}, dN={dy:.3f}")
    else:
        feedback.append("Point 2 missing from export.")

    # CRITERION 4: Global Transformation Integrity (30 pts)
    # The setup script generated points 3..60 using a deterministic pattern from the local origin (5000, 5000).
    tx1, ty1 = 481020.500, 4398100.250
    lx1, ly1 = 5000.000, 5000.000
    
    # Target orientation from Point 1 -> 2
    target_dy = 4398175.400 - 4398100.250
    target_dx = 481150.850 - 481020.500
    target_angle = math.atan2(target_dy, target_dx)

    global_errors = []
    z_errors = []

    for i in range(3, 61):
        if i in parsed_points:
            # Reconstruct original local coordinates exactly as setup_task.ps1 generated them
            local_x = 5000.000 + (i * 10.5)
            local_y = 5000.000 + ((i % 5) * 20.1)
            local_z = 1800.000 + i

            # Apply rigid body transform logically
            ldx = local_x - lx1
            ldy = local_y - ly1

            rot_x = ldx * math.cos(target_angle) - ldy * math.sin(target_angle)
            rot_y = ldx * math.sin(target_angle) + ldy * math.cos(target_angle)

            exp_x = tx1 + rot_x
            exp_y = ty1 + rot_y

            # Compare against exported
            px, py, pz = parsed_points[i]
            
            err_dist = math.hypot(px - exp_x, py - exp_y)
            global_errors.append(err_dist)

            z_err = abs(pz - local_z)
            z_errors.append(z_err)

    if len(global_errors) > 0:
        avg_err = sum(global_errors) / len(global_errors)
        max_err = max(global_errors)
        
        # We allow up to 0.1m tolerance on avg distribution
        if avg_err <= 0.1:
            score += 30
            feedback.append(f"Global geometry preserved, avg error {avg_err:.3f}m (30/30)")
        elif avg_err <= 1.0:
            score += 15
            feedback.append(f"Global geometry rough, avg error {avg_err:.3f}m (15/30)")
        else:
            feedback.append(f"Global geometry distorted, avg error {avg_err:.3f}m (0/30)")
    else:
        feedback.append("Missing topology points for global transform check.")

    # CRITERION 5: Z-Axis Integrity (20 pts)
    # The transformation should be strictly 2D. Elevations should not change.
    if len(z_errors) > 0:
        max_z_err = max(z_errors)
        if max_z_err <= 0.005:  # Tolerate minimal float rounding
            score += 20
            feedback.append("Elevations perfectly preserved (20/20)")
        else:
            feedback.append(f"Elevations incorrectly modified, max deviation {max_z_err:.3f}m")

    # Final logic
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }