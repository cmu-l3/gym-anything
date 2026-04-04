#!/usr/bin/env python3
"""
Verifier for configure_dine_in_workflow task.
Checks if the agent successfully disabled the Guest Selection prompt for DINE IN orders.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dine_in_workflow(traj, env_info, task_info):
    """
    Verify the task using:
    1. Database state (Primary): 'SHOW_GUEST_SELECTION' should be false/0.
    2. VLM Trajectory (Secondary): Verify navigation and final operational check.
    """
    
    # 1. Setup and retrieve exported data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_log = []
    
    # 2. Primary Verification: Database State (60 points)
    # The export script parses the DB query and returns "true" or "false" string for the value
    guest_selection_value = result_data.get("guest_selection_value", "unknown")
    
    db_success = False
    if guest_selection_value == "false":
        score += 60
        db_success = True
        feedback_log.append("SUCCESS: Database confirms 'Show Guest Selection' is DISABLED.")
    elif guest_selection_value == "true":
        feedback_log.append("FAIL: Database shows 'Show Guest Selection' is still ENABLED.")
    else:
        feedback_log.append(f"FAIL: Could not determine database state (Value: {guest_selection_value}).")

    # 3. Secondary Verification: VLM Trajectory Analysis (40 points)
    # We want to see:
    # a) Back Office access (PIN entry)
    # b) Interaction with Order Type explorer
    # c) Final state showing DINE IN clicked without the popup
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # We combine frames for the VLM to analyze the workflow
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    if not images_to_check:
        feedback_log.append("WARNING: No screenshots available for VLM verification.")
        vlm_score = 0
    else:
        prompt = """
        You are verifying a software configuration task in Floreant POS.
        The goal was to disable the "Guest Count" popup for DINE IN orders.
        
        Review the sequence of screenshots:
        1. Did the user enter the "Back Office" (admin interface)?
        2. Did they navigate to "Explorers" or "Order Type" settings?
        3. In the final frames, does the screen look like an order is being taken (table selection or menu items visible), 
           OR is there a small popup dialog asking "How many guests?" blocking the view?
           
        If the "How many guests" popup is visible in the FINAL frame, the task failed.
        If the user is successfully in the order screen or table map without the popup, the task likely succeeded.
        
        Return JSON:
        {
            "entered_back_office": true/false,
            "accessed_settings": true/false,
            "final_state_no_popup": true/false,
            "reasoning": "..."
        }
        """
        
        try:
            vlm_response = query_vlm(images=images_to_check, prompt=prompt)
            vlm_data = vlm_response.get('parsed', {})
            
            # Score breakdown
            if vlm_data.get('entered_back_office'):
                score += 10
                feedback_log.append("VLM: Confirmed Back Office access.")
            
            if vlm_data.get('accessed_settings'):
                score += 10
                feedback_log.append("VLM: Confirmed settings navigation.")
                
            if vlm_data.get('final_state_no_popup'):
                score += 20
                feedback_log.append("VLM: Final screen confirms no guest count popup blocking the view.")
            else:
                feedback_log.append("VLM: Final screen suggests popup might still be present or workflow incomplete.")
                
        except Exception as e:
            feedback_log.append(f"VLM verification failed: {str(e)}")
            # Fallback: if DB check passed, we give partial credit for VLM to avoid penalizing verification errors
            if db_success:
                score += 20 

    # 4. Final Verdict
    passed = (score >= 70) and db_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }