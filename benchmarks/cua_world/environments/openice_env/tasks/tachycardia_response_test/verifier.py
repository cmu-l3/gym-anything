#!/usr/bin/env python3
"""
Verifier for tachycardia_response_test task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tachycardia_response(traj, env_info, task_info):
    """
    Verify tachycardia simulation task.
    
    Criteria:
    1. Device Created (Multiparameter Monitor) - 20 pts
    2. App Launched (Vital Signs) - 20 pts
    3. Evidence Screenshot Exists - 20 pts
    4. Report Exists - 10 pts
    5. Report Content (Valid HR > 150) - 15 pts
    6. Report Content (Visual observation described) - 15 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Device Created (20 pts)
    if result.get('device_created', False):
        score += 20
        feedback_parts.append("Device created")
    elif result.get('window_increase', 0) >= 1:
        score += 10
        feedback_parts.append("Window count increased (implied device/app)")
    else:
        feedback_parts.append("No device creation detected")

    # 2. App Launched (20 pts)
    if result.get('app_launched', False):
        score += 20
        feedback_parts.append("Vital Signs app launched")
    else:
        feedback_parts.append("Vital Signs app not detected")

    # 3. Evidence Screenshot (20 pts)
    if result.get('evidence_exists', False):
        score += 20
        feedback_parts.append("Evidence screenshot saved")
        
        # Optional: In a real VLM scenario, we would download /tmp/evidence_copy.png
        # and verify it shows a red number. For now, existence is the primary check.
    else:
        feedback_parts.append("Evidence screenshot MISSING")

    # 4. Report Exists (10 pts)
    if result.get('report_exists', False):
        score += 10
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file MISSING")

    # 5. Report HR Value (15 pts)
    max_hr = result.get('max_hr_found', 0)
    target_min = task_info.get('metadata', {}).get('target_hr_min', 150)
    
    if max_hr >= target_min:
        score += 15
        feedback_parts.append(f"Reported HR valid ({max_hr} > {target_min})")
    else:
        feedback_parts.append(f"Reported HR invalid or missing (found: {max_hr})")

    # 6. Report Keywords (15 pts)
    if result.get('report_has_keywords', False):
        score += 15
        feedback_parts.append("Report describes visual alarm")
    else:
        feedback_parts.append("Report missing description of visual alarm")

    # Pass Threshold
    passed = score >= 65 and result.get('evidence_exists', False) and result.get('report_exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }