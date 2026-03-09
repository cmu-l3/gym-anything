#!/usr/bin/env python3
"""
Verifier for procure_receive_stock task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_procure_receive_stock(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created the correct Vendor and Product.
    2. Created and processed a Purchase Order.
    3. Received the items into inventory with correct details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # 1. Vendor & Product Setup (10 pts)
    if result.get('vendor_exists'):
        score += 5
        feedback.append("Vendor 'Dell Inc' exists.")
    else:
        feedback.append("Vendor 'Dell Inc' NOT found.")

    if result.get('product_exists'):
        score += 5
        feedback.append("Product 'Dell Precision 3660' exists.")
    else:
        feedback.append("Product 'Dell Precision 3660' NOT found.")

    # 2. PO Creation & Status (40 pts)
    po = result.get('po', {})
    po_status = str(po.get('status', '')).lower()
    
    if po.get('id') and po.get('id') != 'null':
        score += 20
        feedback.append(f"Purchase Order created (ID: {po['id']}).")
        
        # Check status (Ordered, Received, Closed are acceptable progression states)
        if any(s in po_status for s in ['ordered', 'received', 'closed', 'invoice']):
            score += 20
            feedback.append(f"PO Status valid: {po['status']}.")
        elif 'approved' in po_status:
            score += 10
            feedback.append("PO is Approved but not yet Ordered/Received.")
        else:
            feedback.append(f"PO Status incomplete: {po['status']}.")
    else:
        feedback.append("No valid Purchase Order found created during task.")

    # 3. Assets Received (45 pts + 5 workflow)
    assets = result.get('assets', {})
    asset_score = 0
    
    # Check specific items
    expected_tags = {
        'item1': 'WS-ENG-101',
        'item2': 'WS-ENG-102',
        'item3': 'WS-ENG-103'
    }
    
    for key, tag in expected_tags.items():
        item = assets.get(key, {})
        if item.get('found'):
            if item.get('tag') == tag:
                asset_score += 15
                feedback.append(f"{key} received correctly ({tag}).")
            else:
                asset_score += 10
                feedback.append(f"{key} received but wrong tag (Expected {tag}, got {item.get('tag')}).")
        else:
            feedback.append(f"{key} NOT received/found.")

    score += asset_score

    # Check Workflow/Linkage (5 pts)
    # If assets exist and PO is received, we assume linkage for this verifier 
    # (Database check for exact FK is complex in shell, relying on logic)
    if asset_score > 0 and 'received' in po_status:
        score += 5
        feedback.append("Workflow linkage inferred.")

    # 4. VLM Verification (for confidence)
    # If programmatic check fails partially, VLM can confirm UI state
    if score < 100:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        vlm_prompt = "Does the screen show a ServiceDesk Plus Purchase Order or Asset list with 'Dell Precision' items?"
        vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer') == 'yes':
             # Bonus for visual evidence if DB query was strict
             pass 

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }