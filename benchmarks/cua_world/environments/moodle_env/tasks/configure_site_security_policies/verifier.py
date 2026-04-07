#!/usr/bin/env python3
"""Verifier for Configure Site Security Policies task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_site_security_policies(traj, env_info, task_info):
    """
    Verify that Moodle security settings have been correctly updated.
    
    Scoring Breakdown (Total 100):
    - Password Policy Settings (55 pts)
    - Account Lockout Settings (30 pts)
    - Session Timeout Setting (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from task metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {
        "passwordpolicy": "1",
        "minpasswordlength": "12",
        "minpassworddigits": "2",
        "minpasswordlower": "2",
        "minpasswordupper": "2",
        "minpasswordnonalphanum": "2",
        "maxconsecutiveidentchars": "3",
        "lockoutthreshold": "5",
        "lockoutwindow": "900",
        "lockoutduration": "900",
        "sessiontimeout": "7200"
    })

    # Detailed scoring weights
    weights = {
        "passwordpolicy": 5,
        "minpasswordlength": 10,
        "minpassworddigits": 10,
        "minpasswordlower": 10,
        "minpasswordupper": 10,
        "minpasswordnonalphanum": 5,
        "maxconsecutiveidentchars": 5,
        "lockoutthreshold": 10,
        "lockoutwindow": 10,
        "lockoutduration": 10,
        "sessiontimeout": 15
    }

    try:
        # Load result from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        current_state = result.get('current_state', {})
        initial_state = result.get('initial_state', {})
        
        score = 0
        max_score = sum(weights.values())
        feedback_parts = []
        
        # Verify each setting
        for key, target_val in targets.items():
            actual_val = str(current_state.get(key, "")).strip()
            initial_val = str(initial_state.get(key, "")).strip()
            points = weights.get(key, 0)
            
            # Check for match
            if actual_val == target_val:
                score += points
                # Optional: Check if it actually changed (for feedback, not necessarily strict scoring if default happened to match)
                if actual_val != initial_val:
                    feedback_parts.append(f"✓ {key} set to {actual_val}")
                else:
                    feedback_parts.append(f"✓ {key} correct ({actual_val})")
            else:
                feedback_parts.append(f"✗ {key}: expected {target_val}, got '{actual_val}'")

        # Group feedback for readability
        password_score = sum([weights[k] for k in weights if "password" in k or "identchars" in k])
        lockout_score = sum([weights[k] for k in weights if "lockout" in k])
        session_score = weights["sessiontimeout"]
        
        current_password_score = 0
        for k in weights:
            if ("password" in k or "identchars" in k) and str(current_state.get(k, "")).strip() == targets[k]:
                current_password_score += weights[k]

        passed = score >= 60 and current_password_score >= 20 # Require at least some password settings to be correct for a pass
        
        # Formulate final feedback
        summary = f"Score: {score}/{max_score}. "
        if not passed:
            summary += "Failed to meet threshold (60 pts). "
        
        full_feedback = summary + "Details: " + ", ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": full_feedback,
            "details": {
                "current_state": current_state,
                "targets": targets
            }
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification system error: {str(e)}"
        }