#!/usr/bin/env python3
"""Verifier for configure_production_scanner task.

Scenario: Bosch automotive parts factory inbound goods verification using bcWebCam
on a conveyor. Parts arrive with mirrored Code 128 barcodes visible from above.
Must flip image, enable linear barcodes, use TAB for spreadsheet data entry, and
deduplicate jammed conveyor double-scans.

Scoring breakdown (100 points total):
  - Criterion 1 (25 pts): FlipBitmap == "True" (mirrored label support)
  - Criterion 2 (25 pts): BarcodeL Type != "0" (linear/Code 128 enabled)
  - Criterion 3 (25 pts): SendKeysPostfix == "{TAB}" (spreadsheet data entry)
  - Criterion 4 (25 pts): BcGracePeriod == "2" (2-second duplicate prevention)

Pass threshold: 75 points (3 of 4 criteria correct).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_production_scanner(traj, env_info, task_info):
    """Verify bcWebCam is configured for Bosch production line conveyor scanning.

    Checks:
    1. Image flip enabled for mirrored labels (FlipBitmap = True)
    2. Linear barcode scanning enabled (BarcodeL Type != 0)
    3. TAB terminating character for spreadsheet (SendKeysPostfix = {TAB})
    4. 2-second duplicate prevention for conveyor jams (BcGracePeriod = 2)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_flip = metadata.get('expected_flip_bitmap', 'True')
    expected_postfix = metadata.get('expected_send_keys_postfix', '{TAB}')
    expected_grace = metadata.get('expected_bc_grace_period', '2')

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('C:\\Windows\\Temp\\configure_production_scanner_result.json', tmp.name)
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
    actual_flip = general.get('FlipBitmap')
    actual_barcode_l = result.get('barcode_l_type')
    actual_postfix = general.get('SendKeysPostfix')
    actual_grace = general.get('BcGracePeriod')

    score = 0
    feedback_parts = []
    details = {}

    # Criterion 1: Image flip enabled (25 pts)
    flip_ok = (
        actual_flip is not None and
        actual_flip.lower() == expected_flip.lower()
    )
    if flip_ok:
        score += 25
        feedback_parts.append("Image flip (mirrored label support) enabled correctly")
    else:
        feedback_parts.append(
            f"Image flip not enabled: FlipBitmap='{actual_flip}', expected 'True'"
        )
    details['flip_bitmap'] = {'actual': actual_flip, 'expected': expected_flip, 'ok': flip_ok}

    # Criterion 2: Linear barcodes enabled (25 pts)
    linear_enabled = (
        actual_barcode_l is not None and
        actual_barcode_l != "0" and
        actual_barcode_l != ""
    )
    if linear_enabled:
        score += 25
        feedback_parts.append(f"Linear barcodes (Code 128) enabled (Type={actual_barcode_l})")
    else:
        feedback_parts.append(
            f"Linear barcodes not enabled: BarcodeL Type='{actual_barcode_l}', expected non-zero"
        )
    details['barcode_l_enabled'] = {'actual': actual_barcode_l, 'expected': 'non-zero', 'ok': linear_enabled}

    # Criterion 3: TAB terminating character (25 pts)
    postfix_ok = (actual_postfix == expected_postfix)
    if postfix_ok:
        score += 25
        feedback_parts.append("TAB terminating character set correctly")
    else:
        feedback_parts.append(
            f"Wrong terminating character: got '{actual_postfix}', expected '{expected_postfix}'"
        )
    details['send_keys_postfix'] = {'actual': actual_postfix, 'expected': expected_postfix, 'ok': postfix_ok}

    # Criterion 4: 2-second grace period (25 pts)
    grace_ok = (actual_grace == expected_grace)
    if grace_ok:
        score += 25
        feedback_parts.append("2-second duplicate prevention set correctly")
    else:
        feedback_parts.append(
            f"Wrong grace period: got '{actual_grace}', expected '{expected_grace}'"
        )
    details['bc_grace_period'] = {'actual': actual_grace, 'expected': expected_grace, 'ok': grace_ok}

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "flip_bitmap_enabled": flip_ok,
            "linear_barcodes_enabled": linear_enabled,
            "tab_terminator": postfix_ok,
            "grace_period_2s": grace_ok
        }
    }
