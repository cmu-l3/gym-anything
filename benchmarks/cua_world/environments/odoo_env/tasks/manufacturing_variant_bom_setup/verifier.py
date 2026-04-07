#!/usr/bin/env python3
"""
Verifier for manufacturing_variant_bom_setup task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manufacturing_variant_bom_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback = []

    # 1. BoM Existence (20 pts)
    if result.get('bom_exists'):
        score += 20
        feedback.append("Master BoM created successfully.")
    else:
        feedback.append("No BoM found for the Ergo-Flex Desk template.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Logic Verification (60 pts total)
    logic = result.get('logic_correct', {})
    
    # Universal parts (10 pts)
    if logic.get('frame') and logic.get('hardware'):
        score += 10
        feedback.append("Universal components configured correctly (Frame, Hardware).")
    else:
        feedback.append("Universal components missing or incorrectly restricted.")

    # Motors (15 pts)
    if logic.get('motor_std') and logic.get('motor_pro'):
        score += 15
        feedback.append("Motor variants configured correctly.")
    else:
        feedback.append("Motor configuration incorrect (Standard vs Pro logic).")

    # Tops (15 pts)
    if logic.get('top_oak') and logic.get('top_white'):
        score += 15
        feedback.append("Desktop finish variants configured correctly.")
    else:
        feedback.append("Desktop finish configuration incorrect.")

    # Accessory (20 pts)
    if logic.get('cable_tray'):
        score += 20
        feedback.append("Pro-only accessory (Cable Tray) configured correctly.")
    else:
        feedback.append("Cable Tray not correctly restricted to Pro edition.")

    # 3. MO Verification (20 pts)
    if result.get('mo_created'):
        if result.get('mo_components_correct'):
            score += 20
            feedback.append("Verification MO created with correct component list.")
        else:
            score += 5 # Partial for creating MO
            found = result.get('mo_components_found', [])
            feedback.append(f"MO created but components were incorrect. Found: {found}")
    else:
        feedback.append("No verification Manufacturing Order found for 'Pro, White' variant.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }