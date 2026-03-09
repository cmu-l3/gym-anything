#!/usr/bin/env python3
"""Verifier for token_participant_management task.

An I-O psychologist must convert an existing 360-degree leadership survey
from open access to token-based closed access, add 4 specific participants,
customize the invitation email subject, and generate tokens.

Scoring (100 points):
- Tokens enabled (token table exists) (30 pts)
- Participants added: 4 expected (30 pts — full 30 if >= 4, partial 15 if >= 2)
- Expected emails present in participant list (20 pts — 5 pts each)
- Invitation email subject customized with '360-Degree Leadership Feedback' (20 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_EMAILS = [
    "m.thompson@acmecorp.com",
    "s.chen@acmecorp.com",
    "d.okafor@acmecorp.com",
    "p.sharma@acmecorp.com",
]


def verify_token_participant_management(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/token_result.json", tmp.name)
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

    # GATE: Survey must exist (SID must be non-empty)
    survey_id = result.get("survey_id", "")
    if not survey_id or survey_id == "None" or survey_id == "":
        return {
            "passed": False,
            "score": 0,
            "feedback": "Leadership Competency Assessment 360 survey not found — was it deleted?"
        }

    # Criterion 1: Tokens enabled (30 pts)
    tokens_enabled = result.get("tokens_enabled", False)
    if tokens_enabled:
        score += 30
        subscores["tokens_enabled"] = True
        feedback_parts.append("Token-based closed access enabled [30/30]")
    else:
        subscores["tokens_enabled"] = False
        feedback_parts.append(
            "Tokens NOT enabled — survey is still open access. "
            "Must enable participant token management [0/30]"
        )

    # Criterion 2: Participants added (30 pts)
    participant_count = result.get("participant_count", 0)
    tokens_generated = result.get("tokens_generated", 0)
    if participant_count >= 4:
        score += 30
        subscores["participants"] = True
        feedback_parts.append(
            f"{participant_count} participants added, {tokens_generated} tokens generated [30/30]"
        )
    elif participant_count >= 2:
        score += 15
        subscores["participants"] = "partial"
        feedback_parts.append(
            f"Only {participant_count} participants added (need 4) [15/30]"
        )
    elif participant_count >= 1:
        score += 5
        subscores["participants"] = "partial"
        feedback_parts.append(
            f"Only {participant_count} participant added (need 4) [5/30]"
        )
    else:
        subscores["participants"] = False
        feedback_parts.append("No participants added to the token list [0/30]")

    # Criterion 3: Correct participant emails present (20 pts — 5 pts each)
    emails_found_count = result.get("expected_emails_present_count", 0)
    emails_raw = result.get("participant_emails_found", "").lower()

    # Also check directly from the emails string
    emails_actually_found = sum(
        1 for e in EXPECTED_EMAILS if e.lower() in emails_raw
    )
    emails_found_count = max(emails_found_count, emails_actually_found)

    email_score = emails_found_count * 5
    score += email_score
    subscores["correct_emails"] = emails_found_count
    if emails_found_count == 4:
        feedback_parts.append(f"All 4 expected participant emails present [20/20]")
    elif emails_found_count > 0:
        feedback_parts.append(
            f"{emails_found_count}/4 expected emails found (m.thompson, s.chen, d.okafor, p.sharma @acmecorp.com) [{email_score}/20]"
        )
    else:
        feedback_parts.append(
            "None of the 4 expected participants found (m.thompson, s.chen, d.okafor, p.sharma @acmecorp.com) [0/20]"
        )

    # Criterion 4: Invitation email subject customized (20 pts)
    invite_subject = result.get("invite_subject", "")
    invite_has_keyword = result.get("invite_subject_has_keyword", False)

    # Check directly on the subject
    subject_lower = invite_subject.lower()
    has_360 = "360" in subject_lower
    has_leadership = "leadership" in subject_lower
    has_feedback = "feedback" in subject_lower

    if invite_has_keyword or (has_360 and has_leadership and has_feedback):
        score += 20
        subscores["email_subject"] = True
        feedback_parts.append(
            f"Invitation email subject customized with '360-Degree Leadership Feedback' [20/20]"
        )
    elif has_360 or (has_leadership and has_feedback):
        score += 10
        subscores["email_subject"] = "partial"
        feedback_parts.append(
            f"Email subject partially customized but missing required wording. "
            f"Found: '{invite_subject[:80]}' [10/20]"
        )
    else:
        subscores["email_subject"] = False
        feedback_parts.append(
            f"Email subject not customized (still default). "
            f"Must contain '360-Degree Leadership Feedback' [0/20]"
        )

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "survey_id": survey_id,
            "tokens_enabled": tokens_enabled,
            "participant_count": participant_count,
            "emails_found_count": emails_found_count,
            "invite_subject": invite_subject[:100] if invite_subject else "",
        }
    }
