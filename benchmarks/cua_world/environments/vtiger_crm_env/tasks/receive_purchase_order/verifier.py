#!/usr/bin/env python3
"""
Verifier for receive_purchase_order task.
Checks CRM database fields and workflow progression via VLM.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt to verify that the agent used the UI to complete the task
VLM_PROMPT = """
You are verifying an agent's trajectory in Vtiger CRM.
The task was to open an existing Purchase Order called 'Restock Milwaukee Tools Q1', edit it, and update its Tracking Number to 'FEDEX-883311', Carrier to 'FedEx', and Status to 'Received Shipment'.

Look at the provided trajectory screenshots.
Did the agent successfully navigate to the Purchase Order edit view and enter/select these values in the UI?
Respond in JSON format with a single boolean field "used_ui_properly" and a "reasoning" string.
"""

def verify_receive_purchase_order(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_status = metadata.get('expected_status', 'Received Shipment')
    expected_tracking = metadata.get('expected_tracking', 'FEDEX-883311')
    expected_carrier = metadata.get('expected_carrier', 'FedEx')
    
    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/receive_po_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Verify Database State
    po_found = result.get('po_found', False)
    if not po_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target Purchase Order was not found or was deleted."
        }

    status = result.get('status', '')
    tracking = result.get('tracking_no', '')
    carrier = result.get('carrier', '')
    mtime = result.get('modified_time', 0)
    task_start = result.get('task_start_time', 0)
    
    initial_stock = result.get('initial_stock', 0)
    current_stock = result.get('current_stock', 0)

    # Status Check (30 pts)
    if status == expected_status:
        score += 30
        feedback_parts.append("Status updated to Received Shipment (+30)")
    else:
        feedback_parts.append(f"Status is '{status}' (Expected '{expected_status}')")

    # Tracking Check (20 pts)
    if tracking.strip().upper() == expected_tracking.upper():
        score += 20
        feedback_parts.append("Tracking Number correct (+20)")
    else:
        feedback_parts.append(f"Tracking Number is '{tracking}'")

    # Carrier Check (10 pts)
    if carrier == expected_carrier:
        score += 10
        feedback_parts.append("Carrier correct (+10)")
    else:
        feedback_parts.append(f"Carrier is '{carrier}'")

    # Anti-Gaming / Modified Time Check (10 pts)
    if mtime > task_start:
        score += 10
        feedback_parts.append("Record edited during task time (+10)")
    else:
        feedback_parts.append("Record was NOT modified during the task!")

    # Auto-Increment Inventory Check (10 pts)
    # Vtiger triggers inventory logic on status change.
    if float(current_stock) > float(initial_stock):
        score += 10
        feedback_parts.append(f"Inventory stock auto-incremented from {initial_stock} to {current_stock} (+10)")
    else:
        feedback_parts.append(f"Inventory stock did not increment (Currently: {current_stock})")

    # 3. VLM Verification (20 pts)
    frames = sample_trajectory_frames(traj, n=6)
    vlm_result = None
    if frames and env_info.get('query_vlm'):
        try:
            vlm_response = env_info['query_vlm'](
                images=frames,
                prompt=VLM_PROMPT
            )
            vlm_result = vlm_response.get("parsed", {}).get("used_ui_properly", False)
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            
    if vlm_result:
        score += 20
        feedback_parts.append("VLM verified UI interaction (+20)")
    else:
        feedback_parts.append("VLM could not verify UI interaction")

    # 4. Final calculation
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }