#!/usr/bin/env python3
"""
Verifier for correct_visitor_signout_time task.
"""

import json
import os
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_visitor_signout_time(traj, env_info, task_info):
    """
    Verifies that the agent corrected the sign-out time for Elena Fisher.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    target_visitor = f"{metadata.get('target_visitor_first', 'Elena')} {metadata.get('target_visitor_last', 'Fisher')}"
    target_time_str = metadata.get('target_time_string', "12:15")
    
    # Retrieve Result JSON
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verification Logic
    score = 0
    feedback_parts = []
    max_score = 100

    # Criterion 1: File Exists (20 pts)
    if result.get("file_exists", False):
        score += 20
        feedback_parts.append("Export file found")
    else:
        return {"passed": False, "score": 0, "feedback": "Export file 'corrected_log.csv' not found in Documents."}

    # Decode Content
    content_b64 = result.get("file_content_b64", "")
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        content = ""

    # Parse CSV roughly (looking for the row with the visitor)
    visitor_found = False
    time_corrected = False
    status_out = False
    
    lines = content.splitlines()
    target_row = ""
    
    # Simple substring search first
    if target_visitor in content:
        visitor_found = True
        # Find the specific line
        for line in lines:
            if target_visitor in line:
                target_row = line
                break
    
    # Criterion 2: Visitor Record Present in Log (20 pts)
    if visitor_found:
        score += 20
        feedback_parts.append(f"Visitor '{target_visitor}' found in log")
    else:
        feedback_parts.append(f"Visitor '{target_visitor}' NOT found in log")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback_parts)}

    # Criterion 3: Status is Out (20 pts)
    # Look for "Out", "Signed Out", or non-empty sign-out time column
    # We assume standard CSV format where fields are comma separated.
    # We look for indications of being out.
    if "Out" in target_row or "Signed Out" in target_row:
        status_out = True
        score += 20
        feedback_parts.append("Status updated to Signed Out")
    else:
        # Heuristic: if 12:15 is present, they are likely signed out
        if target_time_str in target_row:
            status_out = True
            score += 20
            feedback_parts.append("Status likely Out (timestamp present)")
        else:
            feedback_parts.append("Visitor status does not appear to be 'Out'")

    # Criterion 4: Time Corrected to 12:15 (40 pts)
    # This is the core instruction.
    if target_time_str in target_row:
        time_corrected = True
        score += 40
        feedback_parts.append(f"Sign-out time correctly set to {target_time_str}")
    else:
        feedback_parts.append(f"Sign-out time '{target_time_str}' NOT found in visitor record")

    passed = (score >= 80) # Requires at least file + visitor + time or status

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }