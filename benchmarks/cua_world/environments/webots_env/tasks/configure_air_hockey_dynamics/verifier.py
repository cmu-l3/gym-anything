#!/usr/bin/env python3
"""
Verifier for configure_air_hockey_dynamics task.

Evaluates if the agent properly configured the contact properties in Webots.
Requires:
1. Puck & Table pair -> coulombFriction <= 0.01 (ideally 0.002)
2. Puck & Wall pair -> bounce >= 0.90 (ideally 0.95)
3. Puck & Striker pair -> 0.80 <= bounce <= 0.89 (ideally 0.85)
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_air_hockey_dynamics(traj, env_info, task_info):
    """
    Verify the air hockey physics configuration was correctly saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/air_hockey_ready.wbt')
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch export result metadata
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Failed to read task result JSON: {e}")
        result_meta = {}

    if not result_meta.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Target file {output_path} not found. Ensure you save using File > Save World As."
        }

    score += 10
    feedback_parts.append("File correctly saved")

    # 2. Fetch the actual WBT file to parse properties
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Could not read the saved world file: {e}"
        }

    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": score,
            "feedback": "Saved world file is suspiciously small or empty."
        }

    # 3. Parse ContactProperties nodes
    # Find all ContactProperties { ... } blocks
    blocks = re.findall(r'ContactProperties\s*\{([^}]+)\}', wbt_content)
    
    pairs_found = {}
    
    for block in blocks:
        # Extract materials
        m1_match = re.search(r'material1\s+"([^"]+)"', block)
        m2_match = re.search(r'material2\s+"([^"]+)"', block)
        
        # Extract properties
        fric_match = re.search(r'coulombFriction\s*(?:\[\s*)?([\d.]+)', block)
        bounce_match = re.search(r'bounce\s+([\d.]+)', block)
        
        if m1_match and m2_match:
            m1 = m1_match.group(1)
            m2 = m2_match.group(1)
            pair_key = tuple(sorted([m1, m2]))
            
            fric = float(fric_match.group(1)) if fric_match else -1.0
            bounce = float(bounce_match.group(1)) if bounce_match else -1.0
            
            pairs_found[pair_key] = {'fric': fric, 'bounce': bounce}

    # 4. Evaluate parsed properties
    # Criteria 1: Puck & Table
    pt_key = tuple(sorted(["puck", "table"]))
    if pt_key in pairs_found:
        score += 10
        fric = pairs_found[pt_key]['fric']
        if fric != -1.0 and fric <= 0.01:
            score += 20
            feedback_parts.append(f"Puck-Table friction correct ({fric})")
        else:
            feedback_parts.append(f"Puck-Table exists but friction incorrect ({fric})")
    else:
        feedback_parts.append("Puck-Table ContactProperties missing")

    # Criteria 2: Puck & Wall
    pw_key = tuple(sorted(["puck", "wall"]))
    if pw_key in pairs_found:
        score += 10
        bounce = pairs_found[pw_key]['bounce']
        if bounce >= 0.90:
            score += 20
            feedback_parts.append(f"Puck-Wall bounce correct ({bounce})")
        else:
            feedback_parts.append(f"Puck-Wall exists but bounce incorrect ({bounce})")
    else:
        feedback_parts.append("Puck-Wall ContactProperties missing")

    # Criteria 3: Puck & Striker
    ps_key = tuple(sorted(["puck", "striker"]))
    if ps_key in pairs_found:
        score += 10
        bounce = pairs_found[ps_key]['bounce']
        if 0.80 <= bounce <= 0.89:
            score += 20
            feedback_parts.append(f"Puck-Striker bounce correct ({bounce})")
        else:
            feedback_parts.append(f"Puck-Striker exists but bounce incorrect ({bounce})")
    else:
        feedback_parts.append("Puck-Striker ContactProperties missing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }