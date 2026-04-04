#!/usr/bin/env python3
"""
Verifier for incident_resolution_knowledge_base task.

Scoring breakdown (100 pts total, pass threshold: 60):
  Criterion 1 (25 pts): Ticket 1002 (email) resolved — status changed from Open.
                         +5 bonus if resolution text contains 'smtp'/'relay'/'mail server'.
  Criterion 2 (20 pts): Ticket 1005 (Adobe) resolved — status changed from Open.
                         +5 bonus if resolution text contains 'acrobat'/'adobe'/'sccm'.
  Criterion 3 (15 pts): Ticket 1002 closed (status=Closed, not just Resolved).
  Criterion 4 (30 pts): KB Solution article created with 'SMTP' in title/content.

Wrong-target gate: If neither ticket 1002 nor ticket 1005 changed status AND no KB article exists,
return score=0 (agent took no meaningful action on required items).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_incident_resolution_knowledge_base(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')

    if copy_from_env is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verifier error: copy_from_env not available."
        }

    with tempfile.TemporaryDirectory() as tmp_dir:
        result_path = os.path.join(tmp_dir, 'result.json')
        try:
            copy_from_env('/tmp/incident_resolution_knowledge_base_result.json', result_path)
            with open(result_path) as f:
                data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read result file from VM: {e}"
            }

    score = 0
    feedback_parts = []
    subscores = {}

    ticket_1002_resolved = data.get('ticket_1002_resolved', False)
    ticket_1005_resolved = data.get('ticket_1005_resolved', False)
    kb_exists = data.get('kb_smtp_article_exists', False)

    # --- Wrong-target gate ---
    status_1002 = data.get('status_1002', 2)
    status_1005 = data.get('status_1005', 2)
    tickets_unchanged = (
        (status_1002 == 2 or status_1002 == 0) and
        (status_1005 == 2 or status_1005 == 0)
    )

    if tickets_unchanged and not kb_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Neither ticket 1002 nor ticket 1005 had their status changed from Open, "
                "and no KB article with 'SMTP' was found. The agent appears to have taken no action "
                "on the required items."
            ),
            "subscores": {
                "email_ticket_resolved": 0,
                "adobe_ticket_resolved": 0,
                "email_ticket_closed": 0,
                "kb_article_created": 0
            }
        }

    # --- Criterion 1: Ticket 1002 resolved (25 pts + 5 bonus for correct resolution) ---
    if ticket_1002_resolved:
        c1_base = 25
        score += c1_base
        smtp_in_res = bool(data.get('smtp_in_resolution_1002', 0))
        if smtp_in_res:
            score += 5
            subscores['email_ticket_resolved'] = 30
            feedback_parts.append(
                f"PASS: Email ticket (1002) resolved with SMTP-related resolution. "
                f"(status: {data.get('status_name_1002', '')}) (+30 pts)"
            )
        else:
            subscores['email_ticket_resolved'] = c1_base
            feedback_parts.append(
                f"PASS: Email ticket (1002) resolved. "
                f"Note: resolution should mention SMTP/relay settings. "
                f"(status: {data.get('status_name_1002', '')}) (+{c1_base} pts)"
            )
    else:
        subscores['email_ticket_resolved'] = 0
        feedback_parts.append(
            f"FAIL: Email ticket (1002) not resolved. "
            f"Current status: {data.get('status_name_1002', str(data.get('status_1002', '?')))} (+0 pts)"
        )

    # --- Criterion 2: Ticket 1005 resolved (20 pts + 5 bonus) ---
    if ticket_1005_resolved:
        c2_base = 20
        score += c2_base
        acrobat_in_res = bool(data.get('acrobat_in_resolution_1005', 0))
        if acrobat_in_res:
            score += 5
            subscores['adobe_ticket_resolved'] = 25
            feedback_parts.append(
                f"PASS: Adobe ticket (1005) resolved with Acrobat/SCCM-related resolution. "
                f"(status: {data.get('status_name_1005', '')}) (+25 pts)"
            )
        else:
            subscores['adobe_ticket_resolved'] = c2_base
            feedback_parts.append(
                f"PASS: Adobe ticket (1005) resolved. "
                f"Note: resolution should mention Acrobat/SCCM. "
                f"(status: {data.get('status_name_1005', '')}) (+{c2_base} pts)"
            )
    else:
        subscores['adobe_ticket_resolved'] = 0
        feedback_parts.append(
            f"FAIL: Adobe Acrobat ticket (1005) not resolved. "
            f"Current status: {data.get('status_name_1005', str(data.get('status_1005', '?')))} (+0 pts)"
        )

    # --- Criterion 3: Ticket 1002 CLOSED (not just resolved) ---
    ticket_1002_closed = data.get('ticket_1002_closed', False)
    if ticket_1002_closed:
        score += 15
        subscores['email_ticket_closed'] = 15
        feedback_parts.append("PASS: Email ticket (1002) fully closed. (+15 pts)")
    else:
        subscores['email_ticket_closed'] = 0
        feedback_parts.append(
            "FAIL: Email ticket (1002) not yet closed (must be set to 'Closed', not just 'Resolved'). "
            f"Current status: {data.get('status_name_1002', '')} (+0 pts)"
        )

    # --- Criterion 4: KB article with SMTP in title ---
    if kb_exists:
        score += 30
        subscores['kb_article_created'] = 30
        feedback_parts.append(
            "PASS: Knowledge Base article about SMTP email issues created. (+30 pts)"
        )
    else:
        subscores['kb_article_created'] = 0
        feedback_parts.append(
            "FAIL: No Knowledge Base solution article with 'SMTP' in the title was found. "
            "Create an article in the Solutions/Knowledge Base module. (+0 pts)"
        )

    # Cap score at 100 (bonus points could push it over)
    score = min(score, 100)

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
