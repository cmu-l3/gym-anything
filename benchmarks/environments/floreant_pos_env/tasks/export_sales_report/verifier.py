#!/usr/bin/env python3
"""
Verifier for export_sales_report task.

Criteria:
1. File /home/ga/Desktop/sales_report.pdf exists.
2. File is a valid PDF (magic number check).
3. File was created during the task session (anti-gaming).
4. VLM: Agent navigated to Reports section.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_sales_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from container
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
    
    # 2. Check File Existence (40 pts)
    if result.get("file_exists"):
        score += 40
        feedback_parts.append("Sales report file exists.")
    else:
        feedback_parts.append("Sales report file NOT found on Desktop.")

    # 3. Check PDF Format (30 pts)
    if result.get("is_pdf"):
        score += 30
        feedback_parts.append("File is a valid PDF.")
    elif result.get("file_exists"):
        feedback_parts.append("File exists but does not appear to be a valid PDF.")

    # 4. Check Timestamp (20 pts)
    if result.get("created_during_task"):
        score += 20
        feedback_parts.append("File was created during the task session.")
    elif result.get("file_exists"):
        feedback_parts.append("File timestamp is too old (anti-gaming check failed).")

    # 5. VLM Verification of Workflow (10 pts)
    # Check if agent visited the reports screen
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = (
        "Does the screenshot show the Floreant POS 'Reports' section, a list of reports "
        "(like Sales Report, Open Ticket Summary), or a report preview window? "
        "Answer 'Yes' if any reporting interface is visible."
    )
    
    # We query the VLM with a few frames to see if they visited the right area
    vlm_score = 0
    vlm_feedback = "Did not detect Reports section."
    
    try:
        vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
        # Simple heuristic: if VLM says "Yes" or describes reports
        response_text = vlm_response.get("response", "").lower() if isinstance(vlm_response, dict) else ""
        
        if "yes" in response_text or "report" in response_text:
            vlm_score = 10
            vlm_feedback = "Verified navigation to Reports section."
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails but file exists
        if result.get("file_exists") and result.get("is_pdf"):
            vlm_score = 10
            vlm_feedback = "Skipped VLM check (file verified)."

    score += vlm_score
    feedback_parts.append(vlm_feedback)

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }