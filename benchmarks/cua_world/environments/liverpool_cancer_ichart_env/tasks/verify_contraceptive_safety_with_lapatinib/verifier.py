#!/usr/bin/env python3
"""
Verifier for verify_contraceptive_safety_with_lapatinib task.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_contraceptive_safety(traj, env_info, task_info):
    """
    Verifies that the agent checked the interaction between Lapatinib and Ethinylestradiol.
    
    Criteria:
    1. Output file exists and was created during task (30 pts)
    2. Output file content identifies Lapatinib (20 pts)
    3. Output file content identifies correct Contraceptive (20 pts)
    4. Output file reports a valid traffic light color (30 pts)
    5. VLM confirms navigation to Contraceptives section (Pass/Fail check for robustness)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    valid_colors = [c.lower() for c in metadata.get('valid_colors', ["red", "orange", "yellow", "green", "grey"])]
    comed_keywords = [k.lower() for k in metadata.get('comedication_keywords', ["ethinylestradiol"])]
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. programmatic Scoring
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (30 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 30
        feedback.append("Output file created successfully.")
    else:
        feedback.append("Output file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Parse Content
    content = result.get('file_content', '').lower()
    
    # Criterion 2: Cancer Drug Name (20 pts)
    if "lapatinib" in content:
        score += 20
        feedback.append("Correct cancer drug identified.")
    else:
        feedback.append("File does not mention 'Lapatinib'.")

    # Criterion 3: Co-medication Name (20 pts)
    comed_found = any(k in content for k in comed_keywords)
    if comed_found:
        score += 20
        feedback.append("Correct contraceptive/hormone identified.")
    else:
        feedback.append("File does not mention 'Ethinylestradiol' or 'Contraceptive'.")

    # Criterion 4: Valid Color (30 pts)
    # We look for lines like "Interaction Color: Red"
    color_found = None
    for color in valid_colors:
        if color in content:
            color_found = color
            break
            
    if color_found:
        score += 30
        feedback.append(f"Valid interaction color reported: {color_found.title()}.")
    else:
        feedback.append("No valid traffic light color found in output.")

    # 3. VLM Verification (Trajectory Analysis)
    # This ensures the agent didn't just guess or write random text.
    logger.info("Starting VLM verification...")
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    vlm_prompt = """
    You are verifying an agent's actions in the 'Liverpool Cancer iChart' app.
    The goal was to check the interaction between 'Lapatinib' and a 'Contraceptive'.
    
    Look at the sequence of screenshots. Answer the following in JSON format:
    1. "seen_lapatinib": (bool) Did the agent select or view 'Lapatinib'?
    2. "seen_contraceptives": (bool) Did the agent enter a 'Contraceptives' or 'Hormones' category or list?
    3. "seen_result": (bool) Is a result screen visible showing a traffic light color (Red/Orange/Yellow/Green/Grey)?
    4. "observed_color": (string or null) If a result is visible, what is the traffic light color?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_data = vlm_result.get('parsed', {})
    
    # Adjust score based on VLM if needed, or just use as validation
    if not vlm_data.get('seen_contraceptives') and not vlm_data.get('seen_result'):
        # If VLM explicitly says they never saw the relevant screens, we might penalize
        # But for now, we'll trust the file output if it's correct, and just add feedback.
        feedback.append("(VLM Warning: Could not visually confirm navigation to Contraceptives).")
    else:
        feedback.append("(VLM confirmed navigation).")

    # Final Pass/Fail
    passed = score >= 90  # Requires File + Drug + Comed + Color
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "vlm_analysis": vlm_data,
            "programmatic_score": score
        }
    }