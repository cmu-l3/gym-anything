#!/usr/bin/env python3
"""
Verifier for check_acid_reducer_with_erlotinib@1

Verification Strategy:
1. File Verification (45 pts):
   - Check if /sdcard/erlotinib_omeprazole_result.txt exists.
   - Verify it was created during the task (anti-gaming).
   - Verify it contains "Erlotinib", "Omeprazole", and a valid color.

2. VLM Verification (55 pts):
   - Trajectory Analysis: Verify agent navigated through the app (Drug List -> Erlotinib -> Omeprazole).
   - Visual Confirmation: Verify the color visible in the app matches the text file report.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, List

# Import VLM utilities provided by the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/mock for standalone testing
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_acid_reducer_with_erlotinib(traj, env_info, task_info):
    """
    Verify the agent checked the Erlotinib + Omeprazole interaction and reported it.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_colors = metadata.get('expected_colors', ["red", "orange"])
    
    score = 0
    feedback_parts = []
    
    # Load result JSON from device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. File-based Verification (45 points)
    output_exists = result_data.get('output_exists', False)
    file_fresh = result_data.get('file_created_during_task', False)
    raw_content = result_data.get('file_content_raw', "")
    
    reported_color = None

    if output_exists:
        score += 10
        feedback_parts.append("Output file exists.")
        
        if file_fresh:
            score += 10
            feedback_parts.append("File created during task.")
        else:
            feedback_parts.append("WARNING: File timestamp predates task start (stale data).")

        # Parse content (newlines were replaced by | in export script)
        content_lower = raw_content.lower()
        
        if "erlotinib" in content_lower:
            score += 5
            feedback_parts.append("Correct drug name found.")
        else:
            feedback_parts.append("Missing 'Erlotinib' in file.")
            
        if "omeprazole" in content_lower:
            score += 5
            feedback_parts.append("Correct co-medication found.")
        else:
            feedback_parts.append("Missing 'Omeprazole' in file.")

        # Extract color
        valid_colors = ["red", "orange", "yellow", "green", "grey", "gray"]
        found_colors = [c for c in valid_colors if c in content_lower]
        
        if found_colors:
            score += 15
            reported_color = found_colors[0] # Take the first found
            feedback_parts.append(f"Reported color: {reported_color}.")
        else:
            feedback_parts.append("No valid traffic light color found in file.")
    else:
        feedback_parts.append("Output file not found.")

    # 3. VLM Verification (55 points)
    
    # A. Workflow Trajectory Verification (25 points)
    frames = sample_trajectory_frames(traj, n=6)
    workflow_prompt = """
    Analyze these screenshots of a user using the 'Cancer iChart' app.
    The goal is to find the interaction between 'Erlotinib' and 'Omeprazole'.
    
    Check for these specific steps:
    1. Is the app Main Menu or Search visible?
    2. Is 'Erlotinib' visible in a list or search result?
    3. Is 'Omeprazole' visible in a list?
    4. Is a traffic light color (Red/Orange/Yellow/Green) visible next to Omeprazole?

    Return JSON:
    {
        "erlotinib_seen": boolean,
        "omeprazole_seen": boolean,
        "interaction_result_visible": boolean,
        "observed_color": "string or null"
    }
    """
    
    vlm_workflow = query_vlm(images=frames, prompt=workflow_prompt)
    workflow_data = vlm_workflow.get('parsed', {}) if vlm_workflow.get('success') else {}
    
    if workflow_data.get('erlotinib_seen'):
        score += 10
        feedback_parts.append("VLM: Navigated to Erlotinib.")
    
    if workflow_data.get('omeprazole_seen'):
        score += 10
        feedback_parts.append("VLM: Located Omeprazole.")
        
    if workflow_data.get('interaction_result_visible'):
        score += 5
        feedback_parts.append("VLM: Interaction result displayed.")

    # B. Visual Ground Truth Verification (30 points)
    # We compare the reported color with what VLM sees
    visual_color = workflow_data.get('observed_color', '').lower() if workflow_data.get('observed_color') else None
    
    # If workflow didn't catch the color, try the final screenshot specifically
    if not visual_color:
        final_ss = get_final_screenshot(traj)
        color_prompt = "What is the color of the interaction traffic light icon shown for Omeprazole? Return just the color name."
        vlm_final = query_vlm(image=final_ss, prompt=color_prompt)
        if vlm_final.get('success'):
            visual_color = vlm_final.get('result', '').lower()

    # Normalize VLM color
    if visual_color:
        if "red" in visual_color: visual_color = "red"
        elif "orange" in visual_color: visual_color = "orange"
        elif "yellow" in visual_color: visual_color = "yellow"
        elif "green" in visual_color: visual_color = "green"
        elif "grey" in visual_color or "gray" in visual_color: visual_color = "grey"

    # Cross-check
    match_bonus = 0
    if reported_color and visual_color:
        if reported_color == visual_color:
            match_bonus = 20
            feedback_parts.append(f"SUCCESS: Reported color '{reported_color}' matches visual evidence.")
        else:
            feedback_parts.append(f"WARNING: Reported '{reported_color}' but VLM saw '{visual_color}'.")
            # Partial credit if reported color is scientifically correct even if VLM failed to see it clearly
            if reported_color in expected_colors:
                match_bonus = 10 
                feedback_parts.append("Awarding partial credit for scientifically correct answer.")
    elif reported_color and reported_color in expected_colors:
        # Blind verification (VLM failed to see color, but answer is correct per metadata)
        match_bonus = 20
        feedback_parts.append("VLM could not confirm color, but reported answer matches expected medical data.")
    
    # Evidence of valid attempt
    if workflow_data.get('erlotinib_seen') and workflow_data.get('omeprazole_seen'):
         score += 10 # Base points for doing the work
         
    score += match_bonus

    # 4. Final Scoring
    # Cap score at 100
    score = min(100, score)
    
    # Pass logic: Must have file with correct info AND some visual evidence of work
    passed = score >= 60 and output_exists and (workflow_data.get('erlotinib_seen') or match_bonus > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }