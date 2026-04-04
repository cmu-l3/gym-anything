#!/usr/bin/env python3
"""Verifier for security_incident_reopening task.

Checks that the DevOps engineer correctly handled the SSL cert security incident:
1. SSL cert issue status changed to In Progress          (20 pts)
2. SSL cert issue priority changed to Immediate          (20 pts)
3. SSL cert issue has REOPENED comment                   (20 pts)
4. New certbot monitoring issue created (assigned to
   carol.santos, priority High, version Q1 2025 Goals)  (20 pts)
5. SSL cert issue has 2.0h time entry logged             (20 pts)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _any_comment_contains(comments: list, text: str) -> bool:
    text_lower = text.lower()
    for c in comments:
        if isinstance(c, str) and text_lower in c.lower():
            return True
    return False


def verify_security_incident_reopening(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = task_info.get('metadata', {}).get(
        'result_file', '/tmp/security_incident_reopening_result.json')
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env(result_path, tmp.name)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result file not found — export script may not have run"}
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON parse error: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    subscores = {}

    ssl = result.get('ssl_cert_issue', {})
    certbot = result.get('certbot_monitoring_issue')

    # --- Check 1: SSL cert status = In Progress (20 pts) ---
    ssl_status = ssl.get('status', '')
    if ssl_status.lower() == 'in progress':
        score += 20
        subscores['ssl_status_in_progress'] = True
        feedback.append("SSL cert issue status changed to In Progress")
    else:
        subscores['ssl_status_in_progress'] = False
        feedback.append(f"SSL cert issue status is '{ssl_status}' (expected In Progress)")

    # --- Check 2: SSL cert priority = Immediate (20 pts) ---
    ssl_priority = ssl.get('priority', '')
    if ssl_priority.lower() == 'immediate':
        score += 20
        subscores['ssl_priority_immediate'] = True
        feedback.append("SSL cert issue priority changed to Immediate")
    else:
        subscores['ssl_priority_immediate'] = False
        feedback.append(f"SSL cert issue priority is '{ssl_priority}' (expected Immediate)")

    # --- Check 3: SSL cert has REOPENED comment (20 pts) ---
    ssl_comments = ssl.get('comments', [])
    baseline_count = ssl.get('baseline_comment_count', 0)
    has_reopened = _any_comment_contains(ssl_comments, 'REOPENED')
    if has_reopened:
        score += 20
        subscores['ssl_reopened_comment'] = True
        feedback.append("SSL cert issue has REOPENED comment")
    else:
        subscores['ssl_reopened_comment'] = False
        feedback.append(
            f"SSL cert issue missing REOPENED comment "
            f"(total comments: {len(ssl_comments)}, baseline: {baseline_count})"
        )

    # --- Check 4: New certbot monitoring issue created (20 pts) ---
    if certbot and certbot != 'null':
        certbot_ok = True
        certbot_details = []

        assignee = certbot.get('assigned_to', '')
        if 'carol' in assignee.lower() or 'santos' in assignee.lower():
            certbot_details.append(f"assigned to '{assignee}'")
        else:
            certbot_ok = False
            certbot_details.append(f"wrong assignee: '{assignee}' (expected Carol Santos)")

        priority = certbot.get('priority', '')
        if priority.lower() == 'high':
            certbot_details.append("priority High")
        else:
            certbot_ok = False
            certbot_details.append(f"wrong priority: '{priority}' (expected High)")

        version = certbot.get('fixed_version', '')
        if 'q1' in version.lower() or '2025' in version.lower():
            certbot_details.append(f"version '{version}'")
        else:
            certbot_ok = False
            certbot_details.append(f"wrong version: '{version}' (expected Q1 2025 Goals)")

        if certbot_ok:
            score += 20
            subscores['certbot_issue_created'] = True
            feedback.append(f"Certbot monitoring issue created correctly: {', '.join(certbot_details)}")
        else:
            score += 5  # Partial credit for creating the issue at all
            subscores['certbot_issue_created'] = 'partial'
            feedback.append(
                f"Certbot issue found but has issues: {', '.join(certbot_details)}"
            )
    else:
        subscores['certbot_issue_created'] = False
        feedback.append("No certbot monitoring issue found in infra-devops project")

    # --- Check 5: 2.0h time entry on SSL cert issue (20 pts) ---
    time_entries = ssl.get('time_entries', [])
    total_hours = ssl.get('total_hours_logged', 0)
    has_dev_activity = any(
        te.get('activity', '').lower() in ('development', 'dev')
        for te in time_entries
    )
    # Accept if total logged hours includes at least 2.0h development
    dev_hours = sum(
        te.get('hours', 0)
        for te in time_entries
        if te.get('activity', '').lower() in ('development', 'dev')
    )
    if dev_hours >= 2.0:
        score += 20
        subscores['ssl_time_entry_logged'] = True
        feedback.append(f"SSL cert issue has {dev_hours}h Development time logged")
    elif total_hours >= 2.0:
        score += 10
        subscores['ssl_time_entry_logged'] = 'partial'
        feedback.append(
            f"SSL cert issue has {total_hours}h total time logged "
            f"(Development hours: {dev_hours}, expected >=2.0h Development)"
        )
    else:
        subscores['ssl_time_entry_logged'] = False
        feedback.append(
            f"SSL cert issue has {total_hours}h total time logged (expected >=2.0h Development)"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "ssl_status": ssl_status,
            "ssl_priority": ssl_priority,
            "ssl_comment_count": len(ssl_comments),
            "ssl_total_hours": total_hours,
            "certbot_issue": certbot,
        }
    }
