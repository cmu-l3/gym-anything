#!/usr/bin/env python3
"""
Verifier for delete_workout_routine task.

VERIFICATION STRATEGY (Multiple independent signals):
1. DB check: Target routine "5x5 Beginner" does not exist (40 points)
2. DB check: "Push-Pull-Legs" routine still exists (15 points)
3. DB check: "Upper-Lower Split" routine still exists (15 points)
4. DB check: Total routine count decreased by exactly 1 (10 points)
5. VLM trajectory: Agent actually navigated to the delete dialog and confirmed (20 points)
6. Anti-gaming: Ensure elapsed time is reasonable (> 5 seconds)

Total: 100 points
Pass Threshold: 80 points with key criteria met.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully completed a task in the wger fitness application.

TASK: Delete the workout routine named '5x5 Beginner'.

Please review these trajectory frames (taken while the agent worked) and the final screenshot. 
Determine if the agent performed a deletion workflow.

Look for:
1. Navigation to the routine overview or a specific routine page.
2. Interaction with a "Delete" button or dropdown menu containing a delete option.
3. A confirmation dialog asking "Are you sure you want to delete this?" or similar warning modal.

Respond in JSON format:
{
    "navigated_to_routines": true/false,
    "delete_dialog_seen": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_delete_workout_routine(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # Read result from environment
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # Check Anti-gaming (Timestamps)
    # ================================================================
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    elapsed = task_end - task_start
    
    if elapsed < 5:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Task completed suspiciously fast ({elapsed}s). Possible gaming detected."
        }

    # ================================================================
    # Evaluate DB state
    # ================================================================
    db_state = result.get('db_state', {})
    
    if 'error' in db_state:
        return {"passed": False, "score": 0, "feedback": f"DB Query Error: {db_state['error']}"}

    beginner_exists = db_state.get('beginner_exists', True)
    ppl_exists = db_state.get('ppl_exists', False)
    uls_exists = db_state.get('uls_exists', False)
    final_count = db_state.get('final_count', 0)
    initial_count = result.get('initial_count', 3)

    # Criterion 1: Target deleted (40 points)
    if not beginner_exists:
        score += 40
        feedback_parts.append("Target routine '5x5 Beginner' deleted (40/40)")
    else:
        feedback_parts.append("Target routine '5x5 Beginner' STILL EXISTS (0/40)")

    # Criterion 2: PPL preserved (15 points)
    if ppl_exists:
        score += 15
        feedback_parts.append("'Push-Pull-Legs' preserved (15/15)")
    else:
        feedback_parts.append("Error: 'Push-Pull-Legs' was deleted (0/15)")

    # Criterion 3: ULS preserved (15 points)
    if uls_exists:
        score += 15
        feedback_parts.append("'Upper-Lower Split' preserved (15/15)")
    else:
        feedback_parts.append("Error: 'Upper-Lower Split' was deleted (0/15)")

    # Criterion 4: Exact count logic (10 points)
    if final_count == initial_count - 1:
        score += 10
        feedback_parts.append("Total count decreased by exactly 1 (10/10)")
    else:
        feedback_parts.append(f"Total count changed from {initial_count} to {final_count} (0/10)")

    # ================================================================
    # VLM Trajectory Verification
    # ================================================================
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames
            
            if images:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    navigated = parsed.get("navigated_to_routines", False)
                    dialog_seen = parsed.get("delete_dialog_seen", False)
                    
                    if navigated:
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed navigation to routines (10/10)")
                    
                    if dialog_seen:
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed deletion dialog interaction (10/10)")
                    
                    if not navigated and not dialog_seen:
                        feedback_parts.append("VLM did not detect deletion workflow (0/20)")
                else:
                    feedback_parts.append("VLM evaluation failed, skipping VLM penalty")
                    vlm_score = 20  # Don't penalize if VLM infrastructure fails
            else:
                feedback_parts.append("No images available for VLM")
                vlm_score = 20 # Pass through if trajectory is empty due to infra
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM evaluation error")
            vlm_score = 20
    else:
        # Give points if VLM isn't available to avoid failing good runs
        vlm_score = 20
        feedback_parts.append("VLM not available, granting default trajectory score")

    score += vlm_score

    # ================================================================
    # Final Decision
    # ================================================================
    key_criteria_met = (not beginner_exists) and ppl_exists and uls_exists
    passed = (score >= 80) and key_criteria_met

    feedback_str = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }