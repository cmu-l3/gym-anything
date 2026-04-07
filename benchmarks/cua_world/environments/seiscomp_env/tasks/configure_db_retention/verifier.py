#!/usr/bin/env python3
"""
Verifier for Database Retention Script task.

Verification Strategy:
1. File exists at expected location (15 pts)
2. File was created during task (10 pts)
3. File is executable (10 pts)
4. Content analysis: Uses scdbstrip (20 pts)
5. Content analysis: Uses 365 days constraint (15 pts)
6. Dynamic execution check: Test runs successfully with code 0 (15 pts)
7. VLM check: Trajectory frames confirm agent workflow in terminal/editor (15 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_db_retention(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1 & 2. Existence & Timestamp Verification (25 points total)
    if result.get("script_exists"):
        score += 15
        feedback.append("Script exists")
        
        if result.get("created_during_task"):
            score += 10
            feedback.append("Script created during task (passed anti-gaming)")
        else:
            feedback.append("Script not created during task (failed anti-gaming)")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target script /home/ga/scripts/cleanup_events.sh was not found."
        }

    # 3. Permissions Verification (10 points)
    if result.get("script_executable"):
        score += 10
        feedback.append("Script is executable")
    else:
        feedback.append("Script is NOT executable")

    # 4 & 5. Content Verification (35 points total)
    content = result.get("script_content", "")
    has_scdbstrip = "scdbstrip" in content
    has_days = "365" in content and ("-d" in content or "--days" in content)

    if has_scdbstrip:
        score += 20
        feedback.append("Found target tool (scdbstrip) in script")
    else:
        feedback.append("Missing required tool 'scdbstrip' in script")

    if has_days:
        score += 15
        feedback.append("Found correct retention parameter (365 days)")
    else:
        feedback.append("Missing correct retention argument for 365 days")

    # 6. Dynamic Execution Verification (15 points)
    exit_code = result.get("test_exit_code")
    if exit_code == 0:
        score += 15
        feedback.append("Test execution successful (exit code 0)")
    else:
        feedback.append(f"Test execution failed with exit code {exit_code}")

    # 7. VLM Workflow Verification (15 points)
    vlm_score = 0
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are evaluating an AI agent. The task is to create a bash script for database retention.
Analyze these trajectory frames and output JSON indicating if you observe:
1. The agent using a terminal or text editor (like nano/vim).
2. The agent typing/editing a script that contains 'scdbstrip'.

Respond in strict JSON format:
{
  "terminal_or_editor_used": true/false,
  "typing_script_observed": true/false
}"""
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("terminal_or_editor_used"): vlm_score += 5
                if parsed.get("typing_script_observed"): vlm_score += 10
                feedback.append(f"VLM visual workflow verified (+{vlm_score})")
            else:
                feedback.append("VLM verification failed to parse")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback.append("VLM check error")
    
    score += vlm_score
    
    # Must meet core criteria to pass
    passed = (score >= 75) and result.get("script_exists") and has_scdbstrip
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }