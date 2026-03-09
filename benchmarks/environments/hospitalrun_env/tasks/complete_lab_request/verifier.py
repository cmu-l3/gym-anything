#!/usr/bin/env python3
"""
Verifier for complete_lab_request task.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory for shared utilities if needed, 
# though we rely mainly on data passed from export_result.sh
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_complete_lab_request(traj, env_info, task_info):
    """
    Verify that the lab request was completed with correct data.
    
    Criteria:
    1. Document was modified (anti-gaming)
    2. Status is 'completed'
    3. Result text contains specific values (7.2, 4.8, 14.1, 42.3, 245)
    4. Notes field contains 'normal range'
    5. VLM verification of UI interaction
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    lab_data = result_data.get('lab_data', {})
    
    if not lab_data.get('exists'):
        return {"passed": False, "score": 0, "feedback": "Lab document not found in database."}

    score = 0
    feedback_parts = []
    
    # 1. Check Modification (10 pts)
    if lab_data.get('is_modified'):
        score += 10
        feedback_parts.append("Record modified successfully")
    else:
        feedback_parts.append("Record NOT modified")
        return {"passed": False, "score": 0, "feedback": "The lab record was not modified at all."}

    # 2. Check Status (20 pts)
    status = lab_data.get('status', '').lower()
    if status == 'completed':
        score += 20
        feedback_parts.append("Status is 'completed'")
    else:
        feedback_parts.append(f"Status is '{status}' (expected 'completed')")

    # 3. Check Result Values (50 pts, 10 per value)
    result_text = lab_data.get('result_text', '')
    
    # Values to look for: 7.2, 4.8, 14.1, 42.3, 245
    # We check string inclusion, being flexible about spacing
    checks = {
        "WBC (7.2)": "7.2",
        "RBC (4.8)": "4.8",
        "Hgb (14.1)": "14.1",
        "Hct (42.3)": "42.3",
        "Plt (245)": "245"
    }
    
    val_score = 0
    missing_vals = []
    for label, val in checks.items():
        if val in result_text:
            val_score += 10
        else:
            missing_vals.append(label)
    
    score += val_score
    if not missing_vals:
        feedback_parts.append("All result values present")
    else:
        feedback_parts.append(f"Missing values: {', '.join(missing_vals)}")

    # 4. Check Notes (10 pts)
    notes = lab_data.get('notes', '').lower()
    if "normal range" in notes:
        score += 10
        feedback_parts.append("Notes correct")
    else:
        feedback_parts.append("Notes missing 'normal range'")

    # 5. VLM / Trajectory Verification (10 pts)
    # Simple check: did we get screenshots?
    # In a full implementation, we'd use the VLM to check the UI state in trajectory frames
    # Here we'll award points if the task seems legitimately attempted based on file mod
    # and meaningful content changes.
    if val_score >= 30 and status == 'completed':
        score += 10 # Bonus for coherent completion
    
    passed = (score >= 60) and (status == 'completed') and (val_score >= 30)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }