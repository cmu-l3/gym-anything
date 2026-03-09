#!/usr/bin/env python3
"""Verifier for submit_response task in LimeSurvey environment."""

import json
import tempfile
import os


def verify_submit_response(traj, env_info, task_info):
    """Verify that a survey response was submitted in LimeSurvey.

    Verification criteria (adversarial-resistant):
    1. Response count must have increased
    2. Response must have a valid submit date (not null)
    3. Age value must be present and equal to 35
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_age = metadata.get('expected_response_value', '35')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/submit_response_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get counts
    initial = result.get('initial_response_count', 0)
    current = result.get('current_response_count', 0)

    # Check 1: Response count must have increased
    if current <= initial:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No new response submitted. Response count unchanged: {initial} -> {current}"
        }

    # Check if response details are available
    if not result.get('response_submitted'):
        return {
            "passed": False,
            "score": 30,
            "feedback": f"Response count increased ({initial} -> {current}) but couldn't verify response details"
        }

    # Response was submitted - get details
    response = result.get('response', {})
    response_id = response.get('response_id', '')
    submit_date = response.get('submit_date', '')
    age_value = response.get('age_value', '')

    score = 30  # Base score for response count increase
    issues = []

    # Check 2: Response must have a valid submit date
    if submit_date and submit_date != 'NULL' and submit_date != '':
        score += 20
    else:
        issues.append("Response has no valid submit date")

    # Check 3: Age value must be present and correct
    if age_value:
        try:
            age_float = float(age_value)
            expected_float = float(expected_age)
            if abs(age_float - expected_float) < 0.01:
                score += 50
            else:
                score += 20  # Partial credit for having an age value
                issues.append(f"Age value mismatch: expected {expected_age}, got {age_value}")
        except (ValueError, TypeError):
            issues.append(f"Age value not a valid number: '{age_value}'")
    else:
        issues.append("Age value not found in response")

    # Determine pass/fail
    if score >= 100:
        return {
            "passed": True,
            "score": 100,
            "feedback": f"Response submitted correctly! ID: {response_id}, Age: {age_value}, Submitted: {submit_date}"
        }
    elif score >= 70:
        return {
            "passed": True,
            "score": score,
            "feedback": f"Response submitted with minor issues. ID: {response_id}. Issues: {'; '.join(issues)}"
        }
    elif score >= 50:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Response submitted but doesn't meet all criteria. Issues: {'; '.join(issues)}"
        }
    else:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Response verification failed. Issues: {'; '.join(issues)}"
        }
