#!/usr/bin/env python3
"""Verifier for phq9_clinical_survey task.

A clinical researcher must build a complete PHQ-9 survey in LimeSurvey with
3 question groups, an Array question with 9 sub-questions, mandatory setting,
anonymized responses, and activate the survey.

Scoring (100 points):
- Survey exists with PHQ-9 related title (gate: 0 if missing): gate
- 3 question groups created (25 pts)
- Array question with >= 9 sub-questions (25 pts)
- Survey anonymized = Y (25 pts)
- Survey active = Y (25 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_phq9_clinical_survey(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/phq9_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: Survey must exist
    if not result.get("survey_found", False):
        initial = result.get("initial_survey_count", 0)
        current = result.get("current_survey_count", 0)
        if current <= initial:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new survey was created. Survey count unchanged."
            }
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "A new survey was created but no PHQ-9/mental health screening survey "
                "was found. Ensure the title contains 'PHQ-9' or 'Mental Health Screening'."
            )
        }

    # Criterion 1: 3 question groups (25 pts)
    group_count = result.get("group_count", 0)
    if group_count >= 3:
        score += 25
        subscores["groups"] = True
        feedback_parts.append(f"3 question groups created ({group_count} found) [25/25]")
    elif group_count == 2:
        score += 10
        subscores["groups"] = "partial"
        feedback_parts.append(f"Only 2 question groups (expected 3) [10/25]")
    else:
        subscores["groups"] = False
        feedback_parts.append(f"Insufficient question groups: {group_count} (expected 3) [0/25]")

    # Criterion 2: Array question with >= 9 sub-questions (25 pts)
    array_count = result.get("array_question_count", 0)
    sub_count = result.get("array_subquestion_count", 0)
    if array_count >= 1 and sub_count >= 9:
        score += 25
        subscores["array_with_subquestions"] = True
        feedback_parts.append(
            f"Array question with {sub_count} sub-questions (PHQ-9 items) [25/25]"
        )
    elif array_count >= 1 and sub_count >= 5:
        score += 12
        subscores["array_with_subquestions"] = "partial"
        feedback_parts.append(
            f"Array question found but only {sub_count} sub-questions (need >= 9 for PHQ-9) [12/25]"
        )
    elif array_count >= 1:
        score += 5
        subscores["array_with_subquestions"] = "partial"
        feedback_parts.append(
            f"Array question found but only {sub_count} sub-questions (need >= 9) [5/25]"
        )
    else:
        subscores["array_with_subquestions"] = False
        feedback_parts.append("No Array question found — PHQ-9 items must use Array question type [0/25]")

    # Criterion 3: Anonymized responses (25 pts)
    anonymized = result.get("survey_anonymized", "N")
    if str(anonymized).strip().upper() == "Y":
        score += 25
        subscores["anonymized"] = True
        feedback_parts.append("Response anonymization enabled (IRB requirement) [25/25]")
    else:
        subscores["anonymized"] = False
        feedback_parts.append(
            "Survey anonymization NOT enabled. IRB requires anonymized data collection [0/25]"
        )

    # Criterion 4: Survey activated (25 pts)
    active = result.get("survey_active", "N")
    if str(active).strip().upper() == "Y":
        score += 25
        subscores["active"] = True
        feedback_parts.append("Survey activated and ready for data collection [25/25]")
    else:
        subscores["active"] = False
        feedback_parts.append("Survey NOT activated — must be activated to collect data [0/25]")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "survey_id": result.get("survey_id"),
            "survey_title": result.get("survey_title"),
            "group_count": result.get("group_count"),
            "array_subquestion_count": result.get("array_subquestion_count"),
            "anonymized": result.get("survey_anonymized"),
            "active": result.get("survey_active"),
        }
    }
