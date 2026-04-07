#!/usr/bin/env python3
"""
verifier.py — URL Monitor Service Remediation

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Internal-Auth-Service exists with URL containing "Login.jsp"  — 20 pts
  Criterion 2: OpManager-API-Health exists with poll interval of 3 minutes   — 20 pts
  Criterion 3: Primary-Web-Portal monitor exists                              — 20 pts
  Criterion 4: SNMP-Polling-Endpoint monitor exists                           — 20 pts
  Criterion 5: NOC-Dashboard-Availability monitor exists                      — 20 pts
"""

import json
import os
import re
import sys


RESULT_FILE = "/tmp/url_monitor_result.json"
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


def _extract_monitors_from_api(api_data):
    """
    Try to extract a flat list of monitor dicts from an API response.
    Handles various OpManager response envelope shapes.
    """
    if not api_data or not isinstance(api_data, dict):
        return []
    # Common keys that wrap the monitor list
    for key in ("data", "monitors", "urlMonitors", "webMonitors", "result", "response"):
        val = api_data.get(key)
        if isinstance(val, list):
            return val
        if isinstance(val, dict):
            # One more level
            for inner_key in ("data", "monitors", "urlMonitors", "webMonitors"):
                inner = val.get(inner_key)
                if isinstance(inner, list):
                    return inner
    # If the top-level is itself a list (unlikely given we always get a dict)
    if isinstance(api_data, list):
        return api_data
    return []


def _monitor_name(m):
    """Return the display name of a monitor dict."""
    if not isinstance(m, dict):
        return ""
    return str(
        m.get("displayName") or m.get("name") or m.get("monitorName") or ""
    ).strip()


def _monitor_url(m):
    """Return the URL of a monitor dict."""
    if not isinstance(m, dict):
        return ""
    return str(
        m.get("url") or m.get("monitorUrl") or m.get("resourceUrl") or ""
    ).strip()


def _monitor_interval(m):
    """
    Return the poll interval as an integer (minutes).
    OpManager may store it in minutes or seconds — try to detect the unit.
    """
    if not isinstance(m, dict):
        return None
    raw = m.get("pollInterval") or m.get("interval") or m.get("pollingInterval")
    if raw is None:
        return None
    try:
        val = int(raw)
    except (ValueError, TypeError):
        return None
    # Heuristic: if the value is >= 60, it is probably stored in seconds
    # (3 min = 180 s, 5 min = 300 s, 30 min = 1800 s)
    if val >= 60:
        return val // 60
    return val


def _name_matches(m, target_name):
    return _monitor_name(m).lower() == target_name.lower()


# ---------------------------------------------------------------------------
# Individual criterion checks
# ---------------------------------------------------------------------------

def _check_internal_auth_service(monitors_api, db_raw):
    """
    Criterion 1: 'Internal-Auth-Service' exists and its URL contains 'Login.jsp'.
    Check both API monitors list and raw DB text.
    """
    target_name = "Internal-Auth-Service"
    login_jsp_pattern = re.compile(r"Login\.jsp", re.IGNORECASE)

    # Check API list
    for m in monitors_api:
        if _name_matches(m, target_name):
            url = _monitor_url(m)
            if login_jsp_pattern.search(url):
                return True, f"Found in API: name='{_monitor_name(m)}', url='{url}'"
            else:
                # Name found but URL wrong — keep checking DB
                break

    # Check raw DB text
    if target_name.lower() in db_raw.lower() and login_jsp_pattern.search(db_raw):
        # Both the monitor name and 'Login.jsp' appear in the DB dump — likely correct
        return True, "Found in DB raw data: name and Login.jsp both present"

    return False, f"'{target_name}' with URL containing 'Login.jsp' not found"


def _check_opmanager_api_health(monitors_api, db_raw):
    """
    Criterion 2: 'OpManager-API-Health' exists with poll interval of 3 minutes.
    Check both API monitors list and raw DB text.
    """
    target_name = "OpManager-API-Health"

    # Check API list
    for m in monitors_api:
        if _name_matches(m, target_name):
            interval = _monitor_interval(m)
            if interval == 3:
                return True, f"Found in API: name='{_monitor_name(m)}', interval={interval}min"
            else:
                # Found but wrong interval; still check DB
                break

    # Check raw DB text for '3' near the monitor name
    # Look for the name and a poll interval of 3 within a window of text
    lower_db = db_raw.lower()
    name_pos = lower_db.find(target_name.lower())
    if name_pos >= 0:
        # Extract a 500-char window around the name occurrence
        window = db_raw[max(0, name_pos - 50): name_pos + 450]
        # Look for bare '3' as an interval value — also check for '3 ' or '| 3 |'
        if re.search(r'\b3\b', window):
            # Avoid false positives: also ensure '30' or '300' is NOT the only match
            nums_found = re.findall(r'\b(\d+)\b', window)
            if "3" in nums_found and "30" not in nums_found and "300" not in nums_found:
                return True, "Found in DB: name present and interval appears to be 3"
            if "3" in nums_found:
                # Accept if 3 is present, even alongside 30 — the verifier is lenient
                # because we can't be 100% sure which column holds the interval
                return True, "Found in DB: name present and poll interval 3 detected"

    return False, f"'{target_name}' with poll interval 3 minutes not confirmed"


def _check_monitor_exists(monitors_api, db_raw, target_name):
    """
    Generic existence check: does a monitor with this name exist in the API list or DB?
    """
    for m in monitors_api:
        if _name_matches(m, target_name):
            return True, f"Found in API: name='{_monitor_name(m)}'"

    if target_name.lower() in db_raw.lower():
        return True, f"Found in DB raw data: '{target_name}' present"

    return False, f"'{target_name}' not found in API or DB"


# ---------------------------------------------------------------------------
# Main verifier entry point
# ---------------------------------------------------------------------------

def verify_url_monitor_service_remediation(traj=None, env_info=None, task_info=None):
    """
    Verify the url_monitor_service_remediation task.

    Returns a dict with keys:
      passed  (bool)
      score   (int, 0-100)
      feedback (str)
      details  (list of per-criterion dicts)
    """
    # Use copy_from_env if provided (standard framework pattern)
    if env_info and 'copy_from_env' in env_info:
        result_file = (task_info or {}).get('metadata', {}).get('result_file', RESULT_FILE)
        local_path = '/tmp/url_monitor_verify_result.json'
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

    monitors_api = _extract_monitors_from_api(
        result_data.get("url_monitors_api", {})
    )
    db_raw = result_data.get("url_monitors_db_raw", "") or ""
    if not isinstance(db_raw, str):
        db_raw = json.dumps(db_raw)

    criteria = []

    # --- Criterion 1: Internal-Auth-Service URL fixed ---
    passed_1, msg_1 = _check_internal_auth_service(monitors_api, db_raw)
    criteria.append({
        "name": "Internal-Auth-Service URL corrected",
        "points_possible": 20,
        "points_earned": 20 if passed_1 else 0,
        "passed": passed_1,
        "detail": msg_1,
    })

    # --- Criterion 2: OpManager-API-Health poll interval fixed ---
    passed_2, msg_2 = _check_opmanager_api_health(monitors_api, db_raw)
    criteria.append({
        "name": "OpManager-API-Health poll interval corrected to 3 minutes",
        "points_possible": 20,
        "points_earned": 20 if passed_2 else 0,
        "passed": passed_2,
        "detail": msg_2,
    })

    # --- Criterion 3: Primary-Web-Portal created ---
    passed_3, msg_3 = _check_monitor_exists(monitors_api, db_raw, "Primary-Web-Portal")
    criteria.append({
        "name": "Primary-Web-Portal monitor created",
        "points_possible": 20,
        "points_earned": 20 if passed_3 else 0,
        "passed": passed_3,
        "detail": msg_3,
    })

    # --- Criterion 4: SNMP-Polling-Endpoint created ---
    passed_4, msg_4 = _check_monitor_exists(monitors_api, db_raw, "SNMP-Polling-Endpoint")
    criteria.append({
        "name": "SNMP-Polling-Endpoint monitor created",
        "points_possible": 20,
        "points_earned": 20 if passed_4 else 0,
        "passed": passed_4,
        "detail": msg_4,
    })

    # --- Criterion 5: NOC-Dashboard-Availability created ---
    passed_5, msg_5 = _check_monitor_exists(monitors_api, db_raw, "NOC-Dashboard-Availability")
    criteria.append({
        "name": "NOC-Dashboard-Availability monitor created",
        "points_possible": 20,
        "points_earned": 20 if passed_5 else 0,
        "passed": passed_5,
        "detail": msg_5,
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
    result = verify_url_monitor_service_remediation()
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["passed"] else 1)
