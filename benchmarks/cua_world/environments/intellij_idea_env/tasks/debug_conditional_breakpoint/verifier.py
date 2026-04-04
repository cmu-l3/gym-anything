#!/usr/bin/env python3
"""Verifier for debug_conditional_breakpoint task."""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_conditional_breakpoint(traj, env_info, task_info):
    """Verify that the agent found the correct value using the debugger without modifying code.

    Criteria:
    1. Solution file exists (10 pts)
    2. Source code was NOT modified (40 pts) - Critical constraint!
    3. Value matches ground truth (50 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get the Agent's Result
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    # 2. Get the Ground Truth (Hidden file)
    try:
        tmp_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_truth.close()
        copy_from_env("/var/lib/task/ground_truth.txt", tmp_truth.name)
        with open(tmp_truth.name, 'r') as f:
            ground_truth_str = f.read().strip()
        os.unlink(tmp_truth.name)
        ground_truth_val = float(ground_truth_str)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Solution File Exists (10 pts) ---
    if result.get("solution_exists", False):
        score += 10
        feedback_parts.append("Solution file created")
    else:
        feedback_parts.append("Solution file missing")
        return {"passed": False, "score": 0, "feedback": "Solution file not found"}

    # --- Criterion 2: Source Code Unmodified (40 pts) ---
    # This is critical. If they modified the source (e.g. added System.out.println), 
    # they failed the specific constraint of the task.
    if result.get("source_modified", True):
        feedback_parts.append("FAIL: Source code was modified. Task required using debugger on read-only code.")
        # Zero score for this section is a severe penalty
    else:
        score += 40
        feedback_parts.append("Source code integrity maintained (read-only constraint respected)")

    # --- Criterion 3: Value Accuracy (50 pts) ---
    agent_val_str = result.get("solution_content", "")
    try:
        agent_val = float(agent_val_str)
        # Tolerance check (epsilon 1e-9)
        if math.isclose(agent_val, ground_truth_val, rel_tol=1e-9):
            score += 50
            feedback_parts.append("Correct value identified")
        else:
            feedback_parts.append(f"Value incorrect. Expected approx {ground_truth_val}, got {agent_val}")
    except ValueError:
        feedback_parts.append(f"Invalid numeric format in solution: '{agent_val_str}'")

    # --- Final Assessment ---
    # Strict pass condition: Must get the value right AND not modify source
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }