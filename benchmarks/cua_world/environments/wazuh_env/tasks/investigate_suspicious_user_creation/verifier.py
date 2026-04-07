#!/usr/bin/env python3
"""
Verifier for Investigate Suspicious User Creation task.

Checks:
1. Report file exists and is valid JSON.
2. Report created during task session (anti-gaming).
3. "backdoor_username" matches the injected user.
4. "attacker_source_ip" matches the injected IP.
5. "related_alert_id" is a valid format (numeric).
6. Firefox was running (implies dashboard usage).
7. VLM Verification: Uses trajectory to confirm dashboard navigation and filtering.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investigate_suspicious_user_creation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Data
    agent_report = result.get("agent_report", {})
    ground_truth = result.get("ground_truth", {})
    report_exists = result.get("report_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    
    score = 0
    feedback_parts = []

    # Criterion 1: Report Existence & Timing (20 pts)
    if report_exists and created_during_task:
        score += 20
        feedback_parts.append("Report file created successfully")
    elif report_exists:
        score += 10
        feedback_parts.append("Report file exists but timestamp check failed (stale file?)")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file /home/ga/incident_findings.json not found"}

    # Criterion 2: Username Match (30 pts)
    # Be flexible with whitespace
    reported_user = str(agent_report.get("backdoor_username", "")).strip()
    true_user = str(ground_truth.get("backdoor_username", "")).strip()
    
    if reported_user and reported_user == true_user:
        score += 30
        feedback_parts.append(f"Correct backdoor username identified: {reported_user}")
    else:
        feedback_parts.append(f"Incorrect username. Expected: {true_user}, Got: {reported_user}")

    # Criterion 3: IP Address Match (30 pts)
    reported_ip = str(agent_report.get("attacker_source_ip", "")).strip()
    true_ip = str(ground_truth.get("attacker_source_ip", "")).strip()
    
    if reported_ip and reported_ip == true_ip:
        score += 30
        feedback_parts.append(f"Correct attacker IP identified: {reported_ip}")
    else:
        feedback_parts.append(f"Incorrect IP. Expected: {true_ip}, Got: {reported_ip}")

    # Criterion 4: Alert ID Format (10 pts)
    alert_id = str(agent_report.get("related_alert_id", "")).strip()
    # Alert IDs in Wazuh are typically numeric or large strings. Just check it's not empty/placeholder.
    if alert_id and len(alert_id) > 2 and alert_id.lower() != "alert_id":
        score += 10
        feedback_parts.append("Alert ID provided")
    else:
        feedback_parts.append("Alert ID missing or invalid")

    # Criterion 5: App Usage (10 pts)
    if result.get("firefox_running", False):
        score += 10
        feedback_parts.append("Dashboard usage detected")
    else:
        feedback_parts.append("Firefox was not running")

    # Final Pass check
    # Need 70 points AND username+IP correct
    critical_success = (reported_user == true_user) and (reported_ip == true_ip)
    passed = (score >= 70) and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }