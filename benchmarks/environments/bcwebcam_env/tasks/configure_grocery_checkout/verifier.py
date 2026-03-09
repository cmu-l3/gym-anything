#!/usr/bin/env python3
"""Verifier for configure_grocery_checkout task.

Scoring breakdown (100 points total):
  - Criterion 1 (34 pts): SendKeysPostfix == "{TAB}"
  - Criterion 2 (33 pts): BcGracePeriod == "3"
  - Criterion 3 (33 pts): Beep == "False"

Pass threshold: 80 points (all 3 criteria correct scores 100).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_grocery_checkout(traj, env_info, task_info):
    """Verify bcWebCam is configured for NCR POS grocery checkout.

    Checks:
    1. TAB terminating character (SendKeysPostfix = {TAB})
    2. 3-second duplicate prevention (BcGracePeriod = 3)
    3. Acoustic beep disabled (Beep = False)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_postfix = metadata.get('expected_send_keys_postfix', '{TAB}')
    expected_grace = metadata.get('expected_bc_grace_period', '3')
    expected_beep = metadata.get('expected_beep', 'False')

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('C:\\Windows\\Temp\\configure_grocery_checkout_result.json', tmp.name)
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
    actual_grace = general.get('BcGracePeriod')
    actual_beep = general.get('Beep')

    score = 0
    feedback_parts = []
    details = {}

    # Criterion 1: TAB terminating character (34 pts)
    postfix_ok = (actual_postfix == expected_postfix)
    if postfix_ok:
        score += 34
        feedback_parts.append("TAB terminating character set correctly")
    else:
        feedback_parts.append(
            f"Wrong terminating character: got '{actual_postfix}', expected '{expected_postfix}'"
        )
    details['send_keys_postfix'] = {'actual': actual_postfix, 'expected': expected_postfix, 'ok': postfix_ok}

    # Criterion 2: 3-second grace period (33 pts)
    grace_ok = (actual_grace == expected_grace)
    if grace_ok:
        score += 33
        feedback_parts.append("3-second duplicate prevention set correctly")
    else:
        feedback_parts.append(
            f"Wrong grace period: got '{actual_grace}', expected '{expected_grace}'"
        )
    details['bc_grace_period'] = {'actual': actual_grace, 'expected': expected_grace, 'ok': grace_ok}

    # Criterion 3: Beep disabled (33 pts)
    beep_ok = (actual_beep is not None and actual_beep.lower() == expected_beep.lower())
    if beep_ok:
        score += 33
        feedback_parts.append("Acoustic beep disabled correctly")
    else:
        feedback_parts.append(
            f"Wrong beep setting: got '{actual_beep}', expected '{expected_beep}'"
        )
    details['beep'] = {'actual': actual_beep, 'expected': expected_beep, 'ok': beep_ok}

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "tab_terminator": postfix_ok,
            "grace_period_3s": grace_ok,
            "beep_disabled": beep_ok
        }
    }
