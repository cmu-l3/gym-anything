#!/usr/bin/env python3
"""Verifier for student_profile_config task.

Checks that:
1. Sugar profile nick was changed to 'AlexC'
2. Sugar XO icon color was changed from the default (#FF2B34,#005FE4)
3. Sugar Journal has an entry titled 'Student Setup Log'
"""

import json
import os
import tempfile


def verify_student_profile_config(traj, env_info, task_info):
    """Verify student profile was configured correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_nick = metadata.get('expected_nick', 'AlexC')
    expected_journal_title = metadata.get('expected_journal_title', 'Student Setup Log')
    initial_nick = metadata.get('initial_nick', 'Learner')
    initial_color = metadata.get('initial_color', '#FF2B34,#005FE4')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/student_profile_config_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Nickname changed to expected value (40 pts)
    nick = result.get('nick_value', '')
    if result.get('nick_correct'):
        score += 40
        feedback.append(f"Nickname set to '{expected_nick}'")
    elif nick and nick.lower() == expected_nick.lower():
        # Case-insensitive match — partial credit
        score += 20
        feedback.append(f"Nickname set to '{nick}' (case mismatch, expected '{expected_nick}')")
    elif nick and nick != initial_nick:
        score += 10
        feedback.append(f"Nickname changed to '{nick}' (expected '{expected_nick}')")
    else:
        feedback.append(f"Nickname unchanged: '{nick}' (expected '{expected_nick}')")

    # Criterion 2: XO icon color changed from default (35 pts)
    color = result.get('color_value', '')
    if result.get('color_changed'):
        score += 35
        feedback.append(f"XO color changed from default (new: {color})")
    elif color and color == initial_color:
        feedback.append(f"XO color unchanged (still default: {color})")
    else:
        feedback.append(f"XO color not verified (value: '{color}')")

    # Criterion 3: Journal entry 'Student Setup Log' (25 pts)
    if result.get('journal_found'):
        score += 25
        feedback.append("Journal entry 'Student Setup Log' found")
    else:
        feedback.append("Journal entry 'Student Setup Log' not found")

    # Pass: score >= 65 AND nick is correct AND color was changed
    passed = (score >= 65 and
              result.get('nick_correct', False) and
              result.get('color_changed', False))

    if passed:
        feedback.append("Student profile configured successfully!")
    else:
        reasons = []
        if not result.get('nick_correct'):
            reasons.append(f"nick is '{result.get('nick_value', '')}' (need '{expected_nick}')")
        if not result.get('color_changed'):
            reasons.append("XO color not changed from default")
        if score < 65:
            reasons.append(f"score {score} < 65")
        feedback.append(f"FAILED: {'; '.join(reasons)}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "nick_correct": result.get('nick_correct', False),
            "color_changed": result.get('color_changed', False),
            "journal_found": result.get('journal_found', False)
        }
    }
