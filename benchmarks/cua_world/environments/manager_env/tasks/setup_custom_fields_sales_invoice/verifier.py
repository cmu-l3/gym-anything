#!/usr/bin/env python3
"""
Verifier for setup_custom_fields_sales_invoice task.

Criteria:
1. "Customer PO Number" exists in Custom Fields settings (20 pts)
2. "Vehicle Registration" exists in Custom Fields settings (20 pts)
3. "Customer PO Number" visible on Sales Invoice form (20 pts)
4. "Vehicle Registration" visible on Sales Invoice form (20 pts)
5. VLM Verification of trajectory/screenshots (20 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_custom_fields(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Programmatic Checks (80 pts max)
    
    # Check 1: Custom Field Definitions (Settings List)
    if result.get('po_in_list'):
        score += 20
        feedback_parts.append("'Customer PO Number' defined")
    else:
        feedback_parts.append("'Customer PO Number' missing from settings")

    if result.get('veh_in_list'):
        score += 20
        feedback_parts.append("'Vehicle Registration' defined")
    else:
        feedback_parts.append("'Vehicle Registration' missing from settings")

    # Check 2: Form Placement (Visible on Sales Invoice)
    # This proves they selected the correct "Placement" option
    if result.get('po_on_form'):
        score += 20
        feedback_parts.append("'Customer PO Number' active on Invoice form")
    else:
        feedback_parts.append("'Customer PO Number' NOT on Invoice form (check placement)")

    if result.get('veh_on_form'):
        score += 20
        feedback_parts.append("'Vehicle Registration' active on Invoice form")
    else:
        feedback_parts.append("'Vehicle Registration' NOT on Invoice form (check placement)")

    # 2. VLM Verification (20 pts max)
    # We check if the agent actually interacted with the UI meaningfully
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user configuring Manager.io accounting software.
    The goal is to create two Custom Fields: 'Customer PO Number' and 'Vehicle Registration'.
    
    Look for:
    1. The 'Settings' or 'Custom Fields' screen.
    2. A form creating a new field with text 'Customer PO Number'.
    3. A form creating a new field with text 'Vehicle Registration'.
    4. A Sales Invoice form showing these fields (optional but good).
    
    Did the user perform these actions?
    Respond in JSON: {"success": true/false, "confidence": 0-10, "details": "string"}
    """
    
    try:
        # Use frames to detect the workflow
        vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        vlm_data = vlm_result.get('parsed', {})
        
        if vlm_data.get('success', False):
            score += 20
            feedback_parts.append("VLM verified configuration workflow")
        else:
            feedback_parts.append("VLM could not verify workflow visually")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Don't penalize too heavily if programmatic passed
        if score >= 60:
            score += 10 
            feedback_parts.append("VLM check skipped (error)")

    passed = score >= 55  # Requires at least some programmatic success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }