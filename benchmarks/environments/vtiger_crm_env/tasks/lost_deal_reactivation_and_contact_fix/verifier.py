#!/usr/bin/env python3
"""
Verifier for lost_deal_reactivation_and_contact_fix task.

The agent must complete three subtasks:
1. Reactivate IronShield deal: stage=Value Proposition, prob=55, amount=$198500, date=2026-08-31  [40 pts]
2. Fix contact records: Victoria Blackwell email + title, Thomas Park phone + title              [30 pts]
3. Schedule Blackstone IronShield reactivation call: date=2026-03-18, start=14:00, type=Call    [30 pts]

Pass threshold: 65/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_lost_deal_reactivation_and_contact_fix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/ironshield_result.json', tmp.name)
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

    # --- Criterion 1: Deal reactivation (40 pts) ---
    deal_found = result.get('deal_found', False)
    deal_score = 0
    deal_fb = []

    if not deal_found:
        feedback.append("C1 Deal (0/40): IronShield Network Hardening deal not found ✗")
    else:
        deal_stage = result.get('deal_stage', '').strip().lower()
        if 'value proposition' in deal_stage or 'value' in deal_stage:
            deal_score += 12
            deal_fb.append("stage=Value Proposition ✓")
        elif deal_stage and 'closed' not in deal_stage:
            deal_score += 5
            deal_fb.append(f"stage='{deal_stage}' (expected Value Proposition) ~")
        else:
            deal_fb.append(f"stage='{deal_stage}' (still Closed Lost or unset) ✗")

        try:
            deal_prob = float(result.get('deal_probability', -1))
        except (TypeError, ValueError):
            deal_prob = -1.0
        if abs(deal_prob - 55) <= 3:
            deal_score += 10
            deal_fb.append(f"probability={deal_prob}% ✓")
        elif 45 <= deal_prob <= 65:
            deal_score += 5
            deal_fb.append(f"probability={deal_prob}% (expected 55) ~")
        else:
            deal_fb.append(f"probability={deal_prob}% (expected 55) ✗")

        try:
            deal_amount = float(result.get('deal_amount', 0))
        except (TypeError, ValueError):
            deal_amount = 0
        if abs(deal_amount - 198500) <= 500:
            deal_score += 10
            deal_fb.append(f"amount=${deal_amount} ✓")
        elif abs(deal_amount - 198500) <= 10000:
            deal_score += 5
            deal_fb.append(f"amount=${deal_amount} (expected $198,500) ~")
        else:
            deal_fb.append(f"amount=${deal_amount} (expected $198,500) ✗")

        deal_closedate = result.get('deal_closedate', '').strip()
        if deal_closedate == '2026-08-31':
            deal_score += 8
            deal_fb.append("closedate=2026-08-31 ✓")
        elif deal_closedate.startswith('2026-08'):
            deal_score += 4
            deal_fb.append(f"closedate={deal_closedate} (expected 2026-08-31) ~")
        else:
            deal_fb.append(f"closedate={deal_closedate} (expected 2026-08-31) ✗")

        score += deal_score
        feedback.append(f"C1 Deal ({deal_score}/40): {', '.join(deal_fb)}")

    # --- Criterion 2: Contact record fixes (30 pts) ---
    contact_score = 0
    contact_fb = []

    # Victoria Blackwell (15 pts)
    vb_found = result.get('contact_vb_found', False)
    if not vb_found:
        contact_fb.append("Victoria Blackwell not found ✗")
    else:
        vb_email = result.get('contact_vb_email', '').strip().lower()
        vb_title = result.get('contact_vb_title', '').strip().lower()

        if 'victoria.blackwell' in vb_email or 'blackstone' in vb_email:
            contact_score += 9
            contact_fb.append(f"Blackwell email='{vb_email}' ✓")
        elif '@' in vb_email and vb_email:
            contact_score += 4
            contact_fb.append(f"Blackwell email='{vb_email}' (unexpected domain) ~")
        else:
            contact_fb.append(f"Blackwell email='{vb_email}' (missing) ✗")

        if 'director' in vb_title and ('it' in vb_title or 'security' in vb_title or 'information' in vb_title):
            contact_score += 6
            contact_fb.append("Blackwell title=Director of IT Security ✓")
        elif 'director' in vb_title or 'security' in vb_title:
            contact_score += 3
            contact_fb.append(f"Blackwell title='{vb_title}' (partial) ~")
        else:
            contact_fb.append(f"Blackwell title='{vb_title}' (expected Director of IT Security) ✗")

    # Thomas Park (15 pts)
    tp_found = result.get('contact_tp_found', False)
    if not tp_found:
        contact_fb.append("Thomas Park not found ✗")
    else:
        tp_phone = result.get('contact_tp_phone', '').strip()
        tp_title = result.get('contact_tp_title', '').strip().lower()

        # Phone check — normalize by stripping non-digits for comparison
        tp_phone_digits = ''.join(c for c in tp_phone if c.isdigit())
        expected_digits = '13125550847'
        if tp_phone_digits == expected_digits or '555-0847' in tp_phone or '5550847' in tp_phone_digits:
            contact_score += 9
            contact_fb.append(f"Park phone='{tp_phone}' ✓")
        elif len(tp_phone_digits) >= 7:
            contact_score += 4
            contact_fb.append(f"Park phone='{tp_phone}' (unexpected number) ~")
        else:
            contact_fb.append(f"Park phone='{tp_phone}' (missing) ✗")

        if 'vp' in tp_title or 'vice president' in tp_title:
            if 'operations' in tp_title or 'ops' in tp_title:
                contact_score += 6
                contact_fb.append("Park title=VP of Operations ✓")
            else:
                contact_score += 3
                contact_fb.append(f"Park title='{tp_title}' (VP but not Operations) ~")
        elif 'operations' in tp_title:
            contact_score += 3
            contact_fb.append(f"Park title='{tp_title}' (has Operations, missing VP) ~")
        else:
            contact_fb.append(f"Park title='{tp_title}' (expected VP of Operations) ✗")

    score += contact_score
    feedback.append(f"C2 Contacts ({contact_score}/30): {', '.join(contact_fb)}")

    # --- Criterion 3: Reactivation call event (30 pts) ---
    call_found = result.get('call_found', False)
    call_score = 0
    call_fb = []

    if not call_found:
        feedback.append("C3 Call (0/30): No IronShield reactivation call found ✗")
    else:
        call_subject = result.get('call_subject', '').strip().lower()
        call_date = result.get('call_date', '').strip()
        call_start = result.get('call_start', '').strip()
        call_type = result.get('call_type', '').strip().lower()
        call_status = result.get('call_status', '').strip().lower()

        if 'ironshield' in call_subject or 'iron shield' in call_subject:
            call_score += 8
            call_fb.append("subject mentions IronShield ✓")
        elif 'blackstone' in call_subject:
            call_score += 4
            call_fb.append("subject mentions Blackstone ~")
        else:
            call_fb.append(f"subject='{call_subject}' (expected IronShield/Blackstone) ✗")

        if call_date == '2026-03-18':
            call_score += 8
            call_fb.append("date=2026-03-18 ✓")
        elif call_date.startswith('2026-03'):
            call_score += 4
            call_fb.append(f"date={call_date} (expected 2026-03-18) ~")
        else:
            call_fb.append(f"date={call_date} (expected 2026-03-18) ✗")

        if call_start.startswith('14:00') or call_start == '14:00:00':
            call_score += 7
            call_fb.append("start=14:00 ✓")
        else:
            call_fb.append(f"start={call_start} (expected 14:00) ✗")

        if call_type == 'call':
            call_score += 7
            call_fb.append("type=Call ✓")
        else:
            call_fb.append(f"type='{call_type}' (expected Call) ✗")

        score += call_score
        feedback.append(f"C3 Call ({call_score}/30): {', '.join(call_fb)}")

    score = min(score, 100)
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
