#!/usr/bin/env python3
"""
Verifier for Check Antipsychotic Safety with Vemurafenib task.

Verifies:
1.  Output file existence and freshness (created during task).
2.  Content accuracy: Correct drugs, correct color (Red/Orange), correct risk (QT).
3.  VLM Trajectory: Visual confirmation of navigation to Vemurafenib -> Antipsychotics -> Quetiapine.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vemurafenib_quetiapine(traj, env_info, task_info):
    """
    Verify the agent correctly identified the interaction between Vemurafenib and Quetiapine.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('expected_colors', ['red', 'orange'])
    risk_keywords = metadata.get('risk_keywords', ['QT', 'interval', 'cardiac'])

    # 1. Fetch Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/tasks/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. File Verification (40 points)
    file_exists = result_data.get('file_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    content_raw = result_data.get('file_content', "")
    content_lines = content_raw.split('|')

    if file_exists and created_during:
        score += 10
        feedback_parts.append("Output file created successfully.")
        
        # Check content
        content_str = content_raw.lower()
        
        # Drug names (10 pts)
        if "vemurafenib" in content_str and "quetiapine" in content_str:
            score += 10
            feedback_parts.append("Correct drugs identified.")
        else:
            feedback_parts.append("Failed to identify correct drug names in file.")

        # Color (10 pts)
        # We look for red or orange (Vemurafenib + Quetiapine is high risk for QT)
        found_color = False
        for color in expected_colors:
            if color in content_str:
                found_color = True
                break
        
        if found_color:
            score += 10
            feedback_parts.append("Correct interaction color reported.")
        else:
            feedback_parts.append(f"Incorrect interaction color. Expected one of: {expected_colors}")

        # Risk keywords (10 pts)
        found_risk = False
        for kw in risk_keywords:
            if kw.lower() in content_str:
                found_risk = True
                break
        
        if found_risk:
            score += 10
            feedback_parts.append("Clinical risk (QT/Cardiac) correctly identified.")
        else:
            feedback_parts.append("Failed to mention QT/Cardiac risk in output.")

    else:
        feedback_parts.append("Output file not found or not created during task execution.")

    # 3. VLM Trajectory Verification (60 points)
    # We need to see: 
    # a) Selection of Vemurafenib
    # b) Selection of Antipsychotics category
    # c) Viewing of Quetiapine details
    
    images = sample_trajectory_frames(traj, n=8)
    
    prompt = """
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' Android app.
    The goal was to check the interaction between 'Vemurafenib' and 'Quetiapine'.
    
    Analyze the sequence of screenshots. Look for these specific steps:
    1. Navigation to the cancer drug 'Vemurafenib'.
    2. Navigation to a co-medication category like 'Antipsychotics' or 'Neuroleptics'.
    3. Viewing a list containing 'Quetiapine'.
    4. Viewing a detail screen for 'Quetiapine' showing a traffic-light color (Red, Orange, Yellow, Green).
    
    Respond in JSON:
    {
        "found_vemurafenib": true/false,
        "found_category": true/false,
        "found_quetiapine_list": true/false,
        "found_detail_screen": true/false,
        "interaction_color": "red/orange/yellow/green/grey/unknown"
    }
    """
    
    vlm_result = query_vlm(prompt=prompt, images=images)
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('found_vemurafenib'):
        score += 15
        feedback_parts.append("VLM confirmed navigation to Vemurafenib.")
    
    if vlm_data.get('found_category'):
        score += 15
        feedback_parts.append("VLM confirmed navigation to Antipsychotics category.")
        
    if vlm_data.get('found_detail_screen') or vlm_data.get('found_quetiapine_list'):
        score += 30
        feedback_parts.append("VLM confirmed viewing Quetiapine interaction.")
    else:
        feedback_parts.append("VLM did not see Quetiapine interaction details.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }