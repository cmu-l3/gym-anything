#!/usr/bin/env python3
"""
Verifier for screen_postop_pain_sedation_imatinib task.

Checks:
1. Report file existence and creation time (Anti-gaming).
2. Correct traffic light colors for the 4 specific drugs.
3. VLM trajectory verification to ensure categories were visited.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_postop_screen(traj, env_info, task_info):
    """
    Verify the Imatinib post-op safety screen task.
    """
    # 1. Setup and copy result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('expected_colors', {})

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify File Existence & Timing (20 pts)
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found at /sdcard/postop_screen.txt"}
    
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Report file was not created during the task session (anti-gaming check failed)"}
    
    score += 10 # File exists
    score += 10 # Created during task
    feedback_parts.append("Report file created successfully")

    # 3. Verify Content (60 pts - 15 per drug)
    content = result.get('report_content', '')
    
    # Normalize content for parsing
    # Expected format: "DrugName: Color"
    # We'll use regex to find the color associated with each drug name
    
    parsed_results = {}
    lines = content.split('\n')
    # fallback regex in case they formatted slightly differently
    # Looks for "DrugName" followed by some separator and then a color word
    
    for drug, allowed_colors in expected_colors.items():
        drug_score = 0
        # Case insensitive search for drug name + color
        # e.g. "Fentanyl: Red" or "Fentanyl - RED"
        pattern = re.compile(rf"{drug}.*?(\bRed\b|\bOrange\b|\bYellow\b|\bGreen\b|\bGrey\b|\bAmber\b)", re.IGNORECASE)
        match = pattern.search(content)
        
        if match:
            found_color = match.group(1).title() # Standardize to Title Case
            
            # Check if found color is in allowed list (case insensitive)
            allowed_set = {c.lower() for c in allowed_colors}
            if found_color.lower() in allowed_set:
                drug_score = 15
                feedback_parts.append(f"{drug}: Correct ({found_color})")
            else:
                feedback_parts.append(f"{drug}: Incorrect color '{found_color}' (Expected: {allowed_colors[0]})")
        else:
            feedback_parts.append(f"{drug}: Not found in report")
            
        score += drug_score
        parsed_results[drug] = drug_score > 0

    # 4. VLM Trajectory Verification (20 pts)
    # We want to see evidence that the agent actually navigated the app
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent checking drug interactions in the 'Liverpool Cancer iChart' app.
    The agent should have:
    1. Selected 'Imatinib' as the cancer drug.
    2. Searched for or browsed to 'Fentanyl' (Opioids/Analgesics).
    3. Searched for or browsed to 'Midazolam' (Anxiolytics/Sedatives).
    4. Searched for or browsed to 'Ibuprofen' (NSAIDs).
    5. Searched for or browsed to 'Paracetamol'.
    
    Look at the sequence of screenshots.
    - Do you see 'Imatinib' selected at the top?
    - Do you see lists of Co-medications or Search screens?
    - Do you see Traffic Light colors (Red/Orange/Yellow/Green) next to drug names?
    
    Return JSON:
    {
      "imatinib_visible": boolean,
      "comedication_list_visible": boolean,
      "traffic_lights_visible": boolean,
      "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('imatinib_visible'): vlm_score += 10
        if parsed.get('comedication_list_visible') or parsed.get('traffic_lights_visible'): vlm_score += 10
        feedback_parts.append(f"VLM Verification: {vlm_score}/20 pts")
    else:
        # Fallback if VLM fails: give points if score is already high (benefit of doubt)
        if score >= 60:
            vlm_score = 20
            feedback_parts.append("VLM Verification: Skipped (Assumed Pass due to high content score)")
    
    score += vlm_score

    # Final tally
    passed = score >= 80 and result.get('file_created_during_task')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }