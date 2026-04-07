#!/usr/bin/env python3
"""
Verifier for configure_tcp_output task.
Uses a hybrid approach (Registry checks + VLM Trajectory Verification) to ensure robust scoring and prevent gaming.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_tcp_output(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_host = metadata.get('expected_host', '127.0.0.1')
    expected_port = metadata.get('expected_port', '9100')

    # 1. Read programmatic result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract telemetric data
    host_found = result_data.get('host_found_in_reg', False)
    port_found = result_data.get('port_found_in_reg', False)
    reg_changed = result_data.get('registry_changed', False)
    app_running = result_data.get('app_running', False)

    score = 0
    feedback = []

    # Scoring programmatic signals (Max 50 points)
    if host_found and port_found:
        score += 30
        feedback.append("Registry: Host and Port values successfully detected in application settings.")
    elif reg_changed:
        score += 10
        feedback.append("Registry: Settings modified, but exact host/port strings not found natively.")
    else:
        feedback.append("Registry: No configuration changes detected. Anti-gaming triggered.")

    if app_running:
        score += 20
        feedback.append("App is still running.")

    # 3. VLM Trajectory Verification (Max 50 points)
    # Why? Registry serialization can sometimes be obfuscated or proprietary. UI intention provides definitive truth.
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames

    if not all_frames:
        return {"passed": False, "score": score, "feedback": "No frames available for VLM verification."}

    prompt = f"""
    You are verifying a task where an agent configures TCP/IP Network Output in a barcode scanning application.

    Task requirements:
    - Enable TCP/IP output.
    - Set Host address to '{expected_host}'.
    - Set Port number to '{expected_port}'.

    Look at these chronological trajectory screenshots and determine:
    1. Did the agent open the settings/options dialog?
    2. Did the agent navigate to the TCP/IP or network output configuration section?
    3. Is the TCP/IP output explicitly enabled (e.g., checkbox or toggle is checked)?
    4. Is the host explicitly set to '{expected_host}' in the UI?
    5. Is the port explicitly set to '{expected_port}' in the UI?

    Respond in JSON format:
    {{
        "opened_settings": true/false,
        "navigated_to_tcp": true/false,
        "tcp_enabled": true/false,
        "host_correct": true/false,
        "port_correct": true/false,
        "confidence": "high/medium/low",
        "reasoning": "Brief explanation"
    }}
    """

    vlm_result = query_vlm(prompt=prompt, images=all_frames)
    parsed = vlm_result.get("parsed", {})

    if parsed.get("opened_settings"):
        score += 10
        feedback.append("VLM: Opened settings dialog.")
    if parsed.get("navigated_to_tcp"):
        score += 10
        feedback.append("VLM: Navigated to TCP/IP network section.")
    if parsed.get("tcp_enabled"):
        score += 10
        feedback.append("VLM: TCP/IP explicitly enabled.")
    if parsed.get("host_correct"):
        score += 10
        feedback.append(f"VLM: Host correctly set to {expected_host}.")
    if parsed.get("port_correct"):
        score += 10
        feedback.append(f"VLM: Port correctly set to {expected_port}.")

    # Evaluate Pass condition
    # Requires key steps complete: Opened settings, enabled it, and correctly populated parameters.
    key_criteria_met = parsed.get("tcp_enabled", False) and parsed.get("host_correct", False) and parsed.get("port_correct", False)
    passed = score >= 70 and key_criteria_met and reg_changed

    return {
        "passed": bool(passed),
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": parsed
    }