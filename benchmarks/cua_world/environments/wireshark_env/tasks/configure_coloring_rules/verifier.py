#!/usr/bin/env python3
"""
Verifier for configure_coloring_rules task.

Checks:
1. Validates ~/.config/wireshark/coloringrules for correct filter strings and colors.
2. Validates the identified frame number against ground truth.
3. Checks for evidence screenshot.
"""

import json
import base64
import tempfile
import os
import re

def verify_coloring_rules(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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
    
    # Metadata
    metadata = task_info.get('metadata', {})
    expected_rst_filter = metadata.get('expected_rst_filter', 'tcp.flags.reset == 1')
    expected_syn_filter = metadata.get('expected_syn_filter', 'tcp.flags.syn == 1 && tcp.flags.ack == 0')
    
    # Parse Config Content
    config_b64 = result.get('config_content_b64', '')
    config_content = ""
    if config_b64:
        try:
            config_content = base64.b64decode(config_b64).decode('utf-8', errors='ignore')
        except:
            feedback_parts.append("Failed to decode configuration file")

    # Wireshark coloring rules format: @Name@Filter@[bg_r,bg_g,bg_b]@[fg_r,fg_g,fg_b]
    # Colors are 16-bit (0-65535). 
    # Red: [65535,0,0] (approx)
    # White: [65535,65535,65535]
    # Yellow: [65535,65535,0]
    # Black: [0,0,0]
    
    # Normalize content for checking (remove spaces inside brackets for easier regex)
    # Actually, simpler to just check containment of key parts
    
    # --- Criterion 1: RST Rule (25 pts) ---
    has_rst_rule = False
    if "Alert_High_RST" in config_content:
        if expected_rst_filter in config_content:
            # Check colors (Red Background)
            # Regex for Red BG: @\[65535,\s*0,\s*0\]
            if re.search(r"@\[65535,\s*0,\s*0\]", config_content):
                score += 25
                has_rst_rule = True
                feedback_parts.append("RST Rule correctly configured (Name, Filter, Color)")
            else:
                score += 15
                feedback_parts.append("RST Rule found but color is incorrect (expected Red)")
        else:
            score += 5
            feedback_parts.append("RST Rule name found but filter is incorrect")
    else:
        feedback_parts.append("RST Rule 'Alert_High_RST' not found")

    # --- Criterion 2: SYN Rule (25 pts) ---
    has_syn_rule = False
    if "Alert_Medium_SYN" in config_content:
        # Check filter (handle potential spacing differences in &&)
        # We'll just look for the key parts or normalize spaces
        normalized_config = config_content.replace(" ", "")
        normalized_syn_filter = expected_syn_filter.replace(" ", "")
        
        if normalized_syn_filter in normalized_config:
            # Check colors (Yellow Background: [65535, 65535, 0])
            if re.search(r"@\[65535,\s*65535,\s*0\]", config_content):
                score += 25
                has_syn_rule = True
                feedback_parts.append("SYN Rule correctly configured")
            else:
                score += 15
                feedback_parts.append("SYN Rule found but color is incorrect (expected Yellow)")
        else:
            score += 5
            feedback_parts.append("SYN Rule name found but filter is incorrect")
    else:
        feedback_parts.append("SYN Rule 'Alert_Medium_SYN' not found")

    # --- Criterion 3: Configuration Saved (20 pts) ---
    # Implicitly checked if rules were found in the file, but let's give points for the file existing and being modified
    if result.get('config_exists'):
        # If we found at least one rule, we assume it was saved correctly
        if has_rst_rule or has_syn_rule:
            score += 20
            feedback_parts.append("Configuration saved successfully")
        elif len(config_content) > 20: # Arbitrary small size to check it's not empty
            score += 10
            feedback_parts.append("Configuration file exists but rules missing")
    else:
        feedback_parts.append("Configuration file not found")

    # --- Criterion 4: Correct Packet ID (20 pts) ---
    user_frame = str(result.get('user_frame_number', ''))
    ground_truth_frame = str(result.get('ground_truth_frame', ''))
    
    if user_frame and user_frame == ground_truth_frame:
        score += 20
        feedback_parts.append(f"Correctly identified RST packet frame #{user_frame}")
    elif user_frame:
        feedback_parts.append(f"Wrong frame number identified (Got: {user_frame}, Expected: {ground_truth_frame})")
    else:
        feedback_parts.append("No frame number output found")

    # --- Criterion 5: Evidence Screenshot (10 pts) ---
    if result.get('user_screenshot_exists'):
        score += 10
        feedback_parts.append("Evidence screenshot created")
    else:
        feedback_parts.append("Missing evidence screenshot")

    passed = (score >= 70) and has_rst_rule
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }