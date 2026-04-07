#!/usr/bin/env python3
"""
Verifier for configure_mining_remote_monitoring task.

A robotics engineer must configure a mining robot's communication and display devices,
and add atmospheric Fog to simulate mine dust conditions.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - Emitter range = 500: 15 points
  - Emitter channel = 7: 15 points
  - Display width = 320: 15 points
  - Display height = 240: 15 points
  - Fog node present with visibilityRange in [40.0, 60.0]: 20 points
  - Fog fogType = "EXPONENTIAL": 10 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_node_block(content, node_type, node_def=None):
    """
    Extracts the block of a node from the Webots scene content.
    Handles nested braces to capture the full node block.
    """
    if node_def:
        pattern = f'DEF {node_def} {node_type} {{'
    else:
        pattern = f'{node_type} {{'
        
    start_idx = content.find(pattern)
    if start_idx == -1:
        return None
        
    brace_start = content.find('{', start_idx)
    depth = 0
    for i in range(brace_start, len(content)):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
            if depth == 0:
                return content[start_idx:i+1]
    return None

def verify_configure_mining_remote_monitoring(traj, env_info, task_info):
    """
    Verify that the mining simulation world has been correctly saved with new configs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/mining_robot_configured.wbt')
    
    score = 0
    feedback_parts = []
    
    # --- Try to copy the .wbt file independently ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None
    
    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    # --- Check file existence and integrity ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world using File > Save World As."
        }
        
    score += 10
    feedback_parts.append("World file saved at correct path")

    # Anti-gaming: Ensure original components still exist (agent didn't just save an empty world)
    if "MINING_ROBOT" not in wbt_content or "radio_emitter" not in wbt_content:
        return {
            "passed": False,
            "score": score,
            "feedback": "Original robot or devices missing from the saved world. Did you accidentally overwrite the world with an empty scene?"
        }

    # --- Extract device and environment blocks ---
    emitter_block = extract_node_block(wbt_content, "Emitter", "radio_emitter")
    display_block = extract_node_block(wbt_content, "Display", "status_display")
    fog_block = extract_node_block(wbt_content, "Fog")

    # --- Check Emitter modifications ---
    if emitter_block:
        range_match = re.search(r'range\s+([\d.]+)', emitter_block)
        if range_match and float(range_match.group(1)) == 500.0:
            score += 15
            feedback_parts.append("Emitter range set to 500")
        else:
            feedback_parts.append("Emitter range not set to 500")
            
        channel_match = re.search(r'channel\s+(\d+)', emitter_block)
        if channel_match and int(channel_match.group(1)) == 7:
            score += 15
            feedback_parts.append("Emitter channel set to 7")
        else:
            feedback_parts.append("Emitter channel not set to 7")
    else:
        feedback_parts.append("Emitter 'radio_emitter' block not found")

    # --- Check Display modifications ---
    if display_block:
        width_match = re.search(r'width\s+(\d+)', display_block)
        if width_match and int(width_match.group(1)) == 320:
            score += 15
            feedback_parts.append("Display width set to 320")
        else:
            feedback_parts.append("Display width not set to 320")
            
        height_match = re.search(r'height\s+(\d+)', display_block)
        if height_match and int(height_match.group(1)) == 240:
            score += 15
            feedback_parts.append("Display height set to 240")
        else:
            feedback_parts.append("Display height not set to 240")
    else:
        feedback_parts.append("Display 'status_display' block not found")

    # --- Check Fog node additions ---
    if fog_block:
        vis_match = re.search(r'visibilityRange\s+([\d.]+)', fog_block)
        if vis_match:
            vis = float(vis_match.group(1))
            if 40.0 <= vis <= 60.0:
                score += 20
                feedback_parts.append(f"Fog visibilityRange set correctly ({vis})")
            else:
                feedback_parts.append(f"Fog visibilityRange is {vis}, expected 50.0")
        else:
            feedback_parts.append("Fog visibilityRange field not found")
            
        type_match = re.search(r'fogType\s+"([^"]+)"', fog_block)
        if type_match and type_match.group(1) == "EXPONENTIAL":
            score += 10
            feedback_parts.append("Fog fogType correctly set to EXPONENTIAL")
        else:
            feedback_parts.append("Fog fogType not set to EXPONENTIAL")
    else:
        feedback_parts.append("Fog node not found. Add a Fog node to the world root to simulate mine dust.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }