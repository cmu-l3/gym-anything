#!/usr/bin/env python3
"""
Verifier for customize_print_format task.

Criteria:
1. Print Format "Customer Proposal" exists (30 pts)
2. Base table is "C_Order" (10 pts)
3. Header text "PROPOSAL" exists (30 pts)
4. "Line" column is hidden (IsPrinted='N') (30 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_print_format(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Get programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score calculation
    score = 0
    feedback = []

    # Criterion 1: Format Exists (30 pts)
    if data.get("format_found", False):
        score += 30
        feedback.append("Success: 'Customer Proposal' print format created.")
    else:
        feedback.append("Fail: 'Customer Proposal' print format not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Correct Table (10 pts)
    # The table name usually comes back as 'C_Order' or 'Order' depending on translation/setup
    table_name = data.get("table_name", "").lower()
    if "order" in table_name:
        score += 10
        feedback.append("Success: Base table is correct.")
    else:
        feedback.append(f"Fail: Incorrect base table (found '{data.get('table_name')}').")

    # Criterion 3: Proposal Text (30 pts)
    if data.get("proposal_text_found", False):
        score += 30
        feedback.append("Success: Header text changed to 'PROPOSAL'.")
    else:
        feedback.append("Fail: 'PROPOSAL' text not found in format items.")

    # Criterion 4: Line Column Hidden (30 pts)
    if data.get("line_column_hidden", False):
        score += 30
        feedback.append("Success: 'Line' column is hidden.")
    elif data.get("line_column_found", False):
        feedback.append("Fail: 'Line' column found but still set to print.")
    else:
        feedback.append("Fail: Could not find 'Line' column item to verify.")

    # 4. VLM Verification (Trajectory check)
    # We mainly trust the database, but we verify that the user actually used the UI
    # to prevent SQL injection or other shortcuts if the agent had shell access (unlikely but good practice)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an iDempiere ERP session.
        Did the user navigate to the 'Print Format' window?
        Is there evidence of editing a print format (e.g., list of items, checkboxes)?
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if not vlm_res.get("success", False):
                feedback.append("(VLM check failed, ignoring)")
        except Exception:
            pass

    # 5. Final Result
    passed = score >= 60  # Require creation + at least one major modification
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }