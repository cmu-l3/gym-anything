#!/usr/bin/env python3
"""Verifier for configure_workspace_service_availability task."""

import json
import tempfile
import os
import sys

def verify_configure_workspace_service_availability(traj, env_info, task_info):
    """Verify that WFS/WCS are disabled and WMS is enabled with correct title for 'ne' workspace."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_workspace_service_availability_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Optional check if file missing
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Check WFS Disabled (30 points)
    wfs_status = result.get('wfs_status', 'UNKNOWN')
    if wfs_status == 'DISABLED':
        score += 30
        feedback_parts.append("WFS correctly disabled")
    elif wfs_status == 'ACCESSIBLE':
        feedback_parts.append("FAIL: WFS is still accessible")
    else:
        feedback_parts.append(f"WFS status unknown: {wfs_status}")

    # 2. Check WCS Disabled (10 points)
    wcs_status = result.get('wcs_status', 'UNKNOWN')
    if wcs_status == 'DISABLED':
        score += 10
        feedback_parts.append("WCS correctly disabled")
    elif wcs_status == 'ACCESSIBLE':
        feedback_parts.append("FAIL: WCS is still accessible")
    else:
        feedback_parts.append(f"WCS status unknown: {wcs_status}")

    # 3. Check WMS Enabled (30 points)
    wms_status = result.get('wms_status', 'UNKNOWN')
    if wms_status == 'ACCESSIBLE':
        score += 30
        feedback_parts.append("WMS is accessible")
    elif wms_status == 'DISABLED':
        feedback_parts.append("FAIL: WMS was disabled (should be enabled)")
    else:
        feedback_parts.append(f"WMS status unknown: {wms_status}")

    # 4. Check WMS Title (30 points)
    if result.get('wms_title_found'):
        score += 30
        feedback_parts.append("WMS Service Title correct")
    else:
        actual = result.get('actual_wms_title', 'None')
        feedback_parts.append(f"WMS Title incorrect. Found: '{actual}'")

    # Anti-gaming: Check for GUI interaction via logs or settings file changes
    # If the user did everything via REST API (which isn't the instructions but valid technically),
    # the settings files would exist.
    # If using GUI, logs would show interaction.
    # We won't penalize for method as long as functional result is correct, 
    # but we will fail if NO work was done (reflected by score=0).
    
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }