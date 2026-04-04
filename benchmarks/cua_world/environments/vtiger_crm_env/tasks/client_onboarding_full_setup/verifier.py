#!/usr/bin/env python3
"""
Verifier for client_onboarding_full_setup task.

The agent must complete four independent subtasks:
1. Create organization 'ClearSky Aerospace Technologies' with correct details [25 pts]
2. Create both contacts (Harrison Yates + Priya Natarajan), linked to ClearSky org [25 pts]
3. Create deal 'ClearSky Zero-Trust Security Implementation', $425K, Qualification, 20%, 2026-06-30 [30 pts]
4. Schedule kickoff meeting: subject matches ClearSky Kickoff/Onboarding, 2026-03-20, 10:00, Meeting [20 pts]

Pass threshold: 70/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_client_onboarding_full_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/onboarding_result.json', tmp.name)
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

    # --- Criterion 1: Organization created (25 pts) ---
    org_found = result.get('org_found', False)
    org_score = 0
    org_fb = []

    if not org_found:
        feedback.append("C1 Org (0/25): Organization 'ClearSky Aerospace Technologies' not found ✗")
    else:
        org_score += 5
        org_fb.append("org exists ✓")

        org_phone = result.get('org_phone', '').strip()
        if org_phone:
            org_score += 4
            org_fb.append("phone set ✓")
        else:
            org_fb.append("phone missing ✗")

        org_website = result.get('org_website', '').strip().lower()
        if 'clearsky' in org_website or 'aerospace' in org_website:
            org_score += 4
            org_fb.append("website set ✓")
        else:
            org_fb.append(f"website='{org_website}' (expected clearsky/aerospace domain) ✗")

        try:
            org_employees = int(result.get('org_employees', 0))
        except (TypeError, ValueError):
            org_employees = 0
        if 800 <= org_employees <= 1000:
            org_score += 4
            org_fb.append(f"employees={org_employees} ✓")
        elif org_employees > 0:
            org_score += 2
            org_fb.append(f"employees={org_employees} (expected ~900) ~")
        else:
            org_fb.append("employees not set ✗")

        org_city = result.get('org_city', '').strip().lower()
        org_state = result.get('org_state', '').strip().lower()
        if 'dulles' in org_city or 'dulles' in org_state:
            org_score += 4
            org_fb.append("location=Dulles ✓")
        elif 'virginia' in org_state or org_state in ('va', 'virginia'):
            org_score += 2
            org_fb.append(f"state=Virginia (expected Dulles VA) ~")
        else:
            org_fb.append(f"location='{org_city},{org_state}' (expected Dulles,VA) ✗")

        try:
            org_revenue = float(result.get('org_revenue', 0))
        except (TypeError, ValueError):
            org_revenue = 0
        if 160000000 <= org_revenue <= 200000000:
            org_score += 4
            org_fb.append(f"revenue={org_revenue} ✓")
        elif org_revenue > 0:
            org_score += 2
            org_fb.append(f"revenue={org_revenue} (expected ~180M) ~")
        else:
            org_fb.append("revenue not set ✗")

        score += org_score
        feedback.append(f"C1 Org ({org_score}/25): {', '.join(org_fb)}")

    # --- Criterion 2: Contacts created and linked (25 pts) ---
    contact_a_found = result.get('contact_a_found', False)
    contact_b_found = result.get('contact_b_found', False)
    contact_a_linked = result.get('contact_a_org_linked', False)
    contact_b_linked = result.get('contact_b_org_linked', False)

    contact_score = 0
    contact_fb = []

    if contact_a_found:
        contact_score += 5
        contact_fb.append("Harrison Yates exists ✓")
        contact_a_email = result.get('contact_a_email', '').strip()
        contact_a_phone = result.get('contact_a_phone', '').strip()
        contact_a_title = result.get('contact_a_title', '').strip()
        if contact_a_email:
            contact_score += 2
            contact_fb.append("Yates email set ✓")
        if contact_a_phone:
            contact_score += 1
            contact_fb.append("Yates phone set ✓")
        if contact_a_title:
            contact_score += 1
            contact_fb.append("Yates title set ✓")
        if contact_a_linked:
            contact_score += 3
            contact_fb.append("Yates linked to ClearSky ✓")
        else:
            contact_fb.append("Yates not linked to ClearSky ✗")
    else:
        contact_fb.append("Harrison Yates not found ✗")

    if contact_b_found:
        contact_score += 5
        contact_fb.append("Priya Natarajan exists ✓")
        contact_b_email = result.get('contact_b_email', '').strip()
        contact_b_phone = result.get('contact_b_phone', '').strip()
        contact_b_title = result.get('contact_b_title', '').strip()
        if contact_b_email:
            contact_score += 2
            contact_fb.append("Natarajan email set ✓")
        if contact_b_phone:
            contact_score += 1
            contact_fb.append("Natarajan phone set ✓")
        if contact_b_title:
            contact_score += 1
            contact_fb.append("Natarajan title set ✓")
        if contact_b_linked:
            contact_score += 4
            contact_fb.append("Natarajan linked to ClearSky ✓")
        else:
            contact_fb.append("Natarajan not linked to ClearSky ✗")
    else:
        contact_fb.append("Priya Natarajan not found ✗")

    score += contact_score
    feedback.append(f"C2 Contacts ({contact_score}/25): {', '.join(contact_fb)}")

    # --- Criterion 3: Deal created (30 pts) ---
    deal_found = result.get('deal_found', False)
    deal_score = 0
    deal_fb = []

    if not deal_found:
        feedback.append("C3 Deal (0/30): Deal 'ClearSky Zero-Trust Security Implementation' not found ✗")
    else:
        deal_score += 5
        deal_fb.append("deal exists ✓")

        try:
            deal_amount = float(result.get('deal_amount', 0))
        except (TypeError, ValueError):
            deal_amount = 0
        if abs(deal_amount - 425000) <= 5000:
            deal_score += 8
            deal_fb.append(f"amount=${deal_amount} ✓")
        elif abs(deal_amount - 425000) <= 25000:
            deal_score += 4
            deal_fb.append(f"amount=${deal_amount} (expected $425K) ~")
        else:
            deal_fb.append(f"amount=${deal_amount} (expected $425,000) ✗")

        deal_stage = result.get('deal_stage', '').strip().lower()
        if 'needs analysis' in deal_stage or 'analysis' in deal_stage:
            deal_score += 7
            deal_fb.append("stage=Needs Analysis ✓")
        elif deal_stage:
            deal_score += 3
            deal_fb.append(f"stage='{deal_stage}' (expected Needs Analysis) ~")
        else:
            deal_fb.append("stage not set ✗")

        try:
            deal_prob = float(result.get('deal_probability', -1))
        except (TypeError, ValueError):
            deal_prob = -1.0
        if abs(deal_prob - 40) <= 5:
            deal_score += 5
            deal_fb.append(f"probability={deal_prob}% ✓")
        elif 25 <= deal_prob <= 55:
            deal_score += 2
            deal_fb.append(f"probability={deal_prob}% (expected 40) ~")
        else:
            deal_fb.append(f"probability={deal_prob}% (expected 40) ✗")

        deal_closedate = result.get('deal_closedate', '').strip()
        if deal_closedate == '2026-10-31':
            deal_score += 5
            deal_fb.append("closedate=2026-10-31 ✓")
        elif deal_closedate.startswith('2026-10'):
            deal_score += 2
            deal_fb.append(f"closedate={deal_closedate} (expected 2026-10-31) ~")
        else:
            deal_fb.append(f"closedate={deal_closedate} (expected 2026-10-31) ✗")

        score += deal_score
        feedback.append(f"C3 Deal ({deal_score}/30): {', '.join(deal_fb)}")

    # --- Criterion 4: Kickoff meeting event (20 pts) ---
    event_found = result.get('event_found', False)
    event_score = 0
    event_fb = []

    if not event_found:
        feedback.append("C4 Meeting (0/20): No ClearSky kickoff/onboarding event found ✗")
    else:
        event_subject = result.get('event_subject', '').strip()
        event_date = result.get('event_date', '').strip()
        event_start = result.get('event_start', '').strip()
        event_type = result.get('event_type', '').strip()

        if 'clearsky' in event_subject.lower() or 'clear sky' in event_subject.lower():
            event_score += 5
            event_fb.append("subject contains ClearSky ✓")
        else:
            event_fb.append(f"subject='{event_subject}' (expected ClearSky Kickoff/Onboarding) ✗")

        if event_date == '2026-03-20':
            event_score += 6
            event_fb.append("date=2026-03-20 ✓")
        elif event_date.startswith('2026-03'):
            event_score += 3
            event_fb.append(f"date={event_date} (expected 2026-03-20) ~")
        else:
            event_fb.append(f"date={event_date} (expected 2026-03-20) ✗")

        if event_start.startswith('10:00') or event_start == '10:00:00':
            event_score += 5
            event_fb.append("start=10:00 ✓")
        else:
            event_fb.append(f"start={event_start} (expected 10:00) ✗")

        if event_type.lower() == 'meeting':
            event_score += 4
            event_fb.append("type=Meeting ✓")
        else:
            event_fb.append(f"type='{event_type}' (expected Meeting) ✗")

        score += event_score
        feedback.append(f"C4 Meeting ({event_score}/20): {', '.join(event_fb)}")

    score = min(score, 100)
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
