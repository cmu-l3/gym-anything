#!/usr/bin/env python3
"""
Verifier for Flight Operations Manual Revision task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flight_manual_revision(traj, env_info, task_info):
    """
    Verifies the ODT revision task based on criteria:
    1. File exists and saved during task.
    2. Text content is updated.
    3. Revision bar (left border) is applied.
    4. Warning box (border + bold) is formatted.
    5. Header is updated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the result JSON from the container
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
            
    # Initialize Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Timestamp (10 pts)
    if result.get("file_exists") and result.get("file_saved_during_task"):
        score += 10
        feedback_parts.append("File saved successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found or not saved during task."}

    # Criterion 2: Text Updated (25 pts)
    if result.get("text_updated"):
        score += 25
        feedback_parts.append("Text updated correctly.")
    else:
        feedback_parts.append("Text content not updated.")

    # Criterion 3: Revision Bar (Left Border) (25 pts)
    if result.get("revision_bar_found"):
        score += 25
        feedback_parts.append("Revision bar (left border) applied.")
    else:
        feedback_parts.append("Revision bar missing.")

    # Criterion 4: Warning Box Formatting (20 pts)
    # 10 pts for border, 10 pts for bold
    if result.get("warning_box_found"):
        score += 10
        feedback_parts.append("Warning box border applied.")
    
    if result.get("warning_bold_found"):
        score += 10
        feedback_parts.append("Warning text bolded.")

    # Criterion 5: Header Updated (20 pts)
    if result.get("header_updated"):
        score += 20
        feedback_parts.append("Header updated to Revision 05.")
    else:
        feedback_parts.append("Header not updated.")

    # Check for VLM verification (optional boost if VLM detects visual border)
    # For now, we rely on the robust XML parsing logic above.

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }