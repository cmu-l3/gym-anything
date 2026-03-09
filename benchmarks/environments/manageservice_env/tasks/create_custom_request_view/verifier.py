#!/usr/bin/env python3
"""
Verifier for create_custom_request_view task.

Verifies:
1. View existence in DB.
2. Correct criteria logic (Priority, Technician, Status).
3. Evidence from screenshots (VLM).
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_request_view(traj, env_info, task_info):
    """
    Verify that the 'Critical Unassigned Triage' view was created with correct criteria.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load results from container
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

    score = 0
    feedback_parts = []
    
    # 2. DB Verification
    view_found = result.get('view_found', False)
    view_criteria = result.get('view_criteria_raw', "")
    
    if view_found:
        score += 30
        feedback_parts.append("View created in database.")
    else:
        feedback_parts.append("View 'Critical Unassigned Triage' NOT found in database.")
        
    # Check criteria content
    # We look for keywords in the raw DB output because column mapping is version-dependent.
    # Typically criteria rows contain: ColumnName, Value.
    
    criteria_lower = view_criteria.lower()
    
    # Priority: High
    if "priority" in criteria_lower and "high" in criteria_lower:
        score += 20
        feedback_parts.append("Priority criterion found.")
    else:
        feedback_parts.append("Missing or incorrect 'Priority' criterion.")

    # Status: Open
    if "status" in criteria_lower and "open" in criteria_lower:
        score += 10
        feedback_parts.append("Status criterion found.")
    else:
        feedback_parts.append("Missing or incorrect 'Status' criterion.")

    # Technician: Unassigned (stored as 'null' or empty string often, or matching 'technician' column with null comparator)
    # Common DB representation: 'technicianID' ... 'null' or 'is empty'
    tech_check = False
    if "technician" in criteria_lower:
        if "null" in criteria_lower or "empty" in criteria_lower or "unassigned" in criteria_lower:
            tech_check = True
    
    if tech_check:
        score += 20
        feedback_parts.append("Technician criterion found.")
    else:
        feedback_parts.append("Missing or incorrect 'Technician' criterion.")

    # 3. VLM Verification
    # We use VLM to verify the UI state, which acts as a secondary check 
    # and confirms the user actually interacted with the UI (anti-gaming).
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    I am verifying if an agent created a custom view in a helpdesk system.
    Goal: Create a view named 'Critical Unassigned Triage'.
    
    Look at the sequence of images and the final image.
    1. Do you see a form for creating or editing a "Custom View"?
    2. In that form, are there filters for Priority (High), Status (Open), or Technician (Unassigned)?
    3. In the final image, is the view 'Critical Unassigned Triage' visible/selected in the header?
    
    Answer JSON: {"form_seen": bool, "criteria_seen": bool, "final_view_active": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).get('parsed', {})
        
        if vlm_res.get('form_seen'):
            score += 5
        if vlm_res.get('criteria_seen'):
            score += 5
        if vlm_res.get('final_view_active'):
            score += 10
            feedback_parts.append("Visual confirmation: View is active.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if DB passed, we assume good faith, but max score is limited if VLM fails entirely? 
        # No, we just don't add VLM points.

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }