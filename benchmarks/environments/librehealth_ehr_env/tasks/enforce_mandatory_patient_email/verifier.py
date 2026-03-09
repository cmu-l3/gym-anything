#!/usr/bin/env python3
"""
Verifier for enforce_mandatory_patient_email task.

Verification Strategy:
1. Database Check (Primary): Verify 'layout_options' table has uor=2 for 'email'.
2. State Change Check (Anti-gaming): Verify uor changed from 1 to 2 during task.
3. VLM Verification (Secondary): Check trajectory for Layout Editor interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_mandatory_patient_email(traj, env_info, task_info):
    """
    Verify that the agent set the email field to required.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Step 1: Retrieve Result JSON ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Step 2: Database Configuration Verification (Primary) ---
    initial_uor = result.get('initial_uor', -1)
    final_uor = result.get('final_uor', -1)
    
    # Expected: 2 (Required)
    # OpenEMR/LibreHealth UOR codes: 0=Unused, 1=Optional, 2=Required
    
    if final_uor == 2:
        score += 50
        feedback_parts.append("Database configuration correct (Email is Required).")
    elif final_uor == 1:
        feedback_parts.append("Database check failed: Email is still Optional.")
    elif final_uor == 0:
        feedback_parts.append("Database check failed: Email is set to Unused.")
    else:
        feedback_parts.append(f"Database check failed: Unknown state {final_uor}.")

    # --- Step 3: Anti-Gaming / Action Verification ---
    # Ensure the state actually CHANGED. If it started as 2 (setup error) and ended as 2,
    # the agent might have done nothing. Setup script tries to force 1, but we verify here.
    if initial_uor != 2 and final_uor == 2:
        score += 30
        feedback_parts.append("Configuration change verified (Action performed).")
    elif initial_uor == 2 and final_uor == 2:
        # Fallback if setup failed to reset, but agent preserved the correct state
        # We give partial credit but flag it
        score += 10
        feedback_parts.append("Configuration is correct, but was already correct at start (Setup issue?).")
    elif final_uor != 2:
        pass # Already handled above

    # --- Step 4: VLM Trajectory Verification ---
    # We want to see if the agent actually visited the Layout Editor
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's workflow in an Electronic Health Record system.
    The goal was to modify a layout configuration.
    
    Look at these screenshots and answer:
    1. Did the agent navigate to an 'Administration' or 'Layouts' page?
    2. Is there a table of fields or a form builder visible?
    3. Is 'Demographics' or 'Email' visible in the configuration screens?
    
    Return JSON: {"layout_editor_visited": bool, "confidence": float}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    layout_visited = False
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('layout_editor_visited', False):
            layout_visited = True
            score += 20
            feedback_parts.append("Visual evidence of Layout Editor navigation found.")
        else:
            feedback_parts.append("No visual evidence of Layout Editor navigation.")
    else:
        # Fallback if VLM fails but DB is correct
        if final_uor == 2:
            score += 20
            feedback_parts.append("VLM unavailable, but DB check passed.")

    # --- Final Scoring ---
    passed = (score >= 90) # Requires correct DB state (50) + Change performed (30) + VLM/Nav (20) roughly
    
    # Hard fail if DB state is wrong
    if final_uor != 2:
        passed = False
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }