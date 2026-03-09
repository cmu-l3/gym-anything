#!/usr/bin/env python3
"""
Verifier for open_shift task.

Checks:
1. Database record of a new shift with $200.00 opening balance (Primary).
2. Database files modified during task (Anti-gaming).
3. VLM verification of the workflow (Secondary/Fallback).
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we usually assume gym_anything provides the vlm interface passed to verify function.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_open_shift(traj, env_info, task_info):
    """
    Verifies that the agent opened a new shift with $200.00 balance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utils dynamically if possible or use the provided query_vlm in env logic
    # Here we assume the verifier is run in an environment where we can access VLM helpers
    # via gym_anything.vlm. Since we can't import that here directly in this standalone file 
    # without the framework, we rely on the `query_vlm` function often passed or available.
    # For this template, we'll implement the logic assuming `query_vlm` is not passed but
    # we can use the `traj` images.
    
    # NOTE: In the framework, VLM evaluation is usually done via a helper or 
    # we need to construct the VLM call here if `env_info` provides a client.
    # We will score based on DB results primarily.

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract Data
    db_ver = result.get('db_verification', {})
    shift_found = db_ver.get('shift_found', False)
    opening_balance = db_ver.get('opening_balance', 0.0)
    db_modified = result.get('db_modified', False)
    
    # ---------------------------------------------------------
    # Criterion 1: Database Verification (Max 60 points)
    # ---------------------------------------------------------
    if shift_found:
        score += 30
        feedback_parts.append("New shift record found.")
        
        # Check Balance
        expected = 200.00
        if abs(opening_balance - expected) < 0.01:
            score += 30
            feedback_parts.append(f"Opening balance is correct (${opening_balance}).")
        else:
            feedback_parts.append(f"Opening balance incorrect (Found: ${opening_balance}, Expected: $200.00).")
    else:
        # If DB query failed but files were modified, we give partial credit and rely on VLM
        if db_modified:
            score += 10
            feedback_parts.append("Database files modified, but specific record could not be verified (programmatic check failed).")
        else:
            feedback_parts.append("No database modification detected.")

    # ---------------------------------------------------------
    # Criterion 2: VLM Verification of Trajectory (Max 40 points)
    # ---------------------------------------------------------
    # This detects if the agent was actually navigating the UI
    # We need to request VLM verification here using the framework's facility
    # Since we don't have direct access to `query_vlm` in this standalone script unless 
    # it's injected, we will simulate the logic or assume the score is adjusted externally.
    # However, standard pattern is to use `gym_anything.vlm` imports.
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying an agent's actions in a POS system (Floreant POS).
    The goal was to Open a New Shift with an opening balance of $200.00.
    
    Review the sequence of images:
    1. Did the agent navigate to the 'Back Office'?
    2. Did the agent enter a PIN (screen with number pad)?
    3. Did the agent see a Shift or Drawer management screen?
    4. Is there any evidence of entering '200' or '$200.00'?
    5. Did the agent return to the main terminal screen at the end?
    
    Respond in JSON:
    {
        "entered_back_office": boolean,
        "saw_shift_screen": boolean,
        "entered_amount": boolean,
        "returned_to_main": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('entered_back_office'): vlm_score += 10
        if parsed.get('saw_shift_screen'): vlm_score += 10
        if parsed.get('entered_amount'): vlm_score += 10
        if parsed.get('returned_to_main'): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/40.")
        
    except Exception as e:
        feedback_parts.append(f"VLM verification failed: {e}")
        # If DB check passed perfectly, we might forgive VLM failure
        if shift_found and score >= 60:
            score += 40 # Grant benefit of doubt if DB is perfect
            feedback_parts.append("Granting visual score based on perfect DB match.")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }