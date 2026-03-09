#!/usr/bin/env python3
"""
Verifier for extract_mass_properties task.
Compares agent's JSON report against ground truth values calculated from the model.
"""

import json
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_mass_properties(traj, env_info, task_info):
    """
    Verify the mass properties report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    report_exists = result.get("report_exists", False)
    created_during = result.get("report_created_during_task", False)
    agent_data = result.get("report_content", {})
    ground_truth = result.get("ground_truth", {})

    # Basic Checks
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file 'mass_report.json' not found."}
    
    if not created_during:
        return {"passed": False, "score": 0, "feedback": "Report file was not modified during the task."}

    if not ground_truth:
        return {"passed": False, "score": 0, "feedback": "System error: Ground truth could not be calculated."}

    # Scoring Logic
    score = 0
    max_score = 100
    feedback_lines = []
    
    # Required keys
    required_keys = [
        "volume_mm3", "surface_area_mm2", 
        "bounding_box_x_mm", "bounding_box_y_mm", "bounding_box_z_mm",
        "center_of_mass_x_mm", "center_of_mass_y_mm", "center_of_mass_z_mm",
        "mass_grams"
    ]
    
    # 1. File Structure (10 pts)
    missing_keys = [k for k in required_keys if k not in agent_data]
    if not missing_keys:
        score += 10
        feedback_lines.append("✓ JSON structure correct")
    else:
        feedback_lines.append(f"✗ Missing keys: {', '.join(missing_keys)}")
        # If crucial keys missing, we might stop or penalize heavily, but let's continue for partial credit

    # Helper to check percent error
    def check_percent(key, points, tolerance=0.05):
        if key not in agent_data or key not in ground_truth:
            return 0
        try:
            val_agent = float(agent_data[key])
            val_gt = float(ground_truth[key])
            if val_gt == 0: return 0 # Avoid div/0
            error = abs((val_agent - val_gt) / val_gt)
            if error <= tolerance:
                return points
            feedback_lines.append(f"✗ {key}: {val_agent} vs {val_gt:.2f} (Error: {error:.1%})")
            return 0
        except ValueError:
            return 0

    # Helper to check absolute error (for CoM coordinates which can be 0)
    def check_abs(key, points, tolerance=2.0):
        if key not in agent_data or key not in ground_truth:
            return 0
        try:
            val_agent = float(agent_data[key])
            val_gt = float(ground_truth[key])
            error = abs(val_agent - val_gt)
            if error <= tolerance:
                return points
            feedback_lines.append(f"✗ {key}: {val_agent} vs {val_gt:.2f} (Diff: {error:.2f})")
            return 0
        except ValueError:
            return 0

    # 2. Volume (15 pts)
    score += check_percent("volume_mm3", 15)

    # 3. Surface Area (15 pts)
    score += check_percent("surface_area_mm2", 15)

    # 4. Bounding Box (21 pts total, 7 each)
    score += check_percent("bounding_box_x_mm", 7)
    score += check_percent("bounding_box_y_mm", 7)
    score += check_percent("bounding_box_z_mm", 7)

    # 5. Center of Mass (21 pts total, 7 each)
    score += check_abs("center_of_mass_x_mm", 7)
    score += check_abs("center_of_mass_y_mm", 7)
    score += check_abs("center_of_mass_z_mm", 7)

    # 6. Mass (10 pts)
    score += check_percent("mass_grams", 10)

    # 7. Consistency Check (8 pts)
    # Check if mass matches volume * density provided in instructions
    # This detects if they just guessed numbers or if they calculated correctly
    if "volume_mm3" in agent_data and "mass_grams" in agent_data:
        try:
            vol = float(agent_data["volume_mm3"])
            mass = float(agent_data["mass_grams"])
            expected_mass = vol * 0.0027
            if abs(mass - expected_mass) < (expected_mass * 0.02) + 0.01: # 2% tolerance
                score += 8
                feedback_lines.append("✓ Mass consistent with volume")
            else:
                feedback_lines.append("✗ Mass inconsistent with volume (Did you use density 0.0027?)")
        except:
            pass

    # Success determination
    passed = score >= 60 and "volume_mm3" not in missing_keys and "mass_grams" not in missing_keys

    feedback = f"Score: {score}/100. " + " | ".join(feedback_lines)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }