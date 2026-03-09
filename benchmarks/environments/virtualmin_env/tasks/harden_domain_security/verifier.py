#!/usr/bin/env python3
"""Verifier for harden_domain_security task.

Scoring (100 points):
- Correct domain: prerequisite (score=0 if wrong)
- SPF DNS record added: 20 points
- DKIM signing enabled: 20 points
- HTTP→HTTPS redirect configured: 20 points
- X-Content-Type-Options: nosniff header: 20 points
- Directory listing disabled (-Indexes): 20 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_harden_domain_security(traj, env_info, task_info):
    """Verify security hardening was applied to acmecorp.test."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_domain = metadata.get('target_domain', 'acmecorp.test')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/harden_domain_security_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL: Check correct domain
        if result.get('domain') != expected_domain:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Wrong domain! Expected {expected_domain}, got {result.get('domain')}"
            }

        # Subtask 1: SPF record (20 points)
        if result.get('spf_exists'):
            spf_record = result.get('spf_record', '').lower()
            if 'v=spf1' in spf_record:
                score += 20
                subscores["spf_record"] = True
                feedback_parts.append("SPF record added with v=spf1")
            else:
                score += 10
                feedback_parts.append(f"SPF-related DNS record found but may be incomplete: {spf_record[:80]}")
        else:
            feedback_parts.append("SPF record NOT found")

        # Subtask 2: DKIM signing (20 points)
        if result.get('dkim_enabled'):
            score += 20
            subscores["dkim_enabled"] = True
            feedback_parts.append("DKIM signing enabled")
        elif result.get('dkim_dns_record'):
            score += 10
            feedback_parts.append("DKIM DNS record found but signing may not be fully enabled")
        else:
            feedback_parts.append("DKIM signing NOT enabled")

        # Subtask 3: SSL redirect (20 points)
        if result.get('ssl_redirect'):
            score += 20
            subscores["ssl_redirect"] = True
            feedback_parts.append("HTTP to HTTPS redirect configured")
        else:
            feedback_parts.append("SSL redirect NOT configured")

        # Subtask 4: X-Content-Type-Options: nosniff (20 points)
        if result.get('nosniff_header'):
            score += 20
            subscores["nosniff_header"] = True
            feedback_parts.append("X-Content-Type-Options: nosniff header set")
        else:
            feedback_parts.append("X-Content-Type-Options header NOT set")

        # Subtask 5: Directory listing disabled (20 points)
        if result.get('indexes_disabled'):
            score += 20
            subscores["indexes_disabled"] = True
            feedback_parts.append("Directory listing disabled (-Indexes)")
        else:
            feedback_parts.append("Directory listing NOT disabled")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No security hardening applied",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
