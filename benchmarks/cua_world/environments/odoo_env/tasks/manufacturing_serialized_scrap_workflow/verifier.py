#!/usr/bin/env python3
"""
Verifier for manufacturing_serialized_scrap_workflow task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_manufacturing_serialized_scrap_workflow(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Scrapped the correct damaged serial number (LENS-A001).
    2. Consumed the correct replacement serial number (LENS-A002).
    3. Produced the final product with correct serial (PROJ-X99).
    4. Completed the Manufacturing Order.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Metadata
    metadata = task_info.get('metadata', {})
    damaged_sn = metadata.get('damaged_sn', 'LENS-A001')
    replacement_sn = metadata.get('replacement_sn', 'LENS-A002')
    final_sn = metadata.get('final_sn', 'PROJ-X99')

    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: MO Completed (20 pts)
    mo_state = result.get('mo_state', '')
    if mo_state == 'done':
        score += 20
        feedback.append("Manufacturing Order completed successfully.")
    else:
        feedback.append(f"Manufacturing Order state is '{mo_state}', expected 'done'.")

    # Check 2: Scrap Record (30 pts)
    # The agent MUST scrap the damaged unit.
    scrap_lot = result.get('scrap_lot', '')
    if result.get('scrap_found') and damaged_sn in str(scrap_lot):
        score += 30
        feedback.append(f"Correct component '{damaged_sn}' was scrapped.")
    else:
        feedback.append(f"Failed to find scrap record for '{damaged_sn}'. Found: {scrap_lot}")

    # Check 3: Correct Replacement Consumed (30 pts)
    consumed_lot = result.get('consumed_lot', '')
    if consumed_lot and replacement_sn in consumed_lot:
        score += 30
        feedback.append(f"Correct replacement '{replacement_sn}' was consumed.")
    else:
        if damaged_sn in str(consumed_lot):
            feedback.append(f"CRITICAL: Damaged component '{damaged_sn}' was consumed instead of replacement!")
        else:
            feedback.append(f"Expected consumption of '{replacement_sn}', found: '{consumed_lot}'.")

    # Check 4: Final SN Assigned (20 pts)
    produced_lot = result.get('produced_lot', '')
    if produced_lot and final_sn in produced_lot:
        score += 20
        feedback.append(f"Final product assigned correct Serial Number '{final_sn}'.")
    else:
        feedback.append(f"Final product Serial Number mismatch. Expected '{final_sn}', found '{produced_lot}'.")

    passed = (score >= 70) and (mo_state == 'done')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }