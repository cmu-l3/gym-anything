#!/usr/bin/env python3
"""Verifier for Insecure Form Security Audit task.

Scoring (100 points total):
- Screaming Frog ran (10 pts)
- Crawl of crawler-test.com detected (Window title or CSV domain) (20 pts)
- Export file created (20 pts)
- Export contains verified form security issues (50 pts)
  - Contains 'crawler-test.com' (20 pts)
  - Contains security specific path components (30 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_insecure_form_security_audit(traj, env_info, task_info):
    """Verify insecure form security audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/insecure_form_audit_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # --- Criterion 1: SF Running (10 pts) ---
    sf_ran = result.get('sf_running', False)
    if sf_ran:
        score += 10
        feedback_parts.append("SF ran (10/10)")
    else:
        feedback_parts.append("SF not running (0/10)")

    # --- Criterion 2: Export File Created (20 pts) ---
    new_csv_count = result.get('new_csv_count', 0)
    if new_csv_count > 0:
        score += 20
        feedback_parts.append(f"Export created ({new_csv_count} files) (20/20)")
    else:
        feedback_parts.append("No export file created (0/20)")

    # --- Criterion 3: Target Domain Verified (20 pts) ---
    # Can be in window title OR in the exported CSV
    window_info = result.get('window_info', '').lower()
    domain_in_csv = result.get('target_domain_found', False)
    
    if 'crawler-test' in window_info or domain_in_csv:
        score += 20
        feedback_parts.append("Target domain verified (20/20)")
    else:
        feedback_parts.append("Target domain not found in window or export (0/20)")

    # --- Criterion 4: Security Issues Identified (50 pts) ---
    has_security_urls = result.get('has_security_urls', False)
    csv_rows = result.get('csv_row_count', 0)
    
    if has_security_urls:
        score += 50
        feedback_parts.append(f"Security vulnerabilities identified in export ({csv_rows} rows) (50/50)")
    elif domain_in_csv and csv_rows > 0:
        # Export exists with domain, but didn't match specific security keywords
        # Maybe they exported "All" instead of "Security" tab?
        score += 10
        feedback_parts.append("Export contains domain but no specific security vulnerability URLs found (10/50)")
    else:
        feedback_parts.append("No security issues identified in export (0/50)")

    # VLM Check (Optional bonus/verification)
    # If score is borderline, VLM could confirm if Security tab was visible
    
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }