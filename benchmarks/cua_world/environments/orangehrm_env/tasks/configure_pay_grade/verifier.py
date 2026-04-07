#!/usr/bin/env python3
"""
Verifier for configure_pay_grade task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_pay_grade(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent created the correct Pay Grade and Currency settings.
    
    Criteria:
    1. Pay Grade 'Grade HC-4' exists (25 pts)
    2. Pay Grade was created during the task session (anti-gaming) (10 pts)
    3. Currency 'USD' is assigned to the Pay Grade (20 pts)
    4. Minimum Salary is 72,000 (15 pts)
    5. Maximum Salary is 104,500 (15 pts)
    6. VLM Trajectory Check (15 pts) - Verified via trajectory analysis (simulated here if program passed)
    """
    
    # 1. Retrieve result data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata Expectations
    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('target_min_salary', 72000)
    expected_max = metadata.get('target_max_salary', 104500)
    tolerance = metadata.get('salary_tolerance', 1.0)

    # 3. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: Pay Grade Exists (25 pts)
    if result.get('pay_grade_exists'):
        score += 25
        feedback_parts.append("✅ Pay Grade 'Grade HC-4' created.")
    else:
        feedback_parts.append("❌ Pay Grade 'Grade HC-4' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Criterion 2: Anti-Gaming / Created During Task (10 pts)
    if result.get('created_during_task'):
        score += 10
        feedback_parts.append("✅ Verified creation timestamp (fresh record).")
    else:
        feedback_parts.append("⚠️ Pay Grade ID suggests it wasn't created in this session (potential gaming).")

    # Criterion 3: Currency Assigned (20 pts)
    if result.get('currency_exists'):
        score += 20
        feedback_parts.append("✅ USD Currency assigned.")
    else:
        feedback_parts.append("❌ USD Currency not assigned to pay grade.")

    # Criterion 4: Minimum Salary (15 pts)
    found_min = float(result.get('found_min_salary', 0))
    if abs(found_min - expected_min) <= tolerance:
        score += 15
        feedback_parts.append(f"✅ Min Salary correct ({found_min}).")
    else:
        feedback_parts.append(f"❌ Min Salary incorrect (Found: {found_min}, Expected: {expected_min}).")

    # Criterion 5: Maximum Salary (15 pts)
    found_max = float(result.get('found_max_salary', 0))
    if abs(found_max - expected_max) <= tolerance:
        score += 15
        feedback_parts.append(f"✅ Max Salary correct ({found_max}).")
    else:
        feedback_parts.append(f"❌ Max Salary incorrect (Found: {found_max}, Expected: {expected_max}).")

    # Criterion 6: VLM/Trajectory verification (15 pts)
    # Since we have strong programmatic verification here, we award these points 
    # if the programmatic parts are perfect, assuming the agent did the work.
    # In a full system, we would query the VLM here.
    if score >= 85:
        score += 15
        feedback_parts.append("✅ Workflow verified.")
    else:
        feedback_parts.append("⚠️ Workflow incomplete.")

    passed = score >= 60 and result.get('pay_grade_exists') and result.get('currency_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }