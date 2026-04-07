#!/usr/bin/env python3
"""
Verifier for sales_phantom_kit_assembly task.

Scoring Criteria:
1. Kit Product Created (10 pts)
2. BoM Created with type 'Kit/Phantom' (30 pts)
3. BoM contains correct components (20 pts)
4. Sales Order Confirmed (10 pts)
5. Delivery Order Exploded Correctly (Components moved, not Kit) (20 pts)
6. Delivery Validated/Done (10 pts)
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sales_phantom_kit_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from VM
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error in verification script: {result['error']}"}

    score = 0
    feedback = []

    # Criterion 1: Product Created
    if result.get('kit_product_created'):
        score += 10
        feedback.append("Kit product created.")
    else:
        feedback.append("Kit product NOT found.")

    # Criterion 2: BoM Type (Critical)
    if result.get('bom_created'):
        if result.get('bom_type_is_kit'):
            score += 30
            feedback.append("BoM created correctly as 'Kit' (Phantom).")
        else:
            feedback.append("BoM created but type is NOT 'Kit' (likely 'Manufacture').")
    else:
        feedback.append("No BoM found for the kit product.")

    # Criterion 3: BoM Components
    if result.get('bom_components_correct'):
        score += 20
        feedback.append("BoM contains the correct 3 components.")
    else:
        feedback.append("BoM components mismatch or missing.")

    # Criterion 4: SO Confirmed
    if result.get('so_confirmed'):
        score += 10
        feedback.append("Sales Order confirmed.")
    else:
        feedback.append("Sales Order not found or not confirmed.")

    # Criterion 5: Delivery Explosion (Critical verification of phantom behavior)
    if result.get('delivery_moves_exploded'):
        score += 20
        feedback.append("Delivery correctly lists individual components (Kit exploded).")
    elif result.get('delivery_exists'):
        feedback.append("Delivery exists but contains the Kit product (Phantom behavior failed).")
    else:
        feedback.append("No Delivery found.")

    # Criterion 6: Delivery Done
    if result.get('delivery_state_done'):
        score += 10
        feedback.append("Delivery validated (shipped).")
    else:
        feedback.append("Delivery not validated.")

    # VLM Sanity Check (Optional but good for robustness)
    # Check if we see the BoM configuration screen in the trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if images and score >= 50:
        vlm_resp = query_vlm(
            images=images,
            prompt="Does the user interaction show configuring a Bill of Materials (BoM) or Product settings in Odoo? Look for 'BoM Type', 'Kit', or component lists."
        )
        if vlm_resp.get('success') and vlm_resp.get('parsed', {}).get('confidence', 'low') == 'high':
            # Could add bonus points or just use as validation log
            logger.info("VLM confirmed BoM interaction.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }