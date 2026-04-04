#!/usr/bin/env python3
"""Verifier for HTTP Session Reconstruction task.

Scoring (100 points):
- Criterion 1: Report file exists and is substantial (10 points)
- Criterion 2: HTTP request URIs extracted (25 points)
- Criterion 3: Web server IP identified (20 points)
- Criterion 4: HTTP response status codes documented (20 points)
- Criterion 5: User-Agent string identified (15 points)
- Criterion 6: HTTP request count correct (10 points)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_http_session_reconstruction(traj, env_info, task_info):
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

        if not result.get('file_exists'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file not created. Agent must save findings to http_analysis_report.txt"
            }

        # Criterion 1: Report exists and is substantial
        content_length = result.get('content_length', 0)
        if content_length >= 150:
            score += 10
            feedback_parts.append(f"Report exists ({content_length} chars)")
        elif content_length > 0:
            score += 5
            feedback_parts.append(f"Report exists but short ({content_length} chars)")
        else:
            feedback_parts.append("Report is empty")

        # Criterion 2: URIs extracted
        uris_found = result.get('uris_found', 0)
        uris_total = result.get('uris_total', 1)
        if uris_total > 0:
            uri_ratio = uris_found / uris_total
            if uri_ratio >= 0.7:
                score += 25
                feedback_parts.append(f"URIs: {uris_found}/{uris_total} found")
            elif uri_ratio >= 0.4:
                score += 15
                feedback_parts.append(f"URIs: {uris_found}/{uris_total} found (partial)")
            elif uris_found > 0:
                score += 8
                feedback_parts.append(f"URIs: only {uris_found}/{uris_total} found")
            else:
                feedback_parts.append("No URIs found in report")
        else:
            feedback_parts.append("No ground truth URIs to check")

        # Criterion 3: Server IP
        if result.get('has_server_ip'):
            score += 20
            feedback_parts.append("Web server IP correctly identified")
        else:
            feedback_parts.append("Web server IP not found in report")

        # Criterion 4: Status codes
        codes_found = result.get('status_codes_found', 0)
        codes_total = result.get('status_codes_total', 1)
        if codes_total > 0:
            code_ratio = codes_found / codes_total
            if code_ratio >= 0.7:
                score += 20
                feedback_parts.append(f"Status codes: {codes_found}/{codes_total} found")
            elif codes_found > 0:
                score += 10
                feedback_parts.append(f"Status codes: {codes_found}/{codes_total} found (partial)")
            else:
                feedback_parts.append("No status codes found in report")

        # Criterion 5: User-Agent
        if result.get('has_user_agent'):
            score += 15
            feedback_parts.append("User-Agent string identified")
        else:
            feedback_parts.append("User-Agent not found in report")

        # Criterion 6: Request count
        if result.get('has_request_count'):
            score += 10
            feedback_parts.append("HTTP request count correct")
        else:
            feedback_parts.append("HTTP request count not found or incorrect")

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
