#!/usr/bin/env python3
"""
Verifier for generate_alert_report_pdf task.

Verification Strategy:
1. File Existence: Checks /home/ga/Downloads for a PDF file.
2. File Content: Checks if the file is actually a PDF (magic bytes).
3. Filename: Checks if the filename contains expected keywords ("Structural", "Quality Alert").
4. Timing: Checks if the file was created during the task (anti-gaming).
5. VLM (Optional): Could verify visual content, but file check is strong enough here.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_alert_report_pdf(traj, env_info, task_info):
    """
    Verify that a quality alert PDF report was downloaded.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence (40 pts)
    file_found = result.get("file_found", False)
    file_name = result.get("file_name", "")
    
    if file_found:
        score += 40
        feedback_parts.append(f"File found: {file_name}")
    else:
        feedback_parts.append("No relevant file found in Downloads")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check File Format (20 pts)
    is_pdf = result.get("is_pdf", False)
    if is_pdf:
        score += 20
        feedback_parts.append("File is a valid PDF")
    else:
        feedback_parts.append("File is NOT a valid PDF")

    # 3. Check Filename Specificity (30 pts)
    # Ideally should contain "Structural" or "Desk" from the alert name
    # "Quality Alert" is the generic prefix Odoo uses
    name_lower = file_name.lower()
    if "structural" in name_lower or "desk" in name_lower:
        score += 30
        feedback_parts.append("Filename matches specific alert")
    elif "quality alert" in name_lower:
        score += 15
        feedback_parts.append("Filename is generic ('Quality Alert') but accepted")
    else:
        feedback_parts.append("Filename does not match expected pattern")

    # 4. Check Timing / Anti-Gaming (10 pts)
    created_during_task = result.get("created_during_task", False)
    if created_during_task:
        score += 10
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("File creation timestamp is outside task window (old file?)")
        # Penalize if it's an old file
        score = max(0, score - 20)

    # Final Pass/Fail
    passed = score >= 70 and file_found and is_pdf

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }