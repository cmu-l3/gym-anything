#!/usr/bin/env python3
"""Verifier for fault_tolerance_test task in OpenICE.

Realistic scenario: Biomedical engineer testing device fault tolerance
before ICU deployment - creates redundant monitors, simulates failure,
verifies continuity, recovers, and documents findings.

Scoring (100 points):
- Initial dual device setup (20 pts): 2+ Multiparameter Monitor instances created
- Vital Signs app launched (15 pts)
- Device failure simulated (20 pts): evidence a device was stopped/closed
- Device recovery (20 pts): replacement device created after stop
- Fault tolerance report exists (15 pts): with meaningful content
- Report quality (10 pts): mentions failure + recovery + assessment

GATE: If report doesn't exist AND score >= threshold -> cap at threshold-1.
Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REPORT_PATH = "/home/ga/Desktop/fault_tolerance_report.txt"


def verify_fault_tolerance_test(traj, env_info, task_info):
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
    mp_count = result.get('multiparameter_create_count', 0)
    window_increase = result.get('window_increase', 0)

    # Criterion 1: Initial dual device setup (20 pts)
    two_devices = result.get('two_devices_created', 0)
    if two_devices or mp_count >= 2:
        score += 20
        subscores['dual_device_setup'] = 20
        feedback_parts.append(f"Dual Multiparameter Monitor setup confirmed ({mp_count} creation events)")
    elif result.get('any_device_created', 0) or window_increase >= 1:
        score += 10
        subscores['dual_device_setup'] = 10
        feedback_parts.append("Some devices created (dual setup not fully confirmed)")
    else:
        subscores['dual_device_setup'] = 0
        feedback_parts.append("No device adapters detected")

    # Criterion 2: Vital Signs app launched (15 pts)
    vital_signs = result.get('vital_signs_launched', 0)
    if vital_signs:
        score += 15
        subscores['vital_signs_app'] = 15
        feedback_parts.append("Vital Signs clinical app launched")
    else:
        subscores['vital_signs_app'] = 0
        feedback_parts.append("Vital Signs app not detected as launched")

    # Criterion 3: Device failure simulated (20 pts)
    device_stopped = result.get('device_stopped', 0)
    # Additional check: if 2+ devices created but final window count didn't increase by 2,
    # a device was likely closed
    if device_stopped:
        score += 20
        subscores['device_failure'] = 20
        feedback_parts.append("Device failure simulation detected (device stopped)")
    elif mp_count >= 2 and window_increase < 2:
        score += 12
        subscores['device_failure'] = 12
        feedback_parts.append("Device stop likely (2 created, window count suggests one closed)")
    else:
        subscores['device_failure'] = 0
        feedback_parts.append("No evidence of device failure simulation")

    # Criterion 4: Device recovery (20 pts)
    device_recovery = result.get('device_recovery', 0)
    report_has_recovery = result.get('report_has_recovery', 0)
    if device_recovery:
        score += 20
        subscores['device_recovery'] = 20
        feedback_parts.append(f"Device recovery confirmed ({mp_count} creation events = initial 2 + replacement)")
    elif report_has_recovery and report_exists:
        score += 10
        subscores['device_recovery'] = 10
        feedback_parts.append("Recovery described in report (not confirmed in log)")
    else:
        subscores['device_recovery'] = 0
        feedback_parts.append("No device recovery detected (only 2 creation events expected 3+)")

    # Criterion 5: Fault tolerance report exists (15 pts)
    if report_exists and report_modified_after_start and report_size >= 300:
        score += 15
        subscores['report_file'] = 15
        feedback_parts.append(f"Fault tolerance report exists ({report_size} bytes)")
    elif report_exists and report_size >= 100:
        score += 8
        subscores['report_file'] = 8
        feedback_parts.append(f"Report exists but small or timestamp concern ({report_size} bytes)")
    else:
        subscores['report_file'] = 0
        feedback_parts.append("Fault tolerance report not found at /home/ga/Desktop/fault_tolerance_report.txt")

    # Criterion 6: Report quality (10 pts)
    has_failure = result.get('report_has_failure', 0)
    has_recovery = result.get('report_has_recovery', 0)
    has_assessment = result.get('report_has_assessment', 0)
    has_two_devices = result.get('report_has_two_devices', 0)
    quality_points = 0
    if has_failure: quality_points += 3
    if has_recovery: quality_points += 3
    if has_assessment: quality_points += 2
    if has_two_devices: quality_points += 2
    quality_points = min(10, quality_points)
    score += quality_points
    subscores['report_quality'] = quality_points
    if quality_points >= 8:
        feedback_parts.append("Report has full fault tolerance documentation")
    elif quality_points >= 4:
        feedback_parts.append("Report has partial fault tolerance content")
    else:
        feedback_parts.append("Report lacks required fault/recovery/assessment content")

    # GATE: report is required deliverable
    if not report_exists and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped: fault tolerance report is a required deliverable")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "debug": {
            "mp_create_count": mp_count,
            "two_devices": two_devices,
            "device_stopped": device_stopped,
            "device_recovery": device_recovery,
            "vital_signs": vital_signs,
            "report_exists": report_exists,
            "report_size": report_size,
            "window_increase": window_increase
        }
    }
