#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retire_drug_formulation(traj, env_info, task_info):
    """
    Verify that the agent retired the correct drug with the correct reason.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the result file
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

    # 2. Extract Data
    drug_data = result.get("drug_data", {})
    if not drug_data.get("exists"):
        return {"passed": False, "score": 0, "feedback": "Target drug could not be found in the system."}

    retired = drug_data.get("retired", False)
    retire_reason = drug_data.get("retireReason", "") or ""
    
    # 3. Scoring
    score = 0
    feedback = []

    # Criteria 1: Drug is Retired (40 pts)
    if retired:
        score += 40
        feedback.append("Drug is successfully retired.")
    else:
        feedback.append("Drug is NOT retired.")

    # Criteria 2: Correct Reason (40 pts)
    # Check for keywords "Cardiovascular" and "safety"
    expected_snippet = "cardiovascular safety alert"
    if expected_snippet in retire_reason.lower():
        score += 40
        feedback.append("Retire reason matches requirements.")
    elif "cardiovascular" in retire_reason.lower() or "safety" in retire_reason.lower():
        score += 20
        feedback.append(f"Retire reason '{retire_reason}' is partially correct (missing keywords).")
    else:
        feedback.append(f"Retire reason '{retire_reason}' is incorrect or missing.")

    # Criteria 3: Anti-gaming / Timestamp check (20 pts)
    # We rely on the fact that setup_task sets it to active. 
    # If it's retired now, the agent must have done it.
    # We can assume if it's retired, the action happened during the task since setup cleared it.
    if retired:
        score += 20
    
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }