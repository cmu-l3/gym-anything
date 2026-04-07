#!/usr/bin/env python3
"""Verifier for noc_monitoring_gap_remediation task."""
import json
import re


def _find_group(groups_data, name):
    """Return True if a group with the given name exists anywhere in the JSON structure."""
    name_lower = name.lower()
    text = json.dumps(groups_data).lower()
    # Check for exact name match (allowing for JSON encoding)
    return name_lower in text


def _find_url_monitor(monitors_data, name=None, url=None):
    """Return True if a URL monitor matching name or url exists."""
    text = json.dumps(monitors_data).lower()
    if name and name.lower() in text:
        return True
    if url and url.lower() in text:
        return True
    return False


def _find_notif_profile(notif_raw, name, email=None):
    """Return True if notification profile with given name (and optionally email) exists in DB raw output."""
    if not notif_raw:
        return False
    text = notif_raw.lower()
    name_found = name.lower() in text
    if email:
        email_found = email.lower() in text
        return name_found and email_found
    return name_found


def verify_noc_monitoring_gap_remediation(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', '/tmp/noc_monitoring_result.json')
    local_path = '/tmp/noc_monitoring_verify_result.json'

    try:
        env_info['copy_from_env'](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Check that export_result.sh ran successfully."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    score = 0
    details = []

    groups = data.get("groups_api", {})
    monitors = data.get("url_monitors_api", {})
    notif_raw = data.get("notification_profiles_db_raw", "")

    # Criterion 1: "Core-Network-Infrastructure" group exists (20 pts)
    if _find_group(groups, "Core-Network-Infrastructure"):
        score += 20
        details.append("PASS: Device group 'Core-Network-Infrastructure' exists (+20)")
    else:
        details.append("FAIL: Device group 'Core-Network-Infrastructure' not found (0/20)")

    # Criterion 2: "Production-Application-Servers" group exists (20 pts)
    if _find_group(groups, "Production-Application-Servers"):
        score += 20
        details.append("PASS: Device group 'Production-Application-Servers' exists (+20)")
    else:
        details.append("FAIL: Device group 'Production-Application-Servers' not found (0/20)")

    # Criterion 3: "DMZ-Security-Perimeter" group exists (20 pts)
    if _find_group(groups, "DMZ-Security-Perimeter"):
        score += 20
        details.append("PASS: Device group 'DMZ-Security-Perimeter' exists (+20)")
    else:
        details.append("FAIL: Device group 'DMZ-Security-Perimeter' not found (0/20)")

    # Criterion 4: URL monitor "OpManager-Self-Monitor" exists with correct URL (20 pts)
    monitor_ok = _find_url_monitor(monitors, name="OpManager-Self-Monitor") or \
                 _find_url_monitor(monitors, url="localhost:8060") or \
                 "opmanager-self-monitor" in json.dumps(monitors).lower()
    if monitor_ok:
        score += 20
        details.append("PASS: URL monitor 'OpManager-Self-Monitor' found (+20)")
    else:
        details.append("FAIL: URL monitor 'OpManager-Self-Monitor' not found (0/20)")

    # Criterion 5: Notification profile "NOC-24x7-Critical-Alert" with email (20 pts)
    notif_ok = _find_notif_profile(notif_raw, "NOC-24x7-Critical-Alert", "noc-oncall@company.internal")
    # Also check API response if present
    notif_api = data.get("notification_profiles_api", {})
    if not notif_ok and notif_api:
        notif_ok = "noc-24x7-critical-alert" in json.dumps(notif_api).lower()
    if notif_ok:
        score += 20
        details.append("PASS: Notification profile 'NOC-24x7-Critical-Alert' with correct email found (+20)")
    else:
        details.append("FAIL: Notification profile 'NOC-24x7-Critical-Alert' not found or wrong email (0/20)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }
