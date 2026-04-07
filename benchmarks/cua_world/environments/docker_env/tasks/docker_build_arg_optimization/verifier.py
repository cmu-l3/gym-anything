#!/usr/bin/env python3
"""
Verifier for docker_build_arg_optimization task.

Scoring (100 points):
- 40 pts: Functional Correctness (App reports correct version at runtime)
- 40 pts: Cache Optimization (Dependency layer preserved when ARG changes)
- 10 pts: Dockerfile modified
- 10 pts: ENV instruction present (Static check backup)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_build_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task result file missing (export failed)."}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Task result JSON malformed."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check if Dockerfile was modified (10 pts)
    if result.get("dockerfile_modified", False):
        score += 10
        feedback.append("Dockerfile was modified.")
    else:
        feedback.append("Dockerfile was NOT modified.")

    # 2. Check Functional Correctness (40 pts)
    # Did the app report "Version: 1.0"?
    if result.get("version_reported_correctly", False):
        score += 40
        feedback.append("Functional check passed: App correctly reports version from ARG->ENV.")
    else:
        resp = result.get("response_output", "No response")
        feedback.append(f"Functional check failed: App reported '{resp}' instead of expected version.")

    # 3. Check Cache Optimization (40 pts)
    # Did the pip install layer ID remain constant?
    if result.get("cache_optimized", False):
        score += 40
        feedback.append("Optimization check passed: Dependency cache preserved across version change.")
    else:
        feedback.append("Optimization check failed: Changing build ARG invalidated the dependency cache (Layer IDs differed).")

    # 4. Check for ENV instruction (10 pts)
    if result.get("has_env_instruction", False):
        score += 10
        feedback.append("ENV instruction found in Dockerfile.")
    else:
        feedback.append("ENV instruction missing from Dockerfile.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }