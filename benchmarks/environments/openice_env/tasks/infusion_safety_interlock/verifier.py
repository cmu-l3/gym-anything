#!/usr/bin/env python3
"""Verifier for infusion_safety_interlock task in OpenICE.

Realistic scenario: Biomedical engineer configuring the closed-loop drug
infusion safety system in OpenICE, requiring two device types and the
Infusion Safety clinical application.

Scoring (100 points):
- Monitoring device created (25 pts): SpO2 source device adapter running
- Infusion pump device created (25 pts): Pump device adapter running
- Infusion Safety app launched (20 pts): Safety app opened and interacted with
- Config report file exists with content (20 pts): /home/ga/Desktop/infusion_safety_config.txt
- Report has clinical quality (10 pts): Mentions SpO2 threshold + behavior description

GATE: If no devices were created at all AND no report exists -> score=0 immediately.
Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REPORT_PATH = "/home/ga/Desktop/infusion_safety_config.txt"


def verify_infusion_safety_interlock(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - task may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = result.get('task_start_timestamp', 0)

    # GATE: If nothing was done (no device, no report), return 0 immediately
    any_device = result.get('any_device_created', 0)
    report_exists = result.get('report_exists', 0)
    if not any_device and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: No device adapter was created and no report file found. Agent did not interact with OpenICE.",
            "subscores": {}
        }

    # Criterion 1: Monitoring device (SpO2 source) created (25 pts)
    monitor_created = result.get('monitor_device_created', 0)
    window_increase = result.get('window_increase', 0)
    # Credit also if any device was created AND there's a window increase >= 2
    # (two devices = two new windows)
    if monitor_created:
        score += 25
        subscores['monitor_device'] = 25
        feedback_parts.append("Monitoring device (SpO2 source) created")
    elif any_device and window_increase >= 1:
        score += 10
        subscores['monitor_device'] = 10
        feedback_parts.append("Some device created (monitoring device not specifically confirmed)")
    else:
        subscores['monitor_device'] = 0
        feedback_parts.append("No monitoring device detected")

    # Criterion 2: Infusion pump device created (25 pts)
    pump_created = result.get('infusion_pump_created', 0)
    if pump_created:
        score += 25
        subscores['infusion_pump'] = 25
        feedback_parts.append("Infusion pump device adapter created")
    elif window_increase >= 2:
        # Two windows opened = likely two devices, even if we can't confirm pump type
        score += 10
        subscores['infusion_pump'] = 10
        feedback_parts.append("Second device likely created (window count +2)")
    else:
        subscores['infusion_pump'] = 0
        feedback_parts.append("Infusion pump device not detected")

    # Criterion 3: Infusion Safety app launched (20 pts)
    safety_launched = result.get('infusion_safety_launched', 0)
    if safety_launched:
        score += 20
        subscores['infusion_safety_app'] = 20
        feedback_parts.append("Infusion Safety clinical app launched")
    else:
        subscores['infusion_safety_app'] = 0
        feedback_parts.append("Infusion Safety app not detected as launched")

    # Criterion 4: Report file exists with clinical content (20 pts)
    report_size = result.get('report_size', 0)
    report_mtime = result.get('report_mtime', 0)
    report_has_types = result.get('report_has_device_types', 0)
    report_modified_after_start = int(report_mtime) > task_start

    if report_exists and report_modified_after_start and report_size >= 100:
        score += 20
        subscores['report_file'] = 20
        feedback_parts.append(f"Config report exists ({report_size} bytes, written after task start)")
    elif report_exists and report_size >= 100:
        score += 10
        subscores['report_file'] = 10
        feedback_parts.append(f"Config report exists ({report_size} bytes) but timestamp unclear")
    elif report_exists:
        score += 5
        subscores['report_file'] = 5
        feedback_parts.append("Config report file exists but is very small")
    else:
        subscores['report_file'] = 0
        feedback_parts.append("Config report file not found at /home/ga/Desktop/infusion_safety_config.txt")

    # Criterion 5: Report has clinical quality (10 pts)
    report_has_spo2 = result.get('report_has_spo2', 0)
    report_has_threshold = result.get('report_has_threshold', 0)
    report_has_behavior = result.get('report_has_behavior', 0)
    quality_score = 0
    if report_has_spo2:
        quality_score += 4
    if report_has_threshold:
        quality_score += 3
    if report_has_behavior:
        quality_score += 3
    quality_score = min(10, quality_score)
    score += quality_score
    subscores['report_quality'] = quality_score
    if quality_score >= 7:
        feedback_parts.append("Report has high clinical quality (SpO2, threshold, behavior described)")
    elif quality_score >= 4:
        feedback_parts.append("Report has partial clinical content")
    else:
        feedback_parts.append("Report lacks required clinical content (SpO2 threshold, behavior)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "debug": {
            "monitor_created": monitor_created,
            "pump_created": pump_created,
            "safety_launched": safety_launched,
            "report_exists": report_exists,
            "report_size": report_size,
            "window_increase": window_increase,
            "task_start": task_start,
            "report_mtime": report_mtime
        }
    }
