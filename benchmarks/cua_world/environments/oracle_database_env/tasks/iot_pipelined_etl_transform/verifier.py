#!/usr/bin/env python3
import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_iot_etl(traj, env_info, task_info):
    """
    Verifies the IoT Pipelined ETL task.
    Checks:
    1. PL/SQL Objects existence and validity.
    2. Correct temperature conversion logic (F -> C).
    3. Correct flag logic (Battery < 20).
    4. Error handling (bad rows logged, valid rows processed).
    5. Output file generation.
    """
    
    # 1. Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    local_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
        os.remove(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}

    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database error during verification: {result['db_error']}"}

    score = 0
    feedback = []

    # 2. Structural Checks (30 pts)
    if result.get("objects_exist"):
        score += 10
        feedback.append("Objects (Type/Package) exist.")
    else:
        feedback.append("Missing required schema objects.")

    if result.get("package_valid"):
        score += 10
        feedback.append("Package compiles successfully.")
    else:
        feedback.append("Package is invalid/does not compile.")

    if result.get("function_pipelined"):
        score += 10
        feedback.append("Function is defined as PIPELINED.")
    else:
        feedback.append("Function is NOT pipelined.")

    # 3. Logic Checks (40 pts)
    test_valid = result.get("test_valid_row", {})
    if test_valid.get("success"):
        # Temp Check (212 F -> 100 C)
        temp = test_valid.get("temp_c")
        if temp is not None and 99.9 <= float(temp) <= 100.1:
            score += 15
            feedback.append("Temperature conversion correct.")
        else:
            feedback.append(f"Temperature conversion incorrect. Expected ~100, got {temp}.")

        # Battery Check (10 -> Y)
        batt = test_valid.get("low_batt")
        if batt == 'Y':
            score += 10
            feedback.append("Low battery flag logic correct.")
        else:
            feedback.append(f"Low battery flag incorrect. Expected 'Y', got '{batt}'.")
    else:
        feedback.append("Functional test failed (execution error).")

    # Error Handling (15 pts)
    test_error = result.get("test_error_row", {})
    if test_error.get("success"):
        score += 10
        feedback.append("Bad row handled gracefully (skipped).")
        if test_error.get("error_logged"):
            score += 5
            feedback.append("Bad row error logged to table.")
    else:
        feedback.append("Error handling test failed (crashed or didn't log).")

    # 4. File Output (15 pts)
    if result.get("file_exists"):
        score += 5
        feedback.append("Output CSV exists.")
        row_count = result.get("file_row_count", 0)
        # We expect ~480 rows from 500 total - ~20 errors
        if 450 <= row_count <= 500:
            score += 10
            feedback.append(f"Output row count ({row_count}) is reasonable.")
        else:
            feedback.append(f"Output row count ({row_count}) is suspicious (expected ~480).")
    else:
        feedback.append("Output CSV not found on Desktop.")

    # Final Score
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }