#!/usr/bin/env python3
"""
Verifier for stale_pipeline_and_ticket_cleanup task.

The agent must complete three audit subtasks (all records must be DISCOVERED — not named):
1. Close all stale deals (past close date, active stage) → Closed Lost / prob=0   [35 pts]
2. Reclassify misclosed Critical/Urgent tickets from Closed → Resolved + SLA note [35 pts]
3. Update Blackstone Industrial: industry + description                            [30 pts]

Pass threshold: 65/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_stale_pipeline_and_ticket_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/crm_cleanup_result.json', tmp.name)
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

    # --- Criterion 1: Stale deal cleanup (35 pts) ---
    stale_score = 0
    stale_fb = []

    remaining_stale = result.get('remaining_stale_deals', 999)
    nexus_stage = result.get('nexus_stage', '').strip().lower()
    nexus_prob_raw = result.get('nexus_probability', '')
    atlas_stage = result.get('atlas_stage', '').strip().lower()
    atlas_prob_raw = result.get('atlas_probability', '')

    try:
        nexus_prob = float(nexus_prob_raw)
    except (TypeError, ValueError):
        nexus_prob = -1.0
    try:
        atlas_prob = float(atlas_prob_raw)
    except (TypeError, ValueError):
        atlas_prob = -1.0

    # Nexus SCADA deal (17 pts)
    if nexus_stage == 'closed lost':
        stale_score += 10
        stale_fb.append("Nexus → Closed Lost ✓")
    elif 'closed' in nexus_stage:
        stale_score += 5
        stale_fb.append(f"Nexus stage='{nexus_stage}' (partial) ~")
    else:
        stale_fb.append(f"Nexus stage='{nexus_stage}' (still active) ✗")

    if nexus_prob == 0:
        stale_score += 7
        stale_fb.append("Nexus prob=0% ✓")
    elif nexus_prob <= 5:
        stale_score += 3
        stale_fb.append(f"Nexus prob={nexus_prob}% (expected 0) ~")
    else:
        stale_fb.append(f"Nexus prob={nexus_prob}% (expected 0) ✗")

    # Atlas Supply Chain deal (18 pts)
    if atlas_stage == 'closed lost':
        stale_score += 11
        stale_fb.append("Atlas → Closed Lost ✓")
    elif 'closed' in atlas_stage:
        stale_score += 5
        stale_fb.append(f"Atlas stage='{atlas_stage}' (partial) ~")
    else:
        stale_fb.append(f"Atlas stage='{atlas_stage}' (still active) ✗")

    if atlas_prob == 0:
        stale_score += 7
        stale_fb.append("Atlas prob=0% ✓")
    elif atlas_prob <= 5:
        stale_score += 3
        stale_fb.append(f"Atlas prob={atlas_prob}% (expected 0) ~")
    else:
        stale_fb.append(f"Atlas prob={atlas_prob}% (expected 0) ✗")

    # Bonus: no remaining stale deals at all
    if remaining_stale == 0:
        stale_score = min(stale_score + 3, 35)
        stale_fb.append("all stale deals cleaned ✓")

    score += stale_score
    feedback.append(f"C1 Stale Deals ({stale_score}/35): {', '.join(stale_fb)}")

    # --- Criterion 2: Ticket reclassification (35 pts) ---
    ticket_score = 0
    ticket_fb = []

    still_misclosed = result.get('still_misclosed_critical_tickets', 999)
    sla_ticket_found = result.get('sla_audit_ticket_found', False)
    sla_ticket_desc = result.get('sla_ticket_desc_snippet', '').strip()

    # No more Closed+Critical/Urgent tickets remaining
    if still_misclosed == 0:
        ticket_score += 15
        ticket_fb.append("no misclosed critical tickets remain ✓")
    else:
        ticket_fb.append(f"{still_misclosed} misclosed critical ticket(s) still remain ✗")

    # SLA-AUDIT marker present in description
    if sla_ticket_found:
        ticket_score += 12
        ticket_fb.append("SLA-AUDIT marker in ticket description ✓")

        # Check description content quality
        if '[sla-audit]' in sla_ticket_desc.lower() and 'resolved' in sla_ticket_desc.lower():
            ticket_score += 8
            ticket_fb.append("description content correct ✓")
        elif '[sla-audit]' in sla_ticket_desc.lower():
            ticket_score += 4
            ticket_fb.append("description has SLA-AUDIT but missing 'Resolved' text ~")
        else:
            ticket_fb.append("description has marker but wrong format ✗")
    else:
        ticket_fb.append("no ticket found with SLA-AUDIT marker ✗")

    score += ticket_score
    feedback.append(f"C2 Tickets ({ticket_score}/35): {', '.join(ticket_fb)}")

    # --- Criterion 3: Blackstone Industrial account update (30 pts) ---
    acct_score = 0
    acct_fb = []

    acct_found = result.get('account_found', False)
    if not acct_found:
        feedback.append("C3 Account (0/30): Blackstone Industrial not found ✗")
    else:
        acct_industry = result.get('account_industry', '').strip().lower()
        acct_desc = result.get('account_description', '').strip().lower()

        # Industry check (15 pts)
        if 'industrial' in acct_industry and ('machinery' in acct_industry or 'equipment' in acct_industry):
            acct_score += 15
            acct_fb.append(f"industry='{acct_industry}' ✓")
        elif 'industrial' in acct_industry or 'manufacturing' in acct_industry:
            acct_score += 7
            acct_fb.append(f"industry='{acct_industry}' (partial match) ~")
        else:
            acct_fb.append(f"industry='{acct_industry}' (expected Industrial Machinery & Equipment) ✗")

        # Description check (15 pts)
        if acct_desc and len(acct_desc) > 20:
            if 'industrial' in acct_desc and ('automation' in acct_desc or 'factory' in acct_desc or 'integration' in acct_desc):
                acct_score += 15
                acct_fb.append("description set with relevant content ✓")
            elif 'industrial' in acct_desc or 'blackstone' in acct_desc:
                acct_score += 8
                acct_fb.append("description partially relevant ~")
            else:
                acct_score += 5
                acct_fb.append("description set but off-topic ~")
        else:
            acct_fb.append("description missing or too short ✗")

        score += acct_score
        feedback.append(f"C3 Account ({acct_score}/30): {', '.join(acct_fb)}")

    score = min(score, 100)
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
