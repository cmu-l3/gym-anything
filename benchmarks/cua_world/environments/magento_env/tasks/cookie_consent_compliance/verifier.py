#!/usr/bin/env python3
"""Verifier for Cookie Consent Compliance task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cookie_consent(traj, env_info, task_info):
    """
    Verify privacy compliance settings.

    Criteria:
    1. CMS Page 'privacy-policy-2026' exists (20 pts)
    2. CMS Page is Active (10 pts)
    3. Cookie Restriction Mode is enabled (20 pts)
    4. Cookie Lifetime is 86400 (15 pts)
    5. HttpOnly is enabled (10 pts)
    6. Footer Copyright updated to include '2026 Acme Corp' (25 pts)

    Pass threshold: 65 pts.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_footer_frag = metadata.get('expected_footer_fragment', '2026 Acme Corp')
    expected_lifetime = metadata.get('expected_cookie_lifetime', '86400')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/cookie_consent_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []

    # 1. CMS Page Created (20 pts)
    if result.get('page_found', False):
        score += 20
        feedback_parts.append("Privacy Policy page created (20 pts)")
    else:
        feedback_parts.append("Privacy Policy page NOT found")

    # 2. CMS Page Active (10 pts)
    if result.get('page_active', False):
        score += 10
        feedback_parts.append("Page is Active (10 pts)")
    elif result.get('page_found', False):
        feedback_parts.append("Page found but is Disabled")

    # 3. Cookie Restriction (20 pts)
    res_val = str(result.get('config_restriction', '0')).strip()
    if res_val == '1':
        score += 20
        feedback_parts.append("Cookie Restriction Mode enabled (20 pts)")
    else:
        feedback_parts.append("Cookie Restriction Mode NOT enabled")

    # 4. Cookie Lifetime (15 pts)
    life_val = str(result.get('config_lifetime', '0')).strip()
    if life_val == str(expected_lifetime):
        score += 15
        feedback_parts.append(f"Cookie Lifetime correct: {life_val} (15 pts)")
    else:
        feedback_parts.append(f"Cookie Lifetime incorrect: got {life_val}, expected {expected_lifetime}")

    # 5. HttpOnly (10 pts)
    http_val = str(result.get('config_httponly', '0')).strip()
    if http_val == '1':
        score += 10
        feedback_parts.append("HttpOnly enabled (10 pts)")
    else:
        feedback_parts.append("HttpOnly NOT enabled")

    # 6. Footer Copyright (25 pts)
    footer_text = result.get('config_footer', '') or ''
    # Case-insensitive check for the key fragment
    if expected_footer_frag.lower() in footer_text.lower():
        score += 25
        feedback_parts.append("Footer Copyright updated correctly (25 pts)")
    else:
        feedback_parts.append(f"Footer Copyright incorrect. Expected fragment '{expected_footer_frag}' not found.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }