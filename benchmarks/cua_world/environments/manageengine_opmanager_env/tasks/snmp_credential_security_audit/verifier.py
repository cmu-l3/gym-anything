#!/usr/bin/env python3
"""
verifier.py — SNMP Credential Security Audit

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Device 'Perimeter-Firewall-01' or IP '192.168.1.100' exists — 34 pts
  Criterion 2: SNMP credential 'netops-monitor-2024' exists in DB            — 33 pts
  Criterion 3: SNMP credential 'netops-dmz-2024' exists in DB                — 33 pts
"""

import json
import os
import re
import sys


RESULT_FILE = "/tmp/snmp_security_result.json"
PASS_THRESHOLD = 60


def _load_result():
    """Load the result JSON; return empty dict on any error."""
    if not os.path.exists(RESULT_FILE):
        return {}
    try:
        with open(RESULT_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _extract_devices(api_data):
    """
    Extract a flat list of device dicts from various OpManager API envelope shapes.
    """
    if not api_data or not isinstance(api_data, dict):
        return []
    for key in ("data", "devices", "deviceList", "result", "response"):
        val = api_data.get(key)
        if isinstance(val, list):
            return val
        if isinstance(val, dict):
            for inner_key in ("data", "devices", "deviceList"):
                inner = val.get(inner_key)
                if isinstance(inner, list):
                    return inner
    if isinstance(api_data, list):
        return api_data
    return []


def _device_display_name(d):
    if not isinstance(d, dict):
        return ""
    return str(
        d.get("displayName") or d.get("name") or d.get("deviceName") or ""
    ).strip()


def _device_ip(d):
    if not isinstance(d, dict):
        return ""
    return str(
        d.get("ipAddress") or d.get("ip") or d.get("deviceIP") or d.get("hostName") or ""
    ).strip()


# ---------------------------------------------------------------------------
# Individual criterion checks
# ---------------------------------------------------------------------------

def _check_device_exists(devices, db_raw):
    """
    Criterion 1: Device 'Perimeter-Firewall-01' or IP '192.168.1.100' exists.
    Check API device list and raw DB text.
    """
    target_name = "Perimeter-Firewall-01"
    target_ip = "192.168.1.100"

    # Check API list
    for d in devices:
        name = _device_display_name(d)
        ip = _device_ip(d)
        if name.lower() == target_name.lower() or ip == target_ip:
            return True, f"Found in API: name='{name}', ip='{ip}'"

    # Check raw DB text
    lower_db = db_raw.lower()
    if target_name.lower() in lower_db or target_ip in db_raw:
        return True, f"Found in DB raw data: '{target_name}' or '{target_ip}' present"

    return False, f"Device '{target_name}' (IP {target_ip}) not found in API or DB"


def _check_snmp_credential(db_raw, credential_name):
    """
    Criterion 2 / 3: Check that a given SNMP credential profile name / community string
    appears in the DB raw dump.
    """
    if credential_name.lower() in db_raw.lower():
        return True, f"Credential '{credential_name}' found in DB raw data"
    return False, f"Credential '{credential_name}' not found in DB raw data"


# ---------------------------------------------------------------------------
# Main verifier entry point
# ---------------------------------------------------------------------------

def verify_snmp_credential_security_audit(traj=None, env_info=None, task_info=None):
    """
    Verify the snmp_credential_security_audit task.

    Returns a dict with keys:
      passed   (bool)
      score    (int, 0-100)
      feedback (str)
      details  (list of per-criterion dicts)
    """
    # Use copy_from_env if provided (standard framework pattern)
    if env_info and 'copy_from_env' in env_info:
        result_file = (task_info or {}).get('metadata', {}).get('result_file', RESULT_FILE)
        local_path = '/tmp/snmp_security_verify_result.json'
        try:
            env_info['copy_from_env'](result_file, local_path)
            with open(local_path) as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file: {e}",
                "details": [],
            }
    else:
        result_data = _load_result()

    if not result_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file '{RESULT_FILE}' is missing or empty.",
            "details": [],
        }

    devices = _extract_devices(result_data.get("devices_api", {}))
    db_raw = result_data.get("snmp_credentials_db_raw", "") or ""
    if not isinstance(db_raw, str):
        db_raw = json.dumps(db_raw)

    criteria = []

    # --- Criterion 1: Perimeter-Firewall-01 / 192.168.1.100 device exists ---
    passed_1, msg_1 = _check_device_exists(devices, db_raw)
    criteria.append({
        "name": "Device Perimeter-Firewall-01 (192.168.1.100) added",
        "points_possible": 34,
        "points_earned": 34 if passed_1 else 0,
        "passed": passed_1,
        "detail": msg_1,
    })

    # --- Criterion 2: SNMP credential 'netops-monitor-2024' exists in DB ---
    passed_2, msg_2 = _check_snmp_credential(db_raw, "netops-monitor-2024")
    criteria.append({
        "name": "SNMP credential 'netops-monitor-2024' exists",
        "points_possible": 33,
        "points_earned": 33 if passed_2 else 0,
        "passed": passed_2,
        "detail": msg_2,
    })

    # --- Criterion 3: SNMP credential 'netops-dmz-2024' exists in DB ---
    passed_3, msg_3 = _check_snmp_credential(db_raw, "netops-dmz-2024")
    criteria.append({
        "name": "SNMP credential 'netops-dmz-2024' exists",
        "points_possible": 33,
        "points_earned": 33 if passed_3 else 0,
        "passed": passed_3,
        "detail": msg_3,
    })

    total_score = sum(c["points_earned"] for c in criteria)
    task_passed = total_score >= PASS_THRESHOLD

    feedback_lines = [
        f"Score: {total_score}/100 ({'PASS' if task_passed else 'FAIL'}, threshold={PASS_THRESHOLD})",
        "",
        "Per-criterion results:",
    ]
    for c in criteria:
        status = "PASS" if c["passed"] else "FAIL"
        feedback_lines.append(
            f"  [{status}] {c['name']} — {c['points_earned']}/{c['points_possible']} pts"
        )
        feedback_lines.append(f"         {c['detail']}")

    return {
        "passed": task_passed,
        "score": total_score,
        "feedback": "\n".join(feedback_lines),
        "details": criteria,
    }


if __name__ == "__main__":
    result = verify_snmp_credential_security_audit()
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["passed"] else 1)
