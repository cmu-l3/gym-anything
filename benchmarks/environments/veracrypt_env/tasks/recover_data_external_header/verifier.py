#!/usr/bin/env python3
import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recover_data_external_header(traj, env_info, task_info):
    """
    Verify the external header recovery task.
    
    Criteria:
    1. File 'Project_Alpha_Budget.csv' is recovered to expected folder (40 pts)
    2. File content matches original (hash check) (20 pts)
    3. Volume state is preserved (header NOT permanently restored) (30 pts)
    4. Volume is dismounted at the end (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Data Recovery (60 pts total)
    if result.get("file_recovered", False):
        if result.get("file_integrity", False):
            score += 60
            feedback_parts.append("File recovered successfully with correct content")
        else:
            score += 40
            feedback_parts.append("File recovered but content mismatch (integrity check failed)")
    else:
        feedback_parts.append("Target file not found in recovery directory")

    # 2. Volume Integrity (30 pts)
    # Critical check: Did agent modify the volume on disk?
    if result.get("volume_intact", False):
        score += 30
        feedback_parts.append("Volume header preserved (Non-destructive recovery verified)")
    else:
        feedback_parts.append("FAIL: Volume header was permanently overwritten (Destructive recovery detected)")

    # 3. Clean State (10 pts)
    if result.get("is_dismounted_clean", False):
        score += 10
        feedback_parts.append("Volume clean dismounted")
    else:
        feedback_parts.append("Volume left mounted")

    # Final scoring
    passed = (score >= 90) # Requires almost perfection (Recovery + Integrity + Preservation)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }