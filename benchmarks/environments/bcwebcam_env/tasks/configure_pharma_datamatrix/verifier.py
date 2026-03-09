#!/usr/bin/env python3
"""Verifier for configure_pharma_datamatrix task.

Scenario: EU FMD pharmaceutical compliance scanning requiring DataMatrix 2D code
support, with linear barcodes disabled to avoid false reads from drug box lot-number
labels, raw scan output for the FMD verification middleware, and deduplication.

Scoring breakdown (100 points total):
  - Criterion 1 (25 pts): BarcodeL Type == "0" (all linear barcodes disabled)
  - Criterion 2 (25 pts): BarcodeD Type != "0" (DataMatrix scanning enabled)
  - Criterion 3 (25 pts): SendKeysPostfix == "" (empty — no extra keystroke for middleware)
  - Criterion 4 (25 pts): BcGracePeriod == "1" (1-second duplicate prevention)

Pass threshold: 75 points (3 of 4 criteria correct).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_pharma_datamatrix(traj, env_info, task_info):
    """Verify bcWebCam is configured for EU FMD pharmaceutical DataMatrix scanning.

    Checks:
    1. All linear barcodes disabled (BarcodeL Type = 0)
    2. DataMatrix scanning enabled (BarcodeD Type != 0)
    3. No terminating character (SendKeysPostfix = empty)
    4. 1-second duplicate prevention (BcGracePeriod = 1)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_barcode_l = metadata.get('expected_barcode_l_type', '0')
    expected_postfix = metadata.get('expected_send_keys_postfix', '')
    expected_grace = metadata.get('expected_bc_grace_period', '1')

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('C:\\Windows\\Temp\\configure_pharma_datamatrix_result.json', tmp.name)
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
    actual_barcode_l = result.get('barcode_l_type')
    actual_barcode_d = result.get('barcode_d_type')
    actual_postfix = general.get('SendKeysPostfix')
    actual_grace = general.get('BcGracePeriod')

    score = 0
    feedback_parts = []
    details = {}

    # Criterion 1: Linear barcodes disabled (25 pts)
    linear_disabled = (actual_barcode_l == expected_barcode_l)  # must be "0"
    if linear_disabled:
        score += 25
        feedback_parts.append("Linear barcodes disabled correctly")
    else:
        feedback_parts.append(
            f"Linear barcodes not disabled: BarcodeL Type='{actual_barcode_l}', expected '0'"
        )
    details['barcode_l_disabled'] = {'actual': actual_barcode_l, 'expected': '0', 'ok': linear_disabled}

    # Criterion 2: DataMatrix enabled (25 pts)
    # BarcodeD Type must be non-zero (any non-zero value means DataMatrix enabled)
    datamatrix_enabled = (
        actual_barcode_d is not None and
        actual_barcode_d != "0" and
        actual_barcode_d != ""
    )
    if datamatrix_enabled:
        score += 25
        feedback_parts.append(f"DataMatrix enabled correctly (Type={actual_barcode_d})")
    else:
        feedback_parts.append(
            f"DataMatrix not enabled: BarcodeD Type='{actual_barcode_d}', expected non-zero"
        )
    details['datamatrix_enabled'] = {'actual': actual_barcode_d, 'expected': 'non-zero', 'ok': datamatrix_enabled}

    # Criterion 3: No terminating character (25 pts)
    actual_postfix_norm = actual_postfix if actual_postfix is not None else ''
    postfix_ok = (actual_postfix_norm == expected_postfix)
    if postfix_ok:
        score += 25
        feedback_parts.append("No terminating character set correctly")
    else:
        feedback_parts.append(
            f"Wrong terminating character: got '{actual_postfix}', expected '' (empty)"
        )
    details['send_keys_postfix'] = {'actual': actual_postfix, 'expected': expected_postfix, 'ok': postfix_ok}

    # Criterion 4: 1-second grace period (25 pts)
    grace_ok = (actual_grace == expected_grace)
    if grace_ok:
        score += 25
        feedback_parts.append("1-second duplicate prevention set correctly")
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
            "linear_barcodes_disabled": linear_disabled,
            "datamatrix_enabled": datamatrix_enabled,
            "no_terminating_char": postfix_ok,
            "grace_period_1s": grace_ok
        }
    }
