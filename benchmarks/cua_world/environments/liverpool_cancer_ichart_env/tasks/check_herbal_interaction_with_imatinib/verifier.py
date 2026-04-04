#!/usr/bin/env python3
"""
Verifier for check_herbal_interaction_with_imatinib task.

Verifies:
1. Result file existence and creation time (Anti-gaming)
2. Content correctness (Drug names, Color, Clinical concern)
3. Visual Trajectory (App navigation, Traffic light visibility)
"""

import json
import base64
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_herbal_interaction(traj, env_info, task_info):
    """
    Verify the agent correctly checked the Imatinib + St John's Wort interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_cancer_drug = metadata.get('cancer_drug', 'Imatinib').lower()
    expected_co_med = metadata.get('co_medication', "St John's Wort").lower()
    expected_color = metadata.get('expected_color', 'Red').lower()

    score = 0
    feedback_parts = []
    max_score = 100

    # 1. Retrieve Result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (20 points)
    if not result_data.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Result file /sdcard/interaction_result.txt not found."}
    
    score += 10
    feedback_parts.append("File exists")

    if result_data.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File predates task start (Anti-gaming penalty)")

    # 3. Check File Content (40 points)
    content_b64 = result_data.get('file_content_b64', "")
    try:
        content_text = base64.b64decode(content_b64).decode('utf-8').lower()
        lines = [l.strip() for l in content_text.split('\n') if l.strip()]
        
        # Check Drug Names (10 pts)
        if expected_cancer_drug in content_text:
            score += 10
            feedback_parts.append(f"Found cancer drug '{expected_cancer_drug}'")
        else:
            feedback_parts.append(f"Missing cancer drug '{expected_cancer_drug}'")

        # Check Co-medication (10 pts)
        # Handle "st john's" vs "st. john's"
        if "st john" in content_text or "st. john" in content_text:
            score += 10
            feedback_parts.append("Found St John's Wort")
        else:
            feedback_parts.append("Missing co-medication 'St John's Wort'")

        # Check Color (10 pts)
        if expected_color in content_text:
            score += 10
            feedback_parts.append(f"Correct interaction color '{expected_color}' reported")
        elif any(c in content_text for c in ['orange', 'yellow', 'green', 'grey']):
            feedback_parts.append("Wrong interaction color reported")
        else:
            feedback_parts.append("No interaction color reported")

        # Check Summary Length (10 pts)
        # Assuming the last line is the summary
        if len(lines) >= 4 and len(lines[-1]) > 10:
            score += 10
            feedback_parts.append("Clinical summary present")
        else:
            feedback_parts.append("Clinical summary missing or too short")

    except Exception as e:
        feedback_parts.append(f"Error parsing file content: {e}")

    # 4. VLM Verification of Trajectory (40 points)
    # We use trajectory frames to verify the agent actually used the app
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' app.
    The goal was to check the interaction between 'Imatinib' and 'St John's Wort'.
    
    Look at these screenshots in order and answer:
    1. Did the agent navigate to the 'Cancer Drugs' list and is 'Imatinib' visible?
    2. Did the agent navigate to 'Co-medications' and is 'St John's Wort' (or Herbal/Complementary category) visible?
    3. Is the final 'Results' screen visible showing a traffic-light colored banner?
    4. What color is the interaction result banner? (Red, Amber, Yellow, Green)
    
    Return JSON:
    {
        "imatinib_seen": boolean,
        "st_johns_wort_seen": boolean,
        "result_screen_seen": boolean,
        "observed_color": "string (or null)"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('imatinib_seen'):
            score += 10
            feedback_parts.append("VLM: Imatinib selection verified")
            
        if parsed.get('st_johns_wort_seen'):
            score += 10
            feedback_parts.append("VLM: Co-medication selection verified")
            
        if parsed.get('result_screen_seen'):
            score += 10
            feedback_parts.append("VLM: Result screen verified")
            
        # Cross-validate visual color with reported color (10 pts)
        obs_color = parsed.get('observed_color', '').lower()
        if expected_color in obs_color:
            score += 10
            feedback_parts.append(f"VLM: Confirmed {expected_color} result on screen")
        else:
            feedback_parts.append(f"VLM: Saw '{obs_color}' on screen (expected {expected_color})")
    else:
        feedback_parts.append("VLM verification failed to run")

    # Final logic
    passed = score >= 60 and "Red" in content_text.title() and result_data.get('file_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }