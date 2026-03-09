#!/usr/bin/env python3
"""
Verifier for check_ccb_interaction_with_olaparib task.

Criteria:
1. Result file exists and was created during the task.
2. Result file contains correct color (Orange/Red) and relevant clinical keywords.
3. VLM Verification: Trajectory shows navigation to Olaparib -> Diltiazem -> Details.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ccb_interaction(traj, env_info, task_info):
    """
    Verify the agent correctly identified the Olaparib-Diltiazem interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_colors = [c.lower() for c in metadata.get('expected_colors', ['orange', 'red', 'amber'])]
    required_keywords = metadata.get('required_keywords', [])

    score = 0
    feedback_parts = []
    
    # 1. File Verification (Programmatic)
    # -----------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy the JSON export from the Android environment
        copy_from_env("/sdcard/tasks/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    file_exists = result_data.get('file_exists', False)
    file_fresh = result_data.get('file_created_during_task', False)
    reported_color = result_data.get('color_reported', '').strip().lower()
    reported_summary = result_data.get('summary_reported', '').strip().lower()

    if file_exists and file_fresh:
        score += 20
        feedback_parts.append("Result file created successfully.")
        
        # Check color
        if any(c in reported_color for c in expected_colors):
            score += 20
            feedback_parts.append(f"Correct interaction color reported ({reported_color}).")
        else:
            feedback_parts.append(f"Incorrect color reported: '{reported_color}'. Expected one of {expected_colors}.")

        # Check summary keywords
        hits = [k for k in required_keywords if k in reported_summary]
        if len(hits) >= 1:
            score += 10
            feedback_parts.append("Summary contains relevant clinical keywords.")
        else:
            feedback_parts.append("Summary missing key clinical terms (dose, reduce, cyp3a, etc.).")
    else:
        feedback_parts.append("Result file not found or not created during task.")

    # 2. VLM Verification (Trajectory)
    # --------------------------------
    # We sample frames to ensure the agent actually used the app
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    The goal was to check the interaction between 'Olaparib' and 'Diltiazem'.
    
    Review these screenshots of the agent's workflow:
    1. Did the agent open the 'Cancer iChart' app?
    2. Is 'Olaparib' visible as the selected cancer drug?
    3. Is 'Diltiazem' visible as the selected co-medication?
    4. Did the agent reach an interaction result screen (showing a colored banner like Orange or Red)?
    5. Did the agent open the interaction details view (text description)?

    Provide a JSON response:
    {
        "app_opened": true/false,
        "olaparib_selected": true/false,
        "diltiazem_selected": true/false,
        "result_screen_reached": true/false,
        "details_viewed": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {}) if vlm_result.get('success') else {}
    
    vlm_score = 0
    if vlm_data.get('app_opened'): vlm_score += 10
    if vlm_data.get('olaparib_selected'): vlm_score += 10
    if vlm_data.get('diltiazem_selected'): vlm_score += 10
    if vlm_data.get('result_screen_reached'): vlm_score += 10
    if vlm_data.get('details_viewed'): vlm_score += 10
    
    score += vlm_score
    feedback_parts.append(f"VLM Verification Score: {vlm_score}/50")

    # Final Pass Determination
    # Must have created file OR have very strong VLM evidence + correct color in file if it exists
    # Threshold: 60 points
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }