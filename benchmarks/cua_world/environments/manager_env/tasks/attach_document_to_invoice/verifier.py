#!/usr/bin/env python3
"""
Verifier for attach_document_to_invoice task.

Checks:
1. JSON result: Invoice was found and 'proof_of_delivery.pdf' is attached.
2. VLM: Trajectory shows usage of file picker/upload dialog.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_attach_document(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load JSON Result
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

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: Invoice Found (20 pts)
    if result.get("invoice_found", False):
        score += 20
        feedback_parts.append("Target invoice located")
    else:
        feedback_parts.append("Target invoice NOT located")

    # Criterion 2: Attachment Present (40 pts)
    if result.get("attachment_found", False):
        score += 40
        feedback_parts.append("Document successfully attached")
    else:
        feedback_parts.append("Document NOT attached to invoice")

    # Criterion 3: VLM - File Picker Usage (40 pts)
    # This prevents 'gaming' where one might somehow drag-drop without using standard flow,
    # or verifies the interaction actually happened in the UI.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of an agent using accounting software.
    Look for evidence that the agent uploaded a file.
    
    Key indicators:
    1. A system file picker / "Open File" dialog is visible.
    2. The agent is interacting with an "Attachments" or "New Attachment" button.
    3. The filename "proof_of_delivery.pdf" is visible in a file dialog or on screen.
    
    Did the agent perform a file upload interaction?
    Return JSON: {"upload_interaction_detected": true/false, "reason": "..."}
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
    
    upload_detected = False
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("upload_interaction_detected", False):
            upload_detected = True
            score += 40
            feedback_parts.append("VLM confirmed file upload interaction")
        else:
            feedback_parts.append("VLM did not detect file upload dialog")
    else:
        # Fallback if VLM fails: give partial credit if attachment exists
        if result.get("attachment_found", False):
            score += 20
            feedback_parts.append("VLM check skipped, partial credit")

    passed = score >= 60 and result.get("attachment_found", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }