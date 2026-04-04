#!/usr/bin/env python3
"""Verifier for account_consolidation task.

Scoring (100 points, pass >= 60):
- Amanda Cortez parent = Company B (primary): 5 pts
- Ben Holloway parent = Company B (primary): 5 pts
- Celia Park parent = Company B (primary): 5 pts
- 2 moved opps (ERP Phase 1 + Security Audit) on Company B: 18 pts (9 each)
  (Meridian Annual License was pre-seeded on Company B — no pts for that)
- Company A is archived (active=False): 15 pts
- Company B has new note after task start (body > 30 chars): 17 pts
- 'Requires-Deduplication' tag removed from Company B: 10 pts
- All 3 opps tagged 'Account-Deduped': 25 pts (8 pts each, partial)
Total: 100 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_account_consolidation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/account_consolidation_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    contacts = result.get('contacts', {})
    opps = result.get('opportunities', {})
    company_b_id = result.get('company_b_id')

    # --- Criterion 1: Amanda Cortez parent = Company B (5 pts) ---
    try:
        amanda = contacts.get('Amanda Cortez', {})
        if amanda.get('on_primary'):
            score += 5
            feedback_parts.append("Amanda Cortez moved to primary")
        else:
            feedback_parts.append(f"Amanda Cortez not on primary (parent_id={amanda.get('parent_id')})")
    except Exception as e:
        feedback_parts.append(f"Amanda check error: {e}")

    # --- Criterion 2: Ben Holloway parent = Company B (5 pts) ---
    try:
        ben = contacts.get('Ben Holloway', {})
        if ben.get('on_primary'):
            score += 5
            feedback_parts.append("Ben Holloway moved to primary")
        else:
            feedback_parts.append(f"Ben Holloway not on primary (parent_id={ben.get('parent_id')})")
    except Exception as e:
        feedback_parts.append(f"Ben check error: {e}")

    # --- Criterion 3: Celia Park parent = Company B (5 pts) ---
    try:
        celia = contacts.get('Celia Park', {})
        if celia.get('on_primary'):
            score += 5
            feedback_parts.append("Celia Park moved to primary")
        else:
            feedback_parts.append(f"Celia Park not on primary (parent_id={celia.get('parent_id')})")
    except Exception as e:
        feedback_parts.append(f"Celia check error: {e}")

    # --- Criterion 4: Moved opps (ERP Phase 1 + Security Audit) on Company B (18 pts, 9 each) ---
    # Note: 'Meridian Annual License' was pre-seeded on Company B — no credit for it
    opp_names = ['Meridian ERP Phase 1', 'Meridian Security Audit', 'Meridian Annual License']
    moved_opp_names = ['Meridian ERP Phase 1', 'Meridian Security Audit']
    try:
        opp_pts = 0
        for opp_name in moved_opp_names:
            opp = opps.get(opp_name, {})
            if opp.get('on_primary'):
                opp_pts += 9
                feedback_parts.append(f"'{opp_name}' moved to primary")
            else:
                feedback_parts.append(f"'{opp_name}' NOT on primary (partner={opp.get('partner_name')})")
        annual = opps.get('Meridian Annual License', {})
        if annual.get('on_primary'):
            feedback_parts.append("'Meridian Annual License' on primary (pre-existing)")
        else:
            feedback_parts.append(f"'Meridian Annual License' NOT on primary (partner={annual.get('partner_name')})")
        score += opp_pts
    except Exception as e:
        feedback_parts.append(f"Opp partner check error: {e}")

    # --- Criterion 5: Company A is archived (15 pts) ---
    try:
        company_a_active = result.get('company_a_active')
        if company_a_active is False:
            score += 15
            feedback_parts.append("Company A archived successfully")
        else:
            feedback_parts.append(f"Company A NOT archived (active={company_a_active})")
    except Exception as e:
        feedback_parts.append(f"Company A archive check error: {e}")

    # --- Criterion 6: Company B has new note after task start (17 pts) ---
    try:
        has_note = result.get('company_b_new_note', False)
        if has_note:
            score += 17
            feedback_parts.append("Company B has new consolidation note")
        else:
            note_count = result.get('company_b_new_note_count', 0)
            feedback_parts.append(f"Company B missing new note after task start (found {note_count} messages)")
    except Exception as e:
        feedback_parts.append(f"Company B note check error: {e}")

    # --- Criterion 7: Requires-Deduplication tag removed from Company B (10 pts) ---
    try:
        has_dedup_tag = result.get('company_b_has_dedup_tag', True)
        if not has_dedup_tag:
            score += 10
            feedback_parts.append("'Requires-Deduplication' tag removed from primary")
        else:
            cats = result.get('company_b_category_names', [])
            feedback_parts.append(f"'Requires-Deduplication' tag still on primary (tags: {cats})")
    except Exception as e:
        feedback_parts.append(f"Dedup tag check error: {e}")

    # --- Criterion 8: All 3 opps tagged 'Account-Deduped' (25 pts, 8 each partial) ---
    try:
        deduped_count = sum(
            1 for opp_name in opp_names
            if opps.get(opp_name, {}).get('has_deduped_tag', False)
        )
        deduped_pts = min(deduped_count * 8, 25)
        if deduped_count == 3:
            deduped_pts = 25
        score += deduped_pts
        if deduped_count == 3:
            feedback_parts.append("All 3 opps tagged 'Account-Deduped'")
        else:
            feedback_parts.append(f"{deduped_count}/3 opps tagged 'Account-Deduped' ({deduped_pts} pts)")
    except Exception as e:
        feedback_parts.append(f"Account-Deduped tag check error: {e}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met"
    }
