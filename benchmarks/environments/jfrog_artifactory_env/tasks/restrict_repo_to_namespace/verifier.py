#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restrict_repo_to_namespace(traj, env_info, task_info):
    """
    Verifies that the agent correctly restricted the repository artifact paths.
    
    Scoring Criteria:
    1. Configuration Match (20 pts): 'includesPattern' is 'com/acme/**'
    2. Positive Test (30 pts): Upload to 'com/acme/...' succeeded.
    3. Negative Test (40 pts): Upload to 'org/rogue/...' was blocked.
    4. Integrity (10 pts): Tests ran (result file exists).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in environment."}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result file contained invalid JSON."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Integrity / Baseline
    score += 10 # Base points for having a result
    
    # 2. Configuration Check
    config_match = result.get("config_match", False)
    actual_pattern = result.get("config_includes_pattern", "UNKNOWN")
    
    if config_match:
        score += 20
        feedback_parts.append("Configuration verified: 'Includes Pattern' set correctly.")
    else:
        feedback_parts.append(f"Configuration mismatch: Found '{actual_pattern}', expected 'com/acme/**'.")

    # 3. Positive Test (Valid Path)
    pos_passed = result.get("positive_test_passed", False)
    pos_code = result.get("positive_test_code", "000")
    
    if pos_passed:
        score += 30
        feedback_parts.append("Positive Test: Upload to 'com/acme/...' succeeded.")
    else:
        feedback_parts.append(f"Positive Test Failed: Upload to 'com/acme/...' failed (HTTP {pos_code}).")

    # 4. Negative Test (Invalid Path) - The most important part
    neg_passed = result.get("negative_test_passed", False)
    neg_code = result.get("negative_test_code", "000")
    
    if neg_passed:
        score += 40
        feedback_parts.append("Negative Test: Upload to 'org/rogue/...' was correctly BLOCKED.")
    else:
        # If code was 201, it means the block didn't work
        if neg_code == "201":
            feedback_parts.append("Negative Test Failed: Repository improperly accepted forbidden path (HTTP 201).")
        else:
            feedback_parts.append(f"Negative Test Failed: Unexpected state (HTTP {neg_code}).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }