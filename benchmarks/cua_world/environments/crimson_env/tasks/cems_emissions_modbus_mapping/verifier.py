#!/usr/bin/env python3
"""
Verifier for CEMS Emissions Modbus Mapping task.

Uses a HYBRID verification strategy (Multiple Independent Signals):
1. PROGRAMMATIC (File Check): Validates the `cems_emissions.c3` file was saved during the task.
2. PROGRAMMATIC (Binary Parsing): Scans the saved `.c3` binary file for expected tag names and Modbus configurations (as Crimson stores tag descriptors and network configs as plaintext within the binary project file).
3. VLM (Trajectory Check): Evaluates sampled frames from the agent's interaction to verify Modbus TCP/IP Protocol and IP configurations visually, preventing 'blind' internal tag creation.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Review these screenshots of the agent's workflow in Red Lion Crimson 3.0.

Task Context: The agent was instructed to configure a Modbus TCP/IP Master device at IP address 10.0.0.150 and map emissions tags.

Please carefully check the trajectory to determine:
1. Did the agent navigate to the "Communications" section and configure "Ethernet 1" / "Protocol 1" to use "Modbus TCP/IP Master"?
2. Did the agent enter the IP address "10.0.0.150" for the target device?
3. Did the agent create tags (NOX_PPM, SO2_PPM, etc.) in the Data Tags section?

Respond in JSON format:
{
    "modbus_configured": true/false,
    "ip_entered": true/false,
    "tags_created": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation of what is visible"
}"""


def verify_cems_emissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_tags = metadata.get('tags', [])
    expected_ip = metadata.get('expected_ip', "10.0.0.150")
    expected_device = metadata.get('expected_device', "CEMS_ANALYZER")

    feedback_parts = []
    score = 0
    key_criteria_met = False

    # -------------------------------------------------------------------------
    # 1. Evaluate JSON Export (File existence & anti-gaming)
    # -------------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\CrimsonTasks\\cems_emissions_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    project_found = result_data.get('project_found', False)
    created_during_task = result_data.get('created_during_task', False)

    if not project_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project file 'cems_emissions.c3' not found. Agent did not save the work."
        }
    
    if not created_during_task:
        feedback_parts.append("Warning: File timestamp indicates it might not have been created during this task.")
    else:
        score += 15
        feedback_parts.append("Project saved successfully")

    # -------------------------------------------------------------------------
    # 2. Extract and Parse the .c3 Binary File
    # -------------------------------------------------------------------------
    temp_c3 = tempfile.NamedTemporaryFile(delete=False, suffix='.c3')
    c3_content = b""
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\CrimsonProjects\\cems_emissions.c3", temp_c3.name)
        with open(temp_c3.name, 'rb') as f:
            c3_content = f.read()
    except Exception as e:
        logger.error(f"Failed to copy or read .c3 file: {e}")
    finally:
        if os.path.exists(temp_c3.name):
            os.unlink(temp_c3.name)

    if not c3_content:
        return {"passed": False, "score": score, "feedback": "Failed to extract project contents for verification."}

    # Extract all ASCII / UTF-16ish printable strings from the binary to search for configurations
    printable_chars = bytes(range(32, 127))
    extracted_strings = b"".join([bytes([b]) if b in printable_chars else b" " for b in c3_content]).decode('ascii', errors='ignore')
    
    # Check for expected tag names
    found_tags = [tag for tag in expected_tags if tag in extracted_strings]
    if len(found_tags) == len(expected_tags):
        score += 25
        feedback_parts.append("All expected tags found in project file")
    else:
        score += len(found_tags) * 5
        feedback_parts.append(f"Found {len(found_tags)}/{len(expected_tags)} tags")

    # Check for Device Name and IP Address config strings
    device_found = expected_device in extracted_strings
    ip_found = expected_ip in extracted_strings

    if device_found and ip_found:
        score += 20
        feedback_parts.append("Modbus IP and Device Name mapped in project file")
    elif ip_found:
        score += 10
        feedback_parts.append("IP Address found but device name mismatch")

    # -------------------------------------------------------------------------
    # 3. VLM Trajectory Verification (Visual confirm of Modbus setup)
    # -------------------------------------------------------------------------
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        # Extract frames from trajectory (Sample 5 frames evenly + final frame)
        frames = [step['observation']['rgb_screen'] for step in traj if 'observation' in step and 'rgb_screen' in step['observation']]
        if frames:
            num_samples = min(5, len(frames))
            indices = [int(i * (len(frames) - 1) / (num_samples - 1)) for i in range(num_samples)] if num_samples > 1 else [0]
            sampled_frames = [frames[i] for i in indices]
            
            try:
                vlm_result = query_vlm(prompt=build_vlm_prompt(), images=sampled_frames)
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("modbus_configured", False):
                    vlm_score += 20
                    feedback_parts.append("VLM visually confirmed Modbus protocol selection")
                
                if parsed.get("ip_entered", False):
                    vlm_score += 20
                    feedback_parts.append("VLM visually confirmed target IP entry")
                    
            except Exception as e:
                logger.error(f"VLM Query failed: {e}")
                feedback_parts.append(f"VLM validation error: {e}")
    else:
        # If VLM unavailable, heavily weight the binary string extraction
        feedback_parts.append("VLM unavailable, extrapolating score from binary extraction")
        if device_found and ip_found:
            vlm_score += 40

    score += vlm_score
    
    # -------------------------------------------------------------------------
    # Final Evaluation
    # -------------------------------------------------------------------------
    # Require File Save + Majority of Tags + Some Modbus Networking
    key_criteria_met = (created_during_task and len(found_tags) >= 4 and (ip_found or vlm_score >= 20))
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }