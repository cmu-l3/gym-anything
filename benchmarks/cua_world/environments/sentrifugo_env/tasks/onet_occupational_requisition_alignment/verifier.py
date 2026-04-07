#!/usr/bin/env python3
"""
Verifier for O*NET Occupational Requisition Alignment task.
Verifies programmatic database state and uses VLM for trajectory verification.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("VLM utilities not available. VLM trajectory verification will be skipped.")
    VLM_AVAILABLE = False


def build_trajectory_prompt():
    return """Examine this sequence of screenshots from an AI agent's trajectory.

Task: The agent must read O*NET text files on the desktop and use them to create Job Titles and Job Requisitions in the Sentrifugo HRMS web application.

Check for evidence of the following:
1. Did the agent open or read the text files on the Desktop (e.g., 'ONET_Financial_Manager_Tasks.txt')?
2. Did the agent navigate the Sentrifugo web interface (e.g., Organization, Job Titles, or Talent Acquisition modules)?
3. Is there evidence of the agent copying/pasting or filling out forms for Job Titles or Requisitions?

Respond in JSON format:
{
    "interacted_with_text_files": true/false,
    "navigated_sentrifugo": true/false,
    "evidence_of_form_filling": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible in the frames."
}"""


def verify_task(traj, env_info, task_info):
    """
    Verify that the O*NET alignment task was completed successfully.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected result file
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

    score = 0
    feedback_parts = []
    
    # Extract DB signals
    fin_title = int(result.get('financial_manager_title_count', 0)) > 0
    train_title = int(result.get('training_manager_title_count', 0)) > 0
    fin_text = int(result.get('financial_req_text_hits', 0)) > 0
    train_text = int(result.get('training_req_text_hits', 0)) > 0
    app_running = result.get('app_running', False)

    # 1. Programmatic Checks (Total 60 Points)
    if fin_title:
        score += 10
        feedback_parts.append("Financial Manager title created (10/10)")
    else:
        feedback_parts.append("Financial Manager title missing (0/10)")

    if train_title:
        score += 10
        feedback_parts.append("Training Manager title created (10/10)")
    else:
        feedback_parts.append("Training Manager title missing (0/10)")

    if fin_text:
        score += 20
        feedback_parts.append("Financial Manager O*NET text found in DB (20/20)")
    else:
        feedback_parts.append("Financial Manager O*NET text missing from DB (0/20)")

    if train_text:
        score += 20
        feedback_parts.append("Training Manager O*NET text found in DB (20/20)")
    else:
        feedback_parts.append("Training Manager O*NET text missing from DB (0/20)")

    # 2. VLM Trajectory Verification (Total 40 Points)
    vlm_points = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=6)
            final_frame = get_final_screenshot(traj)
            
            # Filter out None values just in case
            images = [img for img in frames + [final_frame] if img]
            
            if images:
                vlm_result = query_vlm(images=images, prompt=build_trajectory_prompt())
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    if parsed.get("interacted_with_text_files", False):
                        vlm_points += 20
                        feedback_parts.append("VLM confirmed interaction with O*NET text files (+20)")
                    else:
                        feedback_parts.append("VLM did not detect interaction with text files (+0)")
                        
                    if parsed.get("navigated_sentrifugo", False) or parsed.get("evidence_of_form_filling", False):
                        vlm_points += 20
                        feedback_parts.append("VLM confirmed Sentrifugo UI navigation (+20)")
                    else:
                        feedback_parts.append("VLM did not detect Sentrifugo UI navigation (+0)")
                else:
                    feedback_parts.append("VLM query failed or returned invalid response.")
            else:
                feedback_parts.append("No trajectory images available for VLM verification.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM error: {str(e)}")
    else:
        # If VLM is totally unavailable in the testing env, we distribute the points 
        # to the programmatic checks to avoid penalizing the agent for framework limitations.
        logger.info("VLM not available, falling back to pure programmatic verification.")
        vlm_points = 0
        if fin_title: vlm_points += 5
        if train_title: vlm_points += 5
        if fin_text: vlm_points += 15
        if train_text: vlm_points += 15
        feedback_parts.append("VLM unavailable - awarded substitute points via DB state.")

    score += vlm_points
    
    # Determine pass/fail
    key_criteria_met = fin_text and train_text and app_running
    passed = score >= 60 and key_criteria_met

    if not key_criteria_met:
        if not app_running:
            feedback_parts.append("FAIL: Firefox/Sentrifugo was not running.")
        else:
            feedback_parts.append("FAIL: Missing critical O*NET text entries in the database.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }