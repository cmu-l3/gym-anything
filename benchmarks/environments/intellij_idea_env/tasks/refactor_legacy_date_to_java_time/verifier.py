#!/usr/bin/env python3
"""Verifier for refactor_legacy_date_to_java_time task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_legacy_date_to_java_time(traj, env_info, task_info):
    """Verify that the project was correctly refactored to use java.time.
    
    Criteria:
    1. Flight.java uses LocalDateTime and removed Date (20 pts)
    2. FlightScheduler.java uses LocalDateTime/Duration logic (20 pts)
    3. FlightSchedulerTest.java was updated to compile with new types (20 pts)
    4. Project compiles and tests pass (40 pts)
    5. VLM: Visual confirmation of refactoring work (Bonus/Validation)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract contents
    flight_content = result.get('flight_content', '')
    scheduler_content = result.get('scheduler_content', '')
    test_content = result.get('test_content', '')
    test_result = result.get('test_result', 'unknown')
    flight_modified = result.get('flight_modified', False)
    
    if not flight_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Files were not modified. No work detected."
        }

    # --- Criterion 1: Flight.java Refactoring (20 pts) ---
    has_ldt_import = 'java.time.LocalDateTime' in flight_content
    has_date_import = 'java.util.Date' in flight_content
    has_ldt_field = 'private LocalDateTime departureTime' in flight_content or 'private LocalDateTime arrivalTime' in flight_content
    
    if has_ldt_import and not has_date_import and has_ldt_field:
        score += 20
        feedback_parts.append("Flight.java fully refactored to LocalDateTime")
    elif has_ldt_import and has_date_import:
        score += 10
        feedback_parts.append("Flight.java uses LocalDateTime but still imports Date")
    elif has_ldt_import:
        score += 10
        feedback_parts.append("Flight.java imports LocalDateTime but fields might be wrong")
    else:
        feedback_parts.append("Flight.java not refactored correctly")

    # --- Criterion 2: FlightScheduler.java Logic (20 pts) ---
    # Check for removal of Calendar and usage of plusMinutes/plusHours
    has_calendar = 'java.util.Calendar' in scheduler_content
    has_plus_minutes = 'plusMinutes' in scheduler_content
    has_plus_hours = 'plusHours' in scheduler_content
    has_duration = 'java.time.Duration' in scheduler_content
    
    if not has_calendar and (has_plus_minutes or has_plus_hours or has_duration):
        score += 20
        feedback_parts.append("FlightScheduler.java logic refactored (Calendar removed)")
    elif has_calendar and (has_plus_minutes or has_plus_hours):
        score += 10
        feedback_parts.append("FlightScheduler.java logic updated but Calendar still present")
    elif not has_calendar:
        # Maybe they used a different approach, check if it compiles later
        score += 10
        feedback_parts.append("Calendar removed from FlightScheduler.java")
    else:
        feedback_parts.append("FlightScheduler.java still uses legacy Calendar logic")

    # --- Criterion 3: Test Updates (20 pts) ---
    # The tests must be updated to use LocalDateTime objects
    has_ldt_test = 'LocalDateTime.of' in test_content or 'LocalDateTime.parse' in test_content
    has_calendar_test = 'GregorianCalendar' in test_content
    
    if has_ldt_test and not has_calendar_test:
        score += 20
        feedback_parts.append("Tests updated to use LocalDateTime")
    elif has_ldt_test:
        score += 15
        feedback_parts.append("Tests use LocalDateTime but still contain GregorianCalendar")
    else:
        feedback_parts.append("Tests do not appear to be updated for LocalDateTime")

    # --- Criterion 4: Build & Test Pass (40 pts) ---
    tests_run = result.get('tests_run', 0)
    tests_passed = result.get('tests_passed', 0)
    
    if test_result == 'pass' and tests_run >= 2 and tests_passed == tests_run:
        score += 40
        feedback_parts.append(f"All {tests_run} tests passed successfully")
    elif test_result == 'fail':
        # Partial credit if some tests passed
        if tests_passed > 0:
            points = int(20 * (tests_passed / tests_run))
            score += points
            feedback_parts.append(f"Tests failed: {tests_passed}/{tests_run} passed")
        else:
            feedback_parts.append("Build/Tests failed")
    else:
        feedback_parts.append("Test execution failed or no tests run")

    # --- VLM Verification (Bonus/Confirmation) ---
    # We use this to verify the trajectory shows editing, not just file replacement via shell
    try:
        from gym_anything.vlm import sample_trajectory_frames
        # This is a placeholder for actual VLM logic if available in the environment
        # Real verification relies primarily on the code state (Criteria 1-4)
        pass 
    except ImportError:
        pass

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }