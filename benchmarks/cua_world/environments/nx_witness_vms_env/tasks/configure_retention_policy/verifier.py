#!/usr/bin/env python3
"""
Verifier for configure_retention_policy task.

Verification Logic:
1. API Verification (75 pts): Check if actual camera retention settings match requirements.
2. Report Verification (20 pts): Check if user generated report matches API state/requirements.
3. Anti-Gaming (5 pts): Ensure settings were actually changed from initial state.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retention_policy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_retention = metadata.get('expected_retention', {})
    
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    api_devices = result.get('api_devices', [])
    initial_state = result.get('initial_state', {})
    report_content = result.get('report_content')
    report_exists = result.get('report_exists', False)
    task_start = result.get('task_start', 0)
    report_mtime = result.get('report_mtime', 0)

    score = 0
    feedback_parts = []
    
    # Map API devices by name for easy lookup
    # Normalize names to handle potential minor spacing issues
    device_map = {d.get('name', '').strip(): d for d in api_devices}

    # =========================================================
    # 1. API Verification (15 pts per camera = 75 pts)
    # =========================================================
    cameras_correct = 0
    tolerance = 0.01 # 1% tolerance for float comparisons (though API usually returns int)

    for name, requirements in expected_retention.items():
        device = device_map.get(name)
        if not device:
            feedback_parts.append(f"Camera '{name}' not found in system")
            continue

        actual_min = device.get('minArchivePeriodS', -1)
        actual_max = device.get('maxArchivePeriodS', -1)
        
        expected_min = requirements['min']
        expected_max = requirements['max']

        # Check values
        min_ok = abs(actual_min - expected_min) <= (expected_min * tolerance)
        max_ok = abs(actual_max - expected_max) <= (expected_max * tolerance)

        if min_ok and max_ok:
            score += 15
            cameras_correct += 1
        else:
            feedback_parts.append(f"{name}: Expected min={expected_min}/max={expected_max}, got min={actual_min}/max={actual_max}")

    feedback_parts.append(f"API State: {cameras_correct}/5 cameras configured correctly")

    # =========================================================
    # 2. Report Verification (20 pts)
    # =========================================================
    report_score = 0
    if report_exists and isinstance(report_content, list) and len(report_content) >= 5:
        # Check if report was created during task
        if report_mtime > task_start:
            # Validate content matches API state
            valid_entries = 0
            for entry in report_content:
                entry_id = entry.get('id')
                entry_min = entry.get('minArchivePeriodS')
                entry_max = entry.get('maxArchivePeriodS')
                
                # Find corresponding device in API data
                # We need to find the device with this ID in the list
                matching_device = next((d for d in api_devices if d.get('id') == entry_id), None)
                
                if matching_device:
                    api_min = matching_device.get('minArchivePeriodS', -1)
                    api_max = matching_device.get('maxArchivePeriodS', -1)
                    
                    if entry_min == api_min and entry_max == api_max:
                        valid_entries += 1
            
            if valid_entries >= 5:
                report_score = 20
                feedback_parts.append("Report file valid and accurate")
            elif valid_entries > 0:
                report_score = 10
                feedback_parts.append(f"Report file exists but only {valid_entries} entries match system state")
            else:
                report_score = 5
                feedback_parts.append("Report file exists but content does not match system state")
        else:
            feedback_parts.append("Report file timestamp is before task start")
    else:
        feedback_parts.append("Report file missing or invalid format")

    score += report_score

    # =========================================================
    # 3. Anti-Gaming (5 pts)
    # =========================================================
    changes_detected = 0
    for name, device in device_map.items():
        dev_id = device.get('id')
        if dev_id in initial_state:
            init_data = initial_state[dev_id]
            if (device.get('minArchivePeriodS') != init_data.get('minArchivePeriodS') or 
                device.get('maxArchivePeriodS') != init_data.get('maxArchivePeriodS')):
                changes_detected += 1
    
    if changes_detected >= 3:
        score += 5
        feedback_parts.append("Anti-gaming: Changes verified")
    elif cameras_correct >= 3:
        # If 3 are correct but didn't change, they might have already been correct (unlikely given setup)
        # But we shouldn't penalize if the initial state happened to be correct (rare)
        # However, setup script doesn't force incorrect values, so this is just a sanity check.
        pass
    else:
        feedback_parts.append("Anti-gaming: No significant state changes detected")

    # =========================================================
    # Final Result
    # =========================================================
    # Pass threshold: 60 points (Requires at least 3 cameras correct + report OR 4 cameras correct)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }