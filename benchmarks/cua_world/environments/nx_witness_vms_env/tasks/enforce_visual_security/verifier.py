#!/usr/bin/env python3
"""
Verifier for enforce_visual_security task.

Checks:
1. Visual Watermarking enabled with correct opacity and content.
2. Session Timeout enabled and set to target duration.
3. Secure connections forced.
4. Audit trail enabled.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_visual_security(traj, env_info, task_info):
    """
    Verifies that system security settings match the required policy.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_opacity_min = metadata.get('expected_opacity_min', 0.25)
    expected_opacity_max = metadata.get('expected_opacity_max', 0.45)
    expected_timeout = metadata.get('expected_timeout_seconds', 900) # 15 mins
    timeout_tolerance = metadata.get('timeout_tolerance', 60)
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract settings
    settings = result_data.get('system_settings', {})
    if not settings:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve system settings from API"}

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Visual Watermarking (45 pts total)
    # ---------------------------------------------------------
    watermark_settings = settings.get('watermarkSettings', {})
    
    # Check enabled/username
    use_username = watermark_settings.get('useUserName', False)
    if use_username:
        score += 30
        feedback.append("✅ Watermark enabled with username")
    else:
        feedback.append("❌ Watermark username not enabled")

    # Check opacity
    opacity = watermark_settings.get('opacity', 0.0)
    # Opacity in API usually float 0.0-1.0
    if expected_opacity_min <= opacity <= expected_opacity_max:
        score += 15
        feedback.append(f"✅ Opacity correct ({opacity:.2f})")
    else:
        feedback.append(f"❌ Opacity {opacity:.2f} outside range [{expected_opacity_min}-{expected_opacity_max}]")

    # ---------------------------------------------------------
    # Criterion 2: Session Timeout (25 pts)
    # ---------------------------------------------------------
    # API usually returns 0 for disabled, or seconds for enabled
    timeout_s = settings.get('sessionTimeoutS', 0)
    if timeout_s == 0:
        feedback.append("❌ Session timeout is disabled")
    else:
        diff = abs(timeout_s - expected_timeout)
        if diff <= timeout_tolerance:
            score += 25
            feedback.append(f"✅ Session timeout set to {timeout_s}s (~15m)")
        else:
            feedback.append(f"❌ Session timeout {timeout_s}s is not 15m")

    # ---------------------------------------------------------
    # Criterion 3: Secure Connection (20 pts)
    # ---------------------------------------------------------
    # Keys might vary slightly by version, checking common ones
    forced_secure = settings.get('trafficEncryptionForced', False) or settings.get('forceSecureConnection', False)
    
    if forced_secure:
        score += 20
        feedback.append("✅ HTTPS/Secure connection enforced")
    else:
        feedback.append("❌ Secure connection not forced")

    # ---------------------------------------------------------
    # Criterion 4: Audit Trail (10 pts)
    # ---------------------------------------------------------
    audit_enabled = settings.get('auditTrailEnabled', False)
    if audit_enabled:
        score += 10
        feedback.append("✅ Audit trail enabled")
    else:
        feedback.append("❌ Audit trail not enabled")

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    # Pass threshold: 70 points (Must have Watermark + Timeout at minimum)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }