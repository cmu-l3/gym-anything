#!/usr/bin/env python3
"""
verifier.py — L1 Diagnostic Workflow Automation

Scoring (100 pts total, pass threshold 75):
  - Workflow 'L1-Automated-Triage' exists (50 pts)
  - Ping action included (25 pts)
  - Traceroute action included (25 pts)
"""

import json
import os

def verify_l1_diagnostic_workflow_automation(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/workflow_automation_result.json")
    local_path = "/tmp/workflow_automation_verify_result.json"

    # 1. Retrieve the result file
    try:
        env_info["copy_from_env"](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file '{result_file}': {e}."
        }

    # 2. Parse the result file
    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result file: {e}"
        }

    wf_api = data.get("workflow_api", {})
    wf_db_raw = data.get("workflow_db_raw", "")

    # Convert everything to lower case for case-insensitive searching
    api_text = json.dumps(wf_api).lower()
    db_text = wf_db_raw.lower()
    combined_text = api_text + " \n " + db_text

    target_name = "l1-automated-triage"
    action_ping = "ping"
    action_traceroute = "trace route"
    action_traceroute_alt = "traceroute"

    score = 0
    details = []

    # Criterion 1: Workflow Name Exists
    name_exists = (target_name in combined_text)
    if name_exists:
        score += 50
        details.append("PASS: Workflow 'L1-Automated-Triage' found (+50)")
    else:
        details.append("FAIL: Workflow 'L1-Automated-Triage' not found in database or API (0/50)")

    # Criteria 2 & 3: Actions exist
    # To prevent false positives from generic DB fields, we ensure the name exists first,
    # OR we look closely around the name in the DB dump. Given the specific context,
    # simply checking for the action keywords within the dump where the workflow was found is usually sufficient.
    # We will enforce that the workflow name MUST exist to get credit for actions.
    if name_exists:
        # We try to extract a window around the workflow name to ensure actions are related to it
        # If it's a small DB, it might be safe to just check global text. But windowing is safer.
        idx = combined_text.find(target_name)
        window_start = max(0, idx - 5000)
        window_end = min(len(combined_text), idx + 5000)
        window_text = combined_text[window_start:window_end]

        # Ping
        if action_ping in window_text:
            score += 25
            details.append("PASS: 'Ping' action block found linked to workflow (+25)")
        else:
            details.append("FAIL: 'Ping' action block not found (0/25)")

        # Traceroute
        if action_traceroute in window_text or action_traceroute_alt in window_text:
            score += 25
            details.append("PASS: 'Trace Route' / 'Traceroute' action block found linked to workflow (+25)")
        else:
            details.append("FAIL: 'Trace Route' action block not found (0/25)")
    else:
        details.append("SKIP: Action checks skipped because target workflow was not created.")

    passed = (score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }