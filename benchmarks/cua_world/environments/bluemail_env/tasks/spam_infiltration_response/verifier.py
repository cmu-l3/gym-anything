#!/usr/bin/env python3
"""
Verifier for spam_infiltration_response task.

Occupation context: IT Security Manager / Operations Manager
Context: 10 spam emails bypassed filter and are mixed with 40 legitimate emails in inbox

Scoring (100 points total, pass threshold: 65):
- 25 pts: Junk folder count increased by 7+ from baseline (at least 7 spam found and moved)
- 20 pts: 'Spam-Incidents' folder created in Maildir
- 15 pts: 'Spam-Incidents' folder has 2+ emails
- 25 pts: Draft or sent email to security-response@company.com
- 15 pts: Report subject contains 'spam' or 'incident', OR body mentions a count number

Output-existence gate: Junk not increased AND no draft -> score=0
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_spam_infiltration_response(traj, env_info, task_info):
    """Verify spam infiltration response task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    report_recipient = metadata.get('report_recipient', 'security-response@company.com').lower()
    spam_folder_name = metadata.get('spam_folder_name', 'Spam-Incidents')
    initial_junk = metadata.get('initial_junk_count', 10)

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

    junk_count = result.get('junk_count', initial_junk)
    junk_increase = result.get('junk_increase', junk_count - initial_junk)
    spam_incidents_exists = result.get('spam_incidents_folder_exists', False)
    spam_incidents_count = result.get('spam_incidents_count', 0)
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_outgoing = drafts + sent

    # OUTPUT-EXISTENCE GATE
    if junk_increase <= 0 and len(all_outgoing) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No work done: Junk count unchanged and no emails drafted or sent"
        }

    # ================================================================
    # CRITERION 1: Spam quarantined to Junk (25 pts)
    # ================================================================
    try:
        if junk_increase >= 7:
            score += 25
            subscores['spam_quarantined'] = True
            feedback_parts.append(f"Spam quarantined: {junk_increase} emails moved to Junk")
        elif junk_increase >= 3:
            score += 12
            subscores['spam_quarantined'] = False
            feedback_parts.append(f"Partial quarantine: {junk_increase} moved to Junk (need 7+)")
        else:
            subscores['spam_quarantined'] = False
            feedback_parts.append(f"Junk barely changed: +{junk_increase} (need 7+)")
    except Exception as e:
        feedback_parts.append(f"Junk check error: {e}")

    # ================================================================
    # CRITERION 2: Spam-Incidents folder created (20 pts)
    # ================================================================
    try:
        custom_folders = result.get('custom_folders', {})
        # Check for Spam-Incidents (exact or case-insensitive match)
        folder_found = spam_incidents_exists or any(
            k.lower() == spam_folder_name.lower() for k in custom_folders.keys()
        )
        if folder_found:
            score += 20
            subscores['incidents_folder_exists'] = True
            feedback_parts.append(f"'{spam_folder_name}' folder created")
        else:
            subscores['incidents_folder_exists'] = False
            feedback_parts.append(f"'{spam_folder_name}' folder not found")
    except Exception as e:
        feedback_parts.append(f"Folder check error: {e}")

    # ================================================================
    # CRITERION 3: Spam-Incidents folder has 2+ emails (15 pts)
    # ================================================================
    try:
        # Also check custom_folders for case-insensitive match
        custom_folders = result.get('custom_folders', {})
        actual_count = spam_incidents_count
        for k, v in custom_folders.items():
            if k.lower() == spam_folder_name.lower():
                actual_count = max(actual_count, v)
        if actual_count >= 2:
            score += 15
            subscores['incidents_populated'] = True
            feedback_parts.append(f"'{spam_folder_name}' has {actual_count} emails")
        elif actual_count >= 1:
            score += 7
            subscores['incidents_populated'] = False
            feedback_parts.append(f"'{spam_folder_name}' has only {actual_count} email")
        else:
            subscores['incidents_populated'] = False
            feedback_parts.append(f"'{spam_folder_name}' is empty")
    except Exception as e:
        feedback_parts.append(f"Folder population check error: {e}")

    # ================================================================
    # CRITERION 4: Incident report to security-response@company.com (25 pts)
    # ================================================================
    try:
        report_found = False
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if report_recipient in to_addr:
                report_found = True
                break
        if report_found:
            score += 25
            subscores['report_sent'] = True
            feedback_parts.append(f"Incident report to {report_recipient} found")
        else:
            subscores['report_sent'] = False
            feedback_parts.append(f"No email to {report_recipient} found")
    except Exception as e:
        feedback_parts.append(f"Report check error: {e}")

    # ================================================================
    # CRITERION 5: Report quality - subject/body mentions spam or count (15 pts)
    # ================================================================
    try:
        report_quality_ok = False
        spam_terms = ['spam', 'incident', 'bypass', 'filter', 'junk', 'phishing', 'unsolicited']
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if report_recipient not in to_addr:
                continue
            subject = email.get('subject', '').lower()
            body = email.get('body', '').lower()
            combined = subject + ' ' + body
            has_spam_term = any(t in combined for t in spam_terms)
            has_number = bool(re.search(r'\b\d+\b', combined))
            if has_spam_term and has_number:
                report_quality_ok = True
                break
            elif has_spam_term:
                # Partial credit
                score += 7
                subscores['report_quality'] = False
                feedback_parts.append("Report mentions spam terms but no explicit count")
                report_quality_ok = None  # Partial
                break
        if report_quality_ok is True:
            score += 15
            subscores['report_quality'] = True
            feedback_parts.append("Report has spam terminology and count")
        elif report_quality_ok is False:
            subscores['report_quality'] = False
            feedback_parts.append("Report lacks spam terminology or count")
    except Exception as e:
        feedback_parts.append(f"Report quality check error: {e}")

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
{"spam_incidents_folder_visible": true/false, "junk_folder_visible": true/false, "explanation": "brief"}
Is a 'Spam-Incidents' folder visible? Is Junk folder visible in sidebar?"""
                )
                vlm_text = str(vlm_result).lower() if vlm_result else ''
                if 'spam-incidents' in vlm_text or 'spam_incidents' in vlm_text:
                    bonus = min(5, 100 - score)
                    score += bonus
                    feedback_parts.append("VLM: Spam-Incidents folder visible")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    passed = score >= 65

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "junk_increase": junk_increase,
            "spam_incidents_exists": spam_incidents_exists,
            "spam_incidents_count": spam_incidents_count,
            "draft_count": result.get('draft_count', 0)
        }
    }
