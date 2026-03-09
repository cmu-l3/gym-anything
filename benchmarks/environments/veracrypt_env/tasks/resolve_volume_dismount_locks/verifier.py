#!/usr/bin/env python3
"""
Verifier for resolve_volume_dismount_locks task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_volume_dismount_locks(traj, env_info, task_info):
    """
    Verify that the volume was dismounted and the incident report created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Define scoring weights
    SCORE_DISMOUNT = 40
    SCORE_REPORT_EXISTS = 10
    SCORE_REPORT_ACCURACY = 30
    SCORE_PROCESSES_KILLED = 20

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Verify Volume Dismount (40 pts)
    if result.get("volume_dismounted", False):
        score += SCORE_DISMOUNT
        feedback_parts.append("Volume successfully dismounted")
    else:
        feedback_parts.append("Volume is STILL mounted")

    # 2. Verify Processes Terminated (20 pts)
    # The export script checks if the specific PIDs are running
    if not result.get("blocking_processes_running", True):
        score += SCORE_PROCESSES_KILLED
        feedback_parts.append("Blocking processes successfully terminated")
    else:
        feedback_parts.append("Some blocking processes are still running")

    # 3. Verify Report Existence (10 pts)
    report_content = result.get("report_content", "").lower()
    if result.get("report_exists", False) and result.get("report_created_during_task", False):
        score += SCORE_REPORT_EXISTS
        feedback_parts.append("Incident report created")
        
        # 4. Verify Report Accuracy (30 pts)
        # Look for keywords: gedit, tail, python
        found_keywords = []
        expected_keywords = ["gedit", "tail", "python"]
        
        for keyword in expected_keywords:
            if keyword in report_content:
                found_keywords.append(keyword)
        
        if len(found_keywords) >= 3:
            score += SCORE_REPORT_ACCURACY
            feedback_parts.append(f"Report accurately identifies all processes: {', '.join(found_keywords)}")
        elif len(found_keywords) > 0:
            partial_score = int(SCORE_REPORT_ACCURACY * (len(found_keywords) / 3))
            score += partial_score
            feedback_parts.append(f"Report identifies some processes: {', '.join(found_keywords)}")
        else:
            feedback_parts.append("Report content does not list expected process names")
    else:
        feedback_parts.append("Incident report missing or not created during task")

    # Calculate final status
    passed = score >= 80  # Threshold requiring dismount + report + process kill
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }