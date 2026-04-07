#!/usr/bin/env python3
"""
Verifier for the debug_iot_buoy_firmware task.

Checks whether the agent identified and fixed 5 bugs in the firmware parsers
by analyzing the output generated when running against a hidden binary/hex dataset.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth expected values for the hidden dataset
EXPECTED = {
    "gps_valid": 4,  # All 4 sentences in hidden_telemetry.json have valid checksums
    "salinity": [123.4, 129.2],  # [4,210]->(4<<8)+210=1234->123.4. [5,12]->(5<<8)+12=1292->129.2
    "temperatures": [-6.0, -12.25, 9.375],  # 4000->-96, 3900->-196, 150->150
    "battery_min_valid": 3.0,  # 3500->~3.58V, 3900->~4.0V. Bug cuts to < 0.2V
    "buffer_state": [60, 70, 80, 90, 100, 110, 120, 130, 140, 150]  # Last 10 elements of 15
}

def is_close(val, expected, tol=0.01):
    return abs(val - expected) <= tol

def verify_firmware_fixes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Execution Check
    hidden_output = result.get('hidden_output', {})
    exec_error = result.get('execution_error')
    
    if exec_error:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Simulation script crashed or produced invalid JSON: {exec_error}"
        }

    # 1. NMEA Checksum (15 pts)
    gps_count = hidden_output.get("gps_valid", 0)
    if gps_count == EXPECTED["gps_valid"]:
        score += 15
        feedback_parts.append("[+] NMEA: Checksum skips '$' successfully")
    elif gps_count > 0:
        score += 5
        feedback_parts.append("[-] NMEA: Partially fixed checksum logic")
    else:
        feedback_parts.append("[-] NMEA: Checksum validation still failing on valid sentences")

    # 2. Salinity Endianness (15 pts)
    salinities = hidden_output.get("salinity", [])
    if len(salinities) == len(EXPECTED["salinity"]) and \
       all(is_close(s, e) for s, e in zip(salinities, EXPECTED["salinity"])):
        score += 15
        feedback_parts.append("[+] Salinity: Big-Endian parsing is correct")
    else:
        feedback_parts.append(f"[-] Salinity: Incorrect endianness. Expected {EXPECTED['salinity']}, got {salinities}")

    # 3. Temperature Two's Complement (15 pts)
    temps = hidden_output.get("temperatures", [])
    if len(temps) == len(EXPECTED["temperatures"]) and \
       all(is_close(t, e) for t, e in zip(temps, EXPECTED["temperatures"])):
        score += 15
        feedback_parts.append("[+] Temperature: Negative Two's Complement logic correct")
    else:
        feedback_parts.append(f"[-] Temperature: Two's complement broken. Expected {EXPECTED['temperatures']}, got {temps}")

    # 4. Battery Bitmask (15 pts)
    batts = hidden_output.get("battery", [])
    if len(batts) > 0 and all(b >= EXPECTED["battery_min_valid"] for b in batts):
        score += 15
        feedback_parts.append("[+] Battery: 12-bit mask applied correctly")
    else:
        feedback_parts.append(f"[-] Battery: 8-bit cutoff bug persists. Values were too low: {batts}")

    # 5. Ring Buffer (15 pts)
    buf_state = hidden_output.get("buffer_state", [])
    if buf_state == EXPECTED["buffer_state"]:
        score += 15
        feedback_parts.append("[+] Buffer: Ring buffer capacity and tail overwriting correct")
    elif len(buf_state) > 0 and buf_state[-1] == EXPECTED["buffer_state"][-1]:
        score += 5
        feedback_parts.append("[-] Buffer: Modified but state does not match expected exact history")
    else:
        feedback_parts.append("[-] Buffer: Drops bytes when full instead of overwriting")

    # 6. VLM Trajectory Verification (25 pts)
    # Ensure agent actually used VS Code rather than just echoing out file strings blindly
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = (
                "You are an AI auditor checking if an agent completed a task fairly. "
                "Look at these screenshots taken during the episode. "
                "Did the agent actively use Visual Studio Code to edit Python files? "
                "Reply with ONLY valid JSON: {\"used_vscode\": true/false}"
            )
            vlm_res = query_vlm(images=frames, prompt=prompt)
            try:
                if vlm_res.get("success") and vlm_res.get("parsed", {}).get("used_vscode"):
                    score += 25
                    feedback_parts.append("[+] VLM: Verified VS Code usage via trajectory")
                else:
                    feedback_parts.append("[-] VLM: Could not verify active VS Code usage")
            except Exception:
                feedback_parts.append("[-] VLM: Verification parsing failed")
        else:
            feedback_parts.append("[-] VLM: No trajectory frames available for verification")
    else:
        # Give points if VLM is unavailable but programmatic checks are perfect
        score += 25
        feedback_parts.append("[?] VLM: Unavailable, giving default points")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }