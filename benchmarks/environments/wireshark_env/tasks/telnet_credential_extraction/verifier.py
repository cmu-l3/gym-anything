#!/usr/bin/env python3
"""Verifier for Telnet Credential Extraction task.

Scoring (100 points):
- Criterion 1: Report file exists and is substantial (10 points)
- Criterion 2: Username extracted correctly (20 points)
- Criterion 3: Password extracted correctly (20 points)
- Criterion 4: System banner/OS identified (15 points)
- Criterion 5: Commands listed (20 points)
- Criterion 6: Telnet packet count within tolerance (15 points)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_telnet_credential_extraction(traj, env_info, task_info):
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

        # Criterion 1: Report exists
        if not result.get('file_exists'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file not created. Agent must save findings to telnet_incident_report.txt"
            }

        content_length = result.get('content_length', 0)
        if content_length >= 100:
            score += 10
            feedback_parts.append(f"Report exists ({content_length} chars)")
        elif content_length > 0:
            score += 5
            feedback_parts.append(f"Report exists but short ({content_length} chars)")
        else:
            feedback_parts.append("Report file is empty")

        # Criterion 2: Username
        if result.get('has_username'):
            score += 20
            feedback_parts.append("Username correctly extracted")
        else:
            feedback_parts.append("Username not found in report")

        # Criterion 3: Password
        if result.get('has_password'):
            score += 20
            feedback_parts.append("Password correctly extracted")
        else:
            feedback_parts.append("Password not found in report")

        # Criterion 4: System banner/OS
        if result.get('has_banner'):
            score += 15
            feedback_parts.append("System banner/OS identified")
        else:
            feedback_parts.append("System banner/OS not found in report")

        # Criterion 5: Commands
        has_commands = result.get('has_commands', 'false')
        commands_found = result.get('commands_found', 0)
        if has_commands == 'true' or has_commands is True:
            score += 20
            feedback_parts.append(f"Commands listed ({commands_found} found)")
        elif has_commands == 'partial':
            score += 10
            feedback_parts.append(f"Some commands found ({commands_found})")
        else:
            feedback_parts.append("Commands not found in report")

        # Criterion 6: Telnet packet count
        if result.get('has_telnet_count'):
            score += 15
            feedback_parts.append("Telnet packet count within tolerance")
        else:
            feedback_parts.append("Telnet packet count not found or incorrect")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
