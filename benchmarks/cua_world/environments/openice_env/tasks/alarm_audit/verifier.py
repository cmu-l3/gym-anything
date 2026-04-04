#!/usr/bin/env python3
"""Verifier for alarm_audit task in OpenICE.

Realistic scenario: Patient safety officer auditing ICU alarm configuration
to investigate nursing alarm fatigue complaint.

Scoring (100 points):
- Device adapter created (20 pts)
- Clinical app launched for alarm investigation (15 pts)
- Report exists with alarm terminology (20 pts)
- Report mentions specific vital sign parameters - HR, SpO2, RR (20 pts: up to 7+7+6)
- Report contains numeric threshold values (10 pts)
- Report has specific recommendations with numeric values (15 pts)

GATE: If report doesn't exist AND score would exceed threshold -> cap at threshold-1.
Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REPORT_PATH = "/home/ga/Desktop/alarm_audit.txt"


def verify_alarm_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = result.get('task_start_timestamp', 0)
    report_exists = result.get('report_exists', 0)
    report_mtime = result.get('report_mtime', 0)
    report_size = result.get('report_size', 0)
    report_modified_after_start = int(report_mtime) > task_start

    # Criterion 1: Device adapter created (20 pts)
    any_device = result.get('any_device_created', 0)
    monitor_device = result.get('monitor_device_created', 0)
    window_increase = result.get('window_increase', 0)

    if monitor_device:
        score += 20
        subscores['device_created'] = 20
        feedback_parts.append("Monitoring device adapter created")
    elif any_device or window_increase > 0:
        score += 12
        subscores['device_created'] = 12
        feedback_parts.append("Device adapter created (type unconfirmed)")
    else:
        subscores['device_created'] = 0
        feedback_parts.append("No device adapter detected")

    # Criterion 2: Clinical app launched (15 pts)
    any_app = result.get('any_app_launched', 0)
    alarm_app = result.get('alarm_app_launched', 0)
    if alarm_app:
        score += 15
        subscores['app_launched'] = 15
        feedback_parts.append("Alarm-specific clinical app launched")
    elif any_app:
        score += 10
        subscores['app_launched'] = 10
        feedback_parts.append("A clinical app was launched")
    else:
        subscores['app_launched'] = 0
        feedback_parts.append("No clinical app detected as launched")

    # Criterion 3: Report exists with alarm terminology (20 pts)
    has_alarm_terms = result.get('report_has_alarm_terms', 0)
    if report_exists and report_modified_after_start and has_alarm_terms and report_size >= 200:
        score += 20
        subscores['report_alarm_content'] = 20
        feedback_parts.append(f"Alarm audit report exists with alarm terminology ({report_size} bytes)")
    elif report_exists and has_alarm_terms:
        score += 12
        subscores['report_alarm_content'] = 12
        feedback_parts.append("Report exists with alarm terms (timestamp or size concern)")
    elif report_exists and report_size >= 100:
        score += 6
        subscores['report_alarm_content'] = 6
        feedback_parts.append("Report exists but lacks alarm-specific terminology")
    else:
        subscores['report_alarm_content'] = 0
        feedback_parts.append("Alarm audit report not found at /home/ga/Desktop/alarm_audit.txt")

    # Criterion 4: Specific vital sign parameters mentioned (20 pts)
    has_hr = result.get('report_has_hr', 0)
    has_spo2 = result.get('report_has_spo2', 0)
    has_rr = result.get('report_has_rr', 0)
    param_score = (has_hr * 7) + (has_spo2 * 7) + (has_rr * 6)
    score += param_score
    subscores['vital_sign_params'] = param_score
    params_found = has_hr + has_spo2 + has_rr
    if params_found >= 3:
        feedback_parts.append("Report mentions all required parameters (HR, SpO2, RR)")
    elif params_found == 2:
        feedback_parts.append(f"Report mentions {params_found}/3 vital sign parameters")
    elif params_found == 1:
        feedback_parts.append("Report mentions only 1 vital sign parameter")
    else:
        feedback_parts.append("Report does not name specific vital sign parameters")

    # Criterion 5: Numeric threshold values present (10 pts)
    has_numeric = result.get('report_has_numeric', 0)
    if has_numeric and report_exists:
        score += 10
        subscores['numeric_thresholds'] = 10
        feedback_parts.append("Report contains numeric values (thresholds)")
    else:
        subscores['numeric_thresholds'] = 0
        feedback_parts.append("Report lacks numeric threshold values")

    # Criterion 6: Evidence-based recommendations (15 pts)
    has_recs = result.get('report_has_recommendations', 0)
    if has_recs and report_exists:
        score += 15
        subscores['recommendations'] = 15
        feedback_parts.append("Report contains specific threshold recommendations")
    else:
        subscores['recommendations'] = 0
        feedback_parts.append("Report lacks specific recommendations")

    # GATE: Report is required deliverable - cap score if missing
    if not report_exists and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD-1}: alarm audit report is a required deliverable")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "debug": {
            "device_created": any_device,
            "app_launched": any_app,
            "report_exists": report_exists,
            "report_size": report_size,
            "params_found": params_found,
            "has_recommendations": has_recs
        }
    }
