#!/usr/bin/env python3
"""
Verifier for create_pricebook_products task.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an agent successfully created a Price Book and associated products in Vtiger CRM.
Look at the sequence of screenshots from the agent's trajectory and the final screenshot.
Task:
1. Create a Price Book named 'Premium Partner Pricing Q1 2025'
2. Associate 3 products with discounted list prices.

Check for evidence of:
- The agent navigating to the Price Books module.
- The agent entering the Price Book details (name, active, currency, description).
- The agent adding/selecting products (Wireless Bluetooth Headset, USB-C Docking Station, Ergonomic Keyboard Pro).
- The agent entering the discounted list prices ($59.99, $119.99, $99.99).
- The final state showing the created Price Book with the associated products.

Respond in JSON format:
{
    "navigated_to_pricebooks": true/false,
    "created_pricebook": true/false,
    "associated_products": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of evidence seen in screenshots"
}
"""

def verify_create_pricebook_products(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_p1 = metadata.get('product1_price', 59.99)
    expected_p2 = metadata.get('product2_price', 119.99)
    expected_p3 = metadata.get('product3_price', 99.99)

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
    feedback_parts = []
    
    pb_found = result.get('pb_found', False)
    if pb_found:
        score += 15
        feedback_parts.append("Price Book created successfully")
        
        # Check active (usually '1' or 1 means active)
        active = result.get('active', '0')
        if str(active) == '1' or str(active) == 'on':
            score += 5
            feedback_parts.append("Price Book is Active")
            
        # Check description
        desc = result.get('description', '')
        if "Discounted pricing tier" in desc:
            score += 5
            feedback_parts.append("Description is correct")
            
        # Check products
        prod1_assoc = result.get('prod1_assoc', False)
        prod2_assoc = result.get('prod2_assoc', False)
        prod3_assoc = result.get('prod3_assoc', False)
        
        try:
            p1_price = float(result.get('prod1_price', 0))
            if prod1_assoc and abs(p1_price - expected_p1) < 0.05:
                score += 15
                feedback_parts.append(f"Product 1 associated at {p1_price}")
            elif prod1_assoc:
                score += 5
                feedback_parts.append(f"Product 1 associated, but price {p1_price} != {expected_p1}")
        except ValueError:
            pass

        try:
            p2_price = float(result.get('prod2_price', 0))
            if prod2_assoc and abs(p2_price - expected_p2) < 0.05:
                score += 15
                feedback_parts.append(f"Product 2 associated at {p2_price}")
            elif prod2_assoc:
                score += 5
                feedback_parts.append(f"Product 2 associated, but price {p2_price} != {expected_p2}")
        except ValueError:
            pass

        try:
            p3_price = float(result.get('prod3_price', 0))
            if prod3_assoc and abs(p3_price - expected_p3) < 0.05:
                score += 15
                feedback_parts.append(f"Product 3 associated at {p3_price}")
            elif prod3_assoc:
                score += 5
                feedback_parts.append(f"Product 3 associated, but price {p3_price} != {expected_p3}")
        except ValueError:
            pass
            
        if prod1_assoc and prod2_assoc and prod3_assoc:
            score += 10
            feedback_parts.append("All 3 products associated")
            
        created_during_task = result.get('created_during_task', False)
        if created_during_task:
            score += 5
            feedback_parts.append("Anti-gaming passed: Created during task")
    else:
        feedback_parts.append("Price Book not found in database")

    # VLM Evaluation
    query_vlm = env_info.get('query_vlm')
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    all_images = frames + [final_screenshot] if final_screenshot else frames
    
    if query_vlm and all_images:
        vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=all_images)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('created_pricebook') and parsed.get('associated_products'):
                score += 15
                feedback_parts.append("VLM confirms visual evidence")
            else:
                feedback_parts.append("VLM could not confirm visual evidence")
        else:
            feedback_parts.append("VLM evaluation failed")
    else:
        # Give partial points if VLM is unavailable but database is perfect
        if score >= 75:
            score += 15
            feedback_parts.append("VLM unavailable, auto-granting visual points")

    score = min(100, score)
    passed = pb_found and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }