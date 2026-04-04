#!/usr/bin/env python3
"""
Verifier for vendor_patch_escalation task.

Occupation context: Operations Manager / IT Vendor Manager
Context: 25 emails in inbox including technical patch/update discussions needing escalation

Scoring (100 points total, pass threshold: 65):
- 20 pts: 'Vendor-Escalations' folder created in Maildir
- 25 pts: Folder contains 3+ emails
- 25 pts: Draft or sent email has CC containing vendor-manager@acmecorp.com
- 20 pts: Draft or sent email has BCC or additional To containing compliance@acmecorp.com
- 10 pts: Draft/sent body mentions 'timeline' OR 'deployment' OR 'risk' OR 'assessment' OR 'contact'

Output-existence gate: No folder AND no draft/sent -> score=0
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vendor_patch_escalation(traj, env_info, task_info):
    """Verify vendor patch escalation task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    escalation_folder = metadata.get('escalation_folder', 'Vendor-Escalations').lower()
    cc_address = metadata.get('cc_address', 'vendor-manager@acmecorp.com').lower()
    bcc_address = metadata.get('bcc_address', 'compliance@acmecorp.com').lower()
    min_emails = metadata.get('min_emails_in_folder', 3)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    vendor_esc_exists = result.get('vendor_escalations_exists', False)
    vendor_esc_count = result.get('vendor_escalations_count', 0)
    custom_folders = result.get('custom_folders', {})
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_outgoing = drafts + sent

    # Check custom_folders for case-insensitive Vendor-Escalations match
    for k, v in custom_folders.items():
        if k.lower() == escalation_folder:
            vendor_esc_exists = True
            vendor_esc_count = max(vendor_esc_count, v)

    # OUTPUT-EXISTENCE GATE
    if not vendor_esc_exists and len(all_outgoing) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No work done: Vendor-Escalations folder not created and no emails composed"
        }

    # ================================================================
    # CRITERION 1: Vendor-Escalations folder created (20 pts)
    # ================================================================
    try:
        if vendor_esc_exists:
            score += 20
            subscores['folder_created'] = True
            feedback_parts.append(f"'Vendor-Escalations' folder created ({vendor_esc_count} emails)")
        else:
            subscores['folder_created'] = False
            feedback_parts.append("'Vendor-Escalations' folder not found")
    except Exception as e:
        feedback_parts.append(f"Folder check error: {e}")

    # ================================================================
    # CRITERION 2: Folder contains 3+ emails (25 pts)
    # ================================================================
    try:
        if vendor_esc_count >= min_emails:
            score += 25
            subscores['folder_populated'] = True
            feedback_parts.append(f"Folder has {vendor_esc_count} emails (need {min_emails}+)")
        elif vendor_esc_count >= 1:
            score += 10
            subscores['folder_populated'] = False
            feedback_parts.append(f"Folder has only {vendor_esc_count} email(s) (need {min_emails}+)")
        else:
            subscores['folder_populated'] = False
            feedback_parts.append(f"Folder is empty")
    except Exception as e:
        feedback_parts.append(f"Folder population check error: {e}")

    # ================================================================
    # CRITERION 3: Escalation email has CC to vendor-manager@acmecorp.com (25 pts)
    # ================================================================
    try:
        cc_found = False
        for email in all_outgoing:
            cc = email.get('cc', '').lower()
            to = email.get('to', '').lower()
            # CC field should contain the vendor manager
            if cc_address in cc:
                cc_found = True
                break
            # Some clients put CC in To with multiple recipients
            if cc_address in to:
                cc_found = True
                break
        if cc_found:
            score += 25
            subscores['cc_included'] = True
            feedback_parts.append(f"CC to {cc_address} found")
        else:
            subscores['cc_included'] = False
            feedback_parts.append(f"CC to {cc_address} not found in any draft/sent")
    except Exception as e:
        feedback_parts.append(f"CC check error: {e}")

    # ================================================================
    # CRITERION 4: Escalation email has BCC to compliance@acmecorp.com (20 pts)
    # ================================================================
    try:
        bcc_found = False
        for email in all_outgoing:
            bcc = email.get('bcc', '').lower()
            cc = email.get('cc', '').lower()
            to = email.get('to', '').lower()
            body = email.get('body', '').lower()
            if bcc_address in bcc or bcc_address in to or bcc_address in cc:
                bcc_found = True
                break
        if bcc_found:
            score += 20
            subscores['bcc_included'] = True
            feedback_parts.append(f"BCC/CC to {bcc_address} found")
        else:
            subscores['bcc_included'] = False
            feedback_parts.append(f"BCC to {bcc_address} not found")
    except Exception as e:
        feedback_parts.append(f"BCC check error: {e}")

    # ================================================================
    # CRITERION 5: Escalation body has required content (10 pts)
    # ================================================================
    try:
        content_ok = False
        required_terms = ['timeline', 'deployment', 'risk', 'assessment', 'contact', 'poc', 'point-of-contact']
        for email in all_outgoing:
            # Only check emails that have the CC address (the actual escalation email)
            cc = email.get('cc', '').lower()
            to = email.get('to', '').lower()
            if cc_address not in cc and cc_address not in to:
                continue
            body = email.get('body', '').lower()
            subject = email.get('subject', '').lower()
            combined = body + ' ' + subject
            if any(t in combined for t in required_terms):
                content_ok = True
                break
        if content_ok:
            score += 10
            subscores['content_quality'] = True
            feedback_parts.append("Escalation body has required content (timeline/risk/contact)")
        else:
            subscores['content_quality'] = False
            feedback_parts.append("Escalation body missing required terms (timeline/risk/contact)")
    except Exception as e:
        feedback_parts.append(f"Content check error: {e}")

    # VLM supplementary check
    try:
        query_vlm = env_info.get('query_vlm')
        get_final_screenshot = env_info.get('get_final_screenshot')
        if query_vlm and traj and get_final_screenshot:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_result = query_vlm(
                    image=final_screenshot,
                    prompt="""Analyze this BlueMail screenshot. In JSON:
{"vendor_folder_visible": true/false, "compose_with_cc_visible": true/false, "explanation": "brief"}
Is 'Vendor-Escalations' folder visible in sidebar? Is there a compose window with CC field filled?"""
                )
                vlm_text = str(vlm_result).lower() if vlm_result else ''
                if 'vendor' in vlm_text and ('folder' in vlm_text or 'escalat' in vlm_text):
                    bonus = min(5, 100 - score)
                    score += bonus
                    feedback_parts.append("VLM: Vendor-Escalations visible")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    passed = score >= 65

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "vendor_escalations_exists": vendor_esc_exists,
            "vendor_escalations_count": vendor_esc_count,
            "draft_count": result.get('draft_count', 0)
        }
    }
