#!/usr/bin/env python3
"""Verifier for Admin Security Setup task in Magento."""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_admin_security_setup(traj, env_info, task_info):
    """
    Verify that the admin security settings were configured correctly.
    
    Criteria:
    1. Password Lifetime = 90 (20 pts)
    2. Password Change = Forced (1) (20 pts)
    3. Lockout Failures = 5 (20 pts)
    4. Lockout Threshold = 30 (20 pts)
    5. Session Lifetime = 1800 (20 pts)
    
    Pass threshold: 100 pts (All strict security settings required).
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    exp_lifetime = metadata.get("expected_password_lifetime", "90")
    exp_forced = metadata.get("expected_password_is_forced", "1")
    exp_failures = metadata.get("expected_lockout_failures", "5")
    exp_threshold = metadata.get("expected_lockout_threshold", "30")
    exp_session = metadata.get("expected_session_lifetime", "1800")

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_fn("/tmp/admin_security_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Check Password Lifetime ---
    val_lifetime = result.get("admin/security/password_lifetime", "").strip()
    if val_lifetime == exp_lifetime:
        score += 20
        feedback_parts.append(f"Password Lifetime correct ({val_lifetime})")
    else:
        feedback_parts.append(f"Password Lifetime incorrect: expected {exp_lifetime}, got '{val_lifetime}'")

    # --- Check Password Forced ---
    val_forced = result.get("admin/security/password_is_forced", "").strip()
    if val_forced == exp_forced:
        score += 20
        feedback_parts.append("Password Change Forced correct")
    else:
        feedback_parts.append(f"Password Change incorrect: expected {exp_forced}, got '{val_forced}'")

    # --- Check Lockout Failures ---
    val_failures = result.get("admin/security/lockout_failures", "").strip()
    if val_failures == exp_failures:
        score += 20
        feedback_parts.append(f"Lockout Failures correct ({val_failures})")
    else:
        feedback_parts.append(f"Lockout Failures incorrect: expected {exp_failures}, got '{val_failures}'")

    # --- Check Lockout Threshold ---
    val_threshold = result.get("admin/security/lockout_threshold", "").strip()
    if val_threshold == exp_threshold:
        score += 20
        feedback_parts.append(f"Lockout Time correct ({val_threshold})")
    else:
        feedback_parts.append(f"Lockout Time incorrect: expected {exp_threshold}, got '{val_threshold}'")

    # --- Check Session Lifetime ---
    val_session = result.get("admin/security/session_lifetime", "").strip()
    if val_session == exp_session:
        score += 20
        feedback_parts.append(f"Session Lifetime correct ({val_session})")
    else:
        feedback_parts.append(f"Session Lifetime incorrect: expected {exp_session}, got '{val_session}'")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }