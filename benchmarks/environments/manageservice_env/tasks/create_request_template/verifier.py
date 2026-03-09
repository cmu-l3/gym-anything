#!/usr/bin/env python3
"""
Verifier for create_request_template task.
Verifies that the agent created an incident template with the correct configuration.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_request_template(traj, env_info, task_info):
    """
    Verifies the creation of the 'Network Outage Report' template.
    
    Scoring Criteria:
    1. Template exists in DB (25 pts)
    2. Subject is correct (15 pts)
    3. Description contains required prompts (20 pts)
    4. Priority is 'High' (10 pts)
    5. Category is 'Network' (10 pts)
    6. VLM Verification of Workflow (20 pts)
    
    Anti-gaming:
    - Template count must increase (or new ID found).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Network Outage Report")
    expected_subject = metadata.get('expected_subject', "Network Outage - [Location]")
    required_desc_strings = metadata.get('required_description_strings', [])
    expected_priority = metadata.get('expected_priority', "High")
    expected_category = metadata.get('expected_category', "Network")

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Template Existence (25 pts)
    if result.get('template_found', False):
        score += 25
        feedback.append("Template found in database.")
    else:
        feedback.append("Template NOT found in database.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Check Subject (15 pts)
    actual_subject = result.get('actual_subject', "")
    if actual_subject and expected_subject.lower() in actual_subject.lower():
        score += 15
        feedback.append("Subject is correct.")
    else:
        feedback.append(f"Subject mismatch. Expected '{expected_subject}', got '{actual_subject}'.")

    # 3. Check Description Content (20 pts)
    actual_desc = result.get('actual_description', "")
    missing_strings = []
    for req_str in required_desc_strings:
        if req_str.lower() not in actual_desc.lower():
            missing_strings.append(req_str)
    
    if not missing_strings:
        score += 20
        feedback.append("Description contains all required prompts.")
    else:
        # Partial credit
        hit_count = len(required_desc_strings) - len(missing_strings)
        partial_score = int(20 * (hit_count / len(required_desc_strings)))
        score += partial_score
        feedback.append(f"Description missing terms: {', '.join(missing_strings)}.")

    # 4. Check Priority (10 pts)
    actual_priority = result.get('actual_priority', "")
    if expected_priority.lower() in actual_priority.lower():
        score += 10
        feedback.append(f"Priority set to {actual_priority}.")
    else:
        # Fallback: check if VLM saw it if DB query failed to resolve ID
        pass 

    # 5. Check Category (10 pts)
    actual_category = result.get('actual_category', "")
    if expected_category.lower() in actual_category.lower():
        score += 10
        feedback.append(f"Category set to {actual_category}.")
    else:
        feedback.append(f"Category mismatch or not found (Got: '{actual_category}').")

    # 6. VLM Verification (20 pts)
    # Used to verify UI interaction and catch fields if DB extraction failed
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = f"""
    Analyze these screenshots of a user creating a ServiceDesk Plus template.
    
    Look for:
    1. Navigation to Admin > Incident Templates (or similar).
    2. Filling out a form with Name '{expected_name}'.
    3. Setting Priority to '{expected_priority}'.
    4. Setting Category to '{expected_category}'.
    5. Saving the template.
    
    Did the user successfully create the template with these settings?
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).get('parsed', {})
    
    # We trust the DB for existence, but use VLM for priority/category if DB was empty/unclear
    vlm_confirmed = vlm_result.get('success_probability', 0.0) > 0.7 or "yes" in str(vlm_result).lower()
    
    if vlm_confirmed:
        score += 20
        feedback.append("VLM confirms workflow.")
        
        # Bonus rescue: if DB missed priority/category but VLM saw it clearly, give points
        if "Priority set to" not in str(feedback) and expected_priority.lower() in str(vlm_result).lower():
            score += 10
            feedback.append("VLM confirmed Priority (DB check fallback).")
        if "Category set to" not in str(feedback) and expected_category.lower() in str(vlm_result).lower():
            score += 10
            feedback.append("VLM confirmed Category (DB check fallback).")
    else:
        feedback.append("VLM could not verify workflow clearly.")

    # Cap score
    score = min(100, score)
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }