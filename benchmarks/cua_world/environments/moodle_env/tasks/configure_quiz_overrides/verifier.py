#!/usr/bin/env python3
"""Verifier for Configure Quiz Overrides task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_quiz_overrides(traj, env_info, task_info):
    """
    Verify that user and group overrides were configured correctly.

    Scoring (100 points):
    - User Override (epatel):
        - Exists: 15 pts
        - Time limit = 90 min (5400s): 15 pts
        - Attempts = 2: 10 pts
    - Group Override (Extended Time Group):
        - Exists: 15 pts
        - Time limit = 75 min (4500s): 15 pts
        - Attempts = 2: 10 pts
    - Anti-gaming (Count increased): 10 pts

    Pass threshold: 60 points (must have at least one correct override config)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    exp_user_time = metadata.get('user_override_timelimit', 5400)
    exp_user_attempts = metadata.get('user_override_attempts', 2)
    exp_group_time = metadata.get('group_override_timelimit', 4500)
    exp_group_attempts = metadata.get('group_override_attempts', 2)

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_quiz_overrides_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Anti-gaming check (10 pts)
        initial = int(result.get('initial_count', 0))
        current = int(result.get('current_count', 0))
        if current > initial:
            score += 10
            feedback_parts.append(f"Overrides created (count: {initial} -> {current})")
        else:
            feedback_parts.append("No new overrides created")

        # 2. User Override Verification (40 pts total)
        u_ovr = result.get('user_override', {})
        if u_ovr.get('found'):
            score += 15
            feedback_parts.append("User override exists")
            
            # Check Time
            u_time = int(u_ovr.get('timelimit', 0))
            if u_time == exp_user_time:
                score += 15
                feedback_parts.append("User time correct (90m)")
            else:
                feedback_parts.append(f"User time mismatch: {u_time}s (expected {exp_user_time}s)")
            
            # Check Attempts
            u_attempts = int(u_ovr.get('attempts', 0))
            if u_attempts == exp_user_attempts:
                score += 10
                feedback_parts.append("User attempts correct (2)")
            else:
                feedback_parts.append(f"User attempts mismatch: {u_attempts} (expected {exp_user_attempts})")
        else:
            feedback_parts.append("User override NOT found")

        # 3. Group Override Verification (40 pts total)
        g_ovr = result.get('group_override', {})
        if g_ovr.get('found'):
            score += 15
            feedback_parts.append("Group override exists")
            
            # Check Time
            g_time = int(g_ovr.get('timelimit', 0))
            if g_time == exp_group_time:
                score += 15
                feedback_parts.append("Group time correct (75m)")
            else:
                feedback_parts.append(f"Group time mismatch: {g_time}s (expected {exp_group_time}s)")
            
            # Check Attempts
            g_attempts = int(g_ovr.get('attempts', 0))
            if g_attempts == exp_group_attempts:
                score += 10
                feedback_parts.append("Group attempts correct (2)")
            else:
                feedback_parts.append(f"Group attempts mismatch: {g_attempts} (expected {exp_group_attempts})")
        else:
            feedback_parts.append("Group override NOT found")

        # Determine pass/fail
        # Must score at least 60 points
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}