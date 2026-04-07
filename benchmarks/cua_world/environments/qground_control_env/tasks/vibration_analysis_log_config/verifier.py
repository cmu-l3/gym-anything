#!/usr/bin/env python3
"""
Verifier for vibration_analysis_log_config task.

Multi-signal verification strategy:
1. Live vehicle parameters via MAVLink (50 points, 10 per parameter)
2. Presence and recency of the exported .params file (10 points)
3. Content of the .params file reflecting the required parameters (40 points, 8 per parameter)

Pass threshold is 75, requiring the live vehicle settings to be configured
AND the parameter file successfully exported containing the values.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_PARAMS = {
    'INS_LOG_BAT_MASK': 1.0,
    'INS_LOG_BAT_OPT': 0.0,
    'INS_HNTCH_ENABLE': 0.0,
    'LOG_DISARMED': 1.0,
    'LOG_BITMASK': 65535.0
}


def verify_vibration_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Copy and parse result file
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    details = {}

    # 1. LIVE PARAMETERS CHECK (50 pts total)
    live_params = result.get('live_params', {})
    if not live_params.get('connected', True) and all(live_params.get(p) is None for p in TARGET_PARAMS):
        feedback_parts.append("WARNING: SITL MAVLink connection failed during verification.")
        
    for param_name, target_val in TARGET_PARAMS.items():
        actual_val = live_params.get(param_name)
        details[f'live_{param_name}'] = actual_val
        
        if actual_val is not None:
            try:
                if abs(float(actual_val) - target_val) <= 0.1:
                    score += 10
                    feedback_parts.append(f"Live {param_name}={int(actual_val)} ✓ (+10)")
                else:
                    feedback_parts.append(f"Live {param_name}={actual_val} (need {int(target_val)}) (+0)")
            except (TypeError, ValueError):
                feedback_parts.append(f"Live {param_name} is invalid type (+0)")
        else:
            feedback_parts.append(f"Live {param_name} could not be read (+0)")

    # 2. FILE ARTIFACT CHECK (10 pts)
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    details['file_found'] = file_found
    details['modified'] = modified
    
    if file_found and modified:
        score += 10
        feedback_parts.append("Exported parameters file found and modified during task (+10)")
    elif file_found:
        feedback_parts.append("Export file found but timestamps suggest it wasn't modified during task (+0)")
    else:
        feedback_parts.append("Export file not found at the requested path (+0)")

    # 3. FILE CONTENT CHECK (40 pts total)
    file_content = result.get('file_content', '')
    if isinstance(file_content, str):
        file_content = file_content.replace('\\n', '\n').replace('\\t', '\t')
        
    if file_found and modified:
        for param_name, target_val in TARGET_PARAMS.items():
            # Match standard Ardupilot/QGC param file format (usually TSV or space delimited)
            # Pattern looks for the param name followed by whitespace and a float/integer
            match = re.search(rf'{param_name}\s+([0-9\.\-]+)', file_content)
            
            if match:
                try:
                    file_val = float(match.group(1))
                    details[f'file_{param_name}'] = file_val
                    
                    if abs(file_val - target_val) <= 0.1:
                        score += 8
                        feedback_parts.append(f"File {param_name}={int(file_val)} ✓ (+8)")
                    else:
                        feedback_parts.append(f"File {param_name}={file_val} (need {int(target_val)}) (+0)")
                except ValueError:
                    feedback_parts.append(f"File {param_name} unparseable (+0)")
            else:
                feedback_parts.append(f"File missing {param_name} (+0)")
    else:
        feedback_parts.append("Skipping file content checks (no valid file exported)")

    # Evaluate passing threshold
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }