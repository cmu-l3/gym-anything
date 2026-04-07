#!/usr/bin/env python3
"""
Verifier for panoramic_visual_system_setup task.
Checks existence of 3 INI files and correct geometric/network calculations.
"""

import json
import os
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_panoramic_setup(traj, env_info, task_info):
    """
    Verify the configuration of the 3-channel visual system.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_fov = metadata.get('expected_fov_per_channel', 50.0)
    expected_rotations = metadata.get('expected_rotations', {'left': -50, 'center': 0, 'right': 50})
    network_cfg = metadata.get('network_config', {})
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    files_found = result.get('files_found', {})
    configs = result.get('configs', {})
    
    # Check 1: File Existence (10 pts)
    # visual_left.ini, visual_center.ini, visual_right.ini
    missing = [f for f, found in files_found.items() if not found]
    if not missing:
        score += 10
        feedback_parts.append("All files created.")
    else:
        feedback_parts.append(f"Missing files: {', '.join(missing)}.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: FOV Calculation (25 pts)
    # view_angle should be ~50 in all files
    fov_correct_count = 0
    for fname, cfg in configs.items():
        try:
            val = float(cfg.get('view_angle', -999))
            if abs(val - expected_fov) < 0.5:
                fov_correct_count += 1
        except (ValueError, TypeError):
            pass
    
    if fov_correct_count == 3:
        score += 25
        feedback_parts.append("FOV calculated correctly (50 deg).")
    elif fov_correct_count > 0:
        score += 10
        feedback_parts.append(f"FOV correct in {fov_correct_count}/3 files.")
    else:
        feedback_parts.append("FOV incorrect (expected 50).")

    # Check 3: Rotations (10 pts Center + 30 pts Sides)
    # Center
    center_cfg = configs.get('visual_center.ini', {})
    try:
        c_rot = float(center_cfg.get('look_rotation', -999))
        if abs(c_rot - expected_rotations['center']) < 0.5:
            score += 10
            feedback_parts.append("Center rotation correct (0).")
        else:
            feedback_parts.append(f"Center rotation incorrect ({c_rot}).")
    except:
        feedback_parts.append("Center rotation missing/invalid.")

    # Sides
    left_cfg = configs.get('visual_left.ini', {})
    right_cfg = configs.get('visual_right.ini', {})
    sides_correct = 0
    try:
        l_rot = float(left_cfg.get('look_rotation', -999))
        if abs(l_rot - expected_rotations['left']) < 0.5:
            sides_correct += 1
    except: pass
    
    try:
        r_rot = float(right_cfg.get('look_rotation', -999))
        if abs(r_rot - expected_rotations['right']) < 0.5:
            sides_correct += 1
    except: pass
    
    if sides_correct == 2:
        score += 30
        feedback_parts.append("Side rotations correct (-50, +50).")
    elif sides_correct == 1:
        score += 15
        feedback_parts.append("One side rotation correct.")
    else:
        feedback_parts.append("Side rotations incorrect.")

    # Check 4: Network Config (15 pts)
    net_correct_count = 0
    for fname, cfg in configs.items():
        slave = str(cfg.get('network_slave', '')).strip()
        ip = str(cfg.get('server_ip', '')).strip()
        if slave == '1' and ip == network_cfg.get('ip'):
            net_correct_count += 1
    
    if net_correct_count == 3:
        score += 15
        feedback_parts.append("Network config correct.")
    else:
        score += (net_correct_count * 5)
        feedback_parts.append(f"Network config correct in {net_correct_count}/3 files.")

    # Check 5: Resolution/Graphics (10 pts)
    # width=1920, height=1080, fullscreen=1
    gfx_correct_count = 0
    for fname, cfg in configs.items():
        w = str(cfg.get('screen_width', ''))
        h = str(cfg.get('screen_height', ''))
        fs = str(cfg.get('fullscreen', ''))
        if w == '1920' and h == '1080' and fs == '1':
            gfx_correct_count += 1
            
    if gfx_correct_count == 3:
        score += 10
        feedback_parts.append("Graphics settings correct.")
    else:
        score += (gfx_correct_count * 3)
        feedback_parts.append("Graphics settings incomplete.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }