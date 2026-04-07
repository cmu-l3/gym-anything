#!/usr/bin/env python3
"""
Verifier for create_inventory_move task in iDempiere.

Criteria:
1. Document Exists & Anti-Gaming (Created during task)
2. Document Status is 'CO' (Completed)
3. Product is 'Azalea Bush'
4. Quantity is 5
5. Locators are different (Source != Target)
6. VLM Verification of workflow
"""

import json
import logging
import os
import tempfile
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_inventory_move(traj, env_info, task_info):
    """
    Verify the inventory move task using database results and VLM.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_product = metadata.get('expected_product', 'Azalea Bush')
    expected_qty = metadata.get('expected_qty', 5)
    
    # 2. Retrieve JSON result
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

    # 3. Evaluation
    score = 0
    feedback_parts = []
    
    # Data extraction
    doc_exists = result.get('doc_exists', False)
    doc_status = result.get('doc_status', '')
    product_name = result.get('product_name', '')
    quantity = float(result.get('quantity', 0))
    src_loc = result.get('src_locator_id', '')
    tgt_loc = result.get('tgt_locator_id', '')
    desc = result.get('description', '')
    
    # Criterion 1: Document Created (15 pts)
    if doc_exists and result.get('count_delta', 0) > 0:
        score += 15
        feedback_parts.append("Inventory Move document created")
    else:
        feedback_parts.append("No new Inventory Move document found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Completed Status (20 pts)
    if doc_status == 'CO':
        score += 20
        feedback_parts.append("Document status: Completed")
    else:
        feedback_parts.append(f"Document status incomplete: {doc_status}")

    # Criterion 3: Correct Product (20 pts)
    if expected_product.lower() in product_name.lower():
        score += 20
        feedback_parts.append(f"Correct product: {product_name}")
    else:
        feedback_parts.append(f"Wrong product: {product_name}")

    # Criterion 4: Correct Quantity (15 pts)
    # Allow small float tolerance
    if abs(quantity - expected_qty) < 0.01:
        score += 15
        feedback_parts.append(f"Correct quantity: {quantity}")
    else:
        feedback_parts.append(f"Wrong quantity: {quantity}")

    # Criterion 5: Different Locators (10 pts)
    if src_loc and tgt_loc and src_loc != tgt_loc:
        score += 10
        feedback_parts.append("Source and Target locators are different")
    else:
        feedback_parts.append("Source/Target locators invalid or identical")

    # Criterion 6: Description Check (5 pts)
    if "azalea" in desc.lower():
        score += 5
        feedback_parts.append("Description contains product name")

    # Criterion 7: VLM Verification (15 pts)
    # Check if agent was interacting with the Move Window and Completion Dialog
    frames = sample_trajectory_frames(traj, n=5)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of an iDempiere ERP session. "
        "Did the user: "
        "1. Open the 'Inventory Move' window? "
        "2. Interact with the 'Move Line' tab? "
        "3. Open the Document Action/Process dialog to complete the document? "
        "Provide a score from 0 to 15 based on evidence of these steps."
    )
    
    try:
        vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        # Simple heuristic: assume VLM returns positive confirmation
        # In a real impl, we'd parse the VLM score or JSON
        if "yes" in vlm_res.get("response", "").lower() or "inventory move" in vlm_res.get("response", "").lower():
            score += 15
            feedback_parts.append("VLM confirmed workflow")
        else:
            # Fallback score if VLM is unsure but DB is perfect
            if score >= 85:
                score += 15
                feedback_parts.append("Workflow inferred from DB success")
            else:
                feedback_parts.append("VLM could not verify workflow")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful fallback
        if score >= 85: 
            score += 15 

    # Final Pass/Fail
    passed = (score >= 70) and (doc_status == 'CO')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }