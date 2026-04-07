#!/usr/bin/env python3
"""Verifier for deployment_environment_audit task in OpenICE."""

import json
import tempfile
import os
import time

def verify_deployment_environment_audit(traj, env_info, task_info):
    """Verify the deployment environment audit task.

    Scoring Criteria (100 points total):
    1. Multiparameter Monitor Active (20 pts): Detected via logs or window title.
    2. Infusion Pump Active (20 pts): Detected via logs or window title.
    3. Audit File Exists (10 pts): File created at /home/ga/Desktop/deployment_audit.txt.
    4. JVM Properties Captured (30 pts): File contains valid Java system properties.
    5. Device Inventory Listed (20 pts): File contains text mentioning both devices.

    Pass Threshold: 70 points
    """
    
    # Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # 1. Device Verification (40 pts total)
    monitor_active = result.get('monitor_device_active', False)
    if monitor_active:
        score += 20
        subscores['monitor_active'] = 20
        feedback_parts.append("Multiparameter Monitor active")
    else:
        subscores['monitor_active'] = 0
        feedback_parts.append("Multiparameter Monitor NOT detected")

    pump_active = result.get('pump_device_active', False)
    if pump_active:
        score += 20
        subscores['pump_active'] = 20
        feedback_parts.append("Infusion Pump active")
    else:
        subscores['pump_active'] = 0
        feedback_parts.append("Infusion Pump NOT detected")

    # 2. File Existence & Timestamp (10 pts)
    file_exists = result.get('file_exists', False)
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start', 0)
    
    file_valid = False
    if file_exists and file_mtime > task_start:
        score += 10
        subscores['file_exists'] = 10
        file_valid = True
        feedback_parts.append("Audit file created")
    elif file_exists:
        feedback_parts.append("Audit file exists but timestamp invalid (pre-existing?)")
    else:
        feedback_parts.append("Audit file NOT found")

    # 3. Content Analysis (50 pts total)
    if file_valid:
        # Check for JVM properties (30 pts)
        if result.get('content_has_jvm_props', False):
            score += 30
            subscores['jvm_props'] = 30
            feedback_parts.append("JVM properties captured")
        else:
            subscores['jvm_props'] = 0
            feedback_parts.append("File does not appear to contain JVM properties")

        # Check for device inventory text (20 pts)
        # Split 10 pts for monitor text, 10 pts for pump text
        text_score = 0
        if result.get('content_has_monitor_text', False):
            text_score += 10
        if result.get('content_has_pump_text', False):
            text_score += 10
        
        score += text_score
        subscores['text_content'] = text_score
        if text_score == 20:
            feedback_parts.append("Device inventory listed correctly")
        elif text_score > 0:
            feedback_parts.append("Device inventory partially listed")
        else:
            feedback_parts.append("Device inventory missing from file")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": result
    }