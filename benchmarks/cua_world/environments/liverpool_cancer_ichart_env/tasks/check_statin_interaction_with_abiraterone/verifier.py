#!/usr/bin/env python3
"""
Verifier for check_statin_interaction_with_abiraterone task.

Verifies:
1. File-based evidence: Did the agent create the result text file with correct data?
2. VLM-based evidence: Did the agent actually navigate the app and find the interaction?
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_statin_interaction(traj, env_info, task_info):
    """
    Verify the agent checked the interaction between Abiraterone and Atorvastatin.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_colors = metadata.get('valid_colors', ["red", "orange", "yellow", "green", "grey"])
    
    score = 0
    feedback_parts = []
    
    # 2. Analyze File Output (30 points max)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    content = result_data.get("content", {})
    file_exists = result_data.get("file_exists", False)
    created_during = result_data.get("file_created_during_task", False)

    if file_exists and created_during:
        score += 10
        feedback_parts.append("Result file created successfully.")
        
        # Check Content
        l1 = content.get("line1", "").strip().lower()
        l2 = content.get("line2", "").strip().lower()
        l3 = content.get("line3", "").strip().lower()
        l4 = content.get("line4", "").strip()

        if "abiraterone" in l1:
            score += 5
            feedback_parts.append("Cancer drug correct.")
        
        if "atorvastatin" in l2:
            score += 5
            feedback_parts.append("Co-medication correct.")
            
        if l3 in valid_colors:
            score += 5
            feedback_parts.append(f"Color format valid ({l3}).")
        else:
            feedback_parts.append(f"Invalid color format: {l3}")

        if len(l4) > 10:
            score += 5
            feedback_parts.append("Summary text provided.")
    else:
        feedback_parts.append("Result file missing or stale.")

    file_score = score
    logger.info(f"File-based score: {file_score}/30")

    # 3. VLM Trajectory Verification (70 points max)
    # We need to verify they actually did the work in the app
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the Liverpool Cancer iChart app.
    The agent should be checking for a drug interaction between 'Abiraterone' and 'Atorvastatin'.
    
    Review the sequence of screenshots and answer:
    1. Did the agent search for or select 'Abiraterone' in the Cancer Drugs list?
    2. Did the agent navigate to Co-medications (specifically looking for Lipids/Statins)?
    3. Is 'Atorvastatin' visible in the selection list?
    4. Is a traffic-light color visible next to Atorvastatin? If so, what color is it?
    5. Did the agent open the detailed interaction text view?
    
    Provide output in JSON:
    {
        "abiraterone_selected": boolean,
        "co_meds_navigated": boolean,
        "atorvastatin_found": boolean,
        "color_visible": boolean,
        "observed_color": "red/orange/yellow/green/grey/none",
        "detail_view_opened": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    vlm_score = 0
    if vlm_data.get("abiraterone_selected"):
        vlm_score += 15
        feedback_parts.append("VLM: Abiraterone selection confirmed.")
    
    if vlm_data.get("co_meds_navigated"):
        vlm_score += 15
        feedback_parts.append("VLM: Co-medication navigation confirmed.")
        
    if vlm_data.get("atorvastatin_found") and vlm_data.get("color_visible"):
        vlm_score += 20
        feedback_parts.append(f"VLM: Atorvastatin interaction found (Color: {vlm_data.get('observed_color')}).")
        
    if vlm_data.get("detail_view_opened"):
        vlm_score += 20
        feedback_parts.append("VLM: Detail view opened.")
        
    score += vlm_score
    logger.info(f"VLM score: {vlm_score}/70")

    # 4. Consistency Check
    # Verify the color written in file matches what VLM saw
    observed_color = vlm_data.get("observed_color", "none").lower()
    file_color = content.get("line3", "").strip().lower()
    
    # If VLM saw a color, and file has a color, they should ideally match.
    # We won't penalize heavily if VLM is unsure ("none"), but if VLM is sure and file differs, that's bad.
    if observed_color in valid_colors and file_color in valid_colors:
        if observed_color != file_color:
            feedback_parts.append(f"WARNING: File reports {file_color} but screenshot shows {observed_color}.")
            # We assume the screenshot is truth, but VLM can be wrong, so we don't deduct points aggressively
            # unless we implement strict ground truth checking.
            # For this task, we treat the file entry as the primary intent of the agent.

    passed = score >= 60 and file_exists and vlm_data.get("abiraterone_selected")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }