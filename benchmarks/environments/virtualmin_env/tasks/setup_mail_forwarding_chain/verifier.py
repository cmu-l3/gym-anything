#!/usr/bin/env python3
"""Verifier for setup_mail_forwarding_chain task.

Scoring (100 points):
- Correct domain: prerequisite (score=0 if wrong)
- HR user created: 20 points
- Billing user created: 20 points
- jobs@ alias → hr@: 20 points
- invoices@ alias → billing@: 20 points
- contact@ alias → info@ AND admin@ (multi-dest): 20 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_setup_mail_forwarding_chain(traj, env_info, task_info):
    """Verify mail forwarding chain was set up correctly for acmecorp.test."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_domain = metadata.get('target_domain', 'acmecorp.test')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_mail_forwarding_chain_result.json", temp_file.name)
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

        # Subtask 1: HR user created (20 points)
        if result.get('hr_user_exists'):
            score += 20
            subscores["hr_user"] = True
            feedback_parts.append("HR user created")
        else:
            feedback_parts.append("HR user NOT found")

        # Subtask 2: Billing user created (20 points)
        if result.get('billing_user_exists'):
            score += 20
            subscores["billing_user"] = True
            feedback_parts.append("Billing user created")
        else:
            feedback_parts.append("Billing user NOT found")

        # Subtask 3: jobs@ alias → hr@ (20 points)
        if result.get('jobs_alias_exists'):
            jobs_dest = result.get('jobs_alias_dest', '').lower()
            if 'hr' in jobs_dest:
                score += 20
                subscores["jobs_alias"] = True
                feedback_parts.append("jobs@ alias correctly forwards to hr@")
            else:
                score += 5  # Alias exists but wrong destination
                feedback_parts.append(f"jobs@ alias exists but forwards to wrong destination: {jobs_dest}")
        else:
            feedback_parts.append("jobs@ alias NOT found")

        # Subtask 4: invoices@ alias → billing@ (20 points)
        if result.get('invoices_alias_exists'):
            invoices_dest = result.get('invoices_alias_dest', '').lower()
            if 'billing' in invoices_dest:
                score += 20
                subscores["invoices_alias"] = True
                feedback_parts.append("invoices@ alias correctly forwards to billing@")
            else:
                score += 5  # Alias exists but wrong destination
                feedback_parts.append(f"invoices@ alias exists but forwards to wrong destination: {invoices_dest}")
        else:
            feedback_parts.append("invoices@ alias NOT found")

        # Subtask 5: contact@ alias → info@ AND admin@ (20 points)
        if result.get('contact_alias_exists'):
            has_info = result.get('contact_has_info_dest', False)
            has_admin = result.get('contact_has_admin_dest', False)
            if has_info and has_admin:
                score += 20
                subscores["contact_alias"] = True
                feedback_parts.append("contact@ alias correctly forwards to both info@ and admin@")
            elif has_info or has_admin:
                score += 10  # Partial: only one destination
                feedback_parts.append(f"contact@ alias has only one destination (info={has_info}, admin={has_admin})")
            else:
                score += 3  # Alias exists but wrong destinations
                feedback_parts.append(f"contact@ alias exists but wrong destinations: {result.get('contact_alias_dest')}")
        else:
            feedback_parts.append("contact@ alias NOT found")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No mail routing configured",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
