#!/usr/bin/env python3
"""
Verifier for Moodle Clinical Rotation Choice Task.

Evaluates the resulting task_result.json from the Moodle database export.
Uses multiple signals:
1. Database state (Activity creation, name, global settings).
2. Option data (Option texts and specific numeric limits).
3. Trajectory checking (VLM) to verify UI interaction.
"""

import os
import json
import logging
import tempfile
import re

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def verify_setup_clinical_rotation_choice(traj, env_info, task_info):
    """Verify that the Choice activity was configured correctly with capacity limits."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_options = metadata.get('expected_options', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Check if course was found
    if not result.get("course_found", False):
        return {"passed": False, "score": 0, "feedback": "NURS101 Course not found in database."}
        
    # Check if Choice exists
    choice_exists = result.get("choice_exists", False)
    if not choice_exists:
        return {"passed": False, "score": 0, "feedback": "Choice activity 'Fall Clinical Rotation Selection' was not created."}
    
    score += 15
    feedback_parts.append("Choice activity created")
    
    # Anti-gaming: Check if created during task
    if result.get("choice_created_during_task", False):
        score += 5
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("Warning: Activity might have existed before task start")
        
    # Check Activity Name exactness
    choice_name = result.get("choice_name", "")
    if "Fall Clinical Rotation Selection" in choice_name:
        score += 5
    else:
        feedback_parts.append(f"Name mismatch: got '{choice_name}'")

    # Check Global Settings
    # limitanswers = 1 (Yes)
    limit_answers = result.get("limit_answers", 0)
    if limit_answers == 1:
        score += 15
        feedback_parts.append("Limit responses enabled")
    else:
        feedback_parts.append("Limit responses NOT enabled")
        
    # showresults = 2 (Show only after answer)
    show_results = result.get("show_results", 0)
    if show_results == 2:
        score += 15
        feedback_parts.append("Show results after answering set correctly")
    else:
        feedback_parts.append(f"Incorrect result display setting (got {show_results}, expected 2)")

    # Verify Options and Capacities
    actual_options = result.get("options", [])
    
    # Check count
    if len(actual_options) == 5:
        score += 10
        feedback_parts.append("Exactly 5 options created")
    elif len(actual_options) > 0:
        feedback_parts.append(f"Found {len(actual_options)} options instead of 5")
    else:
        feedback_parts.append("No options were created")
        
    # Score individual options and limits
    options_score = 0
    max_options_score = 25
    matched_hospitals = 0
    
    for expected in expected_options:
        exp_name = expected["name"].lower().strip()
        exp_limit = expected["limit"]
        
        # Look for a match in actual options
        match_found = False
        for actual in actual_options:
            act_name = str(actual.get("text", "")).lower().strip()
            # Strip out HTML tags (Moodle sometimes wraps text in <p>)
            act_name = re.sub('<[^<]+>', '', act_name).strip()
            
            if exp_name in act_name or act_name in exp_name:
                match_found = True
                matched_hospitals += 1
                
                # Option name matches, now check the limit
                act_limit = actual.get("limit", 0)
                if act_limit == exp_limit:
                    options_score += (max_options_score / 5) # 5 pts per perfect option
                else:
                    # Give partial credit for creating the option but wrong limit
                    options_score += 2
                    feedback_parts.append(f"Wrong limit for {exp_name}: got {act_limit}, expected {exp_limit}")
                break
                
        if not match_found:
            feedback_parts.append(f"Missing hospital option: {expected['name']}")
            
    score += int(options_score)
    if matched_hospitals == 5 and int(options_score) == 25:
        feedback_parts.append("All 5 hospitals configured with perfect capacity limits")

    # Trajectory Verification via VLM (ensure they used the UI)
    vlm_score = 0
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are analyzing a sequence of screenshots of an agent configuring a Moodle 'Choice' activity.
Look at these chronological frames and determine:
1. Did the agent interact with the Moodle web interface?
2. Is there evidence of the agent typing hospital names or configuring numeric capacity limits?

Respond in JSON format:
{
    "moodle_ui_used": true/false,
    "form_interaction_visible": true/false
}"""
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("moodle_ui_used", False):
                    vlm_score += 5
                if parsed.get("form_interaction_visible", False):
                    vlm_score += 5
            else:
                # Fallback if VLM fails but programmatic passes perfectly
                if score >= 80: vlm_score = 10 
        score += vlm_score
    except Exception as e:
        logger.warning(f"VLM trajectory verification failed: {e}")
        # Graceful degradation
        if score >= 80: score += 10

    # Determine passing state
    # Key criteria: limitanswers MUST be enabled, and at least 3 limits configured correctly
    key_criteria_met = (limit_answers == 1) and (options_score >= 15)
    passed = (score >= 75) and key_criteria_met
    
    if not key_criteria_met and score >= 75:
        feedback_parts.append("Failed: Critical capacity constraints (limitanswers=1 and correct limits) were not met.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }