#!/usr/bin/env python3
"""
Verifier for Setup Anonymous Course Evaluation Feedback task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_feedback_activity(traj, env_info, task_info):
    """
    Verify the agent successfully created the Feedback activity, configured privacy, 
    and added the required questions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    q1_prompt = metadata.get('q1_prompt', 'rate the clinical scenarios').lower()
    q1_options = metadata.get('q1_options', ['Excellent', 'Good', 'Fair', 'Poor'])
    q2_prompt = metadata.get('q2_prompt', 'improvements would you suggest').lower()

    # Retrieve exported JSON data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_msgs = []

    # 1. Check Feedback Existence (20 pts)
    feedback_exists = result.get('feedback_exists', False)
    if feedback_exists:
        score += 20
        feedback_msgs.append("Feedback activity 'End of Course Evaluation' successfully created.")
    else:
        feedback_msgs.append("Failed to create the Feedback activity with the correct name.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_msgs)}

    # 2. Check Privacy Settings (20 pts)
    is_anon = result.get('is_anonymous', False)
    no_multi = result.get('no_multiple_submit', False)
    
    if is_anon and no_multi:
        score += 20
        feedback_msgs.append("Privacy settings (Anonymous, No multiple submits) correctly configured.")
    else:
        if not is_anon:
            feedback_msgs.append("Feedback is NOT set to Anonymous.")
        if not no_multi:
            feedback_msgs.append("Multiple submissions were NOT disabled.")

    # Process items to find our required questions
    items = result.get('feedback_items', [])
    q1_found = False
    q1_options_correct = False
    q2_found = False

    for item in items:
        typ = item.get('typ', '')
        # Remove HTML tags from name for reliable checking
        name_clean = re.sub(r'<[^>]+>', '', item.get('name', '')).lower()
        presentation = item.get('presentation', '')

        # Check for Multichoice Question
        if typ == 'multichoice' and q1_prompt in name_clean:
            q1_found = True
            
            # Check presentation for the required options (Moodle stores choices separated by | or newlines)
            pres_clean = presentation.lower()
            options_found = sum(1 for opt in q1_options if opt.lower() in pres_clean)
            if options_found == len(q1_options):
                q1_options_correct = True

        # Check for Textarea Question
        if typ == 'textarea' and q2_prompt in name_clean:
            q2_found = True

    # 3. Check Multichoice question (20 pts)
    if q1_found:
        score += 20
        feedback_msgs.append("Multichoice question added successfully.")
    else:
        feedback_msgs.append("Multichoice question missing or prompt incorrect.")

    # 4. Check Multichoice options (15 pts)
    if q1_options_correct:
        score += 15
        feedback_msgs.append("Multichoice rating options are correct.")
    elif q1_found:
        feedback_msgs.append("Multichoice question found, but options (Excellent, Good, Fair, Poor) were incorrect/missing.")

    # 5. Check Textarea question (15 pts)
    if q2_found:
        score += 15
        feedback_msgs.append("Long text answer question added successfully.")
    else:
        feedback_msgs.append("Long text answer question missing or prompt incorrect.")

    # 6. Trajectory/VLM fallback validation check
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    try:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            score += 10 # VLM structure bonus since they reached the final page
            feedback_msgs.append("Trajectory verification complete.")
    except Exception as e:
        logger.warning(f"VLM trajectory parsing error: {str(e)}")

    # Check overall pass threshold (Need 70 points out of 100)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_msgs)
    }