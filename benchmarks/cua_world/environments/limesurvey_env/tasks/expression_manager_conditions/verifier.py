#!/usr/bin/env python3
"""Verifier for expression_manager_conditions task.

A conference coordinator must configure Expression Manager conditional logic on
the 'Annual Tech Summit 2024' survey:
  - Session Feedback group shown only when ATTENDED_SESSIONS == Y (grelevance)
  - IMPROVE_COMMENTS question shown only when OVERALL_RATING <= 6 (relevance)
  - End redirect URL set to techsummit.example.com/thank-you

Scoring (100 points):
- Session Feedback group has a non-trivial grelevance condition (25 pts)
- That condition references ATTENDED_SESSIONS (25 pts)
- IMPROVE_COMMENTS has a condition referencing OVERALL_RATING (25 pts)
- End redirect URL contains 'techsummit' (25 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_expression_manager_conditions(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/expr_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
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

    # ── GATE: survey must exist ───────────────────────────────────────────────
    survey_found = result.get("survey_found", False)
    if isinstance(survey_found, str):
        survey_found = survey_found.lower() in ("true", "1", "yes")

    if not survey_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAILED: 'Annual Tech Summit 2024' survey not found in LimeSurvey. "
                "The pre-built survey may have been accidentally deleted."
            ),
        }

    survey_id = result.get("survey_id", "")
    feedback_parts.append(f"Survey found (SID={survey_id}).")

    # ── Helper ────────────────────────────────────────────────────────────────
    def is_true(val):
        if isinstance(val, bool):
            return val
        if isinstance(val, str):
            return val.lower() in ("true", "1", "yes")
        return bool(val)

    # ── Criterion 1 — Session Feedback group has a non-trivial grelevance ─────
    # 25 pts
    session_has_cond = is_true(result.get("session_group_has_condition", False))
    session_cond_text = result.get("session_group_condition", "")

    if session_has_cond:
        score += 25
        subscores["session_group_condition"] = True
        feedback_parts.append(
            f"[+25] Session Feedback group condition set: '{session_cond_text[:120]}'"
        )
    else:
        subscores["session_group_condition"] = False
        feedback_parts.append(
            "[ 0] Session Feedback group has NO condition (grelevance empty or '1'). "
            "Expected a condition based on whether the respondent attended sessions."
        )

    # ── Criterion 2 — Group condition references ATTENDED_SESSIONS ────────────
    # 25 pts (only if criterion 1 also passed)
    attended_in_cond = is_true(result.get("attended_sessions_in_group_condition", False))

    if session_has_cond and attended_in_cond:
        score += 25
        subscores["attended_sessions_referenced"] = True
        feedback_parts.append(
            "[+25] Session Feedback group condition references ATTENDED_SESSIONS."
        )
    elif session_has_cond and not attended_in_cond:
        subscores["attended_sessions_referenced"] = False
        feedback_parts.append(
            "[ 0] Group condition exists but does NOT reference ATTENDED_SESSIONS. "
            "Expected e.g. ATTENDED_SESSIONS.NAOK == 'Y'."
        )
    else:
        subscores["attended_sessions_referenced"] = False
        feedback_parts.append(
            "[ 0] Cannot check ATTENDED_SESSIONS reference — no group condition found."
        )

    # ── Criterion 3 — IMPROVE_COMMENTS condition references OVERALL_RATING ────
    # 25 pts
    improve_has_cond = is_true(result.get("improve_question_has_condition", False))
    improve_cond_text = result.get("improve_question_condition", "")
    overall_in_q_cond = is_true(result.get("overall_rating_in_question_condition", False))

    if improve_has_cond and overall_in_q_cond:
        score += 25
        subscores["improve_comments_condition"] = True
        feedback_parts.append(
            f"[+25] IMPROVE_COMMENTS condition references OVERALL_RATING: "
            f"'{improve_cond_text[:120]}'"
        )
    elif improve_has_cond and not overall_in_q_cond:
        subscores["improve_comments_condition"] = "partial"
        feedback_parts.append(
            f"[ 0] IMPROVE_COMMENTS has condition '{improve_cond_text[:80]}' "
            "but it does not reference OVERALL_RATING with a numeric threshold. "
            "Expected e.g. OVERALL_RATING.NAOK <= 6."
        )
    else:
        subscores["improve_comments_condition"] = False
        feedback_parts.append(
            "[ 0] IMPROVE_COMMENTS question has NO condition (relevance empty or '1'). "
            "Expected a condition showing the text box only when OVERALL_RATING <= 6."
        )

    # ── Criterion 4 — End redirect URL contains 'techsummit' ─────────────────
    # 25 pts
    end_url_ok = is_true(result.get("end_url_has_techsummit", False))
    end_url = result.get("end_url", "")

    if end_url_ok:
        score += 25
        subscores["end_url"] = True
        feedback_parts.append(f"[+25] End redirect URL set: '{end_url}'")
    elif end_url:
        subscores["end_url"] = "partial"
        feedback_parts.append(
            f"[ 0] End URL set ('{end_url}') but does not contain 'techsummit'. "
            "Expected 'http://techsummit.example.com/thank-you'."
        )
    else:
        subscores["end_url"] = False
        feedback_parts.append(
            "[ 0] No end redirect URL set. "
            "Expected 'http://techsummit.example.com/thank-you' in survey end settings."
        )

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "survey_id": survey_id,
            "session_has_cond": session_has_cond,
            "attended_in_cond": attended_in_cond,
            "improve_has_cond": improve_has_cond,
            "overall_in_q_cond": overall_in_q_cond,
            "end_url": end_url[:100] if end_url else "",
        },
    }
