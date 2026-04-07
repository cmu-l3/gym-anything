#!/usr/bin/env python3
"""
Verifier for himalayan_rotorcraft_rescue_pressure task.

Validates whether the agent identified the correct dataset (Surface Pressure vs SLP),
navigated to the correct region/time, and extracted a geophysically accurate value.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_himalayan_rotorcraft_rescue_pressure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_dataset = metadata.get('dataset_used', 'pres.mon.ltm.nc')
    expected_month = metadata.get('target_month', 'May')
    min_pa = metadata.get('pressure_min_pa', 45000)
    max_pa = metadata.get('pressure_max_pa', 65000)

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/himalayan_rotorcraft_rescue_pressure_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Map Artifact Created (20 pts)
    # ----------------------------------------------------------------
    map_exists = result.get('map_exists', False)
    map_mtime = int(result.get('map_mtime', 0))
    map_size = int(result.get('map_size', 0))

    if map_exists and map_mtime >= task_start and map_size >= 15000:
        score += 20
        feedback.append(f"Map artifact exported ({map_size} bytes)")
    elif map_exists and map_mtime >= task_start:
        score += 10
        feedback.append(f"Map artifact present but small ({map_size} bytes, expected >=15KB)")
    else:
        feedback.append("Map artifact missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 2: Report Formatted Correctly (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    target_month_raw = result.get('target_month', '').strip()
    dataset_used_raw = result.get('dataset_used', '').strip()
    himalayan_pressure_raw = result.get('himalayan_pressure', '').strip()
    sea_level_diff_raw = result.get('sea_level_diff', '').strip()

    has_all_keys = bool(target_month_raw) and bool(dataset_used_raw) and bool(himalayan_pressure_raw) and bool(sea_level_diff_raw)

    if report_exists and report_mtime >= task_start and has_all_keys:
        score += 20
        feedback.append("Report formatted correctly with all keys")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("Report present but missing some required keys")
    else:
        feedback.append("Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 3: Correct Target Month (10 pts)
    # ----------------------------------------------------------------
    if expected_month.lower() in target_month_raw.lower():
        score += 10
        feedback.append("Correct target month (May)")
    else:
        feedback.append(f"Incorrect or missing target month: '{target_month_raw}'")

    # ----------------------------------------------------------------
    # Criterion 4: Correct Dataset Identified (20 pts)
    # ----------------------------------------------------------------
    if expected_dataset.lower() in dataset_used_raw.lower():
        score += 20
        feedback.append(f"Correct dataset identified ({expected_dataset})")
    elif "slp" in dataset_used_raw.lower():
        feedback.append("CRITICAL ERROR: Identified Sea Level Pressure (SLP) instead of Surface Pressure")
    else:
        feedback.append(f"Incorrect dataset identified: '{dataset_used_raw}'")

    # ----------------------------------------------------------------
    # Criterion 5: Physics Validation - Pressure Range (30 pts)
    # ----------------------------------------------------------------
    val_str = himalayan_pressure_raw.lower()
    physics_passed = False
    extracted_val = None
    
    # Extract numbers including decimals
    nums = re.findall(r"[-+]?\d*\.\d+|\d+", val_str)
    if nums:
        extracted_val = float(nums[0])
        # Handle if agent converted to hPa/mb or if they just reported raw hPa
        # Surface pressure in Himalayas is ~500-600 hPa (50000-60000 Pa)
        if 'hpa' in val_str or 'mb' in val_str or 'millibar' in val_str:
            extracted_val *= 100  # Convert to Pa
        elif 400 <= extracted_val <= 700:
            # If they just wrote "550" without units, it's clearly hPa since 550 Pa is a vacuum.
            extracted_val *= 100

        if min_pa <= extracted_val <= max_pa:
            score += 30
            physics_passed = True
            feedback.append(f"Physics validation passed: Pressure {extracted_val:.0f} Pa is correct for altitude")
        elif 95000 <= extracted_val <= 105000:
            feedback.append(f"Physics validation FAILED: {extracted_val:.0f} Pa is Sea Level Pressure, not ambient!")
        else:
            feedback.append(f"Physics validation FAILED: {extracted_val:.0f} Pa is not plausible for this coordinate")
    else:
        feedback.append("Physics validation FAILED: Could not parse numeric pressure from report")

    # Final evaluation
    # To pass, they MUST have the correct physics value (meaning they avoided the SLP trap and checked the array)
    passed = score >= 70 and physics_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "reported_dataset": dataset_used_raw,
            "reported_pressure": himalayan_pressure_raw,
            "parsed_pressure_pa": extracted_val,
            "physics_passed": physics_passed
        }
    }