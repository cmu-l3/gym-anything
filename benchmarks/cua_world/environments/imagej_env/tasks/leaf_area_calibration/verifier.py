#!/usr/bin/env python3
"""
Verifier for Leaf Area Calibration task.

Verification Logic:
1. CSV File Exists & Created During Task (20 pts)
2. Value is Calibrated (Unit Check) (30 pts)
   - Must be < 1000. If > 10,000, it's raw pixels (Fail).
3. Value is Accurate for Filled Leaf (25 pts)
   - Expected range ~45-65 cm^2.
   - If < 40, they likely didn't Fill Holes (only measured veins).
4. VLM Workflow Verification (25 pts)
   - Checks trajectory for Set Scale or Threshold dialogs.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_leaf_area_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('expected_area_min', 45.0)
    expected_max = metadata.get('expected_area_max', 65.0)
    unfilled_max = metadata.get('unfilled_area_max', 40.0)

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: File Exists & Timestamp (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Result file created successfully.")
    else:
        feedback.append("Result file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Calibration / Unit Check (30 pts)
    area = result.get("measured_area")
    unit = result.get("unit_inferred")
    
    if area is None:
        feedback.append("No numeric area value found in CSV.")
    elif unit == "pixels":
        feedback.append(f"Value {area:.0f} is too large. Likely raw pixels (uncalibrated). Expected cm².")
    elif unit == "calibrated":
        score += 30
        feedback.append(f"Value {area:.2f} indicates successful spatial calibration.")
    else:
        feedback.append(f"Value {area:.2f} is outside expected magnitude.")

    # Criterion 3: Accuracy / Hole Filling (25 pts)
    # Only check this if calibration passed
    if unit == "calibrated":
        if expected_min <= area <= expected_max:
            score += 25
            feedback.append("Area value is within accuracy range (Holes Filled).")
        elif area <= unfilled_max:
            score += 10
            feedback.append("Area value is too low. Did you forget to 'Fill Holes'? You likely measured only veins.")
        else:
            feedback.append("Area value is outside expected range.")

    # Criterion 4: VLM Workflow Check (25 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = """
        Analyze these screenshots of a user using ImageJ/Fiji.
        Look for these specific steps:
        1. "Set Scale" dialog (entering known distance).
        2. "Threshold" dialog (red/binary overlay).
        3. "Fill Holes" operation or a completely solid black/white leaf shape.
        
        Return JSON:
        {
            "set_scale_seen": bool,
            "threshold_seen": bool,
            "fill_holes_seen": bool,
            "results_table_seen": bool
        }
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('set_scale_seen'):
                vlm_score += 10
            if parsed.get('threshold_seen'):
                vlm_score += 5
            if parsed.get('fill_holes_seen'):
                vlm_score += 5
            if parsed.get('results_table_seen'):
                vlm_score += 5
            
            feedback.append(f"VLM verified workflow steps ({vlm_score}/25 pts).")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if value is correct, award VLM points implicitly
            if score >= 75:
                vlm_score = 25
                feedback.append("VLM skipped, but result proves workflow.")
    else:
        # No VLM available
        if score >= 75:
             vlm_score = 25
             feedback.append("VLM unavailable. Assumed correct workflow based on result.")

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }