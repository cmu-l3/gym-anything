#!/usr/bin/env python3
"""
Verifier for configure_generator_runtime task.

Logic:
1. Feed 'generator_hours' must exist.
2. Input 'generator_status' must have a process chain.
3. Chain must include Scaling (x) and Integration (Power to kWh).
4. Scale factor should be ~1000 (to convert 1 'status' to 1 'hour' via kWh math).
   - Math: 1 (status) * 1000 (scale) = 1000 'Watts'.
   - 1000 'Watts' for 1 hour = 1 kWh.
   - 1 kWh = 1 unit in the feed = 1 Hour.
5. Functional test (Slope) checks if the feed actually increments at the right rate.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_generator_runtime(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_slope = metadata.get('expected_slope_10s', 0.00277) # 10s in hours
    slope_tolerance = metadata.get('slope_tolerance', 0.0005)

    # 1. Retrieve Result JSON
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

    score = 0
    feedback_parts = []
    
    # 2. Check Feed Existence (20 pts)
    if result.get('feed_exists', False):
        score += 20
        feedback_parts.append("Feed 'generator_hours' created")
    else:
        return {"passed": False, "score": 0, "feedback": "Feed 'generator_hours' not found"}

    # 3. Check Configuration (Scaling) (30 pts)
    has_scale = result.get('process_has_scale', False)
    try:
        scale_val = float(result.get('process_scale_value', 0))
    except:
        scale_val = 0
        
    if has_scale and (950 <= scale_val <= 1050):
        score += 30
        feedback_parts.append(f"Correct scaling factor ({scale_val})")
    elif has_scale:
        score += 10 # Partial credit for scaling, even if wrong value
        feedback_parts.append(f"Scaling process found but value ({scale_val}) is incorrect (expected ~1000)")
    else:
        feedback_parts.append("Scaling process missing (needed to convert status to hours)")

    # 4. Check Configuration (Integrator) (20 pts)
    if result.get('process_has_integrator', False):
        score += 20
        feedback_parts.append("Integrator 'Power to kWh' found")
    else:
        feedback_parts.append("Integrator process missing")

    # 5. Functional Slope Check (30 pts)
    # Does the feed increment correctly when simulator is running?
    delta = result.get('functional_slope_delta', 0)
    
    # Expected: ~0.00277 for 10s
    # If unscaled (scale=1): ~0.00000277 (Too small)
    
    if abs(delta - expected_slope) < slope_tolerance:
        score += 30
        feedback_parts.append(f"Feed tracking accurately (delta={delta:.5f})")
    elif delta > 0:
        # It's increasing, but wrong rate
        if not has_scale:
             feedback_parts.append(f"Feed is increasing ({delta:.7f}) but too slowly (did you forget to scale?)")
        else:
             feedback_parts.append(f"Feed is increasing ({delta:.5f}) but not at expected rate (expected ~{expected_slope:.5f})")
        score += 10 # Partial functional credit
    else:
        feedback_parts.append("Feed value did not increase during test")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }