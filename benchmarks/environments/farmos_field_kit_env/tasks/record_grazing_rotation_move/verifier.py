#!/usr/bin/env python3
"""
Verifier for record_grazing_rotation_move task.

Verification Strategy:
1. VLM Trajectory Analysis (Primary):
   - Did the agent select "Activity" type?
   - Did the agent change the date to Jan 6, 2025?
   - Did the agent type the full detailed note?
   - Did the agent enter quantity 24 and unit 'head'?
2. App State Check:
   - Was the app running at the end?
   - Does the final screen show the saved log in the list?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grazing_log(traj, env_info, task_info):
    """
    Verify the creation of the grazing rotation log using VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_phrases = metadata.get('required_phrases', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Artifacts from Container
    # ================================================================
    temp_dir = tempfile.mkdtemp()
    try:
        # Copy result JSON
        local_result_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/tasks/record_grazing_rotation_move/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load result JSON: {e}")
            result_data = {}

        # Check if app was running (Basic check - 10 pts)
        if result_data.get("app_was_running", False):
            score += 10
            feedback_parts.append("App was running at end.")
        else:
            feedback_parts.append("App crashed or was closed.")

    finally:
        # Cleanup is handled by VLM logic mostly, but good practice
        pass

    # ================================================================
    # 2. VLM Trajectory Verification (Primary - 90 pts)
    # ================================================================
    
    # Sample frames to see the workflow (Edit screen, typing, saving)
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    
    # Construct VLM Prompt
    prompt = f"""
    You are verifying an agent's performance in the farmOS Field Kit app.
    The agent was tasked with creating a specific grazing log.
    
    EXPECTED DETAILS:
    1. Log Type: "Activity"
    2. Date: "Jan 6, 2025" (or 2025-01-06)
    3. Quantity: "24" with unit "head"
    4. Notes must contain specific details about pastures and forage.
    
    Analyze the screenshots sequence to answer:
    
    Q1. Did the agent create a NEW log? (Look for tapping '+' and 'Edit Log' screen)
    Q2. Did the agent set the Date to Jan 6, 2025?
    Q3. Did the agent enter a long text note containing phrases like "North Pasture A", "residual forage", "3 inches"?
    Q4. Did the agent set Quantity to 24 and unit to "head"?
    Q5. Did the agent SAVE the log (tap back/check)?
    Q6. Does the final screen show the new log in the list (showing date Jan 6)?
    
    Respond in JSON format:
    {{
        "log_created": true/false,
        "date_correct": true/false,
        "notes_entered_detailed": true/false,
        "quantity_correct": true/false,
        "saved_successfully": true/false,
        "final_list_verified": true/false,
        "confidence": "low/medium/high"
    }}
    """
    
    try:
        # Query VLM with all frames including final
        all_images = frames + [final_frame] if final_frame else frames
        vlm_response = query_vlm(images=all_images, prompt=prompt)
        
        if vlm_response.get("success"):
            analysis = vlm_response.get("parsed", {})
            
            # Scoring Logic
            if analysis.get("log_created"):
                score += 10
                feedback_parts.append("Log creation initiated.")
            
            if analysis.get("date_correct"):
                score += 15
                feedback_parts.append("Date set to Jan 6, 2025.")
            else:
                feedback_parts.append("Date incorrect or not visible.")
                
            if analysis.get("notes_entered_detailed"):
                score += 25
                feedback_parts.append("Detailed notes entered.")
            else:
                feedback_parts.append("Notes missing or incomplete.")
                
            if analysis.get("quantity_correct"):
                score += 15
                feedback_parts.append("Quantity (24 head) correct.")
            else:
                feedback_parts.append("Quantity/Unit incorrect.")
                
            if analysis.get("saved_successfully"):
                score += 10
                feedback_parts.append("Log saved.")
                
            if analysis.get("final_list_verified"):
                score += 15
                feedback_parts.append("Log confirmed in final list.")
            else:
                feedback_parts.append("Log not seen in final list.")

        else:
            feedback_parts.append("VLM verification failed.")
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append(f"Verification error: {str(e)}")

    # Final result construction
    passed = score >= 65  # Threshold as defined in verification strategy
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }