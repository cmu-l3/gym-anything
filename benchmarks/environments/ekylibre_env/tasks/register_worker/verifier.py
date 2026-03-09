#!/usr/bin/env python3
"""
Verifier for register_worker task (Ekylibre).

Verifies:
1. Worker "Marie Dupont" exists in the database.
2. Worker was created during the task session (anti-gaming).
3. Worker has the correct Date of Birth (1992-06-15).
4. Total worker count increased.
5. VLM: Validates UI interaction via trajectory.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils if available (assumed from environment context)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_worker(traj, env_info, task_info):
    """
    Verify the agent registered the worker correctly.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dob = metadata.get('expected_dob', '1992-06-15')
    
    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    worker_found = result.get('worker_found', False)
    worker_name = result.get('worker_name', "")
    worker_dob = result.get('worker_dob', "")
    created_during_task = result.get('created_during_task', False)
    count_increased = result.get('count_increased', False)

    # Criterion A: Worker Record Exists (30 pts)
    if worker_found:
        score += 30
        feedback_parts.append(f"Worker record found: '{worker_name}'")
    else:
        feedback_parts.append("No worker record matching 'Marie Dupont' found")

    # Criterion B: Anti-Gaming / Freshness (20 pts)
    if created_during_task:
        score += 20
        feedback_parts.append("Record created during task session")
    elif worker_found:
        feedback_parts.append("Worker exists but was created BEFORE task start (stale data)")
    
    # Criterion C: Data Accuracy - Date of Birth (20 pts)
    # Handle potential formatting differences (Timezone offsets etc)
    dob_match = False
    if expected_dob in worker_dob:
        dob_match = True
    
    if dob_match:
        score += 20
        feedback_parts.append(f"Date of Birth correct ({expected_dob})")
    elif worker_found:
        feedback_parts.append(f"Incorrect Date of Birth: expected {expected_dob}, got {worker_dob}")

    # Criterion D: Count Check (10 pts)
    if count_increased:
        score += 10
        feedback_parts.append("Total worker count increased")

    # Criterion E: VLM Verification (20 pts)
    # We check if the agent actually navigated the UI
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_screen = get_final_screenshot(traj)
            if final_screen:
                frames.append(final_screen)
            
            prompt = (
                "The user is trying to register a farm worker named 'Marie Dupont' in Ekylibre. "
                "Review these screenshots of the agent's actions. "
                "1. Did the agent navigate to a form or list related to 'Workers', 'Employees', or 'Ressources humaines'? "
                "2. Is the name 'Marie Dupont' visible being typed or in a list? "
                "Answer 'YES' if the workflow looks correct, otherwise 'NO'."
            )
            
            vlm_resp = query_vlm(images=frames, prompt=prompt).strip().upper()
            if "YES" in vlm_resp:
                vlm_score = 20
                feedback_parts.append("Visual verification passed (UI workflow confirmed)")
            else:
                feedback_parts.append("Visual verification failed (Workflow unclear)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic check is perfect, give benefit of doubt
            if score >= 80:
                vlm_score = 20
                feedback_parts.append("VLM skipped (error), assumed pass due to perfect data match")
    else:
        # Fallback if VLM not loaded
        if score >= 80:
            vlm_score = 20
            feedback_parts.append("VLM unavailable, score normalized based on data accuracy")

    score += vlm_score

    # 3. Final Determination
    # Pass if score >= 60 AND key criteria (Record Exists + Created During Task) are met
    key_criteria_met = worker_found and created_during_task
    passed = (score >= 60) and key_criteria_met

    full_feedback = " | ".join(feedback_parts)
    if not key_criteria_met and score >= 60:
        full_feedback += " (FAILED: Key criteria not met - fresh record required)"

    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback
    }