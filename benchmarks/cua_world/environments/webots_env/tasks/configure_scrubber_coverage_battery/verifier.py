#!/usr/bin/env python3
"""
Verifier for configure_scrubber_coverage_battery task.

A robotics software engineer must configure an autonomous scrubber simulation by:
1. Adding a Pen node to track the 65cm cleaning deck coverage path.
2. Configuring the robot's battery parameter array for endurance tracking.

Scoring (100 points total):
  - File exists and created during task: 10 points
  - Pen Node added and named "cleaning_trace": 20 points
  - Pen dimensions (leadSize 0.65, maxDistance 0.5): 20 points
  - Pen appearance (inkColor 0 0 1): 15 points
  - Pen active (write TRUE): 15 points
  - Battery configured to [8640000, 8640000, 2000]: 20 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_block(content: str, start_index: int) -> str:
    """Extracts a matching braced block from a string starting at start_index."""
    brace_depth = 0
    in_block = False
    block = ""
    for i in range(start_index, len(content)):
        char = content[i]
        block += char
        if char == '{':
            brace_depth += 1
            in_block = True
        elif char == '}':
            brace_depth -= 1
            if in_block and brace_depth == 0:
                break
    return block

def verify_configure_scrubber_coverage_battery(traj, env_info, task_info):
    """
    Verify that the Scrubber world has been correctly configured with a Pen and Battery.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/factory_scrubber_configured.wbt')
    
    score = 0
    feedback_parts = []

    # --- Step 1: Check basic file metadata ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_scrubber_coverage_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception:
        export_result = {"file_exists": False}

    if not export_result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world via File > Save World As."
        }
        
    if not export_result.get("created_during_task", False):
        feedback_parts.append("Warning: Output file timestamp indicates it might not have been created during this task attempt.")
    else:
        score += 10
        feedback_parts.append("File correctly created and saved")

    # --- Step 2: Extract the .wbt content ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file from VM: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    if len(wbt_content) < 100:
        return {"passed": False, "score": 0, "feedback": "Saved world file is suspiciously empty or unreadable."}

    # --- Step 3: Extract SCRUBBER_ROBOT block ---
    robot_start_idx = wbt_content.find('DEF SCRUBBER_ROBOT Robot')
    if robot_start_idx == -1:
        return {"passed": False, "score": score, "feedback": "DEF SCRUBBER_ROBOT Robot node missing from the saved world."}
    
    robot_block = extract_block(wbt_content, robot_start_idx)

    # --- Step 4: Extract Pen node block inside robot ---
    pen_start_idx = robot_block.find('Pen {')
    has_pen = (pen_start_idx != -1)
    
    if has_pen:
        pen_block = extract_block(robot_block, pen_start_idx)
        
        # Check Name
        name_match = re.search(r'name\s+"([^"]+)"', pen_block)
        if name_match and name_match.group(1) == "cleaning_trace":
            score += 20
            feedback_parts.append("Pen node 'cleaning_trace' added successfully")
        else:
            actual_name = name_match.group(1) if name_match else "unknown"
            feedback_parts.append(f"Pen found but named '{actual_name}', expected 'cleaning_trace'")
            
        # Check Dimensions
        lead_match = re.search(r'leadSize\s+([\d.]+)', pen_block)
        max_dist_match = re.search(r'maxDistance\s+([\d.]+)', pen_block)
        
        lead_ok = False
        dist_ok = False
        if lead_match and float(lead_match.group(1)) == 0.65:
            lead_ok = True
        if max_dist_match and float(max_dist_match.group(1)) == 0.5:
            dist_ok = True
            
        if lead_ok and dist_ok:
            score += 20
            feedback_parts.append("Pen dimensions (leadSize, maxDistance) correct")
        else:
            feedback_parts.append("Pen dimensions incorrect (expected leadSize 0.65 and maxDistance 0.5)")
            
        # Check Appearance
        ink_match = re.search(r'inkColor\s+([\d.\s]+)', pen_block)
        if ink_match:
            ink_vals = [float(x) for x in ink_match.group(1).strip().split()]
            if ink_vals == [0.0, 0.0, 1.0]:
                score += 15
                feedback_parts.append("Pen inkColor correctly set to blue (0 0 1)")
            else:
                feedback_parts.append(f"Pen inkColor incorrect, found {ink_vals}, expected [0.0, 0.0, 1.0]")
        else:
            feedback_parts.append("Pen inkColor not found")
            
        # Check Active State
        write_match = re.search(r'write\s+(TRUE|FALSE)', pen_block)
        if write_match and write_match.group(1) == "TRUE":
            score += 15
            feedback_parts.append("Pen write field enabled (TRUE)")
        else:
            feedback_parts.append("Pen write field not enabled (should be TRUE)")
            
    else:
        feedback_parts.append("Pen node not found in robot's children list")

    # --- Step 5: Check Battery ---
    battery_match = re.search(r'battery\s*\[(.*?)\]', robot_block)
    if battery_match:
        # Webots saves array values spaced out, e.g. "8640000 8640000 2000" or with commas
        vals_str = battery_match.group(1).replace(',', ' ')
        vals = [float(x) for x in vals_str.split() if x.strip()]
        
        if len(vals) == 3 and vals[0] == 8640000 and vals[1] == 8640000 and vals[2] == 2000:
            score += 20
            feedback_parts.append("Battery configured correctly")
        else:
            feedback_parts.append(f"Battery array incorrect: found {vals}, expected [8640000, 8640000, 2000]")
    else:
        feedback_parts.append("Battery array not found or remains unconfigured")

    # --- Final Conclusion ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }