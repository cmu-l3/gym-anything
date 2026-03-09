#!/usr/bin/env python3
"""
Verifier for check_corticosteroid_with_dabrafenib task.

Verification Strategy:
1. Programmatic: Check if report file exists and was created during the task.
2. Programmatic: Check if report contains required drug names and a valid color.
3. VLM (Trajectory): Verify the agent actually navigated to Dabrafenib -> Dexamethasone.
4. VLM (Cross-validation): Verify the reported color matches the screen content.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Import VLM utilities (mocked for this implementation based on context)
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback/Mock for standalone testing
    def query_vlm(prompt, images=None, image=None):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n):
        return []
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_corticosteroid_with_dabrafenib(traj, env_info, task_info):
    """
    Verify the agent checked the interaction and reported results correctly.
    """
    # 0. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_colors = metadata.get('valid_colors', ["red", "orange", "amber", "yellow", "green", "grey", "gray"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get Programmatic Results from Device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve report data from device."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Verify File Existence and Creation (Anti-Gaming)
    report_exists = result_data.get("report_exists", False)
    fresh_file = result_data.get("file_created_during_task", False)
    content = result_data.get("report_content_preview", "").lower()
    
    if report_exists:
        score += 10
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file NOT found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}
        
    if fresh_file:
        score += 10
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("File timestamp indicates it was pre-existing!")
        # Severe penalty for pre-existing file
        score = 0 
        
    # 3. Verify Report Content (Text Analysis)
    drugs_mentioned = 0
    if "dabrafenib" in content:
        drugs_mentioned += 1
    if "dexamethasone" in content:
        drugs_mentioned += 1
    
    if drugs_mentioned == 2:
        score += 10
        feedback_parts.append("Both drugs mentioned in report.")
    elif drugs_mentioned == 1:
        score += 5
        feedback_parts.append("Only one drug mentioned in report.")
    else:
        feedback_parts.append("Correct drug names not found in report.")

    # Identify reported color
    reported_color = None
    for color in valid_colors:
        if color in content:
            reported_color = color
            break
            
    if reported_color:
        score += 10
        feedback_parts.append(f"Reported color: {reported_color}.")
    else:
        feedback_parts.append("No valid traffic light color found in report.")

    if len(content) > 30: # Rudimentary check for description/recommendation
        score += 10
        feedback_parts.append("Report contains description text.")

    # 4. VLM Verification (Trajectory & Cross-Validation)
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = f"""
    You are verifying an agent interacting with the 'Liverpool Cancer iChart' app.
    The goal is to check the interaction between 'Dabrafenib' and 'Dexamethasone'.
    
    Look at the sequence of screenshots.
    
    1. Did the agent select 'Dabrafenib' from a list?
    2. Did the agent select 'Dexamethasone' (possibly under Corticosteroids)?
    3. Did the agent reach a screen showing 'Interaction Details' or specific interaction results?
    4. If an interaction result is visible, what is the color of the traffic light/banner? (Red, Amber/Yellow, Green, Grey)
    
    JSON Output:
    {{
        "dabrafenib_selected": boolean,
        "dexamethasone_selected": boolean,
        "interaction_screen_reached": boolean,
        "observed_color": "color_name_or_null",
        "confidence": "low/medium/high"
    }}
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    vlm_data = {}
    if vlm_result and vlm_result.get("success"):
        vlm_data = vlm_result.get("parsed", {})
        
        # Scoring VLM observations
        if vlm_data.get("dabrafenib_selected"):
            score += 15
            feedback_parts.append("VLM confirmed Dabrafenib selection.")
        
        if vlm_data.get("dexamethasone_selected"):
            score += 15
            feedback_parts.append("VLM confirmed Dexamethasone selection.")
            
        if vlm_data.get("interaction_screen_reached"):
            score += 10
            feedback_parts.append("VLM confirmed interaction screen reached.")
            
        # Cross-validation
        observed_color = vlm_data.get("observed_color", "").lower() if vlm_data.get("observed_color") else None
        
        if observed_color and reported_color:
            # Simple fuzzy matching
            match = False
            if reported_color in observed_color or observed_color in reported_color:
                match = True
            elif reported_color in ["amber", "orange", "yellow"] and observed_color in ["amber", "orange", "yellow"]:
                match = True
            
            if match:
                score += 10
                feedback_parts.append(f"Cross-validation PASSED: Reported {reported_color} matches observed {observed_color}.")
            else:
                feedback_parts.append(f"Cross-validation FAILED: Reported {reported_color} but observed {observed_color}.")
        elif not observed_color and reported_color:
            # If VLM couldn't see it but agent reported it, give benefit of doubt if interaction screen was reached
            if vlm_data.get("interaction_screen_reached"):
                score += 5
                feedback_parts.append("VLM couldn't read color, but screen was reached.")
    else:
        feedback_parts.append("VLM verification failed to process.")

    # Final logic
    passed = score >= 60 and fresh_file and vlm_data.get("interaction_screen_reached", False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }