#!/usr/bin/env python3
"""
Verifier for setup_wholesale_price_list task.

Verification Strategy:
1. File Check: Verify 'wholesale_receipt.pdf' exists and was created during the task.
2. Content Check (VLM): Analyze the receipt PDF (or final screenshot) to confirm:
   - Customer is "TechStart Inc."
   - Item "House Blend Coffee Beans" is listed.
   - Price is exactly $18.50.
3. Process Check (VLM Trajectory): Verify the agent accessed:
   - Price List configuration screens.
   - Customer configuration screens.

Multi-modal approach prevents gaming (e.g., just overriding the price manually without setting up the list).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wholesale_price_setup(traj, env_info, task_info):
    """
    Verify the wholesale price list setup and transaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_price = metadata.get('expected_price', '18.50')
    expected_customer = metadata.get('expected_customer', 'TechStart')
    
    # 1. Retrieve Programmatic Results (File System Checks)
    # Windows path mapping might vary, assuming framework handles the path translation 
    # or we defined a known export path.
    # In 'export_result.ps1' we wrote to C:\Users\Docker\AppData\Local\Temp\task_result.json
    # We try to copy from that Windows path.
    
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Adjust path if environment uses different mapping. 
        # Standard dockur/windows often maps /tmp in "copy_from_env" to Temp.
        # We try the full Windows path first.
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
        # Fail gracefully, rely on VLM
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Scoring Breakdown
    score = 0
    feedback_parts = []
    
    # Criterion A: Receipt PDF Created (20 pts)
    receipt_exists = result_data.get('receipt_exists', False)
    receipt_fresh = result_data.get('receipt_created_during_task', False)
    
    if receipt_exists and receipt_fresh:
        score += 20
        feedback_parts.append("Receipt PDF created successfully.")
    elif receipt_exists:
        score += 10
        feedback_parts.append("Receipt PDF exists but timestamp verification failed (check system time).")
    else:
        feedback_parts.append("Receipt PDF NOT found.")

    # Criterion B: VLM Analysis of Receipt/Final Screen (40 pts)
    # We check if the final state shows the transaction details
    final_screen = get_final_screenshot(traj)
    
    receipt_prompt = f"""
    Analyze this image of a Point of Sale system or a receipt.
    I am looking for a specific transaction details:
    1. Customer: '{expected_customer}'
    2. Item: 'House Blend Coffee Beans' (or similar)
    3. Price/Amount: '${expected_price}'
    
    Does the image confirm this transaction occurred at this price?
    Note: The price must be exactly {expected_price}. If it is $24.99, it is WRONG.
    
    Return JSON: {{ "customer_match": bool, "item_match": bool, "price_match": bool, "observed_price": "string" }}
    """
    
    vlm_result = query_vlm(prompt=receipt_prompt, image=final_screen)
    parsed_vlm = vlm_result.get('parsed', {}) if vlm_result.get('success') else {}
    
    if parsed_vlm.get('price_match'):
        score += 40
        feedback_parts.append(f"Confirmed correct wholesale price ${expected_price}.")
    elif parsed_vlm.get('observed_price'):
        feedback_parts.append(f"Wrong price observed: {parsed_vlm.get('observed_price')}.")
    else:
        feedback_parts.append("Could not verify price in final screenshot.")

    # Criterion C: VLM Trajectory Verification (40 pts)
    # Check if they actually set up the price list (Anti-gaming: don't just override price)
    frames = sample_trajectory_frames(traj, n=6)
    
    workflow_prompt = """
    Analyze these screenshots of a user operating Copper Point of Sale.
    I need to verify if the user performed these configuration steps:
    1. Opened a 'Price List' or 'Pricing' configuration dialog.
    2. Edited a customer record (specifically the 'Price List' field).
    
    Look for:
    - A window titled "Price Lists" or "Edit Price List".
    - A dropdown menu inside a Customer dialog selecting a price list.
    
    Return JSON: {{ "price_list_config_seen": bool, "customer_config_seen": bool }}
    """
    
    traj_result = query_vlm(prompt=workflow_prompt, images=frames)
    traj_parsed = traj_result.get('parsed', {}) if traj_result.get('success') else {}
    
    if traj_parsed.get('price_list_config_seen'):
        score += 20
        feedback_parts.append("Verified Price List configuration step.")
    else:
        feedback_parts.append("No Price List configuration detected.")
        
    if traj_parsed.get('customer_config_seen'):
        score += 20
        feedback_parts.append("Verified Customer Price List assignment step.")
    else:
        feedback_parts.append("No Customer configuration detected.")

    # Final Evaluation
    passed = score >= 80  # Requires PDF + Price Correct + At least one config step verified
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }