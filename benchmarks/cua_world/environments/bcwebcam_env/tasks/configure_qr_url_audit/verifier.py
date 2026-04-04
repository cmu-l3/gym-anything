#!/usr/bin/env python3
"""Verifier for configure_qr_url_audit task.

Scenario: Hospital biomedical engineering audit using GS1 Digital Link QR codes.
Each medical device QR encodes a URL to regulatory documentation. bcWebCam must
auto-open URLs, operate silently, pass raw QR payloads, remain semi-transparent
behind the browser, and ignore all 1D barcodes.

Scoring breakdown (100 points total):
  - Criterion 1 (25 pts): URL auto-open enabled (any URL-related General key is True)
  - Criterion 2 (20 pts): Beep == "False" (silent hospital operation)
  - Criterion 3 (20 pts): SendKeysPostfix == "" (no extra keystroke for URL payload)
  - Criterion 4 (20 pts): Opacity == "0,7" (70% — browser visible behind scanner)
  - Criterion 5 (15 pts): BarcodeL Type == "0" (all linear barcodes disabled)

Pass threshold: 60 points (3 of 5 criteria correct).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# All known candidate INI key names for URL auto-open in bcWebCam
_URL_KEY_CANDIDATES = {
    'openurl', 'opendetectedurl', 'opendetectedurl', 'urlopen', 'openurl',
    'openurldetected', 'autourl', 'urlauto', 'openlink', 'autoopen'
}


def _url_open_enabled(general: dict) -> tuple:
    """Check whether any URL-open INI key is set to True.

    Returns (enabled: bool, key_found: str or None, value_found: str or None).
    Checks all keys in `general` for known URL-open candidate names.
    """
    for key, val in general.items():
        if key is None or val is None:
            continue
        if key.lower() in _URL_KEY_CANDIDATES and val.lower() == 'true':
            return True, key, val

    return False, None, None


def verify_configure_qr_url_audit(traj, env_info, task_info):
    """Verify bcWebCam is configured for hospital GS1 Digital Link QR audit.

    Checks:
    1. URL auto-open enabled (any URL-related INI key = True)
    2. Beep disabled (Beep = False)
    3. No terminating character (SendKeysPostfix = empty)
    4. 70% opacity window (Opacity = 0,7)
    5. Linear barcodes disabled (BarcodeL Type = 0)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_beep = metadata.get('expected_beep', 'False')
    expected_postfix = metadata.get('expected_send_keys_postfix', '')
    expected_opacity = metadata.get('expected_opacity', '0,7')
    expected_barcode_l = metadata.get('expected_barcode_l_type', '0')

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('C:\\Windows\\Temp\\configure_qr_url_audit_result.json', tmp.name)
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
    actual_beep = general.get('Beep')
    actual_postfix = general.get('SendKeysPostfix')
    actual_opacity = general.get('Opacity')
    actual_barcode_l = result.get('barcode_l_type')

    score = 0
    feedback_parts = []
    details = {}

    # Criterion 1: URL auto-open enabled (25 pts)
    url_enabled, url_key, url_val = _url_open_enabled(general)
    if url_enabled:
        score += 25
        feedback_parts.append(f"URL auto-open enabled correctly (key={url_key})")
    else:
        feedback_parts.append("URL auto-open not enabled: no URL-related key found set to True")
    details['url_open'] = {'enabled': url_enabled, 'key_found': url_key, 'value': url_val}

    # Criterion 2: Beep disabled (20 pts)
    beep_ok = (
        actual_beep is not None and
        actual_beep.lower() == expected_beep.lower()
    )
    if beep_ok:
        score += 20
        feedback_parts.append("Acoustic beep disabled correctly")
    else:
        feedback_parts.append(
            f"Wrong beep setting: got '{actual_beep}', expected '{expected_beep}'"
        )
    details['beep'] = {'actual': actual_beep, 'expected': expected_beep, 'ok': beep_ok}

    # Criterion 3: No terminating character (20 pts)
    actual_postfix_norm = actual_postfix if actual_postfix is not None else ''
    postfix_ok = (actual_postfix_norm == expected_postfix)
    if postfix_ok:
        score += 20
        feedback_parts.append("No terminating character set correctly")
    else:
        feedback_parts.append(
            f"Wrong terminating character: got '{actual_postfix}', expected '' (empty)"
        )
    details['send_keys_postfix'] = {'actual': actual_postfix, 'expected': expected_postfix, 'ok': postfix_ok}

    # Criterion 4: 70% opacity (20 pts)
    opacity_ok = (actual_opacity == expected_opacity)
    if opacity_ok:
        score += 20
        feedback_parts.append("70% opacity set correctly")
    else:
        feedback_parts.append(
            f"Wrong opacity: got '{actual_opacity}', expected '{expected_opacity}'"
        )
    details['opacity'] = {'actual': actual_opacity, 'expected': expected_opacity, 'ok': opacity_ok}

    # Criterion 5: Linear barcodes disabled (15 pts)
    linear_disabled = (actual_barcode_l == expected_barcode_l)
    if linear_disabled:
        score += 15
        feedback_parts.append("Linear barcodes disabled correctly")
    else:
        feedback_parts.append(
            f"Linear barcodes not disabled: BarcodeL Type='{actual_barcode_l}', expected '0'"
        )
    details['barcode_l_disabled'] = {'actual': actual_barcode_l, 'expected': '0', 'ok': linear_disabled}

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "url_open_enabled": url_enabled,
            "beep_disabled": beep_ok,
            "no_terminating_char": postfix_ok,
            "opacity_70pct": opacity_ok,
            "linear_barcodes_disabled": linear_disabled
        }
    }
