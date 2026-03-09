#!/usr/bin/env python3
"""Verifier for icu_monitoring_setup task in OpenICE.

Realistic scenario: Critical care nurse configuring multi-device monitoring
for a post-cardiac surgery ICU patient using 3 distinct device types.

Scoring (100 points):
- Multiparameter Monitor created (10 pts)
- CO2/respiratory device created (10 pts)
- Third distinct device created (10 pts)
- Vital Signs app launched (15 pts)
- Device detail view opened (15 pts)
- Monitoring checklist report exists + written after start (20 pts)
- Report mentions 3+ device types (20 pts)

GATE: Fewer than 2 devices created AND no report file -> score=0.
Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REPORT_PATH = "/home/ga/Desktop/monitoring_checklist.txt"


def verify_icu_monitoring_setup(traj, env_info, task_info):
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
    device_count = result.get('device_type_count', 0)
    window_increase = result.get('window_increase', 0)
    report_exists = result.get('report_exists', 0)

    # GATE: If fewer than 2 devices AND no report -> nothing was done
    if device_count < 2 and not report_exists and window_increase < 2:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: Fewer than 2 device adapters created and no report found. Agent did not complete setup.",
            "subscores": {}
        }

    # Criterion 1: Multiparameter Monitor created (10 pts)
    mp_created = result.get('multiparameter_created', 0)
    if mp_created:
        score += 10
        subscores['multiparameter'] = 10
        feedback_parts.append("Multiparameter Monitor created")
    else:
        subscores['multiparameter'] = 0
        feedback_parts.append("Multiparameter Monitor not detected")

    # Criterion 2: CO2/respiratory device created (10 pts)
    co2_created = result.get('co2_created', 0)
    if co2_created:
        score += 10
        subscores['co2_device'] = 10
        feedback_parts.append("CO2/respiratory device created")
    else:
        subscores['co2_device'] = 0
        feedback_parts.append("CO2/respiratory device not detected")

    # Criterion 3: Third distinct device created (10 pts)
    third_created = result.get('third_device_created', 0)
    if third_created:
        score += 10
        subscores['third_device'] = 10
        feedback_parts.append("Third distinct device created")
    elif window_increase >= 3:
        # 3 windows = 3 devices even if types weren't identified
        score += 7
        subscores['third_device'] = 7
        feedback_parts.append("Third device likely created (window count +3)")
    else:
        subscores['third_device'] = 0
        feedback_parts.append("Third device not detected")

    # Criterion 4: Vital Signs app launched (15 pts)
    vital_signs = result.get('vital_signs_launched', 0)
    if vital_signs:
        score += 15
        subscores['vital_signs_app'] = 15
        feedback_parts.append("Vital Signs clinical app launched")
    else:
        subscores['vital_signs_app'] = 0
        feedback_parts.append("Vital Signs app not detected as launched")

    # Criterion 5: Device detail view accessed (15 pts)
    details_viewed = result.get('details_viewed', 0)
    if details_viewed or window_increase > 1:
        score += 15
        subscores['detail_view'] = 15
        feedback_parts.append(f"Device detail views accessed (window increase: +{window_increase})")
    else:
        subscores['detail_view'] = 0
        feedback_parts.append("Device detail views not accessed")

    # Criterion 6: Report file exists and was written after task start (20 pts)
    report_size = result.get('report_size', 0)
    report_mtime = result.get('report_mtime', 0)
    report_modified_after_start = int(report_mtime) > task_start

    if report_exists and report_modified_after_start and report_size >= 150:
        score += 20
        subscores['report_file'] = 20
        feedback_parts.append(f"Monitoring checklist exists ({report_size} bytes)")
    elif report_exists and report_size >= 50:
        score += 10
        subscores['report_file'] = 10
        feedback_parts.append(f"Report exists but small or uncertain timestamp ({report_size} bytes)")
    else:
        subscores['report_file'] = 0
        feedback_parts.append("Monitoring checklist not found at /home/ga/Desktop/monitoring_checklist.txt")

    # Criterion 7: Report mentions 3 device types (20 pts)
    has_mp = result.get('report_has_multiparameter', 0)
    has_co2 = result.get('report_has_co2', 0)
    has_third = result.get('report_has_third_device', 0)
    has_confirm = result.get('report_has_confirmation', 0)
    types_mentioned = has_mp + has_co2 + has_third

    if types_mentioned >= 3:
        score += 20
        subscores['report_content'] = 20
        feedback_parts.append("Report mentions all 3 device types with confirmation")
    elif types_mentioned == 2:
        score += 12
        subscores['report_content'] = 12
        feedback_parts.append(f"Report mentions {types_mentioned}/3 device types")
    elif types_mentioned == 1:
        score += 6
        subscores['report_content'] = 6
        feedback_parts.append("Report mentions only 1 device type")
    else:
        subscores['report_content'] = 0
        feedback_parts.append("Report does not mention required device types")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "debug": {
            "device_type_count": device_count,
            "window_increase": window_increase,
            "vital_signs_launched": vital_signs,
            "report_exists": report_exists,
            "report_size": report_size,
            "types_mentioned": types_mentioned
        }
    }
