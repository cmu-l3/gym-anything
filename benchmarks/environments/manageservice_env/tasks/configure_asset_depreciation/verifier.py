#!/usr/bin/env python3
"""
Verifier for configure_asset_depreciation task.

Checks:
1. That a depreciation policy exists for 'Workstation'.
2. Method is 'Straight Line'.
3. Useful Life is 36 months.
4. Salvage Value is 5%.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_asset_depreciation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    db_result = result.get("db_result", {})
    found = db_result.get("found", False)
    data = db_result.get("data", {})

    # Expected Values from Metadata
    metadata = task_info.get("metadata", {})
    exp_method = metadata.get("expected_method", "Straight Line").lower()
    exp_life = metadata.get("expected_useful_life", 36)
    exp_salvage = metadata.get("expected_salvage_value", 5)
    
    scoring = metadata.get("scoring", {
        "policy_exists": 40,
        "correct_method": 20,
        "correct_life": 20,
        "correct_salvage": 20
    })

    score = 0
    feedback = []

    # 1. Check if policy exists (40 pts)
    if not found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No depreciation policy found for 'Workstation'. Did you save the configuration?"
        }
    
    score += scoring["policy_exists"]
    feedback.append("Policy record created.")

    # 2. Check Method (20 pts)
    # DB might return 'Straight Line' or similar. We check fuzzy match.
    actual_method = str(data.get("method_name", "")).lower()
    if exp_method in actual_method or actual_method in exp_method:
        score += scoring["correct_method"]
        feedback.append(f"Method correct ({data.get('method_name')}).")
    else:
        feedback.append(f"Incorrect method. Expected '{exp_method}', got '{actual_method}'.")

    # 3. Check Useful Life (20 pts)
    actual_life = data.get("useful_life_months")
    try:
        if int(actual_life) == int(exp_life):
            score += scoring["correct_life"]
            feedback.append(f"Useful life correct ({actual_life} months).")
        else:
            feedback.append(f"Incorrect useful life. Expected {exp_life}, got {actual_life}.")
    except (ValueError, TypeError):
        feedback.append(f"Invalid useful life value: {actual_life}")

    # 4. Check Salvage Value (20 pts)
    actual_salvage = data.get("salvage_percentage")
    try:
        # DB might store as int (5) or float (5.00)
        if int(float(actual_salvage)) == int(exp_salvage):
            score += scoring["correct_salvage"]
            feedback.append(f"Salvage value correct ({actual_salvage}%).")
        else:
            feedback.append(f"Incorrect salvage value. Expected {exp_salvage}, got {actual_salvage}.")
    except (ValueError, TypeError):
        feedback.append(f"Invalid salvage value: {actual_salvage}")

    # Final Pass Check
    # Threshold: Need 80 points (Must basically get everything right, maybe one minor typo tolerated if strictness relaxed, but logic implies boolean correctness)
    # The prompt specified 80 threshold.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }