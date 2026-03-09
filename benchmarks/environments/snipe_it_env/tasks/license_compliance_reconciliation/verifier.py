#!/usr/bin/env python3
"""Verifier for license_compliance_reconciliation task.

Scoring breakdown (100 points):
  C1: MS365 seats updated to 35 (12 pts)
  C2: MS365 cost updated to ~$9,240 (12 pts)
  C3: Adobe CC seats updated to 15 (12 pts)
  C4: Adobe CC cost updated to ~$9,898.20 (12 pts)
  C5: Win11 expiration updated to 2028-06-01 (12 pts)
  C6: Win11 order number updated to PO-2025-0550-EXT (8 pts)
  C7: New Slack license created with correct details (20 pts)
  C8: No other licenses inadvertently modified (12 pts)
"""

import json
import math
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/license_compliance_reconciliation_result.json"


def verify_license_compliance_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    ms365 = result.get("ms365", {})
    adobe = result.get("adobe_cc", {})
    win11 = result.get("win11", {})
    slack = result.get("slack", {})

    # --- Do-nothing gate ---
    changes = 0
    if int(ms365.get("current_seats", 50)) != int(ms365.get("initial_seats", 50)):
        changes += 1
    if int(adobe.get("current_seats", 10)) != int(adobe.get("initial_seats", 10)):
        changes += 1
    if win11.get("current_expiry", "") != win11.get("initial_expiry", ""):
        changes += 1
    if slack.get("found"):
        changes += 1
    if changes == 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No licenses were modified or created."}

    # --- C1: MS365 seats = 35 (12 pts) ---
    try:
        ms365_seats = int(ms365.get("current_seats", 0))
    except (ValueError, TypeError):
        ms365_seats = 0
    if ms365_seats == 35:
        score += 12
        feedback.append("C1: MS365 seats correctly set to 35 (+12)")
    else:
        feedback.append(f"C1: MS365 seats = {ms365_seats}, expected 35 (+0)")

    # --- C2: MS365 cost ~ $9,240 (12 pts) ---
    try:
        ms365_cost = float(ms365.get("current_cost", 0))
    except (ValueError, TypeError):
        ms365_cost = 0.0
    if math.isclose(ms365_cost, 9240.00, abs_tol=50.0):
        score += 12
        feedback.append("C2: MS365 cost correctly set to ~$9,240 (+12)")
    else:
        feedback.append(f"C2: MS365 cost = ${ms365_cost}, expected ~$9,240 (+0)")

    # --- C3: Adobe CC seats = 15 (12 pts) ---
    try:
        adobe_seats = int(adobe.get("current_seats", 0))
    except (ValueError, TypeError):
        adobe_seats = 0
    if adobe_seats == 15:
        score += 12
        feedback.append("C3: Adobe CC seats correctly set to 15 (+12)")
    else:
        feedback.append(f"C3: Adobe CC seats = {adobe_seats}, expected 15 (+0)")

    # --- C4: Adobe CC cost ~ $9,898.20 (12 pts) ---
    try:
        adobe_cost = float(adobe.get("current_cost", 0))
    except (ValueError, TypeError):
        adobe_cost = 0.0
    if math.isclose(adobe_cost, 9898.20, abs_tol=50.0):
        score += 12
        feedback.append("C4: Adobe CC cost correctly set to ~$9,898.20 (+12)")
    else:
        feedback.append(f"C4: Adobe CC cost = ${adobe_cost}, expected ~$9,898.20 (+0)")

    # --- C5: Win11 expiration = 2028-06-01 (12 pts) ---
    win11_expiry = win11.get("current_expiry", "")
    if "2028-06-01" in win11_expiry:
        score += 12
        feedback.append("C5: Win11 expiration correctly set to 2028-06-01 (+12)")
    else:
        feedback.append(f"C5: Win11 expiration = '{win11_expiry}', expected '2028-06-01' (+0)")

    # --- C6: Win11 order number (8 pts) ---
    win11_order = win11.get("current_order", "")
    if "PO-2025-0550-EXT" in win11_order:
        score += 8
        feedback.append("C6: Win11 order number correctly updated (+8)")
    else:
        feedback.append(f"C6: Win11 order = '{win11_order}', expected 'PO-2025-0550-EXT' (+0)")

    # --- C7: New Slack license (20 pts) ---
    c7_score = 0
    if slack.get("found"):
        c7_score += 5
        feedback.append("C7a: Slack license exists (+5)")

        try:
            slack_seats = int(slack.get("seats", 0))
        except (ValueError, TypeError):
            slack_seats = 0
        if slack_seats == 20:
            c7_score += 5
            feedback.append("C7b: Slack seats = 20 (+5)")
        else:
            feedback.append(f"C7b: Slack seats = {slack_seats}, expected 20 (+0)")

        slack_serial = slack.get("serial", "")
        if "SLACK-BP-2025-001" in slack_serial:
            c7_score += 5
            feedback.append("C7c: Slack serial correct (+5)")
        else:
            feedback.append(f"C7c: Slack serial = '{slack_serial}', expected 'SLACK-BP-2025-001' (+0)")

        try:
            slack_cost = float(slack.get("cost", 0))
        except (ValueError, TypeError):
            slack_cost = 0.0
        if math.isclose(slack_cost, 3000.00, abs_tol=50.0):
            c7_score += 5
            feedback.append("C7d: Slack cost correct (+5)")
        else:
            feedback.append(f"C7d: Slack cost = ${slack_cost}, expected ~$3,000 (+0)")
    else:
        feedback.append("C7: Slack license not found (+0)")
    score += c7_score

    # --- C8: No unexpected license changes (12 pts) ---
    initial_total = int(result.get("initial_total_licenses", 3))
    current_total = int(result.get("current_total_licenses", 3))
    expected_total = initial_total + (1 if slack.get("found") else 0)
    if current_total == expected_total:
        score += 12
        feedback.append("C8: No unexpected licenses created or deleted (+12)")
    elif current_total > expected_total:
        feedback.append(f"C8: Extra licenses created (was {initial_total}, now {current_total}) (+0)")
    else:
        feedback.append(f"C8: Licenses deleted (was {initial_total}, now {current_total}) (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
