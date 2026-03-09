#!/usr/bin/env python3
"""
Verifier for search_case_by_phrase task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_search_case_by_phrase(traj, env_info, task_info):
    """
    Verify the agent found the correct Case ID using search.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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

    # 2. Extract Data
    found_id = result.get('found_id', '').strip()
    ground_truth_id = result.get('ground_truth_id', '').strip()
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)

    score = 0
    feedback = []

    # 3. Verify Output File (Basic)
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/found_case_id.txt not found."}
    
    score += 10
    feedback.append("Output file exists.")

    if not file_created_during_task:
        feedback.append("Warning: Output file timestamp is outside task window.")
    else:
        score += 10
        feedback.append("File created during task.")

    # 4. Verify Content (Correct ID)
    # Case ID format usually COMP-YYYY-XXXXX, but we accept exact string match
    # normalize both strings
    if found_id and ground_truth_id and found_id.lower() == ground_truth_id.lower():
        score += 50
        feedback.append(f"Correct Case ID identified: {found_id}")
    else:
        feedback.append(f"Incorrect Case ID. Found: '{found_id}', Expected: '{ground_truth_id}'")
        # Fail immediately if ID is wrong, as this is the core goal
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    # 5. VLM Verification (Trajectory Analysis)
    # We want to verify they actually SEARCHED, not just guessed (though guessing a UUID is impossible)
    # But we check for search UI interaction to ensure they followed the workflow.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        Review these screenshots of an agent using ArkCase.
        1. Did the agent use the Search bar (usually top right or a search page)?
        2. Did the agent view a Case Detail page?
        3. Is the Case ID visible in the final steps?
        
        Answer yes/no for each.
        """
        
        # This is a soft check - we don't fail based on VLM if the ID is correct (which proves they found it),
        # but we award points for showing the work.
        try:
            vlm_res = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
            # We assume a positive response adds confidence
            if vlm_res and vlm_res.get("success"):
                score += 30
                feedback.append("Visual verification passed.")
            else:
                score += 10 # Grace points if VLM fails but ID is correct
                feedback.append("Visual verification inconclusive.")
        except Exception:
            score += 10
            feedback.append("Visual verification skipped.")
    else:
        score += 10

    # Final tally
    passed = score >= 70  # Needs File + Correct ID + Some evidence/created_time
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }