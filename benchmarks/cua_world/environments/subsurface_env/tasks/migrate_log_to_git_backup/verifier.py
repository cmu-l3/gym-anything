#!/usr/bin/env python3
"""Verifier for migrate_log_to_git_backup task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_migrate_log_to_git_backup(traj, env_info, task_info):
    """
    Verify that the agent migrated the dive log to a Git repository using Subsurface.
    Uses multi-criteria scoring combining file system analysis, Git history, and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    # Retrieve output metrics
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = int(result.get('task_start_time', 0))
    latest_commit_time = int(result.get('latest_commit_time', 0))
    commit_count = int(result.get('commit_count', 0))

    score = 0
    feedback_parts = []

    # Criterion 1: Base backup directory created (15 pts)
    if result.get('base_dir_exists'):
        score += 15
        feedback_parts.append("Backup directory created")
    else:
        feedback_parts.append("Backup directory missing")

    # Criterion 2: Target git dir exists & is valid Git repo (30 pts)
    git_valid = result.get('git_valid', False)
    if git_valid:
        score += 30
        feedback_parts.append("Valid Git repository verified")
    elif result.get('git_dir_exists'):
        score += 10
        feedback_parts.append("Target directory exists but is NOT a valid Git repo")
    else:
        feedback_parts.append("Target Git directory missing")

    # Criterion 3: Anti-gaming & commit history (25 pts)
    is_recent_commit = False
    if commit_count > 0:
        if latest_commit_time >= task_start:
            score += 25
            is_recent_commit = True
            feedback_parts.append(f"Recent Git commit found ({commit_count} commits)")
        else:
            feedback_parts.append("Git commit found, but timestamp predates task start (Anti-gaming check failed)")
    else:
        feedback_parts.append("No commits found in Git repository")

    # Criterion 4: VLM Trajectory Verification (30 pts)
    vlm_score = 0
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=6)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are evaluating an AI agent's performance in a desktop application. 
        The agent's task was to use Subsurface's "Save As" feature to save the log as a "Local Git repository".
        
        Please look at the trajectory screenshots and determine:
        1. Did the agent open a 'Save As' or file saving dialog?
        2. Did the agent change the file type / format filter to 'Local Git repository' (or a similar Git format)?
        
        Respond in strict JSON format:
        {
            "opened_save_dialog": true/false,
            "selected_git_format": true/false,
            "reasoning": "Brief explanation of what UI elements were observed"
        }
        """
        
        vlm_result = query_vlm(images=images, prompt=prompt)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("opened_save_dialog"):
                vlm_score += 10
            if parsed.get("selected_git_format"):
                vlm_score += 20
                vlm_passed = True
                
            score += vlm_score
            feedback_parts.append(f"VLM UI check: {vlm_score}/30 pts")
        else:
            feedback_parts.append("VLM verification failed to process")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM is entirely unavailable, we gracefully fallback and pro-rate the score if Git verification is perfect
        if git_valid and is_recent_commit:
            score += 30
            feedback_parts.append("VLM skipped; points awarded based on perfect programmatic Git state")

    # Determine passing status
    key_criteria_met = result.get('base_dir_exists') and git_valid and is_recent_commit
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }