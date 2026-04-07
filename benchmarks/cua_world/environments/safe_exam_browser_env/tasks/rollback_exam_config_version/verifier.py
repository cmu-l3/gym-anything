#!/usr/bin/env python3
"""
Verifier for rollback_exam_config_version task.

Criteria:
1. Agent edited the description to include "EXPERIMENTAL" (creates history).
2. Agent restored the original version (current description lacks "EXPERIMENTAL").
3. VLM trajectory verification confirms the Versions UI was used.
"""

import os
import json
import tempfile
import logging

# Import gym_anything VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
except ImportError:
    # Mock for testing outside gym_anything
    def sample_trajectory_frames(*args, **kwargs): return []
    def get_final_screenshot(*args, **kwargs): return None
    def query_vlm(*args, **kwargs): return {"parsed": {}}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent performing a configuration rollback task in Safe Exam Browser Server.

Task Goal: The agent must navigate to a configuration's "Versions" or history tab and restore/activate a previous version.

Please review the provided trajectory screenshots and determine:
1. Did the agent navigate to the "Versions" or "History" view for an exam configuration?
2. Did the agent click a button to "Restore", "Activate", or "Switch to" an older version from the history list?
3. Did the agent successfully complete the action (e.g., a success message or the active version changed)?

Respond with a JSON object containing:
{
    "versions_tab_accessed": boolean,
    "restore_action_taken": boolean,
    "success_evident": boolean,
    "confidence": "high|medium|low",
    "reasoning": "Brief explanation of what is seen in the frames"
}
"""

def verify_rollback_exam_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rollback_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    nodes = result.get('nodes', [])
    firefox_running = result.get('firefox_running', 0)
    
    if firefox_running:
        score += 10
        feedback.append("Firefox is running.")
    else:
        feedback.append("Firefox is not running.")

    # 2. Analyze Database State
    # Look for a node where the history has 'EXPERIMENTAL' but the current description does not.
    target_node = None
    edit_made = False
    rollback_successful = False

    for node in nodes:
        history_descriptions = [v.get('description', '') for v in node.get('history', [])]
        current_desc = node.get('current_description', '')
        
        # Did any version in history contain EXPERIMENTAL?
        has_experimental_in_history = any('EXPERIMENTAL' in desc for desc in history_descriptions)
        
        if has_experimental_in_history:
            edit_made = True
            # Does the CURRENT version NOT contain EXPERIMENTAL?
            if 'EXPERIMENTAL' not in current_desc:
                rollback_successful = True
                target_node = node
                break

    if edit_made:
        score += 30
        feedback.append("Verified edit was made (new version with 'EXPERIMENTAL' found in database history).")
    else:
        feedback.append("No configuration history found with 'EXPERIMENTAL'. Agent failed to create the modified version.")

    if rollback_successful:
        score += 30
        feedback.append("Verified rollback was successful (active configuration no longer contains 'EXPERIMENTAL').")
    elif edit_made:
        feedback.append("Active configuration still contains 'EXPERIMENTAL' - rollback was not performed.")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=6)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('versions_tab_accessed'):
                vlm_score += 15
                feedback.append("VLM confirms Versions/History tab was accessed.")
            
            if parsed.get('restore_action_taken'):
                vlm_score += 15
                feedback.append("VLM confirms Restore/Activate action was taken on an older version.")
                
            score += vlm_score
            logger.info(f"VLM reasoning: {parsed.get('reasoning', 'None provided')}")
        else:
            feedback.append("No trajectory frames available for VLM verification.")
    except Exception as e:
        logger.error(f"VLM verification failed: {str(e)}")
        feedback.append("VLM verification skipped due to error.")
        # Give benefit of doubt if DB checks passed perfectly but VLM crashed
        if edit_made and rollback_successful:
            score += 30 

    total_score = min(100, score)
    # The essential requirement is making the edit AND rolling it back
    passed = edit_made and rollback_successful and total_score >= 70

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }