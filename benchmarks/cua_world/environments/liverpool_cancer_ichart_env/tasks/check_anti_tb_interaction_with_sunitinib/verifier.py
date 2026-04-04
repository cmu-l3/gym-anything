#!/usr/bin/env python3
"""
Verifier for check_anti_tb_interaction_with_sunitinib task.
Verifies that the agent correctly identified the Sunitinib-Rifampicin interaction
as RED (Do Not Coadminister) and saved it to the file.
"""

import json
import tempfile
import os
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for local testing without framework
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interaction_check(traj, env_info, task_info):
    """
    Verifies the task result using:
    1. File checks: Did the agent create the file with 'red'?
    2. Timestamp checks: Was it created during the task?
    3. VLM checks: Did the agent actually use the app?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- 1. Retrieve Data from Container ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- 2. Evaluate File & Content (60 points) ---
    score = 0
    feedback_parts = []
    
    file_exists = result_data.get("file_exists", False)
    content = result_data.get("file_content", "").strip().lower()
    created_during = result_data.get("file_created_during_task", False)
    expected_answer = task_info.get("metadata", {}).get("expected_answer", "red")

    if file_exists:
        score += 10
        feedback_parts.append("Result file created")
        
        if created_during:
            score += 10
            feedback_parts.append("File created during task window")
        else:
            feedback_parts.append("File timestamp invalid (pre-existing?)")
            
        if content == expected_answer:
            score += 40
            feedback_parts.append(f"Correct answer: '{content}'")
        else:
            feedback_parts.append(f"Wrong answer: expected '{expected_answer}', got '{content}'")
    else:
        feedback_parts.append("Result file not found")

    # --- 3. VLM Verification (40 points) ---
    # We want to verify the agent didn't just guess 'red' without checking
    frames = sample_trajectory_frames(traj, n=8)
    final_screen = get_final_screenshot(traj)
    
    # Include final screen in analysis if available
    if final_screen:
        frames.append(final_screen)

    vlm_prompt = """
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    The goal was to check the interaction between 'Sunitinib' and 'Rifampicin'.
    
    Look at these screenshots and answer:
    1. Did the agent open the 'Liverpool Cancer iChart' app? (Look for red header/logo)
    2. Did the agent search for or select 'Sunitinib' (cancer drug)?
    3. Did the agent search for or select 'Rifampicin' (co-medication)?
    4. Was a 'RED' interaction result (traffic light/banner) displayed at any point?
    
    Return JSON:
    {
        "app_opened": boolean,
        "sunitinib_seen": boolean,
        "rifampicin_seen": boolean,
        "red_result_seen": boolean
    }
    """

    vlm_score = 0
    if frames:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_resp.get("success"):
            analysis = vlm_resp.get("parsed", {})
            if analysis.get("app_opened"): vlm_score += 10
            if analysis.get("sunitinib_seen"): vlm_score += 10
            if analysis.get("rifampicin_seen"): vlm_score += 10
            if analysis.get("red_result_seen"): vlm_score += 10
            feedback_parts.append(f"VLM verification passed {vlm_score}/40 points")
        else:
            # Fallback if VLM fails: give partial credit if file is correct to avoid unfair failures
            if content == expected_answer:
                vlm_score = 20
                feedback_parts.append("VLM unavailable, partial credit awarded based on correct output")
            else:
                feedback_parts.append("VLM verification failed")
    else:
         feedback_parts.append("No screenshots available for VLM")

    score += vlm_score

    # --- 4. Final Decision ---
    # Pass if: Score >= 70 AND Answer is Correct AND File Created During Task
    passed = (score >= 70) and (content == expected_answer) and created_during
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }