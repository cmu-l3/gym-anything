#!/usr/bin/env python3
"""
Verifier for hipaa_escalation_response task.

The agent must complete three independent subtasks:
1. Escalate the HIPAA ticket: Priority=Urgent, Severity=Critical, Status=In Progress  [35 pts]
2. Update the Pinnacle EHR deal: stage=Negotiation/Review, prob=75, date=2026-05-31   [35 pts]
3. Create emergency meeting: subject matches, date=2026-03-15, start=09:00, type=Meeting [30 pts]

Pass threshold: 70/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_hipaa_escalation_response(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/hipaa_escalation_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # --- Criterion 1: Ticket escalation (35 pts) ---
    ticket_priority = result.get('ticket_priority', '').strip()
    ticket_severity = result.get('ticket_severity', '').strip()
    ticket_status = result.get('ticket_status', '').strip()

    ticket_score = 0
    ticket_fb = []

    if ticket_priority.lower() == 'urgent':
        ticket_score += 12
        ticket_fb.append("priority=Urgent ✓")
    else:
        ticket_fb.append(f"priority='{ticket_priority}' (expected Urgent) ✗")

    if ticket_severity.lower() == 'critical':
        ticket_score += 12
        ticket_fb.append("severity=Critical ✓")
    else:
        ticket_fb.append(f"severity='{ticket_severity}' (expected Critical) ✗")

    if 'progress' in ticket_status.lower() or ticket_status.lower() == 'in progress':
        ticket_score += 11
        ticket_fb.append("status=In Progress ✓")
    else:
        ticket_fb.append(f"status='{ticket_status}' (expected In Progress) ✗")

    score += ticket_score
    feedback.append(f"C1 Ticket ({ticket_score}/35): {', '.join(ticket_fb)}")

    # --- Criterion 2: Deal update (35 pts) ---
    deal_stage = result.get('deal_stage', '').strip()
    deal_closedate = result.get('deal_closedate', '').strip()
    try:
        deal_prob = float(result.get('deal_probability', -1))
    except (TypeError, ValueError):
        deal_prob = -1.0

    deal_score = 0
    deal_fb = []

    if 'negotiation' in deal_stage.lower() or 'review' in deal_stage.lower():
        deal_score += 12
        deal_fb.append("stage=Negotiation/Review ✓")
    else:
        deal_fb.append(f"stage='{deal_stage}' (expected Negotiation/Review) ✗")

    if abs(deal_prob - 75) <= 2:
        deal_score += 12
        deal_fb.append(f"probability={deal_prob}% ✓")
    elif 70 <= deal_prob <= 85:
        deal_score += 6
        deal_fb.append(f"probability={deal_prob}% (close, expected 75) ~")
    else:
        deal_fb.append(f"probability={deal_prob}% (expected 75) ✗")

    if deal_closedate == '2026-05-31':
        deal_score += 11
        deal_fb.append("closedate=2026-05-31 ✓")
    elif deal_closedate.startswith('2026-05'):
        deal_score += 6
        deal_fb.append(f"closedate={deal_closedate} (expected 2026-05-31) ~")
    else:
        deal_fb.append(f"closedate={deal_closedate} (expected 2026-05-31) ✗")

    score += deal_score
    feedback.append(f"C2 Deal ({deal_score}/35): {', '.join(deal_fb)}")

    # --- Criterion 3: Emergency meeting event (30 pts) ---
    event_found = result.get('event_found', False)
    event_subject = result.get('event_subject', '').strip()
    event_date = result.get('event_date', '').strip()
    event_start = result.get('event_start', '').strip()
    event_type = result.get('event_type', '').strip()

    event_score = 0
    event_fb = []

    if not event_found:
        feedback.append("C3 Meeting (0/30): No HIPAA emergency meeting event found ✗")
    else:
        if 'hipaa' in event_subject.lower() and ('pinnacle' in event_subject.lower() or 'remediat' in event_subject.lower()):
            event_score += 10
            event_fb.append("subject matches ✓")
        elif 'hipaa' in event_subject.lower():
            event_score += 5
            event_fb.append("subject has HIPAA but missing Pinnacle/Remediation ~")
        else:
            event_fb.append(f"subject='{event_subject}' (expected HIPAA+Pinnacle/Emergency) ✗")

        if event_date == '2026-03-15':
            event_score += 10
            event_fb.append("date=2026-03-15 ✓")
        elif event_date.startswith('2026-03'):
            event_score += 5
            event_fb.append(f"date={event_date} (expected 2026-03-15) ~")
        else:
            event_fb.append(f"date={event_date} (expected 2026-03-15) ✗")

        if event_start.startswith('09:00') or event_start == '09:00:00':
            event_score += 5
            event_fb.append("start=09:00 ✓")
        else:
            event_fb.append(f"start={event_start} (expected 09:00) ✗")

        if event_type.lower() == 'meeting':
            event_score += 5
            event_fb.append("type=Meeting ✓")
        else:
            event_fb.append(f"type='{event_type}' (expected Meeting) ✗")

        score += event_score
        feedback.append(f"C3 Meeting ({event_score}/30): {', '.join(event_fb)}")

    score = min(score, 100)
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
