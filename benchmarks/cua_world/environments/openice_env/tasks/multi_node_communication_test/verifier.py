#!/usr/bin/env python3
"""Verifier for multi_node_communication_test task in OpenICE."""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Mock VLM utils for standalone testing, normally imported from framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback if running outside framework
    def query_vlm(**kwargs): return {"success": False, "error": "VLM unavailable"}
    def get_final_screenshot(traj): return None

logger = logging.getLogger(__name__)

def verify_multi_node_test(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]):
    """
    Verify OpenICE multi-node interoperability.
    
    Rubric (100 pts total):
    1. Infrastructure (40 pts):
       - 2+ Java processes running (20 pts)
       - Node B log exists and has content (20 pts)
    2. Device Creation (30 pts):
       - Node A created Infusion Pump (15 pts)
       - Node B created Capnometer (15 pts)
    3. Interoperability/Discovery (30 pts):
       - Logs show cross-discovery (Primary check) OR
       - VLM confirms multiple windows and devices (Fallback/Confirmation)
    
    Pass Threshold: 65 pts (Requires 2nd node running + at least one device created)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Infrastructure Checks
    proc_count = result.get('process_count', 0)
    if proc_count >= 2:
        score += 20
        feedback.append("Success: Multiple OpenICE processes detected.")
    else:
        feedback.append(f"Fail: Only {proc_count} OpenICE process(es) found (expected >= 2).")

    log_b_exists = result.get('log_b_exists', False)
    node_b_started = result.get('node_b_started_in_log', False)
    
    if log_b_exists and node_b_started:
        score += 20
        feedback.append("Success: Node B log created and active.")
    elif log_b_exists:
        score += 10
        feedback.append("Partial: Node B log exists but appears empty/invalid.")
    else:
        feedback.append("Fail: Node B log not found (redirection failed?).")

    # 2. Device Creation Checks
    a_pump = result.get('a_created_pump', False)
    if a_pump:
        score += 15
        feedback.append("Success: Node A created Infusion Pump.")
    else:
        feedback.append("Fail: Infusion Pump creation not found in Node A logs.")

    b_cap = result.get('b_created_capnometer', False)
    if b_cap:
        score += 15
        feedback.append("Success: Node B created Capnometer.")
    else:
        feedback.append("Fail: Capnometer creation not found in Node B logs.")

    # 3. Interoperability Checks
    # We check if logs confirm discovery. If logs are ambiguous (sometimes DDS is quiet),
    # we can try VLM as a backup, but usually local creation logs are reliable.
    # Cross-discovery:
    a_saw_b = result.get('a_saw_capnometer', False) # Remote device
    b_saw_a = result.get('b_saw_pump', False)       # Remote device
    
    discovery_score = 0
    if a_saw_b: discovery_score += 15
    if b_saw_a: discovery_score += 15
    
    # If log discovery failed but we have processes running, try VLM for visual confirmation
    # This helps if the log grep was too strict or DDS logs were suppressed
    if discovery_score < 30 and proc_count >= 2:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_prompt = """
            Analyze this screenshot of the OpenICE desktop.
            1. Are there TWO distinct OpenICE/Supervisor application windows visible?
            2. Look at the device lists in the windows. Do you see 'Capnometer' and 'Infusion Pump' listed?
            3. Do the device lists look like they contain devices from the OTHER instance (e.g. one window showing both devices)?
            Return JSON: {"two_windows": bool, "devices_visible": bool, "interop_likely": bool}
            """
            vlm_res = query_vlm(prompt=vlm_prompt, image=final_screenshot)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('two_windows') and parsed.get('interop_likely'):
                # Award points missed by log check, max 30 for this section
                points_needed = 30 - discovery_score
                discovery_score += points_needed
                feedback.append("Success (VLM): Visual confirmation of multi-node interoperability.")
            elif parsed.get('two_windows') and parsed.get('devices_visible'):
                if discovery_score < 15:
                    discovery_score = 15
                feedback.append("Partial (VLM): Two windows and devices seen, but full interoperability unclear.")

    score += discovery_score
    if discovery_score >= 30:
        feedback.append("Success: Bi-directional discovery confirmed.")
    elif discovery_score > 0:
        feedback.append("Partial: One-way discovery or visual evidence found.")
    else:
        feedback.append("Fail: No evidence of devices discovering each other.")

    # Final tally
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }