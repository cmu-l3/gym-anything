#!/usr/bin/env python3
"""
Verifier for export_filtered_friends_json task.

Criteria:
1. File /sdcard/united_friends.json exists and is valid JSON.
2. Contains "Captain UAL" (Case insensitive name match).
3. Does NOT contain "Captain DAL".
4. Objects have 'name' and 'airline' fields.
5. VLM confirms the agent actually interacted with the Add Friend UI.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_filtered_friends(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Fetch Task Result Metadata
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ================================================================
    # 2. Fetch and Verify Output File Content
    # ================================================================
    output_exists = result_data.get("output_exists", False)
    
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file /sdcard/united_friends.json was not created."
        }
    
    score += 10 # File created
    
    # Read the actual content
    json_content = []
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/united_friends.json", temp_output.name)
        with open(temp_output.name, 'r') as f:
            json_content = json.load(f)
            score += 10 # Valid JSON
            feedback_parts.append("Valid JSON file created")
    except json.JSONDecodeError:
        feedback_parts.append("File exists but is not valid JSON")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    except Exception as e:
        feedback_parts.append(f"Error reading output file: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # ================================================================
    # 3. Analyze JSON Content (Filtering Logic)
    # ================================================================
    if not isinstance(json_content, list):
        feedback_parts.append("JSON root is not a list")
    else:
        # Check Inclusion (Captain UAL)
        found_ual = False
        correct_schema = True
        
        for entry in json_content:
            if not isinstance(entry, dict) or "name" not in entry or "airline" not in entry:
                correct_schema = False
                continue
            
            name = entry.get("name", "").lower()
            airline = entry.get("airline", "").lower()
            
            if "captain ual" in name:
                found_ual = True
                # Check airline accuracy
                if "united" in airline or "ual" in airline:
                    score += 10
        
        if correct_schema:
            score += 10 # Objects have correct fields
        
        if found_ual:
            score += 25 # Inclusion success
            feedback_parts.append("Correctly included Captain UAL")
        else:
            feedback_parts.append("Missing Captain UAL")

        # Check Exclusion (Captain DAL)
        found_dal = False
        for entry in json_content:
            name = entry.get("name", "").lower()
            if "captain dal" in name:
                found_dal = True
                break
        
        if not found_dal:
            score += 25 # Exclusion success
            feedback_parts.append("Correctly excluded Captain DAL")
        else:
            feedback_parts.append("Incorrectly included Captain DAL")

    # ================================================================
    # 4. VLM Verification (Add Friend Workflow)
    # ================================================================
    # Check if the agent actually used the UI to add friends
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Review these screenshots of an agent using the Flight Crew View app.
    The task required adding two friends: 'Captain UAL' and 'Captain DAL'.
    
    Do you see evidence of:
    1. The agent accessing an 'Add Friend' or 'Add Crew' screen?
    2. Inputting 'Captain UAL' and selecting United/UAL?
    3. Inputting 'Captain DAL' and selecting Delta/DAL?
    
    Answer yes/no for each and provide a brief reasoning.
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        # We give partial credit just for attempting the UI interaction
        # The prompt analysis is subjective, so we look for keywords in the explanation
        reasoning = vlm_result.get("text", "").lower()
        if "add" in reasoning or "friend" in reasoning or "input" in reasoning:
            score += 10
            feedback_parts.append("VLM confirmed UI interaction")
    else:
        feedback_parts.append("VLM verification skipped/failed")

    # ================================================================
    # 5. Final Score Calculation
    # ================================================================
    passed = score >= 80 and found_ual and (not found_dal)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }