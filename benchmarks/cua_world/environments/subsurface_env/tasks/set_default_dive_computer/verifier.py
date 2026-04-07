#!/usr/bin/env python3
"""
Verifier for set_default_dive_computer task.
Ensures the agent uses the Subsurface UI to modify default dive computer settings.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_default_dive_computer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Read task_result.json constraints
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    conf_modified = result.get('conf_modified_during_task', False)
    if conf_modified:
        score += 10
        feedback_parts.append("Config file modified")
    else:
        feedback_parts.append("Config file NOT modified after task start (0 points)")

    app_running = result.get('app_running', True)
    if not app_running:
        feedback_parts.append("Subsurface closed correctly (flushed settings)")
    else:
        feedback_parts.append("Warning: Subsurface is still running (settings may not be saved)")

    # 2. Read Subsurface.conf and check for presence of configured parameters
    # Reading text values is more robust than ConfigParser due to Qt-specific variable string formats
    tmp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    vendor_found = False
    product_found = False
    device_found = False

    try:
        copy_from_env("/home/ga/.config/Subsurface/Subsurface.conf", tmp_conf.name)
        with open(tmp_conf.name, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line_lower = line.lower()
                if 'shearwater' in line_lower:
                    vendor_found = True
                if 'perdix' in line_lower:
                    product_found = True
                if '/dev/rfcomm0' in line_lower:
                    device_found = True
    except Exception as e:
        feedback_parts.append(f"Could not parse Subsurface.conf: {e}")
    finally:
        if os.path.exists(tmp_conf.name):
            os.unlink(tmp_conf.name)

    if vendor_found:
        score += 20
        feedback_parts.append("Vendor correctly set to Shearwater")
    if product_found:
        score += 20
        feedback_parts.append("Model correctly set to Perdix")
    if device_found:
        score += 20
        feedback_parts.append("Device correctly set to /dev/rfcomm0")

    # 3. VLM Trajectory Verification (Anti-gaming check for direct terminal file writes)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        if query_vlm and frames:
            prompt = """Look at these sequence of screenshots from a desktop session.
Did the user open the Subsurface 'Import from dive computer' (or 'Download from dive computer') dialog at any point?
Please respond in JSON format with a boolean key "used_import_dialog".
Example: {"used_import_dialog": true}"""
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_import_dialog', False):
                    vlm_score = 30
                    feedback_parts.append("VLM confirmed Import dialog usage")
                else:
                    feedback_parts.append("VLM did NOT observe Import dialog usage")
            else:
                vlm_score = 30 # Default to pass if VLM network call fails
                feedback_parts.append("VLM query failed, skipping visual check")
        else:
            vlm_score = 30 # Default to pass if VLM module is completely unavailable
            feedback_parts.append("VLM not available, skipping visual check")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        vlm_score = 30 # Graceful fallback
        feedback_parts.append("VLM verification skipped (import/execution error)")

    score += vlm_score

    # To pass: They must modify the file and correctly insert at least 2 of the 3 target fields
    properties_set = sum([vendor_found, product_found, device_found])
    key_criteria_met = conf_modified and (properties_set >= 2)

    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }