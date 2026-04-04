#!/usr/bin/env python3
"""
Verifier for check_sedative_interaction_with_crizotinib task.

Verification Strategy:
1. File Verification (40 pts):
   - Check if /sdcard/tasks/crizotinib_midazolam_result.txt exists and was created during task.
   - Parse content for correct Drug names (Crizotinib, Midazolam).
   - Parse content for correct Interaction Color (Red/Orange).
   
2. VLM Trajectory Verification (60 pts):
   - Verify agent navigated to Crizotinib.
   - Verify agent found the correct Sedative/Anxiolytic category.
   - Verify agent viewed the interaction result (traffic light).
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sedative_interaction(traj, env_info, task_info):
    """
    Verify the agent correctly identified the Crizotinib-Midazolam interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utils locally to avoid import errors if not in path
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames
    except ImportError:
        # Fallback for testing environment
        logger.warning("gym_anything.vlm not found, using mocks if needed")
        query_vlm = None
        sample_trajectory_frames = lambda t, n: []

    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('expected_colors', ['RED', 'ORANGE'])
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Programmatic File Check
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Get JSON result
        copy_from_env("/sdcard/tasks/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Get Output Text File
        file_content = ""
        if result_data.get("output_file_exists", False):
            copy_from_env("/sdcard/tasks/crizotinib_midazolam_result.txt", temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                file_content = f.read()

    except Exception as e:
        logger.error(f"Failed to copy/read files: {e}")
        return {"passed": False, "score": 0, "feedback": f"System error reading results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_txt.name): os.unlink(temp_txt.name)

    # Scoring File Evidence
    if result_data.get("output_file_exists", False) and result_data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("Output file created.")
        
        # Content Analysis
        content_lower = file_content.lower()
        
        if "crizotinib" in content_lower and "midazolam" in content_lower:
            score += 10
            feedback_parts.append("Correct drugs mentioned.")
        else:
            feedback_parts.append("File missing drug names.")

        # Color Check
        found_color = False
        for color in expected_colors:
            if color.lower() in content_lower:
                found_color = True
                break
        
        if found_color:
            score += 20
            feedback_parts.append("Correct interaction color identified.")
        else:
            feedback_parts.append("Incorrect or missing interaction color.")
            
    else:
        feedback_parts.append("No output file created.")

    # =========================================================
    # 2. VLM Trajectory Verification
    # =========================================================
    # We need to check if they actually used the app
    frames = sample_trajectory_frames(traj, n=8)
    
    if not frames:
        feedback_parts.append("No trajectory frames available.")
    elif query_vlm:
        prompt = """
        You are verifying an agent's interaction with the 'Liverpool Cancer iChart' Android app.
        The goal was to check the interaction between 'Crizotinib' and 'Midazolam'.
        
        Look at these screenshots in order.
        1. Did the agent open the Cancer iChart app?
        2. Did the agent navigate to 'Crizotinib' in the drug list?
        3. Did the agent navigate to a category like 'Sedatives', 'Anxiolytics', or 'Benzodiazepines'?
        4. Did the screen show 'Midazolam' with a traffic light color (Red/Orange/Yellow/Green)?
        
        Respond in JSON:
        {
            "app_opened": boolean,
            "crizotinib_found": boolean,
            "sedatives_category_opened": boolean,
            "midazolam_interaction_seen": boolean,
            "interaction_color_visible": "RED/ORANGE/YELLOW/GREEN/GREY/NONE"
        }
        """
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            
            if parsed.get("app_opened"):
                score += 10
            else:
                feedback_parts.append("VLM: App not seen.")
                
            if parsed.get("crizotinib_found"):
                score += 15
            else:
                feedback_parts.append("VLM: Crizotinib not selected.")
                
            if parsed.get("sedatives_category_opened") or parsed.get("midazolam_interaction_seen"):
                score += 15
                feedback_parts.append("VLM: Navigated to interaction.")
            else:
                feedback_parts.append("VLM: Did not find Midazolam interaction.")
                
            # Bonus check for consistency
            vlm_color = parsed.get("interaction_color_visible", "NONE")
            if vlm_color in ["RED", "ORANGE"]:
                score += 20
                feedback_parts.append("VLM confirmed correct color visible.")
        else:
            # Fallback if VLM fails but file is correct
            if score >= 40:
                score += 20
                feedback_parts.append("VLM check failed, granting partial trust based on file.")

    # Final Score Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }