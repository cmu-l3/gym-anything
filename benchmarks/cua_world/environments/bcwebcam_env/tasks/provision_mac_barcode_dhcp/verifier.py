#!/usr/bin/env python3
"""
Verifier for the Provision Network Switch from MAC Barcode task.

Verification Strategy:
1. Programmatic Config Check: Parses the DHCP config file for the new reservation.
2. Syntax Validation: Ensures ISC DHCP syntax is respected.
3. Content Validation: Checks for the correct Hostname, IP, and formatted MAC address.
4. Anti-Gaming Timestamp Check: Ensures the file was modified AFTER the task started.
5. Evidence Check: Confirms the agent saved the requested evidence screenshot.
6. VLM Check (Optional/Fallback): Analyzes trajectory frames to ensure bcWebCam was actively utilized.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_mac_barcode_dhcp(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_mac_raw = metadata.get('expected_mac_raw', 'F8B156D92A14')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result.get('task_start', 0)
    config_exists = result.get('config_exists', False)
    config_content = result.get('config_content', "")
    config_mtime = result.get('config_mtime', 0)
    evidence_exists = result.get('evidence_exists', False)

    # Criterion 1: File Modified (10 points) - Anti-Gaming
    if config_exists and config_mtime >= task_start:
        score += 10
        feedback_parts.append("Config file was modified during task (+10)")
    else:
        feedback_parts.append("Config file was NOT modified during the task")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Extract the Switch-IDF-02 block
    block_pattern = re.compile(r"host\s+Switch-IDF-02\s*\{([^}]+)\}", re.IGNORECASE)
    block_match = block_pattern.search(config_content)
    
    mac_correctly_formatted = False
    mac_value_accurate = False

    if block_match:
        block_text = block_match.group(1)
        
        # Criterion 2: Syntax Correctness (20 points)
        # Check if hardware ethernet and fixed-address statements exist with semicolons
        mac_stmt = re.search(r"hardware\s+ethernet\s+([0-9a-fA-F:-]+)\s*;", block_text, re.IGNORECASE)
        ip_stmt = re.search(r"fixed-address\s+([0-9\.]+)\s*;", block_text, re.IGNORECASE)
        
        if mac_stmt and ip_stmt:
            score += 20
            feedback_parts.append("ISC DHCP syntax correctly formatted (+20)")
            
            # Criterion 3: IP & Hostname Correct (10 points)
            ip_val = ip_stmt.group(1)
            if ip_val == "10.1.20.5":
                score += 10
                feedback_parts.append("Hostname and IP address are correct (+10)")
            else:
                feedback_parts.append(f"Incorrect IP address: {ip_val}")
                
            # Evaluate MAC Address
            mac_val = mac_stmt.group(1).strip()
            
            # Criterion 4: MAC Formatting (20 points)
            # Standard MAC: exactly 17 chars long and containing 5 colons
            is_properly_formatted = bool(re.match(r"^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$", mac_val))
            if is_properly_formatted:
                score += 20
                mac_correctly_formatted = True
                feedback_parts.append("MAC address strictly formatted with colons (+20)")
            else:
                feedback_parts.append(f"MAC address is not formatted with colons: {mac_val}")
                
            # Criterion 5: MAC Accuracy (30 points)
            # Strip formatting to compare raw hexadecimal content
            cleaned_mac = mac_val.replace(":", "").replace("-", "").upper()
            if cleaned_mac == expected_mac_raw:
                score += 30
                mac_value_accurate = True
                feedback_parts.append("MAC address perfectly matches ground truth (+30)")
            else:
                feedback_parts.append(f"MAC address mismatch (Expected: {expected_mac_raw}, Got: {cleaned_mac})")
        else:
            feedback_parts.append("ISC DHCP Syntax error inside host block")
    else:
        feedback_parts.append("Host block 'Switch-IDF-02' not found or incorrectly structured")

    # Criterion 6: Evidence Capture (10 points)
    if evidence_exists:
        score += 10
        feedback_parts.append("Screenshot evidence saved (+10)")
    else:
        feedback_parts.append("Screenshot evidence missing")

    # Optional Trajectory VLM Check
    # Verify bcWebCam is present in the visual trajectory to prevent scripted backdoor gaming
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = """Analyze these desktop screenshots taken during an agent's task.
            1. Is the 'bcWebCam' application visible anywhere?
            Respond in JSON: {"bcwebcam_visible": true/false}"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if not parsed.get('bcwebcam_visible', True):
                    feedback_parts.append("VLM WARNING: bcWebCam not detected in trajectory!")
                    # Severe penalty for bypassing the core application requirement
                    score = max(0, score - 50)
    except ImportError:
        logger.warning("VLM module not available, skipping trajectory validation.")

    # Pass logic
    # Total possible is 100. Require at least 80 (Meaning they must have extracted and placed the exact MAC correctly).
    passed = (score >= 80) and mac_value_accurate and mac_correctly_formatted

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }