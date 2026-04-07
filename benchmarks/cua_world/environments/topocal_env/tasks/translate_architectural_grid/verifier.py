#!/usr/bin/env python3
"""
Verifier for translate_architectural_grid task.
Evaluates proper coordinate geometry transformation.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_translate_architectural_grid(traj, env_info, task_info):
    """
    Verifies the exported XYZ file matches deterministic math for 
    translation and rotation applied to the State Plane base coordinates.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    
    # 1. Fetch JSON Results
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env(r"C:\tmp\task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    if not result_data.get('xyz_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Exported local_architectural_grid.xyz file not found."
        }
    
    score += 10
    feedback.append("Exported file exists")

    if result_data.get('tcp_exists'):
        score += 10
        feedback.append("Project file saved")

    # 2. Fetch and Parse XYZ
    temp_xyz = tempfile.NamedTemporaryFile(delete=False, suffix='.xyz')
    points = {}
    try:
        copy_from_env(r"C:\workspace\data\local_architectural_grid.xyz", temp_xyz.name)
        with open(temp_xyz.name, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 4:
                    try:
                        pid = int(parts[0])
                        x = float(parts[1])
                        y = float(parts[2])
                        z = float(parts[3])
                        points[pid] = (x, y, z)
                    except ValueError:
                        continue
    except Exception as e:
        logger.error(f"Failed to read XYZ file: {e}")
    finally:
        if os.path.exists(temp_xyz.name):
            os.unlink(temp_xyz.name)

    if 1 not in points:
        feedback.append("Point 1 missing in export")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Check Point 1 Translation
    p1_x, p1_y, p1_z = points[1]
    translation_ok = abs(p1_x - 1000.0) < 0.1 and abs(p1_y - 1000.0) < 0.1
    if translation_ok:
        score += 30
        feedback.append("Base point successfully translated to origin (1000, 1000)")
    else:
        feedback.append(f"Translation failed: Base point is at ({p1_x:.2f}, {p1_y:.2f})")

    if abs(p1_z - 1500.0) < 0.1:
        score += 10
        feedback.append("Z-values preserved correctly")
    else:
        feedback.append("Z-values were flattened or corrupted")

    # 4. Check Rotation Math (Point 15)
    # Original Base (CP1): (3079200.00, 1694800.00)
    # Original P15: (3079250.00, 1694850.00) => dx=50, dy=50 from CP1
    # Rotate 14.5 degrees
    # CW Expected:  (1060.93, 1035.89)
    # CCW Expected: (1035.89, 1060.93) (Accepted in case of CAD angular system quirk)
    rotation_ok = False
    if 15 in points:
        p15_x, p15_y, _ = points[15]
        
        is_cw = abs(p15_x - 1060.93) < 0.5 and abs(p15_y - 1035.89) < 0.5
        is_ccw = abs(p15_x - 1035.89) < 0.5 and abs(p15_y - 1060.93) < 0.5

        if is_cw or is_ccw:
            score += 40
            rotation_ok = True
            feedback.append(f"Global rotation matched target. Checked Point 15 -> ({p15_x:.2f}, {p15_y:.2f})")
        else:
            feedback.append(f"Rotation math incorrect. Expected Point 15 near (1060.93, 1035.89), found ({p15_x:.2f}, {p15_y:.2f})")
    else:
        feedback.append("Point 15 missing; cannot verify global rotation")

    # 5. Anti-gaming check via VLM (ensure they used the software, not just python math)
    vlm_ok = True
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            # Import needed to read trajectory frames
            import sys
            from pathlib import Path
            sys.path.insert(0, str(Path(__file__).parent.parent.parent))
            from gym_anything.vlm import sample_trajectory_frames

            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = "Review these trajectory frames of an agent taking a test. Did the agent actually interact with a visual CAD application (like TopoCal) to manipulate survey data, or did they only open a text editor / scripting environment? Respond strictly with JSON: {\"used_cad_app\": true/false}"
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res.get('success') and vlm_res.get('parsed', {}).get('used_cad_app') is False:
                    vlm_ok = False
                    feedback.append("VLM Detected Gaming (Script used instead of UI)")
                elif vlm_res.get('success'):
                    feedback.append("VLM confirms CAD usage")
        except Exception as e:
            logger.error(f"VLM trajectory check failed: {e}")

    # Threshold for success
    passed = (score >= 80) and translation_ok and rotation_ok and vlm_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }