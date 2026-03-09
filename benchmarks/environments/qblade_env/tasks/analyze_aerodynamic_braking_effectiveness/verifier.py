#!/usr/bin/env python3
"""
Verifier for analyze_aerodynamic_braking_effectiveness task.

Criteria:
1. QBlade Project file saved & modified during task.
2. Report text file exists & modified during task.
3. Report contains logical values for Runaway TSR at 0deg and 5deg.
   - 0deg TSR should be roughly 11.0 - 16.0
   - 5deg TSR should be roughly 7.0 - 12.0
   - 0deg TSR MUST be > 5deg TSR (braking effect)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_braking_analysis(traj, env_info, task_info):
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Metadata / Ground Truth
    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})
    tsr_0_min = gt.get('tsr_0deg_min', 11.0)
    tsr_0_max = gt.get('tsr_0deg_max', 16.0)
    tsr_5_min = gt.get('tsr_5deg_min', 7.0)
    tsr_5_max = gt.get('tsr_5deg_max', 12.0)
    min_diff = gt.get('min_difference', 1.0)

    # 3. Retrieve Result JSON
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

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Check Project File (10 pts)
    if result.get('project_exists') and result.get('project_created_during_task'):
        score += 10
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file missing or not saved during task")

    # Check Report File Existence (10 pts)
    if result.get('report_exists') and result.get('report_created_during_task'):
        score += 10
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file missing")

    # Check TSR Values
    try:
        val_0 = float(result.get('tsr_0_val', 0))
        val_5 = float(result.get('tsr_5_val', 0))
    except (ValueError, TypeError):
        val_0 = 0.0
        val_5 = 0.0
        feedback_parts.append("Could not parse numeric values from report")

    # Score 0 deg value (30 pts)
    if tsr_0_min <= val_0 <= tsr_0_max:
        score += 30
        feedback_parts.append(f"0° TSR correct ({val_0})")
    elif val_0 > 0:
        score += 10 # Partial credit for finding a number
        feedback_parts.append(f"0° TSR out of range ({val_0}, expected {tsr_0_min}-{tsr_0_max})")
    else:
        feedback_parts.append("0° TSR not found")

    # Score 5 deg value (30 pts)
    if tsr_5_min <= val_5 <= tsr_5_max:
        score += 30
        feedback_parts.append(f"5° TSR correct ({val_5})")
    elif val_5 > 0:
        score += 10 # Partial credit
        feedback_parts.append(f"5° TSR out of range ({val_5}, expected {tsr_5_min}-{tsr_5_max})")
    else:
        feedback_parts.append("5° TSR not found")

    # Score Physics/Logic (20 pts)
    # The runaway speed must decrease when pitch is increased (braking effect)
    if val_0 > (val_5 + min_diff) and val_5 > 0:
        score += 20
        feedback_parts.append("Braking effect confirmed (0° > 5°)")
    elif val_0 > 0 and val_5 > 0:
        feedback_parts.append(f"Logic error: 0° TSR ({val_0}) not significantly higher than 5° TSR ({val_5})")
    
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }