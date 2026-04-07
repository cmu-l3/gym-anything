#!/usr/bin/env python3
"""Verifier for alert_escalation_profile_setup task."""
import json


def _find_profile(db_raw, api_data, name, email=None):
    """Return True if a notification profile matching name (and optionally email) is found
    in either the DB raw dump or the API response JSON."""
    name_lower = name.lower()

    # Check DB raw text
    if db_raw:
        db_text = db_raw.lower()
        name_in_db = name_lower in db_text
        if email:
            email_in_db = email.lower() in db_text
            if name_in_db and email_in_db:
                return True
        else:
            if name_in_db:
                return True

    # Check API JSON
    if api_data:
        api_text = json.dumps(api_data).lower()
        name_in_api = name_lower in api_text
        if email:
            email_in_api = email.lower() in api_text
            if name_in_api and email_in_api:
                return True
        else:
            if name_in_api:
                return True

    return False


def verify_alert_escalation_profile_setup(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', '/tmp/alert_escalation_result.json')
    local_path = '/tmp/alert_escalation_verify_result.json'

    try:
        env_info['copy_from_env'](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Could not retrieve result file: {e}. "
                "Check that export_result.sh ran successfully."
            )
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    db_raw   = data.get("notification_profiles_db_raw", "")
    api_data = data.get("notification_profiles_api", {})

    score = 0
    details = []

    # Criterion 1: L1-Operations-Alert with email ops-l1@company.internal (34 pts)
    if _find_profile(db_raw, api_data, "L1-Operations-Alert", "ops-l1@company.internal"):
        score += 34
        details.append("PASS: Profile 'L1-Operations-Alert' with email 'ops-l1@company.internal' found (+34)")
    else:
        details.append("FAIL: Profile 'L1-Operations-Alert' / 'ops-l1@company.internal' not found (0/34)")

    # Criterion 2: L2-NOC-Escalation with email noc-escalation@company.internal (33 pts)
    if _find_profile(db_raw, api_data, "L2-NOC-Escalation", "noc-escalation@company.internal"):
        score += 33
        details.append("PASS: Profile 'L2-NOC-Escalation' with email 'noc-escalation@company.internal' found (+33)")
    else:
        details.append("FAIL: Profile 'L2-NOC-Escalation' / 'noc-escalation@company.internal' not found (0/33)")

    # Criterion 3: L3-Management-Notify with email it-management@company.internal (33 pts)
    if _find_profile(db_raw, api_data, "L3-Management-Notify", "it-management@company.internal"):
        score += 33
        details.append("PASS: Profile 'L3-Management-Notify' with email 'it-management@company.internal' found (+33)")
    else:
        details.append("FAIL: Profile 'L3-Management-Notify' / 'it-management@company.internal' not found (0/33)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }
