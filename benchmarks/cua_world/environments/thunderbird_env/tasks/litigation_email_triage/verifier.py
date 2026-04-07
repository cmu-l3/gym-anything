#!/usr/bin/env python3
"""
Verifier stub for litigation_email_triage task.

A paralegal must organize 15 litigation emails (with generic subjects requiring
content-based routing) into case subfolders, create two compound message filters,
extract contact details from an email signature, and draft a reply.

Primary verification will be done via vlm_checklist_verifier.
This stub provides basic programmatic checks as a fallback.

Scoring (100 points total):
- Meridian_v_Apex parent folder structure created:       5 pts
- Pleadings subfolder with >=4 emails:                  15 pts
- Discovery subfolder with >=4 emails:                  15 pts
- Billing subfolder with >=2 emails:                    10 pts
- Discovery Alerts compound filter (OR, 3 conditions):  15 pts
- Billing Auto-File compound filter (AND+NOT):          15 pts
- Rebecca Torres in address book (email+phone+firm):    15 pts
- Draft reply to Torres with relevant content:          10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/litigation_email_triage_result.json"
PASS_THRESHOLD = 60


def verify_litigation_email_triage(traj, env_info, task_info):
    """Verify litigation email triage task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []

    # ================================================================
    # Read result fields
    # ================================================================
    parent_exists = result.get('parent_sbd_exists', False)
    pleadings_count = int(result.get('pleadings_email_count', 0))
    discovery_count = int(result.get('discovery_email_count', 0))
    billing_count = int(result.get('billing_email_count', 0))
    total_moved = pleadings_count + discovery_count + billing_count

    # ================================================================
    # WRONG-TARGET GUARD: folders created but no emails moved
    # ================================================================
    if parent_exists and total_moved == 0:
        return {
            "passed": False,
            "score": 5,
            "feedback": "GUARD: Folder structure created but no emails moved — agent must route emails to subfolders"
        }

    # ================================================================
    # CRITERION 1: Parent folder structure — 5 pts
    # ================================================================
    if parent_exists:
        score += 5
        feedback_parts.append("Meridian_v_Apex folder structure created (5/5)")
    else:
        feedback_parts.append("Meridian_v_Apex folder structure NOT created (0/5)")

    # ================================================================
    # CRITERION 2: Pleadings subfolder with >= 4 emails — 15 pts
    # ================================================================
    pleadings_folder = result.get('pleadings_folder', '')
    if pleadings_folder and pleadings_count >= 4:
        score += 15
        feedback_parts.append(f"Pleadings subfolder has {pleadings_count} emails (15/15)")
    elif pleadings_folder and pleadings_count >= 3:
        score += 10
        feedback_parts.append(f"Pleadings subfolder has {pleadings_count} emails — expected >=4 (10/15)")
    elif pleadings_folder and pleadings_count >= 1:
        score += 5
        feedback_parts.append(f"Pleadings subfolder has {pleadings_count} email(s) (5/15)")
    elif pleadings_folder:
        score += 2
        feedback_parts.append(f"Pleadings subfolder found but empty (2/15)")
    else:
        feedback_parts.append("Pleadings subfolder not found (0/15)")

    # ================================================================
    # CRITERION 3: Discovery subfolder with >= 4 emails — 15 pts
    # ================================================================
    discovery_folder = result.get('discovery_folder', '')
    if discovery_folder and discovery_count >= 4:
        score += 15
        feedback_parts.append(f"Discovery subfolder has {discovery_count} emails (15/15)")
    elif discovery_folder and discovery_count >= 3:
        score += 10
        feedback_parts.append(f"Discovery subfolder has {discovery_count} emails — expected >=4 (10/15)")
    elif discovery_folder and discovery_count >= 1:
        score += 5
        feedback_parts.append(f"Discovery subfolder has {discovery_count} email(s) (5/15)")
    elif discovery_folder:
        score += 2
        feedback_parts.append(f"Discovery subfolder found but empty (2/15)")
    else:
        feedback_parts.append("Discovery subfolder not found (0/15)")

    # ================================================================
    # CRITERION 4: Billing subfolder with >= 2 emails — 10 pts
    # ================================================================
    billing_folder = result.get('billing_folder', '')
    if billing_folder and billing_count >= 2:
        score += 10
        feedback_parts.append(f"Billing subfolder has {billing_count} emails (10/10)")
    elif billing_folder and billing_count >= 1:
        score += 5
        feedback_parts.append(f"Billing subfolder has {billing_count} email — expected >=2 (5/10)")
    elif billing_folder:
        score += 2
        feedback_parts.append(f"Billing subfolder found but empty (2/10)")
    else:
        feedback_parts.append("Billing subfolder not found (0/10)")

    # ================================================================
    # CRITERION 5: Discovery Alerts filter — 15 pts
    # ================================================================
    discovery_filter = result.get('discovery_filter_exists', False)
    if discovery_filter:
        score += 15
        feedback_parts.append("Discovery Alerts filter detected (15/15)")
    else:
        feedback_parts.append("Discovery Alerts filter not found (0/15)")

    # ================================================================
    # CRITERION 6: Billing Auto-File filter — 15 pts
    # ================================================================
    billing_filter = result.get('billing_filter_exists', False)
    if billing_filter:
        score += 15
        feedback_parts.append("Billing Auto-File filter detected (15/15)")
    else:
        feedback_parts.append("Billing Auto-File filter not found (0/15)")

    # ================================================================
    # CRITERION 7: Rebecca Torres in address book — 15 pts
    # ================================================================
    torres_email = result.get('torres_email_in_abook', False)
    torres_phone = result.get('torres_phone_in_abook', False)
    torres_firm = result.get('torres_firm_in_abook', False)
    torres_name = result.get('torres_in_abook', False)

    if torres_email and torres_phone and torres_firm:
        score += 15
        feedback_parts.append("Rebecca Torres added with email, phone, and firm (15/15)")
    elif torres_email and (torres_phone or torres_firm):
        score += 12
        feedback_parts.append("Rebecca Torres added with email and partial details (12/15)")
    elif torres_email:
        score += 10
        feedback_parts.append("Rebecca Torres added with email only (10/15)")
    elif torres_name:
        score += 5
        feedback_parts.append("Rebecca Torres name found but email not confirmed (5/15)")
    else:
        feedback_parts.append("Rebecca Torres not found in address book (0/15)")

    # ================================================================
    # CRITERION 8: Draft reply to Torres — 10 pts
    # ================================================================
    draft_to_torres = result.get('draft_to_torres', False)
    draft_has_keywords = result.get('draft_has_keywords', False)
    if draft_to_torres and draft_has_keywords:
        score += 10
        feedback_parts.append("Draft reply to Torres with relevant content (10/10)")
    elif draft_to_torres:
        score += 7
        feedback_parts.append("Draft reply to Torres found but keywords missing (7/10)")
    else:
        feedback_parts.append("No draft reply to Torres found (0/10)")

    # ================================================================
    # SCORE CAP: no emails routed
    # ================================================================
    if total_moved == 0 and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD - 1}: no emails routed")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "parent_sbd_exists": parent_exists,
            "pleadings_folder": result.get('pleadings_folder', ''),
            "pleadings_count": pleadings_count,
            "discovery_folder": result.get('discovery_folder', ''),
            "discovery_count": discovery_count,
            "billing_folder": result.get('billing_folder', ''),
            "billing_count": billing_count,
            "discovery_filter": discovery_filter,
            "billing_filter": billing_filter,
            "torres_in_abook": torres_name,
            "torres_email": torres_email,
            "torres_phone": torres_phone,
            "torres_firm": torres_firm,
            "draft_to_torres": draft_to_torres,
            "draft_keywords": draft_has_keywords,
            "total_emails_moved": total_moved,
        }
    }
