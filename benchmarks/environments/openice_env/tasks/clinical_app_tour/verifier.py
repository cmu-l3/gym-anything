#!/usr/bin/env python3
"""Verifier for clinical_app_tour task in OpenICE.

Realistic scenario: Clinical informatics specialist demonstrating all 4 OpenICE
clinical applications to ICU staff and writing an education guide.

Scoring (100 points):
- Multiparameter Monitor device created (15 pts)
- Vital Signs app launched (10 pts)
- Xray Viewer app launched (10 pts)
- Patient ID app launched (10 pts)
- Infusion Safety app launched (10 pts)
- All 4 apps bonus (5 pts)
- Clinical guide file exists (15 pts)
- Guide mentions all 4 app names (15 pts)
- Guide has clinical interoperability content (10 pts)

GATE: If fewer than 3 apps launched AND no guide -> score capped at threshold-1.
Pass threshold: 65 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65
GUIDE_PATH = "/home/ga/Desktop/clinical_guide.txt"


def verify_clinical_app_tour(traj, env_info, task_info):
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
    apps_launched = result.get('apps_launched', 0)
    guide_exists = result.get('guide_exists', 0)
    guide_mtime = result.get('guide_mtime', 0)
    guide_size = result.get('guide_size', 0)
    guide_modified_after_start = int(guide_mtime) > task_start
    window_increase = result.get('window_increase', 0)

    # GATE: Nothing was done
    if apps_launched < 3 and not guide_exists and window_increase < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: Fewer than 3 apps launched and no guide file found.",
            "subscores": {}
        }

    # Criterion 1: Device adapter created (15 pts)
    device_created = result.get('device_created', 0)
    if device_created:
        score += 15
        subscores['device_created'] = 15
        feedback_parts.append("Multiparameter Monitor device adapter created")
    elif window_increase > 0:
        score += 8
        subscores['device_created'] = 8
        feedback_parts.append("A device was created (type unconfirmed)")
    else:
        subscores['device_created'] = 0
        feedback_parts.append("No device adapter detected")

    # Criteria 2-5: Each clinical app (10 pts each, 5pt bonus for all 4)
    vital_signs = result.get('vital_signs_app', 0)
    xray = result.get('xray_app', 0)
    patient_id = result.get('patient_id_app', 0)
    infusion_safety = result.get('infusion_safety_app', 0)

    if vital_signs:
        score += 10
        subscores['vital_signs_app'] = 10
        feedback_parts.append("Vital Signs app launched")
    else:
        subscores['vital_signs_app'] = 0
        feedback_parts.append("Vital Signs app not detected")

    if xray:
        score += 10
        subscores['xray_app'] = 10
        feedback_parts.append("Xray Viewer app launched")
    else:
        subscores['xray_app'] = 0
        feedback_parts.append("Xray Viewer app not detected")

    if patient_id:
        score += 10
        subscores['patient_id_app'] = 10
        feedback_parts.append("Patient ID app launched")
    else:
        subscores['patient_id_app'] = 0
        feedback_parts.append("Patient ID app not detected")

    if infusion_safety:
        score += 10
        subscores['infusion_safety_app'] = 10
        feedback_parts.append("Infusion Safety app launched")
    else:
        subscores['infusion_safety_app'] = 0
        feedback_parts.append("Infusion Safety app not detected")

    # Bonus: all 4 apps launched
    if apps_launched >= 4:
        score += 5
        subscores['all_apps_bonus'] = 5
        feedback_parts.append("All 4 clinical apps demonstrated (bonus)")
    else:
        subscores['all_apps_bonus'] = 0

    # Criterion 6: Guide file exists and written after task start (15 pts)
    if guide_exists and guide_modified_after_start and guide_size >= 300:
        score += 15
        subscores['guide_file'] = 15
        feedback_parts.append(f"Clinical guide exists ({guide_size} bytes)")
    elif guide_exists and guide_size >= 100:
        score += 8
        subscores['guide_file'] = 8
        feedback_parts.append(f"Guide exists but small or uncertain timestamp ({guide_size} bytes)")
    else:
        subscores['guide_file'] = 0
        feedback_parts.append("Clinical guide not found at /home/ga/Desktop/clinical_guide.txt")

    # Criterion 7: Guide mentions all 4 app names (15 pts)
    g_vital = result.get('guide_has_vital', 0)
    g_xray = result.get('guide_has_xray', 0)
    g_patient = result.get('guide_has_patient', 0)
    g_infusion = result.get('guide_has_infusion', 0)
    apps_in_guide = g_vital + g_xray + g_patient + g_infusion

    if apps_in_guide >= 4:
        score += 15
        subscores['guide_app_coverage'] = 15
        feedback_parts.append("Guide covers all 4 applications")
    elif apps_in_guide == 3:
        score += 10
        subscores['guide_app_coverage'] = 10
        feedback_parts.append(f"Guide covers {apps_in_guide}/4 applications")
    elif apps_in_guide == 2:
        score += 5
        subscores['guide_app_coverage'] = 5
        feedback_parts.append(f"Guide covers {apps_in_guide}/4 applications")
    else:
        subscores['guide_app_coverage'] = 0
        feedback_parts.append("Guide does not mention application names")

    # Criterion 8: Guide has clinical interoperability content (10 pts)
    has_clinical = result.get('guide_has_clinical_content', 0)
    if has_clinical and guide_exists:
        score += 10
        subscores['clinical_content'] = 10
        feedback_parts.append("Guide contains clinical interoperability content")
    else:
        subscores['clinical_content'] = 0
        feedback_parts.append("Guide lacks clinical/interoperability content")

    # GATE: guide is required for passing
    if not guide_exists and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped: clinical guide is a required deliverable")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "debug": {
            "apps_launched": apps_launched,
            "apps_in_guide": apps_in_guide,
            "guide_exists": guide_exists,
            "guide_size": guide_size,
            "device_created": device_created
        }
    }
