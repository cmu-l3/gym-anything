#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_merge_conflicts(traj, env_info, task_info):
    """
    Verify that the agent correctly resolved git merge conflicts.
    
    Scoring Breakdown (100 pts total):
    - 15 pts: No conflict markers (<<<<<<<) remaining
    - 20 pts: All PID tests pass (verifies logic merge)
    - 20 pts: All Motor tests pass (verifies logic merge)
    - 15 pts: All Filter tests pass (verifies rename/add)
    - 10 pts: Static check for adaptive features
    - 10 pts: Static check for ramp+clamp features
    - 5 pts: Git status is clean (merge committed)
    - 5 pts: Test files unmodified (anti-gaming)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Conflict Markers (15 pts)
    if result.get("no_conflict_markers"):
        score += 15
        feedback.append("Conflict markers removed (15/15)")
    else:
        feedback.append("FAILED: Conflict markers (<<<<<<<) still present")

    # 2. Test Execution (55 pts total)
    # PID Tests (5 expected)
    pid_pass = result.get("passed_pid_count", 0)
    if pid_pass >= 5:
        score += 20
        feedback.append("PID tests passed (20/20)")
    else:
        feedback.append(f"PID tests failing: {pid_pass}/5 passing")

    # Motor Tests (4 expected)
    motor_pass = result.get("passed_motor_count", 0)
    if motor_pass >= 4:
        score += 20
        feedback.append("Motor tests passed (20/20)")
    else:
        feedback.append(f"Motor tests failing: {motor_pass}/4 passing")

    # Filter Tests (3 expected)
    filters_pass = result.get("passed_filters_count", 0)
    if filters_pass >= 3:
        score += 15
        feedback.append("Filter tests passed (15/15)")
    else:
        feedback.append(f"Filter tests failing: {filters_pass}/3 passing")

    # 3. Static Analysis (20 pts)
    if result.get("has_adaptive_features"):
        score += 10
        feedback.append("Adaptive logic preserved (10/10)")
    else:
        feedback.append("FAILED: Adaptive logic missing in PID")

    if result.get("has_ramp_and_clamp"):
        score += 10
        feedback.append("Ramp & Clamp logic preserved (10/10)")
    else:
        feedback.append("FAILED: Ramp/Clamp logic missing in Motor")

    # 4. Process Hygiene (10 pts)
    if result.get("git_clean"):
        score += 5
    else:
        feedback.append("Warning: Git merge not committed (working tree dirty)")

    if result.get("tests_unmodified"):
        score += 5
    else:
        feedback.append("CRITICAL: Test files were modified! (Anti-gaming penalty)")
        score = 0 # Zero out score if tests were tampered with

    # Final tally
    passed = (score >= 65) and result.get("no_conflict_markers")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }