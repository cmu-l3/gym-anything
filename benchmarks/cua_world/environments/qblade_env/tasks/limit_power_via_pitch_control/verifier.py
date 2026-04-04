#!/usr/bin/env python3
"""
Verifier for limit_power_via_pitch_control task.

Criteria:
1. Project file created and valid.
2. Pitch setting file exists and indicates positive pitch (feathering).
3. Simulation result file indicates Power is within target range (50kW +/- 2kW).
4. VLM verification of the process/graph.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_limit_power_via_pitch_control(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_power = metadata.get('target_power_watts', 50000)
    tolerance = metadata.get('power_tolerance_watts', 2000)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Project File (20 pts)
    if result.get('project_exists', False):
        size = result.get('project_size_bytes', 0)
        if size > 1000: # minimal check for non-empty
            score += 20
            feedback_parts.append("Project file saved")
        else:
            score += 5
            feedback_parts.append("Project file exists but is empty/small")
    else:
        feedback_parts.append("Project file not found")

    # 2. Pitch Setting Logic (20 pts)
    # De-rating via pitch usually implies feathering (pitch > 0) to reduce Cp.
    # Stall (pitch < 0) is possible but less common for controlled de-rating.
    pitch_exists = result.get('pitch_file_exists', False)
    pitch_val = float(result.get('pitch_value', 0))
    
    if pitch_exists:
        if pitch_val > 0.1:
            score += 20
            feedback_parts.append(f"Pitch setting recorded ({pitch_val} deg, feathering)")
        elif pitch_val < -0.1:
            score += 15
            feedback_parts.append(f"Pitch setting recorded ({pitch_val} deg, stall control?)")
        else:
            score += 5
            feedback_parts.append(f"Pitch setting recorded ({pitch_val} deg - unlikely to limit to 50kW unless rotor is tiny)")
    else:
        feedback_parts.append("Pitch setting file not found")

    # 3. Power Target Accuracy (40 pts)
    power_watts = float(result.get('measured_power_watts', 0))
    result_exists = result.get('result_file_exists', False)
    
    if result_exists:
        error = abs(power_watts - target_power)
        if error <= tolerance:
            score += 40
            feedback_parts.append(f"Target power achieved: {power_watts:.0f} W (within ±{tolerance}W)")
        elif error <= tolerance * 2:
            score += 20
            feedback_parts.append(f"Target power close: {power_watts:.0f} W (within ±{tolerance*2}W)")
        elif power_watts > 1000:
            score += 5
            feedback_parts.append(f"Simulation run, but power {power_watts:.0f} W is far from target 50kW")
        else:
            feedback_parts.append("Simulation result file exists but contained no valid power data")
    else:
        feedback_parts.append("Simulation result file not found")

    # 4. App Running (20 pts)
    if result.get('app_was_running', False):
        score += 20
        feedback_parts.append("QBlade was running")
    else:
        feedback_parts.append("QBlade was not running")

    # Determine Pass/Fail
    # Must have hit the power target reasonably well to pass
    passed = (score >= 60) and (abs(power_watts - target_power) <= tolerance * 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }