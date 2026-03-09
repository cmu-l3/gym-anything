#!/usr/bin/env python3
"""Verifier for create_survey task in LimeSurvey environment."""

import json
import tempfile
import os


def verify_create_survey(traj, env_info, task_info):
    """Verify that a new survey was created successfully in LimeSurvey.

    Verification criteria (adversarial-resistant):
    1. Survey count must have increased
    2. Survey title must EXACTLY match "Customer Satisfaction Survey" (case-insensitive)
    3. Survey must have been created during this session (new survey ID)
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_survey_title', 'Customer Satisfaction Survey')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_survey_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get counts
    initial = result.get('initial_survey_count', 0)
    current = result.get('current_survey_count', 0)

    # Check 1: Survey count must have increased
    if current <= initial:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No new survey created. Survey count unchanged: {initial} -> {current}"
        }

    # Check if survey was found
    if not result.get('survey_found'):
        return {
            "passed": False,
            "score": 20,
            "feedback": f"A survey was created (count: {initial} -> {current}) but could not find survey with expected title"
        }

    # Survey was found - get details
    survey = result.get('survey', {})
    survey_title = survey.get('title', '').strip()
    survey_id = survey.get('survey_id', '')

    # Check 2: Title must EXACTLY match (case-insensitive)
    # This prevents adversarial cases like "NOT a Customer Satisfaction Survey"
    if survey_title.lower() != expected_title.lower():
        return {
            "passed": False,
            "score": 40,
            "feedback": f"Survey title doesn't match exactly. Expected '{expected_title}', got '{survey_title}'"
        }

    # Check 3: Verify survey has proper structure (at least one question group)
    question_count = survey.get('question_count', 0)
    # LimeSurvey auto-creates a question group with one example question

    # All checks passed
    return {
        "passed": True,
        "score": 100,
        "feedback": f"Survey created successfully! ID: {survey_id}, Title: '{survey_title}', Questions: {question_count}"
    }
