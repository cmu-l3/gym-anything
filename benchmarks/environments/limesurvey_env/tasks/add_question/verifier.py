#!/usr/bin/env python3
"""Verifier for add_question task in LimeSurvey environment."""

import json
import tempfile
import os


def verify_add_question(traj, env_info, task_info):
    """Verify that a new question was added to a survey in LimeSurvey.

    Verification criteria (adversarial-resistant):
    1. Question count must have increased
    2. Question code must be exactly "QAGE" (case-insensitive)
    3. Question text must contain "what is your age" (case-insensitive)
    4. Question type must be "N" (Numerical input)
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_code = metadata.get('expected_question_code', 'QAGE')
    expected_text = metadata.get('expected_question_text', 'What is your age?')
    expected_type = metadata.get('expected_question_type', 'N')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_question_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get counts
    initial = result.get('initial_question_count', 0)
    current = result.get('current_question_count', 0)

    # Check 1: Question count must have increased
    if current <= initial:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No new question added. Question count unchanged: {initial} -> {current}"
        }

    # Check if question was found
    if not result.get('question_found'):
        return {
            "passed": False,
            "score": 20,
            "feedback": f"A question was added (count: {initial} -> {current}) but couldn't find question with expected criteria"
        }

    # Question was found - get details
    question = result.get('question', {})
    question_code = question.get('code', '').strip()
    question_text = question.get('text', '').strip()
    question_type = question.get('type', '').strip()
    question_id = question.get('question_id', '')

    score = 20  # Base score for finding a question
    issues = []

    # Check 2: Code must be exactly "QAGE" (case-insensitive)
    if question_code.upper() == expected_code.upper():
        score += 30
    else:
        issues.append(f"Code mismatch: expected '{expected_code}', got '{question_code}'")

    # Check 3: Question text must match (case-insensitive, allowing minor variations)
    if expected_text.lower() in question_text.lower() or question_text.lower() in expected_text.lower():
        score += 30
    elif 'age' in question_text.lower() and '?' in question_text:
        score += 15  # Partial credit for age-related question
        issues.append(f"Text partial match: expected '{expected_text}', got '{question_text}'")
    else:
        issues.append(f"Text mismatch: expected '{expected_text}', got '{question_text}'")

    # Check 4: Question type must be Numerical (N)
    if question_type.upper() == expected_type.upper():
        score += 20
    else:
        issues.append(f"Type mismatch: expected '{expected_type}' (Numerical), got '{question_type}'")

    # Determine pass/fail
    if score >= 100:
        return {
            "passed": True,
            "score": 100,
            "feedback": f"Question added correctly! ID: {question_id}, Code: '{question_code}', Type: '{question_type}', Text: '{question_text}'"
        }
    elif score >= 70:
        return {
            "passed": True,
            "score": score,
            "feedback": f"Question added with minor issues. ID: {question_id}. Issues: {'; '.join(issues)}"
        }
    else:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Question found but doesn't meet criteria. Issues: {'; '.join(issues)}"
        }
