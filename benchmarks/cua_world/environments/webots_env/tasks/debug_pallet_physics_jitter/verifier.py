#!/usr/bin/env python3
"""
Verifier for debug_pallet_physics_jitter task.

A simulation engineer must stabilize a Webots rigid body simulation by tuning ODE solver
parameters (CFM, ERP), setting default damping, and softening contact constraints.

Scoring (100 points total):
  - File exists and was created during the task (anti-gaming): 10 points
  - WorldInfo cfm in range [0.001, 0.01]: 20 points
  - WorldInfo erp in range [0.3, 0.5]: 20 points
  - WorldInfo defaultDamping has linear >= 0.1 and angular >= 0.1: 30 points
  - Cardboard ContactProperties softCFM in range [0.0005, 0.005]: 20 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_debug_pallet_physics_jitter(traj, env_info, task_info):
    """
    Verify that the pallet physics configuration world has been correctly saved.
    Uses robust regex parsing to tolerate GUI vs text-editor formatting variations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/stabilized_pallet.wbt')

    score = 0
    feedback_parts = []

    # --- Read export result metadata ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result metadata: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Anti-gaming: Ensure file was created during the task
    if not result_data.get('created_during_task', True):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was not created/modified during this task session."
        }

    # --- Copy the .wbt file independently ---
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

    # --- 1. Check file existence ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world using File > Save World As."
        }

    score += 10
    feedback_parts.append("File saved successfully")

    # --- 2. Verify WorldInfo CFM ---
    cfm_match = re.search(r'\bcfm\s+([\d.eE+-]+)', wbt_content)
    if cfm_match:
        cfm_val = float(cfm_match.group(1))
        if 0.001 <= cfm_val <= 0.01:
            score += 20
            feedback_parts.append(f"Global cfm tuned ({cfm_val})")
        else:
            feedback_parts.append(f"Global cfm {cfm_val} is outside target range [0.001, 0.01]")
    else:
        feedback_parts.append("Global cfm field not found")

    # --- 3. Verify WorldInfo ERP ---
    erp_match = re.search(r'\berp\s+([\d.eE+-]+)', wbt_content)
    if erp_match:
        erp_val = float(erp_match.group(1))
        if 0.3 <= erp_val <= 0.5:
            score += 20
            feedback_parts.append(f"Global erp tuned ({erp_val})")
        else:
            feedback_parts.append(f"Global erp {erp_val} is outside target range [0.3, 0.5]")
    else:
        feedback_parts.append("Global erp field not found")

    # --- 4. Verify Default Damping ---
    damping_match = re.search(r'defaultDamping\s+Damping\s*\{([^}]+)\}', wbt_content)
    if damping_match:
        damping_block = damping_match.group(1)
        linear_match = re.search(r'linear\s+([\d.eE+-]+)', damping_block)
        angular_match = re.search(r'angular\s+([\d.eE+-]+)', damping_block)
        
        lin_val = float(linear_match.group(1)) if linear_match else 0.0
        ang_val = float(angular_match.group(1)) if angular_match else 0.0
        
        if lin_val >= 0.1 and ang_val >= 0.1:
            score += 30
            feedback_parts.append(f"Default Damping applied (lin:{lin_val}, ang:{ang_val})")
        else:
            feedback_parts.append(f"Damping values too low (lin:{lin_val}, ang:{ang_val})")
    else:
        feedback_parts.append("Damping node missing from defaultDamping field")

    # --- 5. Verify Cardboard ContactProperties softCFM ---
    # Find all ContactProperties blocks and isolate the one for cardboard
    cp_blocks = re.findall(r'ContactProperties\s*\{([^}]+)\}', wbt_content)
    cardboard_softcfm = None
    
    for block in cp_blocks:
        if '"cardboard"' in block:
            soft_match = re.search(r'\bsoftCFM\s+([\d.eE+-]+)', block)
            if soft_match:
                cardboard_softcfm = float(soft_match.group(1))
                break

    if cardboard_softcfm is not None:
        if 0.0005 <= cardboard_softcfm <= 0.005:
            score += 20
            feedback_parts.append(f"Cardboard softCFM correctly softened ({cardboard_softcfm})")
        else:
            feedback_parts.append(f"Cardboard softCFM {cardboard_softcfm} is outside target range")
    else:
        feedback_parts.append("Cardboard softCFM not set or ContactProperties missing")

    # Pass threshold logic
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }