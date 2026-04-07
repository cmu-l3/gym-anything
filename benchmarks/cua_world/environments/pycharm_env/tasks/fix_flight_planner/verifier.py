#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_flight_planner(traj, env_info, task_info):
    """
    Verify that the agent fixed all 4 logic bugs in the flight planner.
    
    Scoring (100 pts total):
    1. Distance Unit Fix (25 pts): geo.py calculates NM correctly.
    2. Bearing Quadrant Fix (25 pts): geo.py uses atan2.
    3. Wind Sign Fix (25 pts): wind.py correctly reduces speed for headwind.
    4. Fuel Reserve Fix (25 pts): fuel.py converts minutes to hours.
    
    Pass threshold: 75/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available",
        }

    # Retrieve result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env("/tmp/task_result.json", tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse task result: {e}",
        }

    score = 0
    feedback_parts = []
    
    # 1. Distance Fix
    if result.get("test_distance_pass", False) or result.get("geo_fixed_distance_code", False):
        score += 25
        feedback_parts.append("Distance Unit Fix: PASS (25/25)")
    else:
        feedback_parts.append("Distance Unit Fix: FAIL (0/25) - Check Earth radius unit (KM vs NM)")

    # 2. Bearing Fix
    if result.get("test_bearing_pass", False) or result.get("geo_fixed_bearing_code", False):
        score += 25
        feedback_parts.append("Bearing Quadrant Fix: PASS (25/25)")
    else:
        feedback_parts.append("Bearing Quadrant Fix: FAIL (0/25) - Check atan vs atan2")

    # 3. Wind Fix
    if result.get("test_wind_pass", False) or result.get("wind_fixed_code", False):
        score += 25
        feedback_parts.append("Wind Sign Fix: PASS (25/25)")
    else:
        feedback_parts.append("Wind Sign Fix: FAIL (0/25) - Check headwind math (should subtract)")

    # 4. Fuel Fix
    if result.get("test_fuel_pass", False) or result.get("fuel_fixed_code", False):
        score += 25
        feedback_parts.append("Fuel Reserve Fix: PASS (25/25)")
    else:
        feedback_parts.append("Fuel Reserve Fix: FAIL (0/25) - Check time units (minutes vs hours)")

    passed = score >= 75
    
    # Check overall tests
    if result.get("all_tests_pass", False):
        feedback_parts.append("All tests passed.")
    else:
        feedback_parts.append(f"Some tests failed ({result.get('tests_failed', 0)} failures).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }