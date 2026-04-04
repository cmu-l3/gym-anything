#!/usr/bin/env python3
"""
Verifier for configure_multi_metric_pipeline task.
"""

import json
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pipeline(traj, env_info, task_info):
    """
    Verifies the Emoncms pipeline configuration.
    
    Criteria:
    1. Feeds exist and have values (Functional Test).
    2. Values match expected math based on the rates provided in the task.
       - Power: ~Input
       - Carbon: Input * (0.42 / 1000)
       - Cost: Input * (0.24 / 1000)
    3. Structural check: The process list string contains evidence of branching (Reset to ZERO).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_feeds = metadata.get('expected_feeds', {})
    tolerance_percent = metadata.get('tolerance_percent', 2.0)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    feeds_data = result.get('functional_test', {}).get('feeds', {})
    process_list_raw = result.get('configuration', {}).get('process_list_raw', "")
    
    # 1. Check Power Feed (10 pts)
    # ---------------------------
    p_val = feeds_data.get('facility_power_W')
    if p_val is not None and isinstance(p_val, (int, float)):
        expected = expected_feeds['facility_power_W']
        # Allow small deviation
        if math.isclose(p_val, expected, rel_tol=tolerance_percent/100.0):
            score += 10
            feedback.append(f"Power feed correct ({p_val})")
        else:
            feedback.append(f"Power feed value mismatch: Got {p_val}, Expected {expected}")
    else:
        feedback.append("Power feed missing or null")

    # 2. Check Carbon Feed (30 pts)
    # ---------------------------
    # Needs correct scaling (Watts -> kW) and correct factor
    c_val = feeds_data.get('facility_carbon_kgph')
    if c_val is not None and isinstance(c_val, (int, float)):
        expected = expected_feeds['facility_carbon_kgph']
        if math.isclose(c_val, expected, rel_tol=tolerance_percent/100.0):
            score += 30
            feedback.append(f"Carbon feed correct ({c_val})")
        else:
            feedback.append(f"Carbon feed value mismatch: Got {c_val}, Expected {expected}. Did you convert Watts to kW?")
    else:
        feedback.append("Carbon feed missing or null")

    # 3. Check Cost Feed (30 pts)
    # ---------------------------
    cost_val = feeds_data.get('facility_cost_dollarsph')
    if cost_val is not None and isinstance(cost_val, (int, float)):
        expected = expected_feeds['facility_cost_dollarsph']
        if math.isclose(cost_val, expected, rel_tol=tolerance_percent/100.0):
            score += 30
            feedback.append(f"Cost feed correct ({cost_val})")
        else:
            feedback.append(f"Cost feed value mismatch: Got {cost_val}, Expected {expected}. Did you convert Watts to kW?")
    else:
        feedback.append("Cost feed missing or null")

    # 4. Structural Check (30 pts)
    # ---------------------------
    # We look for the "Reset to ZERO" processor ID. In Emoncms, this is typically ID 24.
    # The process list string format is "process_id:arg,process_id:arg,..."
    if process_list_raw and ("24:" in process_list_raw or "Reset" in process_list_raw): # "24:" is ID for Reset, "Reset" covers if format changes
        score += 30
        feedback.append("Process list contains Reset/Branching logic")
    elif score >= 70: 
        # If they got the right values but we didn't detect ID 24, maybe they did it another way?
        # But this task specifically requested the Reset pattern.
        # If they achieved the result, they likely used Reset or -Input. 
        # We'll give partial credit if values are perfect but structure is ambiguous.
        score += 15
        feedback.append("Correct values, but specific 'Reset to ZERO' processor not explicitly detected in raw string")
    else:
        feedback.append("Process list missing 'Reset to ZERO' logic needed for branching")

    # Final logic
    passed = (score >= 90) # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }