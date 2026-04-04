#!/usr/bin/env python3
"""
Verifier for create_delivery_note@1.
Verifies that the Delivery Notes module was enabled and a specific delivery note was created.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_delivery_note(traj, env_info, task_info):
    """
    Verify the task using data exported from the container + VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
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
    feedback = []

    # --- Programmatic Criteria (80 points total) ---

    # 1. Module Enabled (15 pts)
    if result.get("module_enabled"):
        score += 15
        feedback.append("Delivery Notes module successfully enabled.")
    else:
        feedback.append("Failed to enable Delivery Notes module.")

    # 2. Note Created (10 pts)
    if result.get("new_notes_created", 0) > 0:
        score += 10
        feedback.append("New delivery note created.")
    else:
        feedback.append("No new delivery note found.")

    # 3. Content Verification (55 pts)
    note_data = result.get("latest_note", {})
    
    if note_data.get("customer_match"):
        score += 15
        feedback.append("Correct customer (Ernst Handel).")
    else:
        feedback.append("Incorrect customer.")

    if note_data.get("date_match"):
        score += 10
        feedback.append("Correct date (2025-01-15).")
    else:
        feedback.append("Incorrect date.")

    if note_data.get("item_chai_match"):
        score += 12
        feedback.append("Line item 1 (Chai, 24) correct.")
    else:
        feedback.append("Line item 1 missing or incorrect quantity.")

    if note_data.get("item_chang_match"):
        score += 12
        feedback.append("Line item 2 (Chang, 12) correct.")
    else:
        feedback.append("Line item 2 missing or incorrect quantity.")

    if note_data.get("address_match"):
        score += 6
        feedback.append("Delivery instructions included.")
    else:
        feedback.append("Delivery instructions missing.")

    # --- VLM Verification (20 points total) ---
    # We check if the agent actually navigated the settings and form
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for VLM
    prompt = """
    Analyze these screenshots of a user interacting with accounting software (Manager.io).
    I need to verify if the user:
    1. Went to 'Settings' or 'Customize' to enable a module.
    2. Filled out a 'Delivery Note' form.
    3. The final screen shows a saved Delivery Note.
    
    Return JSON:
    {
      "settings_visited": boolean,
      "form_filled": boolean,
      "final_result_visible": boolean,
      "confidence": float
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
        parsed = vlm_res.get("parsed", {})
        
        vlm_score = 0
        if parsed.get("settings_visited"):
            vlm_score += 8
            feedback.append("VLM confirmed Settings navigation.")
        if parsed.get("form_filled"):
            vlm_score += 7
            feedback.append("VLM confirmed form entry.")
        if parsed.get("final_result_visible"):
            vlm_score += 5
            feedback.append("VLM confirmed final document visibility.")
            
        score += vlm_score
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback.append("VLM verification skipped due to error.")
        # Fallback: Award partial points if programmatic check passed strongly
        if score >= 60:
            score += 10
            feedback.append("Awarded fallback points for strong programmatic result.")

    # --- Final Result ---
    # Pass threshold: 60 points + Module Enabled + Note Created
    key_criteria_met = result.get("module_enabled") and (result.get("new_notes_created", 0) > 0)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }