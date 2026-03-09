#!/usr/bin/env python3
"""Verifier for demographic_quota_sampling task.

A market research analyst must configure 4 demographic quotas (Young Male,
Young Female, Mid-Age Male, Mid-Age Female) each with a limit of 25 responses,
linked to the GENDER and AGE_RANGE questions.

Scoring (100 points):
- At least 4 quotas created (25 pts)
- Quota limits set to 25 (25 pts)
- Quotas linked to GENDER question (25 pts)
- Quotas linked to AGE_RANGE question (25 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_QUOTA_NAMES = ["young male", "young female", "mid-age male", "mid-age female",
                         "male 18-34", "female 18-34", "male 35-54", "female 35-54",
                         "male young", "female young", "male mid", "female mid"]


def verify_demographic_quota_sampling(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/quota_result.json", tmp.name)
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
        return {
            "passed": False,
            "score": 0,
            "feedback": "Consumer Electronics Preferences Study 2024 not found."
        }

    # Criterion 1: At least 4 quotas created (25 pts)
    quota_count = result.get("quota_count", 0)
    quota_names_raw = result.get("quota_names", "").lower()

    if quota_count >= 4:
        score += 25
        subscores["quota_count"] = True
        feedback_parts.append(f"4 quotas created (found {quota_count}) [25/25]")
    elif quota_count == 3:
        score += 15
        subscores["quota_count"] = "partial"
        feedback_parts.append(f"Only 3 quotas created (need 4 for all demographic segments) [15/25]")
    elif quota_count == 2:
        score += 10
        subscores["quota_count"] = "partial"
        feedback_parts.append(f"Only 2 quotas created (need 4) [10/25]")
    elif quota_count == 1:
        score += 5
        subscores["quota_count"] = "partial"
        feedback_parts.append(f"Only 1 quota created (need 4) [5/25]")
    else:
        subscores["quota_count"] = False
        feedback_parts.append("No quotas created [0/25]")

    # Criterion 2: Quota limits set to 25 (25 pts)
    quotas_with_25 = result.get("quotas_with_limit_25", 0)
    if quota_count > 0 and quotas_with_25 >= 4:
        score += 25
        subscores["quota_limits"] = True
        feedback_parts.append(f"All {quotas_with_25} quotas have limit=25 [25/25]")
    elif quota_count > 0 and quotas_with_25 >= 2:
        pts = int(25 * quotas_with_25 / max(quota_count, 4))
        score += pts
        subscores["quota_limits"] = "partial"
        feedback_parts.append(
            f"{quotas_with_25}/{quota_count} quotas have limit=25 [{pts}/25]"
        )
    elif quota_count > 0 and quotas_with_25 == 1:
        score += 5
        subscores["quota_limits"] = "partial"
        feedback_parts.append(f"Only 1 quota has limit=25 [5/25]")
    elif quota_count > 0:
        subscores["quota_limits"] = False
        feedback_parts.append(
            "Quotas exist but none have limit=25. Each segment must allow exactly 25 responses [0/25]"
        )
    else:
        subscores["quota_limits"] = False
        feedback_parts.append("No quotas to check limits [0/25]")

    # Criterion 3: Quotas linked to GENDER question (25 pts)
    gender_link_count = result.get("quotas_linked_to_gender_question", 0)
    gender_qid = result.get("gender_question_id", "")
    if gender_link_count >= 2:
        score += 25
        subscores["gender_link"] = True
        feedback_parts.append(
            f"{gender_link_count} quotas linked to GENDER question [25/25]"
        )
    elif gender_link_count == 1:
        score += 10
        subscores["gender_link"] = "partial"
        feedback_parts.append(
            f"Only 1 quota linked to GENDER question (need at least 2 for male/female split) [10/25]"
        )
    else:
        subscores["gender_link"] = False
        gender_qid_hint = f" (GENDER QID={gender_qid})" if gender_qid else ""
        feedback_parts.append(
            f"No quotas linked to GENDER question{gender_qid_hint}. "
            "Each quota must specify which answer option from GENDER applies [0/25]"
        )

    # Criterion 4: Quotas linked to AGE_RANGE question (25 pts)
    age_link_count = result.get("quotas_linked_to_age_question", 0)
    age_qid = result.get("age_question_id", "")
    if age_link_count >= 2:
        score += 25
        subscores["age_link"] = True
        feedback_parts.append(
            f"{age_link_count} quotas linked to AGE_RANGE question [25/25]"
        )
    elif age_link_count == 1:
        score += 10
        subscores["age_link"] = "partial"
        feedback_parts.append(
            f"Only 1 quota linked to AGE_RANGE question (need at least 2 for age-group split) [10/25]"
        )
    else:
        subscores["age_link"] = False
        age_qid_hint = f" (AGE_RANGE QID={age_qid})" if age_qid else ""
        feedback_parts.append(
            f"No quotas linked to AGE_RANGE question{age_qid_hint}. "
            "Quotas must specify which age-range answers apply [0/25]"
        )

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "survey_id": result.get("survey_id"),
            "quota_count": quota_count,
            "quotas_with_limit_25": quotas_with_25,
            "gender_link_count": gender_link_count,
            "age_link_count": age_link_count,
            "quota_names": result.get("quota_names", "")[:200],
        }
    }
