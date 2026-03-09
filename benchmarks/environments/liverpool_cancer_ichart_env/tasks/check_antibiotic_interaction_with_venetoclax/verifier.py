#!/usr/bin/env python3
"""
Verifier for check_antibiotic_interaction_with_venetoclax task.

Verification Logic:
1. File Check (30 pts): Agent created result.txt with a valid color.
2. Content Match (30 pts): The color written matches the actual interaction (Ground Truth/VLM confirmed).
3. VLM Trajectory (40 pts): Agent actually navigated to Venetoclax -> Ciprofloxacin -> Result.

Note: Interaction colors in this app are traffic lights: Red, Orange (Amber), Yellow, Green.
Venetoclax + Ciprofloxacin is a known interaction (CYP3A4 inhibition), likely ORANGE (Potential) or RED (Contraindicated).
The verifier uses VLM to confirm the ground truth dynamically from the screen to be robust against app updates.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_antibiotic_interaction(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load JSON result from Android environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Extract Data
    file_exists = result_data.get("file_exists", False)
    file_content = result_data.get("file_content", "").lower().strip()
    valid_colors = ["red", "orange", "yellow", "green", "grey"]

    score = 0
    feedback = []

    # 3. Criterion: File Creation & Format (30 pts)
    if file_exists:
        score += 15
        if file_content in valid_colors:
            score += 15
            feedback.append(f"Valid result file created with color: {file_content}.")
        else:
            feedback.append(f"Result file exists but content '{file_content}' is not a valid color.")
    else:
        feedback.append("Result file result.txt not found.")

    # 4. Criterion: VLM Trajectory & Ground Truth Verification (70 pts)
    # We use VLM to:
    # A) Confirm the agent selected Venetoclax and Ciprofloxacin (Process)
    # B) Identify the TRUE color shown on screen (Ground Truth)
    # C) Compare File Content vs Screen Content (Accuracy)

    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for verification."}

    prompt = f"""
    You are verifying a medical task on an Android app. 
    The user must check the interaction between the cancer drug 'Venetoclax' and antibiotic 'Ciprofloxacin'.
    
    Review the screenshots and answer:
    1. Did the agent select 'Venetoclax' in the cancer drug list?
    2. Did the agent select 'Ciprofloxacin' in the co-medication list?
    3. Is an interaction result screen visible in the final steps?
    4. What is the COLOR of the interaction banner/traffic light shown for this pair? (Red, Orange, Yellow, Green, or Grey)
    
    Output JSON:
    {{
        "venetoclax_selected": true/false,
        "ciprofloxacin_selected": true/false,
        "result_screen_visible": true/false,
        "interaction_color_visible": "red/orange/yellow/green/grey/none",
        "reasoning": "..."
    }}
    """

    vlm_response = query_vlm(prompt=prompt, images=frames)
    
    vlm_passed_process = False
    vlm_true_color = None
    
    if vlm_response.get("success"):
        data = vlm_response.get("parsed", {})
        
        # Check Process (30 pts)
        process_score = 0
        if data.get("venetoclax_selected"): process_score += 10
        if data.get("ciprofloxacin_selected"): process_score += 10
        if data.get("result_screen_visible"): process_score += 10
        
        score += process_score
        if process_score == 30:
            feedback.append("VLM confirmed correct navigation workflow.")
            vlm_passed_process = True
        else:
            feedback.append(f"VLM workflow incomplete. Details: {data}")

        # Check Accuracy (40 pts)
        vlm_true_color = data.get("interaction_color_visible", "none").lower()
        
        if vlm_true_color in valid_colors:
            if file_exists and file_content == vlm_true_color:
                score += 40
                feedback.append(f"Success: File content '{file_content}' matches the {vlm_true_color} interaction shown on screen.")
            elif file_exists:
                feedback.append(f"Mismatch: File says '{file_content}' but screen shows '{vlm_true_color}'.")
            else:
                feedback.append(f"Screen shows {vlm_true_color}, but no file was written.")
        else:
            # Fallback if VLM can't read color clearly but file is plausible
            # Venetoclax+Cipro is typically Orange/Red.
            feedback.append("VLM could not definitively identify the color on screen.")
            if file_exists and file_content in ["orange", "red"]:
                score += 20 # Partial credit for plausible answer
                feedback.append("Awarding partial credit for pharmacologically plausible answer (Orange/Red).")

    else:
        feedback.append("VLM verification failed to process images.")

    # Pass Threshold
    # Must have file + valid content + VLM confirmation of correctness
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }