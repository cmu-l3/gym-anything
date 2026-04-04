#!/usr/bin/env python3
"""
Verifier for investigate_brute_force_incident

Scoring (100 points total):
- Report file exists and was created after task start: 30 points
- Report contains correct targeted username 'serviceacct': 25 points
- Report contains correct attacker IP '192.168.10.45': 25 points
- New alert profile created in ELA: 20 points

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_investigate_brute_force_incident(traj, env_info, task_info):
    """Verify brute force incident investigation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_username = metadata.get('targeted_username', 'serviceacct')
    expected_ip = metadata.get('attacker_ip', '192.168.10.45')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/investigate_brute_force_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = result.get('task_start', 0)

    # --- Criterion 1: Report file exists and was modified after task start (30 pts) ---
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_size = result.get('report_size', 0)

    if report_exists and int(report_mtime) > int(task_start) and report_size > 50:
        score += 30
        subscores['report_created'] = True
        feedback_parts.append(f"Incident report created ({report_size} bytes)")
    elif report_exists and report_size > 50:
        # File exists but mtime suggests it's stale — partial credit
        score += 10
        subscores['report_created'] = False
        feedback_parts.append("Report file exists but not created during this task session")
    else:
        subscores['report_created'] = False
        feedback_parts.append("Incident report not found at ~/Desktop/incident_report.txt")

    # --- Criterion 2: Correct targeted username identified (25 pts) ---
    if result.get('has_serviceacct', False):
        score += 25
        subscores['correct_username'] = True
        feedback_parts.append(f"Correct targeted username '{expected_username}' identified")
    else:
        subscores['correct_username'] = False
        feedback_parts.append(f"Report does not identify '{expected_username}' as the targeted account")

    # --- Criterion 3: Correct attacker IP identified (25 pts) ---
    if result.get('has_attacker_ip', False):
        score += 25
        subscores['correct_ip'] = True
        feedback_parts.append(f"Correct attacker IP '{expected_ip}' identified")
    else:
        subscores['correct_ip'] = False
        feedback_parts.append(f"Report does not identify '{expected_ip}' as the attack source")

    # --- Criterion 4: New alert profile created in ELA (20 pts) ---
    if result.get('alert_created', False):
        score += 20
        subscores['alert_created'] = True
        feedback_parts.append("New alert profile created in EventLog Analyzer")
    else:
        subscores['alert_created'] = False
        new_count = result.get('new_alert_count', 0)
        feedback_parts.append(f"No new alert profile detected in ELA (new_count={new_count})")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "task_start": task_start,
            "report_mtime": report_mtime,
            "report_size": report_size,
            "initial_alerts": result.get('initial_alert_count', 0),
            "current_alerts": result.get('current_alert_count', 0),
        }
    }
