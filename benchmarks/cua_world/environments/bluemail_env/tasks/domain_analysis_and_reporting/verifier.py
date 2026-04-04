#!/usr/bin/env python3
"""
Verifier for domain_analysis_and_reporting task.

Occupation context: Operations Manager / Administrative Assistant
Context: 50 inbox emails from various sender domains, need domain-based compliance audit

Scoring (100 points total, pass threshold: 65):
- 20 pts: 3+ folders with 'Domain-' prefix created in Maildir
- 25 pts: At least 2 of the top-3 pre-computed sender domains have corresponding Domain- folders with emails
- 25 pts: Draft or sent email to audit-compliance@yourcompany.com
- 15 pts: Audit email subject contains 'audit' or 'domain' (case-insensitive)
- 15 pts: Audit email body mentions at least 2 domain names (contains '.' suggesting domain format)

Output-existence gate: no Domain- folders AND no draft/sent -> score=0
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_domain_analysis_and_reporting(traj, env_info, task_info):
    """Verify domain analysis and reporting task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    audit_recipient = metadata.get('audit_recipient', 'audit-compliance@yourcompany.com').lower()
    folder_prefix = metadata.get('folder_prefix', 'Domain-').lower()
    min_domain_folders = metadata.get('min_domain_folders', 3)

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

    domain_folders = result.get('domain_folders', {})
    domain_folder_count = result.get('domain_folder_count', 0)
    custom_folders = result.get('custom_folders', {})
    top3_domains = result.get('top3_domains', [])
    top_domains_covered = result.get('top_domains_covered', [])
    top_domains_covered_count = result.get('top_domains_covered_count', 0)
    drafts = result.get('drafts', [])
    sent = result.get('sent', [])
    all_outgoing = drafts + sent

    # Also count Domain- prefixed folders from custom_folders (case-insensitive check)
    if domain_folder_count == 0:
        for fname in custom_folders.keys():
            if fname.lower().startswith('domain-'):
                domain_folder_count += 1

    # OUTPUT-EXISTENCE GATE
    if domain_folder_count == 0 and len(all_outgoing) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No work done: no Domain- folders created and no emails drafted or sent"
        }

    # ================================================================
    # CRITERION 1: 3+ Domain- folders created (20 pts)
    # ================================================================
    try:
        if domain_folder_count >= min_domain_folders:
            score += 20
            subscores['domain_folders_created'] = True
            feedback_parts.append(f"Domain folders created: {domain_folder_count} — {list(domain_folders.keys())[:5]}")
        elif domain_folder_count >= 1:
            score += 8
            subscores['domain_folders_created'] = False
            feedback_parts.append(f"Only {domain_folder_count} Domain- folder(s) created (need {min_domain_folders}+)")
        else:
            subscores['domain_folders_created'] = False
            feedback_parts.append(f"No 'Domain-' prefixed folders found")
    except Exception as e:
        feedback_parts.append(f"Domain folder check error: {e}")

    # ================================================================
    # CRITERION 2: Top sender domains covered (25 pts)
    # ================================================================
    try:
        # Also do a broader check: any domain folder that has emails
        domains_with_emails = {d: c for d, c in domain_folders.items() if c >= 1}
        # Check against custom_folders too
        for fname, count in custom_folders.items():
            if fname.lower().startswith('domain-') and count >= 1:
                domain_part = fname[7:]
                domains_with_emails[domain_part] = count

        # Count how many top-3 are covered
        covered = top_domains_covered_count
        # If top domains weren't pre-computed, award partial for any domain folders with emails
        if not top3_domains:
            covered = min(len(domains_with_emails), 3)

        if covered >= 2:
            score += 25
            subscores['top_domains_covered'] = True
            feedback_parts.append(f"Top domains covered: {covered}/3 — {top_domains_covered}")
        elif covered >= 1:
            score += 12
            subscores['top_domains_covered'] = False
            feedback_parts.append(f"Only {covered} top domain(s) covered")
        elif len(domains_with_emails) >= 1:
            # Domains have emails but might not match top-3 exactly
            score += 8
            subscores['top_domains_covered'] = False
            feedback_parts.append(f"Domain folders have emails but top-3 domains not fully covered")
        else:
            subscores['top_domains_covered'] = False
            feedback_parts.append("No domain folders have emails or top domains not covered")
    except Exception as e:
        feedback_parts.append(f"Top domain coverage check error: {e}")

    # ================================================================
    # CRITERION 3: Audit email to audit-compliance@yourcompany.com (25 pts)
    # ================================================================
    try:
        audit_found = False
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if audit_recipient in to_addr:
                audit_found = True
                break
        if audit_found:
            score += 25
            subscores['audit_sent'] = True
            feedback_parts.append(f"Audit email to {audit_recipient} found")
        else:
            subscores['audit_sent'] = False
            feedback_parts.append(f"No email to {audit_recipient} found")
    except Exception as e:
        feedback_parts.append(f"Audit email check error: {e}")

    # ================================================================
    # CRITERION 4: Audit subject relevant (15 pts)
    # ================================================================
    try:
        subject_ok = False
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if audit_recipient not in to_addr:
                continue
            subject = email.get('subject', '').lower()
            if 'audit' in subject or 'domain' in subject or 'report' in subject or 'compliance' in subject:
                subject_ok = True
                break
        if subject_ok:
            score += 15
            subscores['subject_relevant'] = True
            feedback_parts.append("Audit email subject contains audit/domain/report keyword")
        else:
            subscores['subject_relevant'] = False
            feedback_parts.append("Audit email subject missing relevant keyword")
    except Exception as e:
        feedback_parts.append(f"Subject check error: {e}")

    # ================================================================
    # CRITERION 5: Audit body mentions domain names (15 pts)
    # ================================================================
    try:
        domains_in_body = 0
        for email in all_outgoing:
            to_addr = email.get('to', '').lower()
            if audit_recipient not in to_addr:
                continue
            body = email.get('body', '').lower()
            # Count domain-like patterns (word.word at minimum)
            domain_matches = re.findall(r'\b[\w-]+\.[\w.-]+\b', body)
            # Filter out common non-domain words with dots (like "e.g.", "i.e.", numbers)
            actual_domains = [d for d in domain_matches if len(d.split('.')[0]) > 1 and not d.replace('.', '').isdigit()]
            unique_domains = set(actual_domains)
            domains_in_body = max(domains_in_body, len(unique_domains))
        if domains_in_body >= 2:
            score += 15
            subscores['body_has_domains'] = True
            feedback_parts.append(f"Audit email body mentions {domains_in_body} domain-like strings")
        elif domains_in_body >= 1:
            score += 7
            subscores['body_has_domains'] = False
            feedback_parts.append(f"Audit email body mentions only {domains_in_body} domain-like string")
        else:
            subscores['body_has_domains'] = False
            feedback_parts.append("Audit email body doesn't mention domain names")
    except Exception as e:
        feedback_parts.append(f"Body domain check error: {e}")

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
{"domain_folders_visible": true/false, "compose_visible": true/false, "explanation": "brief"}
Are folders starting with 'Domain-' visible in sidebar? Is there a compose window or audit email?"""
                )
                vlm_text = str(vlm_result).lower() if vlm_result else ''
                if 'domain-' in vlm_text or ('domain' in vlm_text and 'folder' in vlm_text):
                    bonus = min(5, 100 - score)
                    score += bonus
                    feedback_parts.append("VLM: Domain- folders visible in sidebar")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    passed = score >= 65

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "domain_folder_count": domain_folder_count,
            "domain_folders": domain_folders,
            "top3_domains": top3_domains,
            "top_domains_covered": top_domains_covered,
            "draft_count": result.get('draft_count', 0)
        }
    }
