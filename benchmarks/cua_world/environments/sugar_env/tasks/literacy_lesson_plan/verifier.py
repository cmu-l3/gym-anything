#!/usr/bin/env python3
"""Verifier for literacy_lesson_plan task.

Checks that the agent created a weekly literacy lesson plan document in Sugar Write
with required headings (Learning Objectives, Daily Schedule, Assessment), a Mon-Fri
table, saved as literacy_plan.odt and journaled as 'Literacy Plan Week 3'.
"""

import json
import os
import tempfile


def verify_literacy_lesson_plan(traj, env_info, task_info):
    """Verify the literacy lesson plan document was created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/literacy_lesson_plan_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: File exists and was created during task (15 pts)
    if result.get('file_exists'):
        if result.get('file_modified'):
            score += 15
            feedback.append("literacy_plan.odt saved")
        else:
            score += 5
            feedback.append("File exists but mtime check failed")
    else:
        feedback.append("FAIL: literacy_plan.odt not found in /home/ga/Documents/")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: File has meaningful content (5 pts)
    if result.get('file_size', 0) > 1000:
        score += 5
        feedback.append(f"File has content ({result['file_size']} bytes)")
    else:
        feedback.append(f"File very small ({result.get('file_size', 0)} bytes) — may be incomplete")

    # Criterion 3: Has 'Learning Objectives' heading (20 pts)
    if result.get('has_learning_obj'):
        score += 20
        feedback.append("'Learning Objectives' section found")
    else:
        feedback.append("Missing 'Learning Objectives' section")

    # Criterion 4: Has 'Daily Schedule' heading (20 pts)
    if result.get('has_daily_sched'):
        score += 20
        feedback.append("'Daily Schedule' section found")
    else:
        feedback.append("Missing 'Daily Schedule' section")

    # Criterion 5: Has 'Assessment' heading (15 pts)
    if result.get('has_assessment'):
        score += 15
        feedback.append("'Assessment' section found")
    else:
        feedback.append("Missing 'Assessment' section")

    # Criterion 6: Has a table (10 pts)
    if result.get('has_table'):
        score += 10
        feedback.append("Table element present")
    else:
        feedback.append("No table found (expected Mon-Fri schedule table)")

    # Criterion 7: Table contains day names (5 pts — partial check)
    if result.get('has_monday'):
        score += 5
        feedback.append("Monday column found in table")

    # Criterion 8: Sugar Journal entry with correct title (10 pts)
    if result.get('journal_title_found'):
        score += 10
        feedback.append("Journal entry 'Literacy Plan Week 3' found")
    else:
        feedback.append("Journal entry 'Literacy Plan Week 3' not found")

    # Pass: score >= 70 AND all 3 headings present AND file exists
    headings_found = sum([
        result.get('has_learning_obj', False),
        result.get('has_daily_sched', False),
        result.get('has_assessment', False)
    ])
    passed = score >= 70 and headings_found == 3 and result.get('file_exists', False)

    if passed:
        feedback.append("Lesson plan document complete!")
    else:
        reasons = []
        if headings_found < 2:
            reasons.append(f"only {headings_found}/3 required headings found")
        if score < 65:
            reasons.append(f"score {score} < 65")
        feedback.append(f"FAILED: {'; '.join(reasons)}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "file_exists": result.get('file_exists', False),
            "headings_found": headings_found,
            "has_table": result.get('has_table', False),
            "journal_found": result.get('journal_title_found', False)
        }
    }
