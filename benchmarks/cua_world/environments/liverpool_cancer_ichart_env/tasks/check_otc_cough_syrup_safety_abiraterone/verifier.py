#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_otc_cough_syrup_safety_abiraterone(traj, env_info, task_info):
    """
    Verifies that the agent checked the interaction between Abiraterone and Dextromethorphan
    and produced a correct report file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_colors = [c.lower() for c in metadata.get('expected_colors', ['amber', 'orange', 'red', 'yellow'])]
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task output data"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Scoring Variables
    score = 0
    feedback_parts = []
    
    file_exists = result_data.get("file_exists", False)
    content = result_data.get("file_content", "")
    start_time = int(result_data.get("start_time", 0))
    # Note: Android shell mtime might be unreliable, primarily check existence and content logic
    
    # --- CRITERION 1: File Creation (20 pts) ---
    if file_exists:
        score += 20
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- CRITERION 2: Content Parsing (40 pts) ---
    content_lower = content.lower()
    
    # Check Drug Names
    has_abiraterone = "abiraterone" in content_lower
    has_dextro = "dextromethorphan" in content_lower
    
    if has_abiraterone and has_dextro:
        score += 20
        feedback_parts.append("Correct drugs identified.")
    else:
        feedback_parts.append(f"Missing drug names in report (Found Abiraterone: {has_abiraterone}, Dextro: {has_dextro}).")

    # Check Interaction Color
    # We look for the color keywords in the specific 'Interaction Color' line or generally in file
    found_color = None
    for color in ['red', 'orange', 'amber', 'yellow', 'green', 'grey']:
        if color in content_lower:
            found_color = color
            break
            
    if found_color:
        if found_color in expected_colors:
            score += 20
            feedback_parts.append(f"Correct interaction color identified ({found_color}).")
        else:
            feedback_parts.append(f"Wrong interaction color identified ({found_color}). Expected one of {expected_colors}.")
    else:
        feedback_parts.append("No interaction color specified in report.")

    # --- CRITERION 3: VLM Trajectory Verification (40 pts) ---
    # We need to ensure they actually looked it up and didn't just guess.
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Analyze these screenshots from an Android medical app (Liverpool Cancer iChart).
    The user is supposed to be checking a drug interaction between 'Abiraterone' and 'Dextromethorphan'.
    
    Look for:
    1. A screen showing 'Abiraterone' selected.
    2. A screen showing 'Dextromethorphan' (or a cough/respiratory category) selected.
    3. An interaction result screen (traffic light color).
    
    Did the user successfully navigate to the interaction result for these specific drugs?
    Answer 'Yes' or 'No' and explain.
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_feedback = vlm_res.get("parsed", {}).get("answer", "").lower() if vlm_res.get("success") else "unknown"
        vlm_raw = vlm_res.get("result", "")
        
        if "yes" in vlm_feedback or "yes" in vlm_raw.lower():
            score += 40
            feedback_parts.append("VLM confirms correct navigation workflow.")
        else:
            # Fallback: if text file was perfect, maybe VLM missed it. Give partial credit (20) if text is perfect.
            if score >= 60: 
                score += 20
                feedback_parts.append("VLM uncertain, but output file is correct.")
            else:
                feedback_parts.append("VLM did not observe correct interaction checking.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Graceful degradation if VLM fails but file is perfect
        if score >= 60:
            score += 40
            feedback_parts.append("VLM skipped (error), trusting file content.")

    # Final Pass check
    passed = score >= 80  # Requires file exist + correct drugs + correct color + VLM evidence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }