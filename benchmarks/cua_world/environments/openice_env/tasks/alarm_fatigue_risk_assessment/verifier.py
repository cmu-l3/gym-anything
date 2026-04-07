#!/usr/bin/env python3
"""Verifier for alarm_fatigue_risk_assessment task in OpenICE.

Scoring Criteria (100 points total):
- Device Creation (30 pts):
  - Pulse Oximeter (8 pts)
  - Multiparameter Monitor (8 pts)
  - Infusion Pump (8 pts)
  - 4th Device (6 pts)
- App Launch (20 pts):
  - Vital Signs App (10 pts)
  - Infusion Safety App (10 pts)
- Evidence Capture (16 pts):
  - Vital Signs Screenshot (8 pts)
  - Infusion Safety Screenshot (8 pts)
- Risk Assessment Report (34 pts):
  - File exists & valid (10 pts)
  - Content quality (4 sections * 6 pts each = 24 pts)

Gate Condition:
  If (device_count < 2) AND (report_valid == False) AND (no screenshots):
  Score = 0 (Agent did not meaningfully attempt the task).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_alarm_fatigue_risk_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result JSON
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
    
    # Gate Condition
    device_count = result.get('device_count', 0)
    report_valid = result.get('report_valid', False)
    screenshot_vitals = result.get('screenshot_vitals_valid', False)
    screenshot_safety = result.get('screenshot_safety_valid', False)
    
    if device_count < 2 and not report_valid and not (screenshot_vitals or screenshot_safety):
         return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: Insufficient devices created, no report, and no screenshots. Task not attempted.",
        }

    # 1. Device Creation (30 pts)
    if result.get('has_pulse_ox', False):
        score += 8
        feedback_parts.append("Pulse Oximeter created")
    else:
        feedback_parts.append("Pulse Oximeter missing")

    if result.get('has_multiparam', False):
        score += 8
        feedback_parts.append("Multiparameter Monitor created")
    else:
        feedback_parts.append("Multiparameter Monitor missing")

    if result.get('has_pump', False):
        score += 8
        feedback_parts.append("Infusion Pump created")
    else:
        feedback_parts.append("Infusion Pump missing")

    if result.get('has_fourth_device', False):
        score += 6
        feedback_parts.append("4th Device created")
    else:
        feedback_parts.append("4th Device missing")

    # 2. App Launch (20 pts)
    if result.get('has_vital_signs_app', False):
        score += 10
        feedback_parts.append("Vital Signs App launched")
    else:
        feedback_parts.append("Vital Signs App not detected")

    if result.get('has_infusion_safety_app', False):
        score += 10
        feedback_parts.append("Infusion Safety App launched")
    else:
        feedback_parts.append("Infusion Safety App not detected")

    # 3. Screenshots (16 pts)
    if screenshot_vitals:
        score += 8
        feedback_parts.append("Vital Signs screenshot valid")
    else:
        feedback_parts.append("Vital Signs screenshot missing/invalid")

    if screenshot_safety:
        score += 8
        feedback_parts.append("Infusion Safety screenshot valid")
    else:
        feedback_parts.append("Infusion Safety screenshot missing/invalid")

    # 4. Report (34 pts)
    if report_valid:
        score += 10
        feedback_parts.append("Report file valid")
        
        # Content score is 0-4 based on grep matches in export script
        # Map 0-4 scale to 24 points (6 points per section)
        content_level = result.get('report_content_score', 0)
        content_points = content_level * 6
        score += content_points
        feedback_parts.append(f"Report content quality: {content_level}/4 sections ({content_points} pts)")
    else:
        feedback_parts.append("Report file missing or invalid")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }