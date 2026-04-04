#!/usr/bin/env python3
"""Verifier for configure_warehouse_overlay task.

Scenario: Fulfillment center pick-station overlay requiring bcWebCam to float
transparently over the WMS screen, pass raw scan data with no extra keystrokes,
and suppress accidental duplicate picks on a fast conveyor.

Scoring breakdown (100 points total):
  - Criterion 1 (34 pts): SendKeysPostfix == "" (empty — no terminating keystroke)
  - Criterion 2 (33 pts): Opacity == "0,6" (60% transparent overlay)
  - Criterion 3 (33 pts): BcGracePeriod == "1" (1-second duplicate prevention)

Pass threshold: 80 points (all 3 criteria correct scores 100).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_warehouse_overlay(traj, env_info, task_info):
    """Verify bcWebCam is configured for warehouse overlay pick-station use.

    Checks:
    1. No terminating character (SendKeysPostfix = empty string)
    2. 60% opacity overlay (Opacity = 0,6)
    3. 1-second duplicate-pick prevention (BcGracePeriod = 1)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_postfix = metadata.get('expected_send_keys_postfix', '')
    expected_opacity = metadata.get('expected_opacity', '0,6')
    expected_grace = metadata.get('expected_bc_grace_period', '1')

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('C:\\Windows\\Temp\\configure_warehouse_overlay_result.json', tmp.name)
        with open(tmp.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get('ini_exists', False):
        return {"passed": False, "score": 0, "feedback": "INI file not found on VM"}

    general = result.get('general', {})
    actual_postfix = general.get('SendKeysPostfix')
    actual_opacity = general.get('Opacity')
    actual_grace = general.get('BcGracePeriod')

    score = 0
    feedback_parts = []
    details = {}

    # Criterion 1: No terminating character (34 pts)
    # SendKeysPostfix must be empty string (or None if key absent, treated as empty)
    actual_postfix_norm = actual_postfix if actual_postfix is not None else ''
    postfix_ok = (actual_postfix_norm == expected_postfix)
    if postfix_ok:
        score += 34
        feedback_parts.append("No terminating character set correctly")
    else:
        feedback_parts.append(
            f"Wrong terminating character: got '{actual_postfix}', expected '' (empty)"
        )
    details['send_keys_postfix'] = {'actual': actual_postfix, 'expected': expected_postfix, 'ok': postfix_ok}

    # Criterion 2: 60% opacity overlay (33 pts)
    opacity_ok = (actual_opacity == expected_opacity)
    if opacity_ok:
        score += 33
        feedback_parts.append("60% opacity set correctly")
    else:
        feedback_parts.append(
            f"Wrong opacity: got '{actual_opacity}', expected '{expected_opacity}'"
        )
    details['opacity'] = {'actual': actual_opacity, 'expected': expected_opacity, 'ok': opacity_ok}

    # Criterion 3: 1-second grace period (33 pts)
    grace_ok = (actual_grace == expected_grace)
    if grace_ok:
        score += 33
        feedback_parts.append("1-second duplicate prevention set correctly")
    else:
        feedback_parts.append(
            f"Wrong grace period: got '{actual_grace}', expected '{expected_grace}'"
        )
    details['bc_grace_period'] = {'actual': actual_grace, 'expected': expected_grace, 'ok': grace_ok}

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "no_terminating_char": postfix_ok,
            "opacity_60pct": opacity_ok,
            "grace_period_1s": grace_ok
        }
    }
