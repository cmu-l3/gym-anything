#!/usr/bin/env python3
"""Verifier for Configure Completion and Badge task in Moodle.

Scoring breakdown (100 points total):
  Criterion 1 – Lab Safety page view completion      : 15 pts
  Criterion 2 – Cell Membrane Transport Lab submit   : 15 pts
  Criterion 3 – Molecular Biology Quiz pass-grade    : 15 pts
  Criterion 4 – Research Discussion Forum post       : 15 pts
  Criterion 5 – Final Research Report submit         : 10 pts
  Criterion 6 – Course completion criteria set       : 15 pts
  Criterion 7 – Badge with completion criteria       : 10 pts
  Criterion 8 – Badge expiry ~3 years                :  5 pts

Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 3 years expressed in seconds. Julian year = 365.25 days.
# 3 * 365.25 * 24 * 3600 = 94_608_000 s.  Allow ±10 % tolerance.
THREE_YEARS_SECONDS = 94_608_000
THREE_YEARS_TOLERANCE = 0.10  # 10 %
THREE_YEARS_MIN = int(THREE_YEARS_SECONDS * (1 - THREE_YEARS_TOLERANCE))  # ~85_147_200
THREE_YEARS_MAX = int(THREE_YEARS_SECONDS * (1 + THREE_YEARS_TOLERANCE))  # ~104_068_800


def _load_result(env_info: dict) -> dict:
    """Copy result JSON from the environment and parse it."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        raise RuntimeError("copy_from_env not available in env_info")

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    try:
        copy_from_env("/tmp/configure_completion_and_badge_result.json", tmp_path)
        with open(tmp_path, "r") as fh:
            return json.load(fh)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def verify_configure_completion_and_badge(traj, env_info, task_info):
    """
    Verify that BIO302 completion settings and badge were configured correctly.

    Returns a dict with keys: passed (bool), score (int 0-100), feedback (str),
    subscores (dict).
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available – cannot retrieve result file",
            "subscores": {},
        }

    try:
        result = _load_result(env_info)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found – export_result.sh may not have run",
            "subscores": {},
        }
    except json.JSONDecodeError as exc:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {exc}",
            "subscores": {},
        }
    except Exception as exc:
        logger.error("Failed to load result: %s", exc, exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error loading result file: {exc}",
            "subscores": {},
        }

    logger.info("Result data: %s", result)

    score = 0
    feedback_parts: list[str] = []
    subscores: dict[str, bool | int] = {}

    # ------------------------------------------------------------------
    # Helper: safely read int from result, defaulting to 0.
    # ------------------------------------------------------------------
    def _int(key: str) -> int:
        try:
            return int(result.get(key, 0) or 0)
        except (ValueError, TypeError):
            return 0

    def _bool(key: str) -> bool:
        val = result.get(key, False)
        if isinstance(val, bool):
            return val
        if isinstance(val, str):
            return val.lower() == "true"
        return bool(val)

    # ------------------------------------------------------------------
    # Criterion 1 (15 pts): Lab Safety and Ethics Module – view completion.
    # Requires: completion=2 (automatic) AND completionview=1.
    # ------------------------------------------------------------------
    page_completion = _int("page_completion")
    page_view_tracked = _bool("page_view_tracked")
    page_completionview = _int("page_completionview")

    if page_completion == 2 and (page_view_tracked or page_completionview == 1):
        score += 15
        subscores["page_view_completion"] = True
        feedback_parts.append("Lab Safety page: view completion configured correctly")
    elif page_completion == 2:
        # Automatic completion set but view flag unclear – award partial
        score += 7
        subscores["page_view_completion"] = False
        feedback_parts.append(
            "Lab Safety page: automatic completion set but 'require view' not confirmed "
            f"(completionview={page_completionview})"
        )
    else:
        subscores["page_view_completion"] = False
        feedback_parts.append(
            f"Lab Safety page: completion NOT configured (completion={page_completion})"
        )

    # ------------------------------------------------------------------
    # Criterion 2 (15 pts): Cell Membrane Transport Lab – submit completion.
    # Requires: completion=2 AND (completionsubmit=1 OR completionusegrade=1).
    # ------------------------------------------------------------------
    lab_completion = _int("lab_completion")
    lab_submit_tracked = _bool("lab_submit_tracked")
    lab_completionsubmit = _int("lab_completionsubmit")
    lab_completionusegrade = _int("lab_completionusegrade")

    if lab_completion == 2 and (
        lab_submit_tracked
        or lab_completionsubmit == 1
        or lab_completionusegrade == 1
    ):
        score += 15
        subscores["lab_submit_completion"] = True
        feedback_parts.append("Cell Membrane Transport Lab: submit completion configured correctly")
    elif lab_completion == 2:
        # Completion is automatic but no submit/grade condition found – partial
        score += 7
        subscores["lab_submit_completion"] = False
        feedback_parts.append(
            "Cell Membrane Transport Lab: automatic completion set but submit/grade condition "
            f"not confirmed (submit={lab_completionsubmit}, usegrade={lab_completionusegrade})"
        )
    else:
        subscores["lab_submit_completion"] = False
        feedback_parts.append(
            f"Cell Membrane Transport Lab: completion NOT configured (completion={lab_completion})"
        )

    # ------------------------------------------------------------------
    # Criterion 3 (15 pts): Molecular Biology Quiz – pass-grade completion.
    # Requires: completion=2 AND completionusegrade=1 AND completionpassgrade=1.
    # Partial: completion=2 AND completionusegrade=1 (grade required but pass not set).
    # ------------------------------------------------------------------
    quiz_completion = _int("quiz_completion")
    quiz_grade_tracked = _bool("quiz_grade_tracked")
    quiz_pass_required = _bool("quiz_pass_required")
    quiz_completionusegrade = _int("quiz_completionusegrade")
    quiz_completionpassgrade = _int("quiz_completionpassgrade")

    if quiz_completion == 2 and quiz_completionusegrade == 1 and quiz_completionpassgrade == 1:
        score += 15
        subscores["quiz_pass_completion"] = True
        feedback_parts.append("Molecular Biology Quiz: pass-grade completion configured correctly")
    elif quiz_completion == 2 and quiz_completionusegrade == 1:
        # Grade required but passing threshold not enforced
        score += 8
        subscores["quiz_pass_completion"] = False
        feedback_parts.append(
            "Molecular Biology Quiz: grade-based completion set but 'passing grade' condition "
            "not enabled (completionpassgrade=0)"
        )
    elif quiz_completion == 2:
        score += 4
        subscores["quiz_pass_completion"] = False
        feedback_parts.append(
            f"Molecular Biology Quiz: automatic completion set but grade conditions missing "
            f"(usegrade={quiz_completionusegrade}, passgrade={quiz_completionpassgrade})"
        )
    else:
        subscores["quiz_pass_completion"] = False
        feedback_parts.append(
            f"Molecular Biology Quiz: completion NOT configured (completion={quiz_completion})"
        )

    # ------------------------------------------------------------------
    # Criterion 4 (15 pts): Research Discussion Forum – post completion.
    # Requires: completion=2 AND (completionposts>=1 OR completiondiscussions>=1
    #           OR completionreplies>=1).
    # ------------------------------------------------------------------
    forum_completion = _int("forum_completion")
    forum_post_tracked = _bool("forum_post_tracked")
    forum_completionposts = _int("forum_completionposts")
    forum_completiondiscussions = _int("forum_completiondiscussions")
    forum_completionreplies = _int("forum_completionreplies")

    forum_any_post_condition = (
        forum_completionposts >= 1
        or forum_completiondiscussions >= 1
        or forum_completionreplies >= 1
    )

    if forum_completion == 2 and (forum_post_tracked or forum_any_post_condition):
        score += 15
        subscores["forum_post_completion"] = True
        feedback_parts.append("Research Discussion Forum: post completion configured correctly")
    elif forum_completion == 2:
        score += 7
        subscores["forum_post_completion"] = False
        feedback_parts.append(
            "Research Discussion Forum: automatic completion set but no post count condition "
            f"found (posts={forum_completionposts}, discussions={forum_completiondiscussions}, "
            f"replies={forum_completionreplies})"
        )
    else:
        subscores["forum_post_completion"] = False
        feedback_parts.append(
            f"Research Discussion Forum: completion NOT configured (completion={forum_completion})"
        )

    # ------------------------------------------------------------------
    # Criterion 5 (10 pts): Final Research Report – submit completion.
    # Same logic as lab assignment.
    # ------------------------------------------------------------------
    final_completion = _int("final_completion")
    final_submit_tracked = _bool("final_submit_tracked")
    final_completionsubmit = _int("final_completionsubmit")
    final_completionusegrade = _int("final_completionusegrade")

    if final_completion == 2 and (
        final_submit_tracked
        or final_completionsubmit == 1
        or final_completionusegrade == 1
    ):
        score += 10
        subscores["final_submit_completion"] = True
        feedback_parts.append("Final Research Report: submit completion configured correctly")
    elif final_completion == 2:
        score += 5
        subscores["final_submit_completion"] = False
        feedback_parts.append(
            "Final Research Report: automatic completion set but submit/grade condition "
            f"not confirmed (submit={final_completionsubmit}, usegrade={final_completionusegrade})"
        )
    else:
        subscores["final_submit_completion"] = False
        feedback_parts.append(
            f"Final Research Report: completion NOT configured (completion={final_completion})"
        )

    # ------------------------------------------------------------------
    # Criterion 6 (15 pts): Course completion criteria configured.
    # At least 1 criterion in mdl_course_completion_criteria for BIO302.
    # Full credit for >=5 (all activities); partial for >=1.
    # ------------------------------------------------------------------
    criteria_count = _int("course_completion_criteria_count")

    if criteria_count >= 5:
        score += 15
        subscores["course_completion_criteria"] = True
        feedback_parts.append(
            f"Course completion criteria: {criteria_count} criteria configured (all 5 activities)"
        )
    elif criteria_count >= 1:
        partial = max(5, int(15 * criteria_count / 5))
        score += partial
        subscores["course_completion_criteria"] = False
        feedback_parts.append(
            f"Course completion criteria: {criteria_count} criterion/criteria set "
            f"(expected 5, awarded {partial}/15 partial pts)"
        )
    else:
        subscores["course_completion_criteria"] = False
        feedback_parts.append("Course completion criteria: NOT configured (0 criteria found)")

    # ------------------------------------------------------------------
    # Criterion 7 (10 pts): Badge "Advanced Cell Biology Scholar" created
    # with course completion criterion (criteriatype=8).
    # ------------------------------------------------------------------
    badge_found = _bool("badge_found")
    badge_name = result.get("badge_name", "") or ""
    badge_has_completion_criteria = _bool("badge_has_completion_criteria")

    expected_badge_name = "Advanced Cell Biology Scholar"
    badge_name_match = badge_name.strip().lower() == expected_badge_name.strip().lower()

    if badge_found and badge_name_match and badge_has_completion_criteria:
        score += 10
        subscores["badge_with_completion_criteria"] = True
        feedback_parts.append(
            f"Badge '{badge_name}' created with course completion criterion"
        )
    elif badge_found and badge_has_completion_criteria:
        # Badge exists with criterion but wrong name
        score += 5
        subscores["badge_with_completion_criteria"] = False
        feedback_parts.append(
            f"Badge found with completion criterion but name mismatch: "
            f"got '{badge_name}', expected '{expected_badge_name}'"
        )
    elif badge_found and badge_name_match:
        # Correct name but no completion criterion
        score += 5
        subscores["badge_with_completion_criteria"] = False
        feedback_parts.append(
            f"Badge '{badge_name}' found but course completion criterion NOT set "
            "(criteriatype=8 not found in mdl_badge_criteria)"
        )
    elif badge_found:
        score += 3
        subscores["badge_with_completion_criteria"] = False
        feedback_parts.append(
            f"Badge found (name='{badge_name}') but name wrong and no completion criterion"
        )
    else:
        subscores["badge_with_completion_criteria"] = False
        feedback_parts.append("Badge 'Advanced Cell Biology Scholar' NOT found in BIO302")

    # ------------------------------------------------------------------
    # Criterion 8 (5 pts): Badge expiry set to ~3 years (relative, after issue).
    # expiretype=2 (relative) and expireperiod in [THREE_YEARS_MIN, THREE_YEARS_MAX].
    # Also accept expiretype=2 with any positive expireperiod as partial (2 pts).
    # ------------------------------------------------------------------
    badge_expiry_type = _int("badge_expiry_type")
    badge_expiry_period = _int("badge_expiry_period")

    if badge_found:
        if (
            badge_expiry_type == 2
            and THREE_YEARS_MIN <= badge_expiry_period <= THREE_YEARS_MAX
        ):
            score += 5
            subscores["badge_expiry_3_years"] = True
            feedback_parts.append(
                f"Badge expiry: {badge_expiry_period}s (~3 years relative) – correct"
            )
        elif badge_expiry_type == 2 and badge_expiry_period > 0:
            # Relative expiry set but period not ~3 years
            score += 2
            subscores["badge_expiry_3_years"] = False
            feedback_parts.append(
                f"Badge expiry: relative expiry set ({badge_expiry_period}s) "
                f"but not within 10% of 3 years ({THREE_YEARS_SECONDS}s)"
            )
        elif badge_expiry_type == 1 and badge_expiry_period > 0:
            # Fixed-date expiry – not what was asked but shows intent
            score += 1
            subscores["badge_expiry_3_years"] = False
            feedback_parts.append(
                "Badge expiry: fixed-date expiry set (expected relative 3-year expiry)"
            )
        else:
            subscores["badge_expiry_3_years"] = False
            feedback_parts.append(
                f"Badge expiry: NOT set correctly (expiretype={badge_expiry_type}, "
                f"expireperiod={badge_expiry_period})"
            )
    else:
        subscores["badge_expiry_3_years"] = False
        feedback_parts.append("Badge expiry: cannot check – badge not found")

    # ------------------------------------------------------------------
    # Final pass/fail decision
    # ------------------------------------------------------------------
    passed = score >= 60

    logger.info(
        "Score=%d passed=%s subscores=%s",
        score, passed, subscores
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
