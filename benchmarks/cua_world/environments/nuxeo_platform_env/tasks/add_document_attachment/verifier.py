#!/usr/bin/env python3
"""
Verifier for add_document_attachment task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_document_attachment(traj, env_info, task_info):
    """
    Verify that the supplementary file was attached correctly without removing the main file.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error in export script: {result['error']}"}

    score = 0
    feedback = []

    # -----------------------------------------------------------------------
    # Programmatic Verification (65 points max)
    # -----------------------------------------------------------------------
    
    # Criterion 1: Document Exists (5 pts)
    if result.get('doc_exists'):
        score += 5
    else:
        feedback.append("Document 'Project Proposal' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Main File Preserved (15 pts)
    if result.get('main_file_preserved'):
        score += 15
        feedback.append(f"Main file '{result.get('main_file_name')}' preserved.")
    else:
        feedback.append("Main file was deleted or replaced.")

    # Criterion 3: Attachment Present (25 pts)
    # We check if target is found directly
    if result.get('target_attachment_found'):
        score += 25
        feedback.append(f"Target attachment '{result.get('target_attachment_name')}' found.")
    elif result.get('count_increased'):
        score += 10 # Partial credit if something was attached but name mismatch
        feedback.append("An attachment was added, but filename did not match 'Q3_Status_Report'.")
    else:
        feedback.append("No new attachments found.")

    # Criterion 4: Attachment Content/Size (10 pts)
    # 0-byte check
    if result.get('target_attachment_found') and result.get('target_attachment_size', 0) > 0:
        score += 10
    elif result.get('target_attachment_found'):
        feedback.append("Attachment exists but is 0 bytes (empty file).")

    # Criterion 5: Modified Time (10 pts)
    if result.get('modified_after_start') or result.get('timestamp_changed'):
        score += 10
    else:
        feedback.append("Document modification timestamp did not change.")

    # -----------------------------------------------------------------------
    # VLM Verification (35 points max)
    # -----------------------------------------------------------------------
    # We want to see:
    # 1. Edit Mode (User entered edit form)
    # 2. File Picker / Upload interaction
    # 3. No Errors

    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with Nuxeo Platform.
    The goal was to Attach a supplementary file (Q3 Status Report) to a document.
    
    Look for:
    1. The 'Edit' form of a document (showing metadata fields).
    2. Interaction with an 'Attachments' or 'Files' section (distinct from Main Content).
    3. A file upload dialog or file picker selecting a PDF.
    4. Any red error messages or crash dialogs.
    
    Return JSON:
    {
        "edit_mode_seen": true/false,
        "attachments_interaction_seen": true/false,
        "file_picker_seen": true/false,
        "errors_present": true/false,
        "explanation": "brief description"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('edit_mode_seen'):
            score += 10
            feedback.append("VLM: Edit mode verified.")
        
        if parsed.get('attachments_interaction_seen') or parsed.get('file_picker_seen'):
            score += 20
            feedback.append("VLM: Attachment upload interaction verified.")
            
        if not parsed.get('errors_present'):
            score += 5
        else:
            feedback.append("VLM: Detected potential error messages.")
    else:
        # Fallback if VLM fails but programmatic passed
        if score >= 50:
             score += 10 # Give benefit of doubt if VLM fails technically
             feedback.append("VLM check skipped (service unavailable).")

    # -----------------------------------------------------------------------
    # Final Decision
    # -----------------------------------------------------------------------
    # Threshold: 70
    # Mandatory: Attachment must be present (target_attachment_found)
    
    mandatory_met = result.get('target_attachment_found') and result.get('main_file_preserved')
    
    final_passed = (score >= 70) and mandatory_met
    
    return {
        "passed": final_passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }