#!/usr/bin/env python3
"""
Verifier for safety_interlock_fail_safe_validation task.

Scenario: Agent must create devices, confirm operation, then DISCONNECT the sensor
to prove the fail-safe works.

Scoring Breakdown (100 pts total):
1. Setup (30 pts):
   - Pulse Oximeter created (Log) (10)
   - Infusion Pump created (Log) (10)
   - Safety App launched (Log) (10)

2. Action: Sensor Disconnection (30 pts):
   - Logic: Pulse Ox was created (History=True) BUT is currently gone (State=False).
   - This proves the agent actually closed the window/disconnected the device.

3. Context: System Integrity (10 pts):
   - Pump and Safety App windows should still be OPEN. (Don't just close everything).

4. Evidence (30 pts):
   - Baseline screenshot exists (10)
   - Failsafe screenshot exists (10)
   - Report exists and has valid content (10)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_safety_interlock_fail_safe_validation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    state = result.get('state', {})
    history = result.get('history', {})
    artifacts = result.get('artifacts', {})

    # 1. Setup Verification (Logs)
    if history.get('log_pulse_ox_created', False):
        score += 10
        feedback_parts.append("Setup: Pulse Ox created")
    else:
        feedback_parts.append("Setup: Pulse Ox NOT created")

    if history.get('log_pump_created', False):
        score += 10
        feedback_parts.append("Setup: Pump created")
    else:
        feedback_parts.append("Setup: Pump NOT created")

    if history.get('log_safety_app_launched', False):
        score += 10
        feedback_parts.append("Setup: App launched")
    else:
        feedback_parts.append("Setup: App NOT launched")

    # 2. Action Verification (The Disconnect)
    # The Pulse Ox should have been created (history) but shouldn't be open now (state)
    was_created = history.get('log_pulse_ox_created', False)
    is_open = state.get('pulse_ox_window_open', True)

    if was_created and not is_open:
        score += 30
        feedback_parts.append("Action: Pulse Ox disconnected (Success)")
    elif not was_created:
        feedback_parts.append("Action: Pulse Ox never existed")
    elif is_open:
        feedback_parts.append("Action: Pulse Ox still connected (Fail)")

    # 3. Context Verification (System Alive)
    # Pump and App should still be running
    pump_open = state.get('pump_window_open', False)
    app_open = state.get('safety_app_open', False)
    
    if pump_open and app_open:
        score += 10
        feedback_parts.append("Context: System active")
    else:
        feedback_parts.append("Context: System shut down improperly")

    # 4. Evidence Verification
    if artifacts.get('baseline_screenshot_exists', False):
        score += 10
    else:
        feedback_parts.append("Missing baseline screenshot")

    if artifacts.get('failsafe_screenshot_exists', False):
        score += 10
    else:
        feedback_parts.append("Missing failsafe screenshot")

    if artifacts.get('report_exists', False) and artifacts.get('report_content_valid', False):
        score += 10
    elif artifacts.get('report_exists', False):
        score += 5
        feedback_parts.append("Report content weak")
    else:
        feedback_parts.append("Missing report")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }