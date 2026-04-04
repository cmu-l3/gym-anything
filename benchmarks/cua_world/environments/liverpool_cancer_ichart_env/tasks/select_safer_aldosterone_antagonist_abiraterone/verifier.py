#!/usr/bin/env python3
"""
Verifier for select_safer_aldosterone_antagonist_abiraterone.

Criteria:
1. JSON output file exists and is valid.
2. Correctly identifies 'eplerenone' as the safer drug.
3. Correctly identifies colors (Green/Red).
4. VLM Trajectory Verification: Agent actually looked at both drugs.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_safety_check(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # 1. Fetch and Parse Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check File Existence & Timestamp
    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file /sdcard/safety_check.json was not created."}
    
    if not result_data.get('file_created_during_task'):
        feedback.append("Warning: File timestamp indicates it wasn't created during this session.")
        # We don't fail immediately but penalize
    else:
        score += 10
        feedback.append("File created during task.")

    # 3. Validate JSON Content
    content = result_data.get('output_content', {})
    if isinstance(content, str):
        # Handle case where shell script export nested stringified JSON
        try:
            content = json.loads(content)
        except:
            pass # It might be raw dict if logic above worked well

    if not isinstance(content, dict):
        return {"passed": False, "score": 10, "feedback": "Output file does not contain valid JSON object."}

    # Check Safer Drug Name
    agent_safer = str(content.get('safer_drug', '')).strip().lower()
    expected_safer = ground_truth.get('safer_drug', 'eplerenone')
    
    if expected_safer in agent_safer:
        score += 30
        feedback.append(f"Correctly identified safer drug: {agent_safer}")
    else:
        feedback.append(f"Incorrect safer drug. Expected '{expected_safer}', got '{agent_safer}'")

    # Check Colors
    agent_safer_color = str(content.get('safer_drug_color', '')).strip().lower()
    agent_unsafe_color = str(content.get('unsafe_drug_color', '')).strip().lower()
    
    expected_safer_color = ground_truth.get('safer_drug_color', 'green')
    expected_unsafe_color = ground_truth.get('unsafe_drug_color', 'red')

    if agent_safer_color == expected_safer_color:
        score += 15
        feedback.append(f"Correct safer drug color: {agent_safer_color}")
    else:
        feedback.append(f"Wrong color for safer drug. Expected {expected_safer_color}, got {agent_safer_color}")

    if agent_unsafe_color == expected_unsafe_color:
        score += 15
        feedback.append(f"Correct unsafe drug color: {agent_unsafe_color}")
    else:
        feedback.append(f"Wrong color for unsafe drug. Expected {expected_unsafe_color}, got {agent_unsafe_color}")

    # 4. VLM Trajectory Verification
    # Ensure agent actually visited the pages for Spironolactone and Eplerenone
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Analyze these screenshots from the Liverpool Cancer iChart app.
    The user should be comparing 'Spironolactone' and 'Eplerenone' with 'Abiraterone'.
    
    Look for:
    1. A screen showing 'Spironolactone' in the list or its interaction result (Red).
    2. A screen showing 'Eplerenone' in the list or its interaction result (Green).
    3. The cancer drug 'Abiraterone' being selected.
    
    Return JSON:
    {
        "saw_spironolactone": boolean,
        "saw_eplerenone": boolean,
        "saw_abiraterone": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    vlm_score = 0
    if vlm_data.get('saw_abiraterone'): vlm_score += 10
    if vlm_data.get('saw_spironolactone'): vlm_score += 10
    if vlm_data.get('saw_eplerenone'): vlm_score += 10
    
    score += vlm_score
    feedback.append(f"VLM verification: {vlm_data.get('reasoning', 'No reasoning provided')}")

    passed = score >= 70 and (expected_safer in agent_safer)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }