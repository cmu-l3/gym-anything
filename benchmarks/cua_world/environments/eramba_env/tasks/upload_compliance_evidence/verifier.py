#!/usr/bin/env python3
"""
Verifier for upload_compliance_evidence task.

VERIFICATION CRITERIA:
1. Attachment Presence (40 pts): 'attachments' table has record for the ComplianceAnalysis ID.
2. Correct File (40 pts): filename matches 'Backup_Log_Sept2025.pdf'.
3. Anti-gaming (20 pts): 'created' timestamp is after task start.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_compliance_evidence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('evidence_filename', 'Backup_Log_Sept2025.pdf')
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Extract data
    count = result.get('attachment_found_count', 0)
    actual_filename = result.get('last_attachment_filename', '')
    is_newly_created = result.get('is_newly_created', False)
    
    score = 0
    feedback_parts = []
    
    # Check 1: Attachment exists
    if count > 0:
        score += 40
        feedback_parts.append("Attachment record found in database.")
    else:
        feedback_parts.append("No attachment found linked to the compliance record.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
        
    # Check 2: Correct Filename
    if actual_filename == expected_filename:
        score += 40
        feedback_parts.append(f"Filename matches '{expected_filename}'.")
    else:
        feedback_parts.append(f"Wrong filename: found '{actual_filename}', expected '{expected_filename}'.")
        
    # Check 3: Timestamp (Anti-gaming)
    if is_newly_created:
        score += 20
        feedback_parts.append("Upload timestamp valid (occurred during task).")
    else:
        feedback_parts.append("Attachment timestamp is stale (pre-dates task start).")

    # Optional VLM Verification for robustness (if close to passing but maybe ambiguous)
    # Using trajectory to confirm interaction with file dialog
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = f"Does the user appear to be uploading a file named '{expected_filename}' to a compliance analysis record?"
    
    # We only call VLM if we have partial success or want to confirm visual UI state
    # But for this task, DB verification is robust enough. 
    # We will log it for completeness but rely on DB for score to be deterministic.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }