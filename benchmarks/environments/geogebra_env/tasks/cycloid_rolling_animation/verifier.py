#!/usr/bin/env python3
"""
Verifier for Cycloid Rolling Circle Animation task.

Verification Criteria (100 points total):
1. File Creation (15 pts): File exists and was created during the task.
2. Slider (20 pts): Numeric slider present with max range >= 6.0 (approx 2pi).
3. Circle (20 pts): Circle element present (radius ~1 checked heuristically).
4. Cycloid Curve (25 pts): Curve or Locus command present using trigonometric functions.
5. Annotation (20 pts): Text element present.

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60

def verify_cycloid_rolling_animation(traj, env_info, task_info):
    """Verify the cycloid animation task using exported JSON data."""
    
    # 1. Setup: Retrieve result data from the environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
            
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed to load result: {str(e)}"}

    # 2. Evaluation
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Creation (15 pts)
    file_found = result_data.get("file_found", False)
    file_fresh = result_data.get("file_created_during_task", False)
    
    if file_found and file_fresh:
        score += 15
        feedback_parts.append("File created successfully (+15)")
    elif file_found:
        feedback_parts.append("File found but not created during this task session (0/15)")
    else:
        feedback_parts.append("File 'cycloid_animation.ggb' not found (0/15)")

    # Criterion 2: Slider (20 pts)
    has_slider = result_data.get("has_slider", False)
    slider_max = result_data.get("slider_max", 0.0)
    
    if has_slider:
        if slider_max >= 6.0:
            score += 20
            feedback_parts.append(f"Slider found with sufficient range (max={slider_max}) (+20)")
        else:
            score += 10
            feedback_parts.append(f"Slider found but range too small (max={slider_max} < 6.0) (+10)")
    else:
        feedback_parts.append("No numeric slider found (0/20)")

    # Criterion 3: Rolling Circle (20 pts)
    if result_data.get("has_circle", False):
        score += 20
        feedback_parts.append("Rolling circle found (+20)")
    else:
        feedback_parts.append("No circle element found (0/20)")

    # Criterion 4: Cycloid Curve (25 pts)
    has_curve = result_data.get("has_curve", False)
    uses_trig = result_data.get("curve_uses_trig", False)
    
    if has_curve and uses_trig:
        score += 25
        feedback_parts.append("Cycloid curve found with trigonometric definition (+25)")
    elif has_curve:
        score += 10
        feedback_parts.append("Curve found but trigonometric functions not detected (+10)")
    else:
        feedback_parts.append("No curve/locus found (0/25)")

    # Criterion 5: Annotation (20 pts)
    if result_data.get("has_text", False):
        score += 20
        feedback_parts.append("Text annotation found (+20)")
    else:
        feedback_parts.append("No text annotation found (0/20)")

    # 3. Final Result
    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }