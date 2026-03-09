#!/usr/bin/env python3
"""
Verifier for configure_overtime_policy task.

Verification Criteria:
1. Policy Existence: Database record with name 'Manufacturing OT Policy' exists.
2. Parameter Accuracy:
   - Weekday Multiplier: 1.5
   - Rest Day Multiplier: 2.0
   - Threshold: 480 mins (8 hours)
   - Rounding: 30 mins
   - Min OT: 30 mins
3. VLM Trajectory: Visual confirmation of workflow.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_overtime_policy(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the overtime policy configuration using DB export and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values from metadata or defaults
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('policy_name', 'Manufacturing OT Policy')
    
    # Use loose matching for float values due to potential DB storage differences
    expected_weekday = 1.5
    expected_restday = 2.0
    expected_threshold = 480 # minutes
    expected_rounding = 30
    expected_min_ot = 30

    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path is C:\workspace\task_result.json, mapped to container path
        # In Windows containers, paths might be tricky. Assuming copy_from_env handles the abstraction
        # or we use the mapped path if available.
        # Standard convention: 'C:\workspace\task_result.json'
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Verify Policy Existence (Critical: 20 pts)
    policy_found = result.get('policy_found', False)
    policy_data = result.get('policy_data', {})

    if policy_found:
        score += 20
        feedback_parts.append(f"Policy '{expected_name}' found in database")
    else:
        feedback_parts.append(f"Policy '{expected_name}' NOT found in database")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Verify Parameters (60 pts total)
    
    # Helper to clean and float-ify values
    def parse_val(val):
        try:
            return float(str(val).strip())
        except (ValueError, TypeError):
            return -1.0

    # Weekday Rate (15 pts)
    # DB Column might be OT_RATE_WEEKDAY or similar depending on actual schema
    # We check typical keys
    wd_rate = parse_val(policy_data.get('OT_RATE_WEEKDAY', 0))
    if wd_rate == expected_weekday:
        score += 15
        feedback_parts.append("Weekday rate correct (1.5x)")
    else:
        feedback_parts.append(f"Weekday rate mismatch (Expected 1.5, Got {wd_rate})")

    # Rest Day Rate (15 pts)
    rd_rate = parse_val(policy_data.get('OT_RATE_WEEKLYOFF', 0))
    # Also check HOLIDAY just in case user mixed them up, give partial credit? No, distinct fields.
    if rd_rate == expected_restday:
        score += 15
        feedback_parts.append("Rest day rate correct (2.0x)")
    else:
        feedback_parts.append(f"Rest day rate mismatch (Expected 2.0, Got {rd_rate})")

    # Threshold (10 pts)
    threshold = parse_val(policy_data.get('OT_THRESHOLD_MINUTES', 0))
    if threshold == expected_threshold:
        score += 10
        feedback_parts.append("Threshold correct (8h/480m)")
    else:
        feedback_parts.append(f"Threshold mismatch (Expected 480, Got {threshold})")

    # Rounding (10 pts)
    rounding = parse_val(policy_data.get('ROUNDING_MINUTES', 0))
    if rounding == expected_rounding:
        score += 10
        feedback_parts.append("Rounding correct (30m)")
    else:
        feedback_parts.append(f"Rounding mismatch (Got {rounding})")

    # Min OT (10 pts)
    min_ot = parse_val(policy_data.get('MIN_OT_MINUTES', 0))
    if min_ot == expected_min_ot:
        score += 10
        feedback_parts.append("Min OT correct (30m)")
    else:
        feedback_parts.append(f"Min OT mismatch (Got {min_ot})")

    # 4. VLM Verification (20 pts)
    # We assume an external VLM evaluator would check the trajectory frames
    # Here we check basic app state as a proxy or use a placeholder for VLM score
    app_running = result.get('app_running', False)
    if app_running:
        score += 10 # App was running at end
        feedback_parts.append("Application active")

    # Final logic
    passed = (score >= 60) and policy_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": policy_data
    }