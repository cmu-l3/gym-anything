#!/usr/bin/env python3
"""
Verifier for check_antiarrhythmic_with_dasatinib task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_antiarrhythmic(traj, env_info, task_info):
    """
    Verifies the Dasatinib + Amiodarone interaction task.
    
    Scoring (100 pts total):
    - 50 pts: Programmatic checks on the output file
        - File existence & timestamp (10 pts)
        - Correct Drug Names (10 pts)
        - Valid Color Code (10 pts)
        - Detailed Mechanism Text (keywords) (20 pts)
    - 50 pts: VLM Verification of trajectory
        - App Navigation (15 pts)
        - Correct Interaction Found (20 pts)
        - Color/Content Consistency (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # =========================================================
    # PART 1: Programmatic Verification (50 pts)
    # =========================================================
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    content = result_data.get("file_content", "")
    file_exists = result_data.get("file_exists", False)
    file_mtime = int(result_data.get("file_mtime", 0))
    start_time = int(result_data.get("task_start_time", 0))
    
    # Check 1: File Existence & Anti-Gaming (10 pts)
    if file_exists and len(content.strip()) > 10:
        if file_mtime > start_time:
            score += 10
            feedback_parts.append("Report file created successfully during task.")
        else:
            feedback_parts.append("WARNING: File timestamp predates task start (anti-gaming check failed).")
    else:
        feedback_parts.append("Report file missing or empty.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Drug Names (10 pts)
    # Case-insensitive check
    content_lower = content.lower()
    if "dasatinib" in content_lower and "amiodarone" in content_lower:
        score += 10
        feedback_parts.append("Correct drug names found.")
    else:
        feedback_parts.append("Missing drug names (Dasatinib or Amiodarone) in file.")

    # Check 3: Valid Color Code (10 pts)
    metadata = task_info.get('metadata', {})
    valid_colors = metadata.get('valid_colors', ["RED", "ORANGE", "YELLOW", "GREEN", "GREY"])
    found_color = None
    
    for color in valid_colors:
        if color.lower() in content_lower:
            found_color = color
            break
            
    if found_color:
        score += 10
        feedback_parts.append(f"Valid interaction color code found: {found_color}.")
    else:
        feedback_parts.append("No valid interaction color code (Red, Orange, etc.) found in file.")

    # Check 4: Mechanism Text / Keywords (20 pts)
    keywords = metadata.get('required_keywords', ["qt", "prolong", "cyp", "risk", "monitor"])
    # Relaxed match: need at least 2 relevant pharmacological keywords
    found_keywords = [k for k in keywords if k.lower() in content_lower]
    
    if len(found_keywords) >= 2:
        score += 20
        feedback_parts.append(f"Interaction details verified (found keywords: {', '.join(found_keywords)}).")
    elif len(found_keywords) == 1:
        score += 10
        feedback_parts.append("Interaction details sparse (only 1 keyword found).")
    else:
        feedback_parts.append("Interaction details text missing or insufficient.")

    programmatic_score = score
    
    # =========================================================
    # PART 2: VLM Verification (50 pts)
    # =========================================================
    
    # Sample frames to see the workflow
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = f"""
    You are verifying an agent performing a drug interaction check on an Android app.
    
    Task: Check interaction between 'Dasatinib' and 'Amiodarone'.
    
    The agent reported the interaction color is: {found_color if found_color else 'UNKNOWN'}
    
    Review the screenshots provided. 
    1. Did the agent open the 'Cancer iChart' app?
    2. Did the agent navigate to 'Dasatinib'?
    3. Did the agent select 'Amiodarone' in the co-medication list?
    4. Did the agent reach the Interaction Details page?
    5. Does the color shown in the app match the reported color '{found_color}'?
       (Red=High Risk, Orange=Potential, Yellow=Caution, Green=None)
       
    Output JSON:
    {{
        "app_opened": true/false,
        "drugs_selected": true/false,
        "details_page_reached": true/false,
        "color_matches_report": true/false,
        "observed_color": "RED/ORANGE/YELLOW/GREEN/GREY/NONE",
        "confidence": "high/medium/low"
    }}
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # 1. App Navigation (15 pts)
        if parsed.get("app_opened") and parsed.get("drugs_selected"):
            vlm_score += 15
            feedback_parts.append("VLM: Navigation confirmed.")
        else:
            feedback_parts.append("VLM: Navigation incomplete.")

        # 2. Reached Details (20 pts)
        if parsed.get("details_page_reached"):
            vlm_score += 20
            feedback_parts.append("VLM: Interaction details page viewed.")
        else:
            feedback_parts.append("VLM: Failed to view interaction details.")
            
        # 3. Color Consistency (15 pts)
        if parsed.get("color_matches_report"):
            vlm_score += 15
            feedback_parts.append("VLM: Reported color matches app display.")
        elif found_color is not None:
             # If VLM disagrees but we have a valid color, we penalize slightly but check confidence
             feedback_parts.append(f"VLM warning: Observed {parsed.get('observed_color')} vs Reported {found_color}.")
    else:
        # Fallback if VLM fails: assume partial credit if programmatic checks passed strongly
        if programmatic_score >= 40:
            vlm_score = 25
            feedback_parts.append("VLM query failed; partial fallback credit awarded.")
        else:
            feedback_parts.append("VLM query failed.")

    total_score = programmatic_score + vlm_score
    passed = total_score >= 70 and programmatic_score >= 30
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }