#!/usr/bin/env python3
"""
Verifier for Edge Security Compliance task.

Scoring (100 points):
- Compliance report exists and was written after task start: 10 points
- Microsoft Defender SmartScreen enabled (safebrowsing.enabled = true): 20 points
- Password manager disabled (credentials_enable_service = false): 20 points
- Address autofill disabled (autofill.enabled = false): 20 points
- Report mentions DuckDuckGo (search engine change documented): 15 points
- Report mentions "Strict" tracking prevention: 15 points

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/edge_security_compliance_result.json"
PASS_THRESHOLD = 65


def verify_edge_security_compliance(traj, env_info, task_info):
    """Verify the Edge Security Compliance task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
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

        score = 0
        feedback_parts = []
        subscores = {}

        settings = result.get("settings", {})
        report = result.get("compliance_report", {})

        # Criterion 1: Compliance report exists and was written after task start (10 pts)
        if report.get("exists") and report.get("modified_after_start"):
            score += 10
            subscores["report_exists"] = True
            feedback_parts.append("Compliance report created after task start (10/10)")
        elif report.get("exists"):
            score += 4
            subscores["report_exists"] = "stale"
            feedback_parts.append("Compliance report exists but may be pre-existing (4/10)")
        else:
            subscores["report_exists"] = False
            feedback_parts.append("Compliance report not found at /home/ga/Desktop/compliance_report.txt (0/10)")

        # Criterion 2: SmartScreen enabled (20 pts)
        # Only award points if it was actually changed from disabled to enabled
        smartscreen_on = settings.get("smartscreen_enabled", False)
        was_disabled = settings.get("smartscreen_was_disabled", True)
        if smartscreen_on and was_disabled:
            score += 20
            subscores["smartscreen"] = True
            feedback_parts.append("Microsoft Defender SmartScreen enabled (was disabled) (20/20)")
        elif smartscreen_on:
            score += 10
            subscores["smartscreen"] = "unchanged"
            feedback_parts.append("SmartScreen is on but may not have been changed by agent (10/20)")
        else:
            subscores["smartscreen"] = False
            feedback_parts.append("SmartScreen still disabled — policy requires it ENABLED (0/20)")

        # Criterion 3: Password manager disabled (20 pts)
        pw_disabled = settings.get("password_manager_disabled", False)
        pw_was_enabled = settings.get("password_was_enabled", True)
        if pw_disabled and pw_was_enabled:
            score += 20
            subscores["password_manager"] = True
            feedback_parts.append("Password manager disabled (was enabled) (20/20)")
        elif pw_disabled:
            score += 10
            subscores["password_manager"] = "unchanged"
            feedback_parts.append("Password manager disabled but may not have been changed (10/20)")
        else:
            subscores["password_manager"] = False
            feedback_parts.append("Password manager still enabled — policy requires it DISABLED (0/20)")

        # Criterion 4: Address autofill disabled (20 pts)
        af_disabled = settings.get("autofill_disabled", False)
        af_was_enabled = settings.get("autofill_was_enabled", True)
        if af_disabled and af_was_enabled:
            score += 20
            subscores["autofill"] = True
            feedback_parts.append("Address autofill disabled (was enabled) (20/20)")
        elif af_disabled:
            score += 10
            subscores["autofill"] = "unchanged"
            feedback_parts.append("Autofill disabled but may not have been changed (10/20)")
        else:
            subscores["autofill"] = False
            feedback_parts.append("Address autofill still enabled — policy requires it DISABLED (0/20)")

        # Criterion 5: Report mentions DuckDuckGo (15 pts)
        if report.get("mentions_duckduckgo"):
            score += 15
            subscores["duckduckgo"] = True
            feedback_parts.append("Report documents DuckDuckGo search engine change (15/15)")
        else:
            subscores["duckduckgo"] = False
            feedback_parts.append("Report does not mention DuckDuckGo (search engine change not documented) (0/15)")

        # Criterion 6: Report mentions Strict tracking prevention (15 pts)
        if report.get("mentions_strict"):
            score += 15
            subscores["strict_tracking"] = True
            feedback_parts.append("Report documents Strict tracking prevention (15/15)")
        else:
            subscores["strict_tracking"] = False
            feedback_parts.append("Report does not mention Strict tracking prevention (0/15)")

        score = min(score, 100)
        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores,
        }

    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
