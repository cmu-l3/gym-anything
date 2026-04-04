#!/usr/bin/env python3
"""Verifier for SMTP Forensic Analysis task.

Scoring (100 points):
- Criterion 1: Report file exists and is substantial (10 points)
- Criterion 2: Sender email address extracted correctly (20 points)
- Criterion 3: Recipient email address extracted correctly (20 points)
- Criterion 4: Email subject line extracted (20 points)
- Criterion 5: SMTP server banner identified (15 points)
- Criterion 6: SMTP packet count within tolerance (15 points)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_smtp_forensic_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        # Criterion 1: Report file exists and is substantial
        if not result.get('file_exists'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file not created. Agent must save findings to smtp_forensic_report.txt"
            }

        content_length = result.get('content_length', 0)
        if content_length >= 100:
            score += 10
            feedback_parts.append(f"Report file exists ({content_length} chars)")
        elif content_length > 0:
            score += 5
            feedback_parts.append(f"Report file exists but short ({content_length} chars)")
        else:
            feedback_parts.append("Report file is empty")

        # Criterion 2: Sender email extracted
        if result.get('has_sender'):
            score += 20
            feedback_parts.append("Sender email correctly identified")
        else:
            feedback_parts.append("Sender email not found in report")

        # Criterion 3: Recipient email extracted
        if result.get('has_recipient'):
            score += 20
            feedback_parts.append("Recipient email correctly identified")
        else:
            feedback_parts.append("Recipient email not found in report")

        # Criterion 4: Subject line extracted
        if result.get('has_subject'):
            score += 20
            feedback_parts.append("Email subject line correctly extracted")
        else:
            feedback_parts.append("Email subject line not found in report")

        # Criterion 5: Server banner identified
        if result.get('has_banner'):
            score += 15
            feedback_parts.append("SMTP server banner identified")
        else:
            feedback_parts.append("SMTP server banner not found in report")

        # Criterion 6: SMTP packet count
        if result.get('has_smtp_count'):
            score += 15
            feedback_parts.append("SMTP packet count within tolerance")
        else:
            feedback_parts.append("SMTP packet count not found or incorrect")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
